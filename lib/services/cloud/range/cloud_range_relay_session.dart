import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_chunk_cache.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_relay_protocol.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_remote_reader.dart';

class CloudRangeRelaySession implements CloudPlaybackLease {
  CloudRangeRelaySession._({
    required CloudRangeRemoteReader reader,
    required this.directory,
    required this.providerName,
    required this.chunkSize,
    required this.maxChunks,
  }) : _reader = reader;

  static Future<CloudRangeRelaySession> start({
    required CloudRangeRemoteReader reader,
    required Directory directory,
    required String providerName,
    int chunkSize = 16 * 1024 * 1024,
    int maxChunks = 16,
  }) async {
    final session = CloudRangeRelaySession._(
      reader: reader,
      directory: directory,
      providerName: providerName,
      chunkSize: chunkSize,
      maxChunks: maxChunks,
    );
    try {
      await session._start();
      return session;
    } on Object {
      await session.close();
      rethrow;
    }
  }

  final CloudRangeRemoteReader _reader;
  final Directory directory;
  final String providerName;
  final int chunkSize;
  final int maxChunks;
  final _ReadScheduler _scheduler = _ReadScheduler(maxConcurrent: 2);
  final StreamController<CloudRangeRelayStatus> _statuses =
      StreamController<CloudRangeRelayStatus>.broadcast(sync: true);
  final Queue<_TransferSample> _transferSamples = Queue<_TransferSample>();
  final Set<Future<void>> _prefetchTasks = <Future<void>>{};
  final Set<Future<void>> _requestTasks = <Future<void>>{};

  CloudRangeChunkCache? _cache;
  HttpServer? _server;
  StreamSubscription<CloudRangeReaderEvent>? _readerEvents;
  late Uri _uri;
  late var _status = CloudRangeRelayStatus(
    providerName: providerName,
    phase: CloudRangeRelayPhase.connecting,
  );
  late int _totalLength;
  var _supportsRanges = false;
  var _receivedBytes = 0;
  var _prefetchGeneration = 0;
  int? _lastForegroundChunk;
  var _closed = false;
  Future<void>? _closeFuture;

  Uri get uri => _uri;
  int get totalLength => _totalLength;
  String get contentType => _reader.contentType;

  @override
  CloudRangeRelayStatus get currentStatus => _status;

  @override
  Stream<CloudRangeRelayStatus> get statuses => _statuses.stream;

  Future<void> _start() async {
    _readerEvents = _reader.events.listen((event) {
      if (event == CloudRangeReaderEvent.reconnecting ||
          event == CloudRangeReaderEvent.refreshing) {
        _publish(
          phase: CloudRangeRelayPhase.reconnecting,
          message: '$providerName正在重新连接',
        );
      }
    });
    final metadata = await _reader.probe();
    if (_closed) throw StateError('中转会话已关闭');
    _totalLength = metadata.totalLength;
    _supportsRanges = metadata.supportsRanges;
    if (_supportsRanges) {
      _cache = CloudRangeChunkCache(
        directory: directory,
        totalLength: metadata.totalLength,
        chunkSize: chunkSize,
        maxChunks: maxChunks,
      );
    }
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    _server = server;
    final token = _createToken();
    _uri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: '/$token',
    );
    server.listen((request) {
      late final Future<void> task;
      task = _handleRequest(request).whenComplete(() {
        _requestTasks.remove(task);
      });
      _requestTasks.add(task);
    });
    if (_supportsRanges) {
      _publish(
        phase: CloudRangeRelayPhase.prefetching,
        message: '$providerName预缓冲中',
      );
      _launchPrefetch(0, _prefetchGeneration);
      if (metadata.totalLength > chunkSize) {
        final tailOffset =
            ((metadata.totalLength - 1) ~/ chunkSize) * chunkSize;
        _launchPrefetch(tailOffset, _prefetchGeneration);
      }
    } else {
      _publish(
        phase: CloudRangeRelayPhase.ready,
        message: '$providerName仅支持顺序播放，拖动不可用',
      );
    }
  }

  String _createToken() {
    final random = Random.secure();
    return <int>[for (var index = 0; index < 16; index++) random.nextInt(256)]
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response..bufferOutput = false;
    try {
      if (!_isAuthorizedLocalRequest(request)) {
        await _emptyResponse(response, HttpStatus.notFound);
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        await _emptyResponse(response, HttpStatus.methodNotAllowed);
        return;
      }

      _setCommonHeaders(response);
      if (request.method == 'HEAD') {
        response
          ..statusCode = HttpStatus.ok
          ..contentLength = totalLength;
        await response.close();
        return;
      }

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      if (!_supportsRanges) {
        if (rangeHeader != null) {
          try {
            final requested = parseSingleHttpRange(rangeHeader, totalLength);
            if (requested.start != 0 ||
                requested.endInclusive != totalLength - 1) {
              throw RangeNotSatisfiable(totalLength);
            }
          } on RangeNotSatisfiable catch (error) {
            response.headers.set(
              HttpHeaders.contentRangeHeader,
              error.contentRange,
            );
            await _emptyResponse(
              response,
              HttpStatus.requestedRangeNotSatisfiable,
            );
            return;
          }
        }
        response
          ..statusCode = HttpStatus.ok
          ..contentLength = totalLength;
        await _reader.streamAll(response);
        await response.close();
        _publish(phase: CloudRangeRelayPhase.ready);
        return;
      }
      late final ByteRange range;
      if (rangeHeader == null) {
        range = ByteRange(0, totalLength - 1);
        response.statusCode = HttpStatus.ok;
      } else {
        try {
          range = parseSingleHttpRange(rangeHeader, totalLength);
        } on RangeNotSatisfiable catch (error) {
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            error.contentRange,
          );
          await _emptyResponse(
            response,
            HttpStatus.requestedRangeNotSatisfiable,
          );
          return;
        }
        response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            range.contentRange(totalLength),
          );
      }
      response.contentLength = range.length;
      await _serveRange(response, range);
      await response.close();
    } on Object catch (error) {
      if (error is CloudRangeRemoteProtocolException ||
          error is CloudRangeRemoteAuthenticationException ||
          error is CloudRangeRemoteTransportException ||
          error is CloudChunkLoadException) {
        _publish(
          phase: CloudRangeRelayPhase.failed,
          message: '$providerName分段读取失败',
        );
      }
      try {
        response
          ..statusCode = HttpStatus.badGateway
          ..contentLength = 0;
      } on Object {
        // 响应已经开始时只能关闭连接，不能再修改状态码。
      }
      try {
        await response.close();
      } on Object {
        // 客户端主动断开不影响中转会话继续服务其他请求。
      }
    }
  }

  bool _isAuthorizedLocalRequest(HttpRequest request) {
    if (request.connectionInfo?.remoteAddress.address !=
        InternetAddress.loopbackIPv4.address) {
      return false;
    }
    final host = request.headers.host?.toLowerCase();
    return host == InternetAddress.loopbackIPv4.address &&
        request.uri.path == _uri.path;
  }

  void _setCommonHeaders(HttpResponse response) {
    if (_supportsRanges) {
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    }
    response.headers
      ..set(HttpHeaders.contentTypeHeader, contentType)
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
  }

  Future<void> _emptyResponse(HttpResponse response, int statusCode) async {
    response
      ..statusCode = statusCode
      ..contentLength = 0;
    await response.close();
  }

  Future<void> _serveRange(HttpResponse response, ByteRange requested) async {
    final generation = _noteForegroundRequest(requested.start);
    var current = requested.start;
    while (current <= requested.endInclusive && !_closed) {
      final handle = await _acquireChunk(
        current,
        priority: _ReadPriority.foreground,
      );
      try {
        final end = handle.range.endInclusive < requested.endInclusive
            ? handle.range.endInclusive
            : requested.endInclusive;
        await response.addStream(
          handle.openRead(start: current, endInclusive: end),
        );
        current = end + 1;
        _launchSequentialPrefetch(handle.range, generation);
      } finally {
        await handle.release();
      }
    }
  }

  int _noteForegroundRequest(int offset) {
    final chunkIndex = offset ~/ chunkSize;
    final previous = _lastForegroundChunk;
    if (previous != null && (chunkIndex - previous).abs() > 1) {
      _prefetchGeneration++;
    }
    _lastForegroundChunk = chunkIndex;
    return _prefetchGeneration;
  }

  Future<CloudRangeChunkHandle> _acquireChunk(
    int offset, {
    required _ReadPriority priority,
  }) async {
    final cache = _cache!;
    final handle = await cache.acquire(offset, (range, destination) async {
      await _scheduler.run(priority, () async {
        final stopwatch = Stopwatch()..start();
        await _reader.readTo(range, destination);
        stopwatch.stop();
        _recordTransfer(range.length, stopwatch.elapsed);
      });
    });
    _publish(phase: CloudRangeRelayPhase.ready);
    return handle;
  }

  void _launchSequentialPrefetch(ByteRange current, int generation) {
    for (var distance = 1; distance <= 2; distance++) {
      final offset = current.start + distance * chunkSize;
      if (offset < totalLength) _launchPrefetch(offset, generation);
    }
  }

  void _launchPrefetch(int offset, int generation) {
    if (_closed || offset < 0 || offset >= totalLength) return;
    late final Future<void> task;
    task = _prefetch(offset, generation)
        .catchError((Object _) {})
        .whenComplete(() => _prefetchTasks.remove(task));
    _prefetchTasks.add(task);
  }

  Future<void> _prefetch(int offset, int generation) async {
    if (_closed || generation != _prefetchGeneration) return;
    final handle = await _acquireChunk(
      offset,
      priority: _ReadPriority.prefetch,
    );
    await handle.release();
  }

  void _recordTransfer(int bytes, Duration elapsed) {
    final now = DateTime.now();
    _receivedBytes += bytes;
    _transferSamples.add(_TransferSample(now, bytes, elapsed));
    final cutoff = now.subtract(const Duration(seconds: 5));
    while (_transferSamples.isNotEmpty &&
        _transferSamples.first.completedAt.isBefore(cutoff)) {
      _transferSamples.removeFirst();
    }
  }

  double get _bytesPerSecond {
    var bytes = 0;
    var microseconds = 0;
    for (final sample in _transferSamples) {
      bytes += sample.bytes;
      microseconds += sample.elapsed.inMicroseconds;
    }
    if (bytes == 0 || microseconds <= 0) return 0;
    return bytes * Duration.microsecondsPerSecond / microseconds;
  }

  void _publish({
    required CloudRangeRelayPhase phase,
    String? message,
  }) {
    if (_closed || _statuses.isClosed) return;
    final status = CloudRangeRelayStatus(
      providerName: providerName,
      phase: phase,
      bytesPerSecond: _bytesPerSecond,
      receivedBytes: _receivedBytes,
      cachedBytes: _cache?.cachedBytes ?? 0,
      message: message,
    );
    _status = status;
    _statuses.add(status);
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    _prefetchGeneration++;
    await _server?.close(force: true);
    _scheduler.close();
    await _readerEvents?.cancel();
    await _reader.close();
    for (final task in _requestTasks.toList()) {
      try {
        await task;
      } on Object {
        // 关闭中被取消的本机请求无需继续传播。
      }
    }
    for (final task in _prefetchTasks.toList()) {
      try {
        await task;
      } on Object {
        // 关闭中被取消的预取无需继续传播。
      }
    }
    await _cache?.close();
    if (_cache == null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await _statuses.close();
  }
}

enum _ReadPriority { foreground, prefetch }

class _ReadScheduler {
  _ReadScheduler({required this.maxConcurrent});

  final int maxConcurrent;
  final Queue<_ScheduledRead> _foreground = Queue<_ScheduledRead>();
  final Queue<_ScheduledRead> _prefetch = Queue<_ScheduledRead>();
  var _active = 0;
  var _closed = false;

  Future<void> run(_ReadPriority priority, Future<void> Function() action) {
    if (_closed) return Future<void>.error(StateError('远程读取调度器已关闭'));
    final scheduled = _ScheduledRead(action);
    switch (priority) {
      case _ReadPriority.foreground:
        _foreground.add(scheduled);
      case _ReadPriority.prefetch:
        _prefetch.add(scheduled);
    }
    _drain();
    return scheduled.completer.future;
  }

  void _drain() {
    while (!_closed && _active < maxConcurrent) {
      final scheduled = _foreground.isNotEmpty
          ? _foreground.removeFirst()
          : _prefetch.isNotEmpty
              ? _prefetch.removeFirst()
              : null;
      if (scheduled == null) return;
      _active++;
      scheduled.action().then(
        (_) => scheduled.completer.complete(),
        onError: (Object error, StackTrace stackTrace) {
          scheduled.completer.completeError(error, stackTrace);
        },
      ).whenComplete(() {
        _active--;
        _drain();
      });
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final error = StateError('远程读取调度器已关闭');
    for (final queue in <Queue<_ScheduledRead>>[_foreground, _prefetch]) {
      while (queue.isNotEmpty) {
        queue.removeFirst().completer.completeError(error);
      }
    }
  }
}

class _ScheduledRead {
  _ScheduledRead(this.action);

  final Future<void> Function() action;
  final Completer<void> completer = Completer<void>();
}

class _TransferSample {
  const _TransferSample(this.completedAt, this.bytes, this.elapsed);

  final DateTime completedAt;
  final int bytes;
  final Duration elapsed;
}
