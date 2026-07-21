import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_relay_protocol.dart';
import 'package:kanyingyin/services/cloud/quark/quark_range_remote_reader.dart';
import 'package:kanyingyin/services/cloud/quark/quark_request_policy.dart';

void main() {
  late Directory directory;
  final servers = <HttpServer>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('quark-reader-test-');
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

  test('发送精确 Range 并校验响应后写入目标文件', () async {
    String? receivedRange;
    String? receivedCookie;
    final server = await serve((request) async {
      receivedRange = request.headers.value(HttpHeaders.rangeHeader);
      receivedCookie = request.headers.value(HttpHeaders.cookieHeader);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 16-31/64')
        ..headers.contentType = ContentType('video', 'mp4')
        ..contentLength = 16
        ..add(<int>[for (var value = 16; value <= 31; value++) value]);
      await request.response.close();
    });
    final reader = QuarkRangeRemoteReader(
      resource: QuarkRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${server.port}/video'),
        headers: const <String, String>{'Cookie': 'session=secret'},
      ),
      refreshResource: () => throw StateError('不应刷新'),
      uriValidator: allowTestUri,
    );
    final destination = File('${directory.path}/chunk.bin');

    await reader.readTo(const ByteRange(16, 31), destination);

    expect(receivedRange, 'bytes=16-31');
    expect(receivedCookie, 'session=secret');
    expect(await destination.readAsBytes(),
        <int>[for (var value = 16; value <= 31; value++) value]);
    expect(reader.totalLength, 64);
    expect(reader.contentType, 'video/mp4');
    await reader.close();
  });

  test('探测请求取得总长度并丢弃探测字节', () async {
    final server = await serve((request) async {
      expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=0-0');
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-0/64')
        ..headers.contentType = ContentType.binary
        ..contentLength = 1
        ..add(const <int>[7]);
      await request.response.close();
    });
    final reader = QuarkRangeRemoteReader(
      resource: QuarkRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${server.port}/video'),
      ),
      refreshResource: () => throw StateError('不应刷新'),
      uriValidator: allowTestUri,
    );

    final metadata = await reader.probe();

    expect(metadata.totalLength, 64);
    expect(metadata.contentType, 'application/octet-stream');
    await reader.close();
  });

  test('错误 Content-Range 和非零 Range 返回 200 均明确失败', () async {
    final wrongRange = await serve((request) async {
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-15/64')
        ..contentLength = 16
        ..add(List<int>.filled(16, 0));
      await request.response.close();
    });
    final wrongStatus = await serve((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..contentLength = 16
        ..add(List<int>.filled(16, 0));
      await request.response.close();
    });

    for (final server in <HttpServer>[wrongRange, wrongStatus]) {
      final reader = QuarkRangeRemoteReader(
        resource: QuarkRemoteResource(
          uri: Uri.parse('http://127.0.0.1:${server.port}/video'),
        ),
        refreshResource: () => throw StateError('不应刷新'),
        uriValidator: allowTestUri,
      );
      await expectLater(
        reader.readTo(
          const ByteRange(16, 31),
          File('${directory.path}/bad-${server.port}.bin'),
        ),
        throwsA(isA<QuarkRemoteProtocolException>()),
      );
      await reader.close();
    }
  });

  test('鉴权失败只刷新一次并从原 Range 继续', () async {
    var refreshCalls = 0;
    var newAddressCalls = 0;
    final server = await serve((request) async {
      if (request.uri.queryParameters['token'] != 'new' ||
          newAddressCalls > 0) {
        request.response.statusCode = HttpStatus.forbidden;
      } else {
        newAddressCalls++;
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 16-31/64')
          ..contentLength = 16
          ..add(List<int>.filled(16, 9));
      }
      await request.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}/video';
    final reader = QuarkRangeRemoteReader(
      resource: QuarkRemoteResource(uri: Uri.parse('$base?token=old')),
      refreshResource: () async {
        refreshCalls++;
        return QuarkRemoteResource(uri: Uri.parse('$base?token=new'));
      },
      uriValidator: allowTestUri,
    );

    await reader.readTo(
      const ByteRange(16, 31),
      File('${directory.path}/refreshed.bin'),
    );
    await expectLater(
      reader.readTo(
        const ByteRange(16, 31),
        File('${directory.path}/expired-again.bin'),
      ),
      throwsA(isA<QuarkRemoteAuthenticationException>()),
    );

    expect(refreshCalls, 1);
    await reader.close();
  });

  test('连接失败按 500ms、1s、2s 退避且不泄露完整地址', () async {
    final unused = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = unused.port;
    await unused.close(force: true);
    final delays = <Duration>[];
    final reader = QuarkRangeRemoteReader(
      resource: QuarkRemoteResource(
        uri: Uri.parse('http://127.0.0.1:$port/private?id=secret'),
      ),
      refreshResource: () => throw StateError('不应刷新'),
      uriValidator: allowTestUri,
      delay: (duration) async => delays.add(duration),
    );

    Object? error;
    try {
      await reader.readTo(
        const ByteRange(0, 0),
        File('${directory.path}/unreachable.bin'),
      );
    } on Object catch (caught) {
      error = caught;
    }

    expect(error, isNotNull);
    expect(delays, const <Duration>[
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
    ]);
    expect(error.toString(), isNot(contains('private')));
    expect(error.toString(), isNot(contains('secret')));
    await reader.close();
  });

  test('重定向到恶意相似域名时在发送前拒绝', () async {
    final server = await serve((request) async {
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(
          HttpHeaders.locationHeader,
          'https://drive.quark.cn.example.com/private',
        );
      await request.response.close();
    });
    const policy = QuarkRequestPolicy();
    final reader = QuarkRangeRemoteReader(
      resource: QuarkRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${server.port}/redirect'),
      ),
      refreshResource: () => throw StateError('不应刷新'),
      uriValidator: (uri) =>
          allowTestUri(uri) || policy.isTrustedOriginalDownloadUri(uri),
    );

    await expectLater(
      reader.readTo(
        const ByteRange(0, 0),
        File('${directory.path}/redirect.bin'),
      ),
      throwsA(isA<QuarkRemoteProtocolException>()),
    );
    await reader.close();
  });
}
