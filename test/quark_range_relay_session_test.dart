import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';
import 'package:kanyingyin/services/cloud/quark/quark_range_relay_session.dart';
import 'package:kanyingyin/services/cloud/quark/quark_range_remote_reader.dart';

void main() {
  late Directory directory;
  late HttpServer remoteServer;
  late QuarkRangeRemoteReader reader;
  late QuarkRangeRelaySession session;
  final sourceBytes = <int>[for (var value = 0; value < 20; value++) value];
  var activeRequests = 0;
  var maxActiveRequests = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('quark-relay-test-');
    remoteServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    remoteServer.listen((request) async {
      activeRequests++;
      if (activeRequests > maxActiveRequests) {
        maxActiveRequests = activeRequests;
      }
      try {
        final value = request.headers.value(HttpHeaders.rangeHeader)!;
        final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(value)!;
        final start = int.parse(match.group(1)!);
        final end = int.parse(match.group(2)!);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/${sourceBytes.length}',
          )
          ..headers.contentType = ContentType('video', 'mp4')
          ..contentLength = end - start + 1
          ..add(sourceBytes.sublist(start, end + 1));
        await request.response.close();
      } finally {
        activeRequests--;
      }
    });
    reader = QuarkRangeRemoteReader(
      resource: QuarkRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${remoteServer.port}/video'),
      ),
      refreshResource: () => throw StateError('不应刷新'),
      uriValidator: (uri) => uri.host == '127.0.0.1',
    );
    session = await QuarkRangeRelaySession.start(
      reader: reader,
      directory: directory,
      chunkSize: 4,
      maxChunks: 4,
    );
  });

  tearDown(() async {
    await session.close();
    await remoteServer.close(force: true);
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('仅绑定 IPv4 loopback 并使用至少 128 位随机令牌', () {
    expect(session.uri.scheme, 'http');
    expect(session.uri.host, '127.0.0.1');
    expect(session.uri.port, greaterThan(0));
    expect(session.uri.pathSegments, hasLength(1));
    expect(
        session.uri.pathSegments.single, hasLength(greaterThanOrEqualTo(32)));
  });

  test('错误令牌与非本机 Host 均返回 404', () async {
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    final wrongToken = await client.getUrl(
      session.uri.replace(path: '/wrong-token'),
    );
    final wrongTokenResponse = await wrongToken.close();
    expect(wrongTokenResponse.statusCode, HttpStatus.notFound);
    await wrongTokenResponse.drain<void>();
    client.close(force: true);

    final socket = await Socket.connect('127.0.0.1', session.uri.port);
    socket.write(
      'GET ${session.uri.path} HTTP/1.1\r\n'
      'Host: evil.example\r\n'
      'Connection: close\r\n\r\n',
    );
    await socket.flush();
    final responseText = await utf8.decoder.bind(socket).join();
    expect(responseText, startsWith('HTTP/1.1 404'));
    await socket.close();
  });

  test('HEAD、完整 GET、单 Range 和非法多 Range 符合协议', () async {
    final client = HttpClient()..findProxy = (_) => 'DIRECT';

    final head = await client.openUrl('HEAD', session.uri);
    final headResponse = await head.close();
    expect(headResponse.statusCode, HttpStatus.ok);
    expect(headResponse.contentLength, sourceBytes.length);
    expect(headResponse.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    expect(headResponse.headers.contentType?.mimeType, 'video/mp4');
    await headResponse.drain<void>();

    final ranged = await client.getUrl(session.uri);
    ranged.headers.set(HttpHeaders.rangeHeader, 'bytes=3-8');
    final rangedResponse = await ranged.close();
    expect(rangedResponse.statusCode, HttpStatus.partialContent);
    expect(
      rangedResponse.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 3-8/20',
    );
    expect(await _readResponse(rangedResponse), sourceBytes.sublist(3, 9));

    final full = await client.getUrl(session.uri);
    final fullResponse = await full.close();
    expect(fullResponse.statusCode, HttpStatus.ok);
    expect(await _readResponse(fullResponse), sourceBytes);

    final multiple = await client.getUrl(session.uri);
    multiple.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1,4-5');
    final multipleResponse = await multiple.close();
    expect(
        multipleResponse.statusCode, HttpStatus.requestedRangeNotSatisfiable);
    expect(
      multipleResponse.headers.value(HttpHeaders.contentRangeHeader),
      'bytes */20',
    );
    await multipleResponse.drain<void>();
    client.close(force: true);
  });

  test('跨段读取准确且远端并发不超过两个', () async {
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    final requests = <Future<List<int>>>[];
    for (final range in <String>['bytes=1-10', 'bytes=11-19']) {
      requests.add(() async {
        final request = await client.getUrl(session.uri);
        request.headers.set(HttpHeaders.rangeHeader, range);
        return _readResponse(await request.close());
      }());
    }

    final results = await Future.wait(requests);

    expect(results[0], sourceBytes.sublist(1, 11));
    expect(results[1], sourceBytes.sublist(11));
    expect(maxActiveRequests, lessThanOrEqualTo(2));
    client.close(force: true);
  });

  test('成功读取后发布就绪速度与缓存状态', () async {
    final statuses = <QuarkRelayStatus>[];
    final subscription = session.statuses.listen(statuses.add);
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    final request = await client.getUrl(session.uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=4-7');
    await (await request.close()).drain<void>();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(session.currentStatus.phase, QuarkRelayPhase.ready);
    expect(session.currentStatus.receivedBytes, greaterThan(0));
    expect(session.currentStatus.cachedBytes, greaterThan(0));
    expect(statuses.any((status) => status.phase == QuarkRelayPhase.ready),
        isTrue);

    client.close(force: true);
    await subscription.cancel();
  });

  test('关闭幂等并停止监听且删除会话目录', () async {
    final uri = session.uri;
    await session.close();
    await session.close();

    expect(await directory.exists(), isFalse);
    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(milliseconds: 200);
    await expectLater(client.getUrl(uri), throwsA(isA<SocketException>()));
    client.close(force: true);
  });
}

Future<List<int>> _readResponse(HttpClientResponse response) =>
    response.fold(<int>[], (bytes, chunk) => bytes..addAll(chunk));
