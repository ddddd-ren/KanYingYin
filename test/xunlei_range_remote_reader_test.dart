import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_relay_protocol.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_remote_reader.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_range_remote_reader.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_request_policy.dart';

void main() {
  late Directory directory;
  final servers = <HttpServer>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xunlei-reader-test-');
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

  test('迅雷读取器发送 Range、identity 和资源 User-Agent', () async {
    String? range;
    String? encoding;
    String? userAgent;
    String? authorization;
    final server = await serve((request) async {
      range = request.headers.value(HttpHeaders.rangeHeader);
      encoding = request.headers.value(HttpHeaders.acceptEncodingHeader);
      userAgent = request.headers.value(HttpHeaders.userAgentHeader);
      authorization = request.headers.value(HttpHeaders.authorizationHeader);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-3/4')
        ..contentLength = 4
        ..add(const <int>[1, 2, 3, 4]);
      await request.response.close();
    });
    final reader = XunleiRangeRemoteReader(
      resource: CloudRangeRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${server.port}/file'),
        headers: const <String, String>{
          'User-Agent': 'xunlei-download-fixture',
          'Authorization': 'Bearer must-not-forward',
        },
        totalLength: 4,
      ),
      refreshResource: () => throw StateError('不应刷新'),
      uriValidator: allowTestUri,
    );
    final target = File('${directory.path}/chunk');

    await reader.readTo(const ByteRange(0, 3), target);

    expect(range, 'bytes=0-3');
    expect(encoding, 'identity');
    expect(userAgent, 'xunlei-download-fixture');
    expect(authorization, isNull);
    expect(await target.readAsBytes(), <int>[1, 2, 3, 4]);
    await reader.close();
  });

  test('迅雷 401 或 403 在读取器生命周期内只刷新一次', () async {
    var refreshCount = 0;
    var refreshedRequests = 0;
    final server = await serve((request) async {
      if (request.uri.path == '/old') {
        request.response.statusCode = HttpStatus.forbidden;
      } else {
        refreshedRequests++;
        if (refreshedRequests == 1) {
          request.response
            ..statusCode = HttpStatus.partialContent
            ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-3/4')
            ..contentLength = 4
            ..add(const <int>[1, 2, 3, 4]);
        } else {
          request.response.statusCode = HttpStatus.unauthorized;
        }
      }
      await request.response.close();
    });
    final reader = XunleiRangeRemoteReader(
      resource: CloudRangeRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${server.port}/old'),
        totalLength: 4,
      ),
      refreshResource: () async {
        refreshCount++;
        return CloudRangeRemoteResource(
          uri: Uri.parse('http://127.0.0.1:${server.port}/new'),
          totalLength: 4,
        );
      },
      uriValidator: allowTestUri,
    );

    await reader.readTo(
      const ByteRange(0, 3),
      File('${directory.path}/first'),
    );
    await expectLater(
      reader.readTo(
        const ByteRange(0, 3),
        File('${directory.path}/second'),
      ),
      throwsA(isA<CloudRangeRemoteAuthenticationException>()),
    );

    expect(refreshCount, 1);
    await reader.close();
  });

  test('迅雷读取器严格校验 Content-Range', () async {
    final server = await serve((request) async {
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 1-3/4')
        ..contentLength = 3
        ..add(const <int>[2, 3, 4]);
      await request.response.close();
    });
    final target = File('${directory.path}/bad');
    final reader = XunleiRangeRemoteReader(
      resource: CloudRangeRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${server.port}/file'),
      ),
      refreshResource: () => throw StateError('不应刷新'),
      uriValidator: allowTestUri,
    );

    await expectLater(
      reader.readTo(const ByteRange(0, 3), target),
      throwsA(isA<CloudRangeRemoteProtocolException>()),
    );

    expect(await target.exists(), isFalse);
    await reader.close();
  });

  test('迅雷连续分段读取复用同一 HTTP 连接', () async {
    final remotePorts = <int>{};
    final server = await serve((request) async {
      remotePorts.add(request.connectionInfo!.remotePort);
      final value = request.headers.value(HttpHeaders.rangeHeader)!;
      final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(value)!;
      final start = int.parse(match.group(1)!);
      final end = int.parse(match.group(2)!);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/8',
        )
        ..contentLength = end - start + 1
        ..add(<int>[for (var value = start; value <= end; value++) value]);
      await request.response.close();
    });
    final reader = XunleiRangeRemoteReader(
      resource: CloudRangeRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${server.port}/file'),
        totalLength: 8,
      ),
      refreshResource: () => throw StateError('不应刷新'),
      uriValidator: allowTestUri,
    );

    await reader.readTo(
      const ByteRange(0, 3),
      File('${directory.path}/first'),
    );
    await reader.readTo(
      const ByteRange(4, 7),
      File('${directory.path}/second'),
    );

    expect(remotePorts, hasLength(1));
    await reader.close();
  });

  test('迅雷会话缓存可信重定向地址', () async {
    var initialRequests = 0;
    var redirectRequests = 0;
    final redirectServer = await serve((request) async {
      redirectRequests++;
      final value = request.headers.value(HttpHeaders.rangeHeader)!;
      final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(value)!;
      final start = int.parse(match.group(1)!);
      final end = int.parse(match.group(2)!);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/8',
        )
        ..contentLength = end - start + 1
        ..add(<int>[for (var value = start; value <= end; value++) value]);
      await request.response.close();
    });
    final initialServer = await serve((request) async {
      initialRequests++;
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:${redirectServer.port}/cdn',
        );
      await request.response.close();
    });
    final reader = XunleiRangeRemoteReader(
      resource: CloudRangeRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${initialServer.port}/file'),
        totalLength: 8,
      ),
      refreshResource: () => throw StateError('不应刷新'),
      uriValidator: allowTestUri,
    );

    await reader.readTo(
      const ByteRange(0, 3),
      File('${directory.path}/redirect-first'),
    );
    await reader.readTo(
      const ByteRange(4, 7),
      File('${directory.path}/redirect-second'),
    );

    expect(initialRequests, 1);
    expect(redirectRequests, 2);
    await reader.close();
  });

  test('探测返回 200 时支持无 Range 的顺序流', () async {
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
    final reader = XunleiRangeRemoteReader(
      resource: CloudRangeRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${server.port}/file'),
      ),
      refreshResource: () => throw StateError('不应刷新'),
      uriValidator: allowTestUri,
    );

    final metadata = await reader.probe();
    final file = File('${directory.path}/full');
    final sink = file.openWrite();
    await reader.streamAll(sink);
    await sink.close();

    expect(metadata, isA<XunleiRemoteMetadata>());
    expect(metadata.supportsRanges, isFalse);
    expect(metadata.totalLength, 4);
    expect(ranges, <String?>['bytes=0-0', null]);
    expect(await file.readAsBytes(), <int>[1, 2, 3, 4]);
    await reader.close();
  });

  test('默认策略拒绝 HTTP、私网和恶意相似域', () {
    const policy = XunleiRequestPolicy();

    for (final value in <String>[
      'http://download.xunlei.com/file',
      'https://127.0.0.1/file',
      'https://10.0.0.1/file',
      'https://192.168.1.1/file',
      'https://localhost/file',
      'https://xunlei.com.evil.example/file',
      'https://evilxunlei.com/file',
    ]) {
      expect(policy.isTrustedDownloadUri(Uri.parse(value)), isFalse,
          reason: value);
    }
    expect(
      policy.isTrustedDownloadUri(
        Uri.parse('https://download.xunlei.com/file'),
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
    final reader = XunleiRangeRemoteReader(
      resource: CloudRangeRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${server.port}/file'),
      ),
      refreshResource: () => throw StateError('不应刷新'),
      uriValidator: allowTestUri,
    );
    final target = File('${directory.path}/cancelled');
    final read = reader.readTo(const ByteRange(0, 3), target);
    await requestStarted.future;

    await reader.close();

    await expectLater(read, throwsA(anything));
    expect(await target.exists(), isFalse);
  });
}
