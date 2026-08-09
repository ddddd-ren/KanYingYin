import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_relay_protocol.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_relay_session.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_remote_reader.dart';
import 'package:kanyingyin/services/cloud/quark/quark_range_remote_reader.dart';

void main() {
  late Directory directory;
  late HttpServer remoteServer;
  late QuarkRangeRemoteReader reader;
  late CloudRangeRelaySession session;
  final sourceBytes = <int>[for (var value = 0; value < 20; value++) value];
  var activeRequests = 0;
  var maxActiveRequests = 0;

  test('Windows 与 Android 使用各自的吞吐和缓存调优', () {
    final windows = CloudRangeRelayTuning.forPlatform(
      AppPlatformCapabilities.windows,
    );
    final android = CloudRangeRelayTuning.forPlatform(
      AppPlatformCapabilities.android,
    );

    expect(windows.chunkSize, 4 * 1024 * 1024);
    expect(windows.maxChunks, 64);
    expect(
      windows.chunkSize * windows.maxChunks,
      256 * 1024 * 1024,
    );
    expect(windows.maxConcurrentReads, 5);
    expect(windows.maxConcurrentPrefetch, 4);
    expect(windows.prefetchAheadChunks, 8);

    expect(android.chunkSize, 4 * 1024 * 1024);
    expect(android.maxChunks, 32);
    expect(android.chunkSize * android.maxChunks, 128 * 1024 * 1024);
    expect(android.maxConcurrentReads, 4);
    expect(android.maxConcurrentPrefetch, 3);
    expect(android.prefetchAheadChunks, 6);
  });

  test('Android TV 使用低峰值分段与单路预取', () {
    const tuning = CloudRangeRelayTuning.androidTv;

    expect(tuning.chunkSize, 2 * 1024 * 1024);
    expect(tuning.maxChunks, 16);
    expect(tuning.maxConcurrentReads, 3);
    expect(tuning.maxConcurrentPrefetch, 1);
    expect(tuning.prefetchAheadChunks, 2);
    expect(tuning.adaptivePolicy, isNull);
    expect(tuning.prefetchTailOnStart, isFalse);
  });

  test('Android TV 启动预取不会读取文件尾分段', () async {
    final tvDirectory =
        await Directory.systemTemp.createTemp('cloud-relay-tv-tail-');
    final tvReader = _DelayedRangeReader(
      totalLength: 12,
      delay: const Duration(milliseconds: 20),
    );
    final tvSession = await CloudRangeRelaySession.start(
      reader: tvReader,
      directory: tvDirectory,
      providerName: '电视测试网盘',
      tuning: CloudRangeRelayTuning.androidTv,
      chunkSize: 4,
      maxChunks: 4,
    );
    try {
      await _waitUntil(() => tvReader.readRanges.isNotEmpty);
      expect(
        tvReader.readRanges.map((range) => range.start),
        isNot(contains(8)),
      );
    } finally {
      await tvSession.close();
      if (await tvDirectory.exists()) {
        await tvDirectory.delete(recursive: true);
      }
    }
  });

  test('并发分段速度按墙钟时间聚合而不是相加每路耗时', () async {
    const chunkSize = 256 * 1024;
    final speedDirectory =
        await Directory.systemTemp.createTemp('cloud-relay-speed-');
    final speedReader = _DelayedRangeReader(
      totalLength: chunkSize * 2,
      delay: const Duration(milliseconds: 500),
    );
    final speedSession = await CloudRangeRelaySession.start(
      reader: speedReader,
      directory: speedDirectory,
      providerName: '测试网盘',
      chunkSize: chunkSize,
      maxChunks: 2,
    );
    try {
      await _waitUntil(
        () => speedSession.currentStatus.receivedBytes >= chunkSize * 2,
      );

      expect(speedReader.maxActiveReads, 2);
      expect(
        speedSession.currentStatus.bytesPerSecond,
        greaterThan(768 * 1024),
      );
    } finally {
      await speedSession.close();
    }
  });

  test('Android 会话连续播放时启用三路后台预取', () async {
    final androidDirectory =
        await Directory.systemTemp.createTemp('cloud-relay-android-');
    final androidReader = _DelayedRangeReader(
      totalLength: 32,
      delay: const Duration(milliseconds: 100),
    );
    final androidSession = await CloudRangeRelaySession.start(
      reader: androidReader,
      directory: androidDirectory,
      providerName: '测试网盘',
      tuning: CloudRangeRelayTuning.android,
      chunkSize: 4,
      maxChunks: 8,
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final request = await client.getUrl(androidSession.uri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-19');
      await (await request.close()).drain<void>();

      expect(androidReader.maxActiveReads, greaterThanOrEqualTo(3));
      expect(
        androidReader.maxActiveReads,
        lessThanOrEqualTo(CloudRangeRelayTuning.android.maxConcurrentReads),
      );
    } finally {
      client.close(force: true);
      await androidSession.close();
    }
  });

  test('Android 夸克百度高吞吐会话连续播放时达到五路后台预取', () async {
    final highThroughputDirectory = await Directory.systemTemp.createTemp(
      'cloud-relay-high-throughput-',
    );
    final highThroughputReader = _DelayedRangeReader(
      totalLength: 64,
      delay: const Duration(milliseconds: 100),
    );
    final highThroughputSession = await CloudRangeRelaySession.start(
      reader: highThroughputReader,
      directory: highThroughputDirectory,
      providerName: '测试网盘',
      tuning: CloudRangeRelayTuning.androidHighThroughput,
      chunkSize: 4,
      maxChunks: 16,
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final request = await client.getUrl(highThroughputSession.uri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-19');
      await (await request.close()).drain<void>();

      expect(highThroughputReader.maxActiveReads, greaterThanOrEqualTo(5));
      expect(
        highThroughputReader.maxActiveReads,
        lessThanOrEqualTo(
          CloudRangeRelayTuning.androidHighThroughput.maxConcurrentReads,
        ),
      );
    } finally {
      client.close(force: true);
      await highThroughputSession.close();
    }
  });

  test('夸克前台缓存压力升为八路且重连后退回六路', () async {
    final adaptiveDirectory =
        await Directory.systemTemp.createTemp('cloud-relay-adaptive-');
    final adaptiveReader = _AdaptiveRangeReader(
      totalLength: 512,
      delay: const Duration(milliseconds: 100),
    );
    final logs = <String>[];
    final adaptiveSession = await CloudRangeRelaySession.start(
      reader: adaptiveReader,
      directory: adaptiveDirectory,
      providerName: '夸克',
      tuning: CloudRangeRelayTuning.androidQuarkAdaptive,
      chunkSize: 4,
      maxChunks: 48,
      log: logs.add,
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      expect(adaptiveSession.adaptiveMode, CloudRangeRelayAdaptiveMode.base);
      expect(adaptiveSession.currentMaxConcurrentReads, 6);

      final request = await client.getUrl(adaptiveSession.uri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=64-95');
      await (await request.close()).drain<void>();

      expect(
        adaptiveSession.adaptiveMode,
        CloudRangeRelayAdaptiveMode.boosted,
      );
      expect(adaptiveSession.currentMaxConcurrentReads, 8);
      expect(adaptiveSession.currentMaxConcurrentPrefetch, 7);
      final combined = logs.join('\n');
      expect(combined, contains('foreground_cache_pressure'));
      expect(combined, isNot(contains(_AdaptiveRangeReader.secretUri)));
      expect(combined, isNot(contains(_AdaptiveRangeReader.secretCookie)));
      expect(combined, isNot(contains('chunk-private-path')));

      adaptiveReader.emit(CloudRangeReaderEvent.reconnecting);
      expect(adaptiveSession.adaptiveMode, CloudRangeRelayAdaptiveMode.base);
      expect(adaptiveSession.currentMaxConcurrentReads, 6);
      expect(logs.join('\n'), contains('reconnecting'));
    } finally {
      client.close(force: true);
      await adaptiveSession.close();
    }

    expect(logs.join('\n'), contains('event=session_closed'));
    expect(logs.join('\n'), contains('receivedBytes='));
  });

  test('夸克降档后再次出现前台缓存压力可以重新升档', () async {
    final adaptiveDirectory =
        await Directory.systemTemp.createTemp('cloud-relay-readaptive-');
    final adaptiveReader = _AdaptiveRangeReader(
      totalLength: 512,
      delay: const Duration(milliseconds: 100),
    );
    final logs = <String>[];
    final adaptiveSession = await CloudRangeRelaySession.start(
      reader: adaptiveReader,
      directory: adaptiveDirectory,
      providerName: '夸克',
      tuning: CloudRangeRelayTuning.androidQuarkAdaptive,
      chunkSize: 4,
      maxChunks: 48,
      log: logs.add,
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final first = await client.getUrl(adaptiveSession.uri);
      first.headers.set(HttpHeaders.rangeHeader, 'bytes=64-95');
      await (await first.close()).drain<void>();
      expect(
        adaptiveSession.adaptiveMode,
        CloudRangeRelayAdaptiveMode.boosted,
      );

      adaptiveReader.emit(CloudRangeReaderEvent.refreshing);
      expect(adaptiveSession.adaptiveMode, CloudRangeRelayAdaptiveMode.base);

      final second = await client.getUrl(adaptiveSession.uri);
      second.headers.set(HttpHeaders.rangeHeader, 'bytes=256-287');
      await (await second.close()).drain<void>();

      expect(
        adaptiveSession.adaptiveMode,
        CloudRangeRelayAdaptiveMode.boosted,
      );
      expect(adaptiveSession.currentMaxConcurrentReads, 8);
      expect(adaptiveReader.maxActiveReads, lessThanOrEqualTo(8));
      expect(logs.join('\n'), contains('refreshing'));
    } finally {
      client.close(force: true);
      await adaptiveSession.close();
    }
  });

  test('天玑 930 夸克前台缓存压力升为十路且重连后退回八路', () async {
    final adaptiveDirectory =
        await Directory.systemTemp.createTemp('cloud-relay-mt6877-');
    final adaptiveReader = _AdaptiveRangeReader(
      totalLength: 1024,
      delay: const Duration(milliseconds: 100),
    );
    final logs = <String>[];
    final adaptiveSession = await CloudRangeRelaySession.start(
      reader: adaptiveReader,
      directory: adaptiveDirectory,
      providerName: '夸克',
      tuning: CloudRangeRelayTuning.androidQuarkMt6877,
      chunkSize: 4,
      maxChunks: 64,
      log: logs.add,
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      expect(adaptiveSession.adaptiveMode, CloudRangeRelayAdaptiveMode.base);
      expect(adaptiveSession.currentMaxConcurrentReads, 8);
      expect(adaptiveSession.currentMaxConcurrentPrefetch, 7);

      final request = await client.getUrl(adaptiveSession.uri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=128-191');
      await (await request.close()).drain<void>();

      expect(
        adaptiveSession.adaptiveMode,
        CloudRangeRelayAdaptiveMode.boosted,
      );
      expect(adaptiveSession.currentMaxConcurrentReads, 10);
      expect(adaptiveSession.currentMaxConcurrentPrefetch, 9);
      expect(adaptiveReader.maxActiveReads, lessThanOrEqualTo(10));

      adaptiveReader.emit(CloudRangeReaderEvent.reconnecting);
      expect(adaptiveSession.adaptiveMode, CloudRangeRelayAdaptiveMode.base);
      expect(adaptiveSession.currentMaxConcurrentReads, 8);
      expect(logs.join('\n'), contains('reconnecting'));
    } finally {
      client.close(force: true);
      await adaptiveSession.close();
    }
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cloud-relay-test-');
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
    session = await CloudRangeRelaySession.start(
      reader: reader,
      directory: directory,
      providerName: '夸克网盘',
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

  test('跨段读取准确且远端并发不超过平台限制', () async {
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
    expect(
      maxActiveRequests,
      lessThanOrEqualTo(CloudRangeRelayTuning.windows.maxConcurrentReads),
    );
    client.close(force: true);
  });

  test('成功读取后发布就绪速度与缓存状态', () async {
    final statuses = <CloudRangeRelayStatus>[];
    final subscription = session.statuses.listen(statuses.add);
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    final request = await client.getUrl(session.uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=4-7');
    await (await request.close()).drain<void>();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(session.currentStatus.phase, CloudRangeRelayPhase.ready);
    expect(session.currentStatus.receivedBytes, greaterThan(0));
    expect(session.currentStatus.cachedBytes, greaterThan(0));
    expect(statuses.any((status) => status.phase == CloudRangeRelayPhase.ready),
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

  test('远端不支持 Range 时只允许完整顺序流', () async {
    await session.close();
    final fallbackDirectory =
        await Directory.systemTemp.createTemp('cloud-relay-fallback-');
    final fallbackReader = _SequentialOnlyReader(<int>[1, 2, 3, 4, 5]);
    session = await CloudRangeRelaySession.start(
      reader: fallbackReader,
      directory: fallbackDirectory,
      providerName: '测试网盘',
      chunkSize: 2,
      maxChunks: 2,
    );
    final client = HttpClient()..findProxy = (_) => 'DIRECT';

    final head = await client.openUrl('HEAD', session.uri);
    final headResponse = await head.close();
    expect(headResponse.headers.value(HttpHeaders.acceptRangesHeader), isNull);
    await headResponse.drain<void>();

    final ranged = await client.getUrl(session.uri);
    ranged.headers.set(HttpHeaders.rangeHeader, 'bytes=1-3');
    final rangedResponse = await ranged.close();
    expect(
      rangedResponse.statusCode,
      HttpStatus.requestedRangeNotSatisfiable,
    );
    await rangedResponse.drain<void>();

    final full = await client.getUrl(session.uri);
    final fullResponse = await full.close();
    expect(await _readResponse(fullResponse), <int>[1, 2, 3, 4, 5]);
    expect(fallbackReader.readToCalls, 0);
    expect(fallbackReader.streamAllCalls, 1);
    expect(await fallbackDirectory.list().toList(), isEmpty);
    client.close(force: true);
  });
}

Future<List<int>> _readResponse(HttpClientResponse response) =>
    response.fold(<int>[], (bytes, chunk) => bytes..addAll(chunk));

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!predicate()) {
    if (stopwatch.elapsed >= timeout) {
      throw TimeoutException('等待测试条件超时', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _DelayedRangeReader implements CloudRangeRemoteReader {
  _DelayedRangeReader({required this.totalLength, required this.delay});

  @override
  final int totalLength;
  final Duration delay;
  var activeReads = 0;
  var maxActiveReads = 0;
  final List<ByteRange> readRanges = <ByteRange>[];

  @override
  String get contentType => 'video/mp4';

  @override
  Stream<CloudRangeReaderEvent> get events =>
      const Stream<CloudRangeReaderEvent>.empty();

  @override
  Future<CloudRangeRemoteMetadata> probe() async => CloudRangeRemoteMetadata(
        totalLength: totalLength,
        contentType: contentType,
        supportsRanges: true,
      );

  @override
  Future<void> readTo(ByteRange range, File destination) async {
    readRanges.add(range);
    activeReads++;
    if (activeReads > maxActiveReads) maxActiveReads = activeReads;
    try {
      await Future<void>.delayed(delay);
      await destination.writeAsBytes(
        List<int>.filled(range.length, 0),
        flush: true,
      );
    } finally {
      activeReads--;
    }
  }

  @override
  Future<void> streamAll(IOSink destination) async =>
      throw StateError('测试读取器只支持 Range');

  @override
  Future<void> close() async {}
}

class _AdaptiveRangeReader extends _DelayedRangeReader {
  _AdaptiveRangeReader({
    required super.totalLength,
    required super.delay,
  });

  final StreamController<CloudRangeReaderEvent> eventController =
      StreamController<CloudRangeReaderEvent>.broadcast(sync: true);

  static const secretUri = 'https://secret.example/video?id=private';
  static const secretCookie = 'Cookie: secret-cookie';

  @override
  Stream<CloudRangeReaderEvent> get events => eventController.stream;

  void emit(CloudRangeReaderEvent event) => eventController.add(event);

  @override
  String toString() => '$secretUri $secretCookie chunk-private-path';

  @override
  Future<void> close() async {
    await eventController.close();
  }
}

class _SequentialOnlyReader implements CloudRangeRemoteReader {
  _SequentialOnlyReader(this.bytes);

  final List<int> bytes;
  int readToCalls = 0;
  int streamAllCalls = 0;

  @override
  String get contentType => 'video/mp4';

  @override
  Stream<CloudRangeReaderEvent> get events =>
      const Stream<CloudRangeReaderEvent>.empty();

  @override
  int? get totalLength => bytes.length;

  @override
  Future<void> close() async {}

  @override
  Future<CloudRangeRemoteMetadata> probe() async => CloudRangeRemoteMetadata(
        totalLength: bytes.length,
        contentType: contentType,
        supportsRanges: false,
      );

  @override
  Future<void> readTo(ByteRange range, File destination) async {
    readToCalls++;
    throw StateError('不应分段读取');
  }

  @override
  Future<void> streamAll(IOSink destination) async {
    streamAllCalls++;
    destination.add(bytes);
  }
}
