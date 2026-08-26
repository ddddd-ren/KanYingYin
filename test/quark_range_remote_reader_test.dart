import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_relay_protocol.dart';
import 'package:kanyingyin/services/cloud/quark/quark_range_remote_reader.dart';
import 'package:kanyingyin/services/cloud/quark/quark_request_policy.dart';

void main() {
  late Directory directory;
  final servers = <HttpServer>[];

  test('夸克读取器允许天玑 930 专项调度使用十路连接', () {
    final source = File(
      'lib/services/cloud/quark/quark_range_remote_reader.dart',
    ).readAsStringSync();

    expect(source, contains('..maxConnectionsPerHost = maxConnectionsPerHost'));
    expect(source, contains('this.maxConnectionsPerHost = 10'));
    expect(source, contains("..findProxy = (_) => 'DIRECT'"));
    expect(source, contains('..autoUncompress = false'));
  });

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

  test('连续分段读取复用同一 HTTP 连接', () async {
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
    final reader = QuarkRangeRemoteReader(
      resource: QuarkRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${server.port}/video'),
      ),
      refreshResource: () => throw StateError('不应刷新'),
      uriValidator: allowTestUri,
    );

    await reader.readTo(
      const ByteRange(0, 3),
      File('${directory.path}/first.bin'),
    );
    await reader.readTo(
      const ByteRange(4, 7),
      File('${directory.path}/second.bin'),
    );

    expect(remotePorts, hasLength(1));
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

  test('上游 401 和 403 重试后保留真实 HTTP 状态', () async {
    for (final statusCode in <int>[
      HttpStatus.unauthorized,
      HttpStatus.forbidden,
    ]) {
      final server = await serve((request) async {
        request.response.statusCode = statusCode;
        await request.response.close();
      });
      final uri = Uri.parse('http://127.0.0.1:${server.port}/video');
      final reader = QuarkRangeRemoteReader(
        resource: QuarkRemoteResource(uri: uri),
        refreshResource: () async => QuarkRemoteResource(uri: uri),
        uriValidator: allowTestUri,
      );

      await expectLater(
        reader.readTo(
          const ByteRange(0, 0),
          File('${directory.path}/http-$statusCode.bin'),
        ),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('HTTP $statusCode'),
          ),
        ),
      );
      await reader.close();
    }
  });

  test(
    '2 MB/s 保持一MiB而 2 Mbps 动态降为512KiB分块',
    () async {
      const mebibyte = 1024 * 1024;
      const minimumChunk = 512 * 1024;

      Future<List<int>> readAt(
        int bytesPerSecond,
        String name, {
        int totalLength = 2 * mebibyte,
      }) async {
        final requestedLengths = <int>[];
        final server = await serve((request) async {
          final value = request.headers.value(HttpHeaders.rangeHeader)!;
          final match = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(value)!;
          final start = int.parse(match.group(1)!);
          final end = int.parse(match.group(2)!);
          final length = end - start + 1;
          requestedLengths.add(length);
          request.response
            ..statusCode = HttpStatus.partialContent
            ..headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $start-$end/$totalLength',
            )
            ..contentLength = length;
          await request.response.flush();
          await Future<void>.delayed(
            Duration(
              microseconds:
                  (length * Duration.microsecondsPerSecond) ~/ bytesPerSecond,
            ),
          );
          request.response.add(List<int>.filled(length, 1));
          await request.response.close();
        });
        final reader = QuarkRangeRemoteReader(
          resource: QuarkRemoteResource(
            uri: Uri.parse('http://127.0.0.1:${server.port}/video'),
          ),
          refreshResource: () => throw StateError('不应刷新'),
          uriValidator: allowTestUri,
        );
        reader.configureAdaptiveReads(
          minReadSize: minimumChunk,
          initialReadSize: mebibyte,
          maxReadSize: 4 * mebibyte,
        );
        await reader.readTo(
          ByteRange(0, totalLength - 1),
          File('${directory.path}/$name.bin'),
        );
        await reader.close();
        return requestedLengths;
      }

      const twoMegabytesPerSecond = 2 * 1000 * 1000;
      const twoMegabitsPerSecond = 2 * 1000 * 1000 ~/ 8;
      expect(twoMegabytesPerSecond, 2000000);
      expect(twoMegabitsPerSecond, 250000);

      expect(
        await readAt(twoMegabytesPerSecond, 'two-megabytes'),
        everyElement(mebibyte),
      );
      final megabitsRanges = await readAt(twoMegabitsPerSecond, 'two-megabits');
      expect(megabitsRanges.first, mebibyte);
      expect(megabitsRanges.skip(1), everyElement(minimumChunk));

      final normalRanges = await readAt(
        8 * mebibyte,
        'normal-speed',
        totalLength: 5 * mebibyte,
      );
      expect(normalRanges, <int>[mebibyte, 4 * mebibyte]);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    '首字节延迟十五秒仍成功且连续读取停顿按三十秒语义单独超时',
    () async {
      final delayedServer = await serve((request) async {
        await Future<void>.delayed(const Duration(seconds: 15));
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-0/1')
          ..contentLength = 1
          ..add(const <int>[1]);
        await request.response.close();
      });
      final delayedReader = QuarkRangeRemoteReader(
        resource: QuarkRemoteResource(
          uri: Uri.parse('http://127.0.0.1:${delayedServer.port}/video'),
        ),
        refreshResource: () => throw StateError('不应刷新'),
        uriValidator: allowTestUri,
      );

      expect((await delayedReader.probe()).totalLength, 1);
      await delayedReader.close();

      final stalledServer = await serve((request) async {
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-1/2')
          ..contentLength = 2
          ..add(const <int>[1]);
        await request.response.flush();
        await Future<void>.delayed(const Duration(seconds: 1));
      });
      final logs = <String>[];
      final stalledReader = QuarkRangeRemoteReader(
        resource: QuarkRemoteResource(
          uri: Uri.parse('http://127.0.0.1:${stalledServer.port}/video'),
        ),
        refreshResource: () => throw StateError('不应刷新'),
        uriValidator: allowTestUri,
        firstByteTimeout: const Duration(seconds: 1),
        readTimeout: const Duration(milliseconds: 50),
        delay: (_) async {},
        log: logs.add,
      );

      await expectLater(
        stalledReader.readTo(
          const ByteRange(0, 1),
          File('${directory.path}/stalled.bin'),
        ),
        throwsA(isA<QuarkRemoteTransportException>()),
      );
      expect(logs.join('\n'), contains('failure=timeout'));
      expect(
        logs.where((message) => message.contains('stage=retry')),
        hasLength(1),
      );
      await stalledReader.close();
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );

  test('上游 404 和 5xx 快速返回真实状态且日志不泄露地址或 Cookie', () async {
    for (final statusCode in <int>[
      HttpStatus.notFound,
      HttpStatus.badGateway
    ]) {
      final server = await serve((request) async {
        request.response.statusCode = statusCode;
        await request.response.close();
      });
      final logs = <String>[];
      final reader = QuarkRangeRemoteReader(
        resource: QuarkRemoteResource(
          uri: Uri.parse(
            'http://127.0.0.1:${server.port}/private?token=secret',
          ),
          headers: const <String, String>{'Cookie': 'session=secret'},
        ),
        refreshResource: () => throw StateError('不应刷新'),
        uriValidator: allowTestUri,
        log: logs.add,
      );
      final stopwatch = Stopwatch()..start();

      await expectLater(
        reader.readTo(
          const ByteRange(0, 0),
          File('${directory.path}/status-$statusCode.bin'),
        ),
        throwsA(
          isA<QuarkRemoteHttpException>().having(
            (error) => error.statusCode,
            'statusCode',
            statusCode,
          ),
        ),
      );

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      final combined = logs.join('\n');
      expect(combined, contains('stage=response'));
      expect(combined, contains('range=0-0'));
      expect(combined, contains('status=$statusCode'));
      expect(combined, contains('failure=http_status'));
      expect(combined, isNot(contains('private')));
      expect(combined, isNot(contains('secret')));
      expect(combined, isNot(contains('Cookie')));
      await reader.close();
    }
  });

  test('取消播放会立即中断上游读取并删除未完成分块', () async {
    final requestStarted = Completer<void>();
    final server = await serve((request) async {
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-1/2')
        ..contentLength = 2;
      await request.response.flush();
      requestStarted.complete();
      await Future<void>.delayed(const Duration(seconds: 10));
    });
    final reader = QuarkRangeRemoteReader(
      resource: QuarkRemoteResource(
        uri: Uri.parse('http://127.0.0.1:${server.port}/video'),
      ),
      refreshResource: () => throw StateError('不应刷新'),
      uriValidator: allowTestUri,
    );
    final destination = File('${directory.path}/cancelled.bin');
    final read = reader.readTo(const ByteRange(0, 1), destination);
    await requestStarted.future;

    await reader.close();

    await expectLater(
      read.timeout(const Duration(seconds: 1)),
      throwsA(anything),
    );
    expect(await destination.exists(), isFalse);
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
