import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_range_remote_reader.dart';
import 'package:kanyingyin/services/cloud/baidu/baidu_request_policy.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_relay_protocol.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_remote_reader.dart';

void main() {
  late Directory directory;
  final servers = <HttpServer>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('baidu-reader-test-');
  });

  tearDown(() async {
    for (final server in servers) {
      await server.close(force: true);
    }
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<HttpServer> serve(
    Future<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servers.add(server);
    server.listen(handler);
    return server;
  }

  bool allowTestUri(Uri uri) =>
      uri.scheme == 'http' && uri.host == InternetAddress.loopbackIPv4.address;

  test('百度读取器只向首始官方地址附加 access_token', () async {
    Uri? firstRequestUri;
    Uri? redirectRequestUri;
    String? redirectAuthorization;
    final redirectServer = await serve((request) async {
      redirectRequestUri = request.uri;
      redirectAuthorization =
          request.headers.value(HttpHeaders.authorizationHeader);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-3/4')
        ..contentLength = 4
        ..add(const <int>[1, 2, 3, 4]);
      await request.response.close();
    });
    final initialServer = await serve((request) async {
      firstRequestUri = request.uri;
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${redirectServer.port}/cdn?fixture=2',
        );
      await request.response.close();
    });
    final reader = BaiduRangeRemoteReader(
      resource: CloudRangeRemoteResource(
        uri: Uri.parse(
          'http://127.0.0.1:${initialServer.port}/file?fixture=1',
        ),
        headers: const <String, String>{
          'Authorization': 'Bearer must-not-forward',
        },
        totalLength: 4,
      ),
      accessTokenProvider: () async => 'access-fixture',
      refreshResource: () => throw StateError('不应刷新'),
      initialUriValidator: allowTestUri,
      redirectUriValidator: allowTestUri,
    );
    final target = File('${directory.path}/chunk');

    await reader.readTo(const ByteRange(0, 3), target);

    expect(firstRequestUri?.queryParameters['access_token'], 'access-fixture');
    expect(redirectRequestUri?.queryParameters['access_token'], isNull);
    expect(redirectAuthorization, isNull);
    expect(await target.readAsBytes(), <int>[1, 2, 3, 4]);
    await reader.close();
  });

  test('百度 401 或 403 只刷新令牌和 dlink 一次', () async {
    var refreshCount = 0;
    final server = await serve((request) async {
      if (request.uri.path == '/old') {
        request.response.statusCode = HttpStatus.forbidden;
      } else {
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-3/4')
          ..contentLength = 4
          ..add(const <int>[1, 2, 3, 4]);
      }
      await request.response.close();
    });
    final reader = BaiduRangeRemoteReader(
      resource: CloudRangeRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${server.port}/old'),
        totalLength: 4,
      ),
      accessTokenProvider: () async => 'access-fixture',
      refreshResource: () async {
        refreshCount++;
        return CloudRangeRemoteResource(
          uri: Uri.parse('http://127.0.0.1:${server.port}/new'),
          totalLength: 4,
        );
      },
      initialUriValidator: allowTestUri,
      redirectUriValidator: allowTestUri,
    );

    await reader.readTo(
      const ByteRange(0, 3),
      File('${directory.path}/chunk'),
    );

    expect(refreshCount, 1);
    await reader.close();
  });

  test('百度读取器严格校验 206、Content-Range 和响应长度', () async {
    final server = await serve((request) async {
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 1-3/4')
        ..contentLength = 3
        ..add(const <int>[2, 3, 4]);
      await request.response.close();
    });
    final reader = BaiduRangeRemoteReader(
      resource: CloudRangeRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${server.port}/file'),
      ),
      accessTokenProvider: () async => 'access-fixture',
      refreshResource: () => throw StateError('不应刷新'),
      initialUriValidator: allowTestUri,
      redirectUriValidator: allowTestUri,
    );

    await expectLater(
      reader.readTo(
        const ByteRange(0, 3),
        File('${directory.path}/bad'),
      ),
      throwsA(isA<CloudRangeRemoteProtocolException>()),
    );
    expect(await File('${directory.path}/bad').exists(), isFalse);
    await reader.close();
  });

  test('探测返回 200 时顺序流只发起一次无 Range 的完整 GET', () async {
    final ranges = <String?>[];
    final server = await serve((request) async {
      ranges.add(request.headers.value(HttpHeaders.rangeHeader));
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('video', 'mp4')
        ..contentLength = 4
        ..add(const <int>[1, 2, 3, 4]);
      await request.response.close();
    });
    final reader = BaiduRangeRemoteReader(
      resource: CloudRangeRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${server.port}/file'),
      ),
      accessTokenProvider: () async => 'access-fixture',
      refreshResource: () => throw StateError('不应刷新'),
      initialUriValidator: allowTestUri,
      redirectUriValidator: allowTestUri,
    );

    final metadata = await reader.probe();
    final file = File('${directory.path}/full');
    final sink = file.openWrite();
    await reader.streamAll(sink);
    await sink.close();

    expect(metadata.supportsRanges, isFalse);
    expect(metadata.totalLength, 4);
    expect(ranges, <String?>['bytes=0-0', null]);
    expect(await file.readAsBytes(), <int>[1, 2, 3, 4]);
    await reader.close();
  });

  test('默认策略拒绝非 HTTPS、回环、私网和链路本地重定向', () {
    const policy = BaiduRequestPolicy();

    expect(
      policy.isOfficialDownloadUri(
        Uri.parse('https://pan.baidu.com/rest/2.0/xpan/file'),
      ),
      isTrue,
    );
    expect(
      policy.isOfficialDownloadUri(
        Uri.parse('https://d.pcs.baidu.com/file/example'),
      ),
      isTrue,
    );
    for (final value in <String>[
      'http://cdn.example.com/file',
      'https://127.0.0.1/file',
      'https://10.0.0.1/file',
      'https://172.16.0.1/file',
      'https://192.168.1.1/file',
      'https://169.254.1.1/file',
      'https://[::1]/file',
      'https://localhost/file',
    ]) {
      expect(
        policy.isSafeDownloadRedirectUri(Uri.parse(value)),
        isFalse,
        reason: value,
      );
    }
    expect(
      policy.isSafeDownloadRedirectUri(
        Uri.parse('https://cdn.example.com/file'),
      ),
      isTrue,
    );
  });

  test('关闭读取器会取消仍在等待的远程请求', () async {
    final requestStarted = Completer<void>();
    final server = await serve((request) async {
      requestStarted.complete();
      await Completer<void>().future;
    });
    final reader = BaiduRangeRemoteReader(
      resource: CloudRangeRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${server.port}/file'),
      ),
      accessTokenProvider: () async => 'access-fixture',
      refreshResource: () => throw StateError('不应刷新'),
      initialUriValidator: allowTestUri,
      redirectUriValidator: allowTestUri,
    );
    final read = reader.readTo(
      const ByteRange(0, 3),
      File('${directory.path}/cancelled'),
    );
    await requestStarted.future;

    await reader.close();

    await expectLater(read, throwsA(anything));
    expect(await File('${directory.path}/cancelled').exists(), isFalse);
  });
}
