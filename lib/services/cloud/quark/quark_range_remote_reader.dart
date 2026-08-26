import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:kanyingyin/services/cloud/range/cloud_range_relay_protocol.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_remote_reader.dart';
import 'package:kanyingyin/services/cloud/quark/quark_request_policy.dart';
import 'package:kanyingyin/utils/logger.dart';

typedef QuarkRemoteResourceRefresher = Future<QuarkRemoteResource> Function();
typedef QuarkRemoteUriValidator = bool Function(Uri uri);
typedef QuarkHttpClientFactory = HttpClient Function();
typedef QuarkRetryDelay = Future<void> Function(Duration duration);
typedef QuarkRangeRemoteLog = void Function(String message);

typedef QuarkRemoteReaderEvent = CloudRangeReaderEvent;

class QuarkRemoteResource extends CloudRangeRemoteResource {
  QuarkRemoteResource({
    required super.uri,
    super.headers,
    super.totalLength,
    super.contentType,
  });

  @override
  QuarkRemoteResource copyWith({
    Uri? uri,
    Map<String, String>? headers,
    int? totalLength,
    String? contentType,
  }) =>
      QuarkRemoteResource(
        uri: uri ?? this.uri,
        headers: headers ?? this.headers,
        totalLength: totalLength ?? this.totalLength,
        contentType: contentType ?? this.contentType,
      );
}

class QuarkRemoteMetadata extends CloudRangeRemoteMetadata {
  const QuarkRemoteMetadata({
    required super.totalLength,
    required super.contentType,
    super.supportsRanges = true,
  });
}

class QuarkRemoteProtocolException extends CloudRangeRemoteProtocolException {
  const QuarkRemoteProtocolException(super.message);

  @override
  String toString() => 'QuarkRemoteProtocolException($message)';
}

class QuarkRemoteAuthenticationException
    extends CloudRangeRemoteAuthenticationException {
  const QuarkRemoteAuthenticationException(super.message);

  @override
  String toString() => 'QuarkRemoteAuthenticationException($message)';
}

class QuarkRemoteTransportException extends CloudRangeRemoteTransportException {
  const QuarkRemoteTransportException(super.message);

  @override
  String toString() => 'QuarkRemoteTransportException($message)';
}

class QuarkRemoteHttpException extends QuarkRemoteProtocolException {
  QuarkRemoteHttpException(this.statusCode) : super('远程 HTTP 状态无效：$statusCode');

  final int statusCode;
}

class QuarkRangeRemoteReader
    implements CloudRangeRemoteReader, CloudRangeAdaptiveRemoteReader {
  QuarkRangeRemoteReader({
    required QuarkRemoteResource resource,
    required QuarkRemoteResourceRefresher refreshResource,
    QuarkRemoteUriValidator? uriValidator,
    QuarkHttpClientFactory? httpClientFactory,
    QuarkRetryDelay? delay,
    QuarkRangeRemoteLog? log,
    this.connectionTimeout = const Duration(seconds: 15),
    this.firstByteTimeout = const Duration(seconds: 25),
    this.readTimeout = const Duration(seconds: 30),
    this.maxConnectionsPerHost = 10,
  })  : assert(connectionTimeout > Duration.zero),
        assert(firstByteTimeout > Duration.zero),
        assert(readTimeout > Duration.zero),
        assert(maxConnectionsPerHost > 0),
        _resource = resource,
        _refreshResource = refreshResource,
        _uriValidator = uriValidator ??
            const QuarkRequestPolicy().isTrustedOriginalDownloadUri,
        _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _delay = delay ?? Future<void>.delayed,
        _log = log ?? ((message) => AppLogger().i(message)) {
    if (!_uriValidator(resource.uri)) {
      throw const QuarkRemoteProtocolException('远程播放地址不在可信范围内');
    }
    _totalLength = resource.totalLength;
    _contentType = resource.contentType ?? 'application/octet-stream';
  }

  static const List<Duration> _retryDelays = <Duration>[
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  QuarkRemoteResource _resource;
  final QuarkRemoteResourceRefresher _refreshResource;
  final QuarkRemoteUriValidator _uriValidator;
  final QuarkHttpClientFactory _httpClientFactory;
  final QuarkRetryDelay _delay;
  final QuarkRangeRemoteLog _log;
  final Duration connectionTimeout;
  final Duration firstByteTimeout;
  final Duration readTimeout;
  final int maxConnectionsPerHost;
  HttpClient? _client;
  final StreamController<CloudRangeReaderEvent> _events =
      StreamController<CloudRangeReaderEvent>.broadcast(sync: true);

  int? _totalLength;
  String _contentType = 'application/octet-stream';
  bool _authRefreshUsed = false;
  Future<void>? _refreshing;
  bool _closed = false;
  Future<void>? _closeFuture;
  int? _minReadSize;
  int? _maxReadSize;
  int? _currentReadSize;
  var _timeoutCount = 0;

  @override
  int? get totalLength => _totalLength;
  @override
  String get contentType => _contentType;
  @override
  Stream<CloudRangeReaderEvent> get events => _events.stream;

  @override
  void configureAdaptiveReads({
    required int minReadSize,
    required int initialReadSize,
    required int maxReadSize,
  }) {
    if (minReadSize <= 0 ||
        initialReadSize < minReadSize ||
        maxReadSize < initialReadSize) {
      throw ArgumentError('自适应远端分块参数无效');
    }
    _minReadSize = minReadSize;
    _maxReadSize = maxReadSize;
    _currentReadSize = initialReadSize;
  }

  @override
  Future<QuarkRemoteMetadata> probe() async {
    final metadata = await _readWithRecovery(const ByteRange(0, 0), null);
    return metadata;
  }

  @override
  Future<void> readTo(ByteRange range, File destination) async {
    try {
      if (await destination.exists()) await destination.delete();
      var current = range.start;
      var destinationOffset = 0;
      while (current <= range.endInclusive) {
        final readSize = _currentReadSize ?? range.length;
        final endInclusive = min(
          range.endInclusive,
          current + readSize - 1,
        );
        final part = ByteRange(current, endInclusive);
        await _readWithRecovery(
          part,
          destination,
          destinationOffset: destinationOffset,
        );
        current = endInclusive + 1;
        destinationOffset += part.length;
      }
    } on Object {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  Future<QuarkRemoteMetadata> _readWithRecovery(
    ByteRange range,
    File? destination, {
    int destinationOffset = 0,
  }) async {
    var transportAttempt = 0;
    while (true) {
      if (_closed) throw StateError('远程读取器已关闭');
      try {
        return await _readOnce(
          range,
          destination,
          destinationOffset: destinationOffset,
        );
      } on _AuthenticationStatusException catch (error) {
        _logFailure(
          range,
          failure: 'authentication',
          statusCode: error.statusCode,
        );
        _emitEvent(CloudRangeReaderEvent.refreshing);
        await _refreshAfterAuthenticationFailure(error.statusCode);
      } on Object catch (error) {
        if (!_isTransportError(error)) {
          _logFailure(
            range,
            failure: _failureClass(error),
            statusCode:
                error is QuarkRemoteHttpException ? error.statusCode : null,
          );
          rethrow;
        }
        final timedOut = error is TimeoutException;
        if (timedOut) {
          _timeoutCount++;
          _currentReadSize = _minReadSize ?? _currentReadSize;
          _emitEvent(CloudRangeReaderEvent.slow);
        }
        _resetClient();
        final retryLimit = timedOut ? 1 : _retryDelays.length;
        if (transportAttempt >= retryLimit) {
          _logFailure(
            range,
            failure: timedOut ? 'timeout' : 'transport',
          );
          throw const QuarkRemoteTransportException('夸克远程连接重试后仍失败');
        }
        _log(
          'QuarkRangeRemoteReader: stage=retry '
          'range=${range.start}-${range.endInclusive} '
          'retry=${transportAttempt + 1} timeoutCount=$_timeoutCount '
          'failure=${timedOut ? "timeout" : "transport"}',
        );
        _emitEvent(CloudRangeReaderEvent.reconnecting);
        await _delay(_retryDelays[transportAttempt]);
        transportAttempt++;
      }
    }
  }

  Future<QuarkRemoteMetadata> _readOnce(
    ByteRange range,
    File? destination, {
    required int destinationOffset,
  }) async {
    final client = _sharedClient();
    var uri = _resource.uri;
    HttpClientResponse? response;
    var ttfb = Duration.zero;
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      if (!_uriValidator(uri)) {
        throw const QuarkRemoteProtocolException('重定向地址不在可信范围内');
      }
      _log(
        'QuarkRangeRemoteReader: stage=request '
        'range=${range.start}-${range.endInclusive}',
      );
      final stopwatch = Stopwatch()..start();
      final request = await client.getUrl(uri).timeout(connectionTimeout);
      request.followRedirects = false;
      _setRequestHeaders(request, _resource.headers);
      request.headers.set(
        HttpHeaders.rangeHeader,
        'bytes=${range.start}-${range.endInclusive}',
      );
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      response = await request.close().timeout(firstByteTimeout);
      ttfb = stopwatch.elapsed;
      _log(
        'QuarkRangeRemoteReader: stage=response '
        'range=${range.start}-${range.endInclusive} '
        'status=${response.statusCode} ttfbMs=${ttfb.inMilliseconds}',
      );

      if (_isRedirect(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await _closeResponseConnection(response);
        if (location == null || redirectCount == 5) {
          throw const QuarkRemoteProtocolException('远程重定向响应无效');
        }
        final redirected = uri.resolve(location);
        if (!_uriValidator(redirected)) {
          throw const QuarkRemoteProtocolException('重定向地址不在可信范围内');
        }
        uri = redirected;
        continue;
      }
      break;
    }

    if (response == null) {
      throw const QuarkRemoteProtocolException('远程响应为空');
    }
    if (_isAuthenticationStatus(response.statusCode)) {
      await _closeResponseConnection(response);
      throw _AuthenticationStatusException(response.statusCode);
    }
    if (destination == null &&
        range.start == 0 &&
        range.endInclusive == 0 &&
        response.statusCode == HttpStatus.ok) {
      final total = response.contentLength >= 0
          ? response.contentLength
          : _resource.totalLength;
      if (total == null || total <= 0) {
        throw const QuarkRemoteProtocolException('远程完整响应缺少文件长度');
      }
      if (_totalLength != null && _totalLength != total) {
        throw const QuarkRemoteProtocolException('远程文件总长度发生变化');
      }
      final mimeType = response.headers.contentType?.mimeType;
      final metadata = QuarkRemoteMetadata(
        totalLength: total,
        contentType: mimeType == null || mimeType.isEmpty
            ? _contentType
            : mimeType.toLowerCase(),
        supportsRanges: false,
      );
      _resource = _resource.copyWith(
        uri: uri,
        totalLength: metadata.totalLength,
        contentType: metadata.contentType,
      );
      _totalLength = metadata.totalLength;
      _contentType = metadata.contentType;
      await _closeResponseConnection(response);
      return metadata;
    }
    if (response.statusCode != HttpStatus.partialContent) {
      final statusCode = response.statusCode;
      await _closeResponseConnection(response);
      throw QuarkRemoteHttpException(statusCode);
    }

    final metadata = _validateResponse(response, range);
    _resource = _resource.copyWith(
      uri: uri,
      totalLength: metadata.totalLength,
      contentType: metadata.contentType,
    );
    _totalLength = metadata.totalLength;
    _contentType = metadata.contentType;

    RandomAccessFile? output;
    var received = 0;
    final bodyStopwatch = Stopwatch()..start();
    try {
      if (destination != null) {
        output = await destination.open(mode: FileMode.append);
        await output.truncate(destinationOffset);
      }
      await for (final chunk in response.timeout(readTimeout)) {
        received += chunk.length;
        await output?.writeFrom(chunk);
      }
      if (received != range.length) {
        throw QuarkRemoteProtocolException(
          '远程分段长度不符：期望 ${range.length}，实际 $received',
        );
      }
      await output?.flush();
    } finally {
      await output?.close();
    }
    if (destination != null) {
      _recordTransfer(range, ttfb: ttfb, elapsed: bodyStopwatch.elapsed);
    }
    return metadata;
  }

  QuarkRemoteMetadata _validateResponse(
    HttpClientResponse response,
    ByteRange requested,
  ) {
    final value = response.headers.value(HttpHeaders.contentRangeHeader);
    final match = value == null
        ? null
        : RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value.trim());
    if (match == null) {
      throw const QuarkRemoteProtocolException('远程 Content-Range 缺失或无效');
    }
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    if (start != requested.start ||
        end != requested.endInclusive ||
        total == null ||
        total <= requested.endInclusive) {
      throw const QuarkRemoteProtocolException('远程 Content-Range 与请求不一致');
    }
    if (_totalLength != null && _totalLength != total) {
      throw const QuarkRemoteProtocolException('远程文件总长度发生变化');
    }
    if (response.contentLength >= 0 &&
        response.contentLength != requested.length) {
      throw const QuarkRemoteProtocolException('远程 Content-Length 与请求不一致');
    }
    final mimeType = response.headers.contentType?.mimeType;
    return QuarkRemoteMetadata(
      totalLength: total,
      contentType: mimeType == null || mimeType.isEmpty
          ? _contentType
          : mimeType.toLowerCase(),
    );
  }

  @override
  Future<void> streamAll(IOSink destination) async {
    if (_closed) throw StateError('远程读取器已关闭');
    final client = _sharedClient();
    var uri = _resource.uri;
    HttpClientResponse? response;
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      if (!_uriValidator(uri)) {
        throw const QuarkRemoteProtocolException('重定向地址不在可信范围内');
      }
      final request = await client.getUrl(uri).timeout(connectionTimeout);
      request.followRedirects = false;
      _setRequestHeaders(request, _resource.headers);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      response = await request.close().timeout(firstByteTimeout);
      if (_isRedirect(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await _closeResponseConnection(response);
        if (location == null || redirectCount == 5) {
          throw const QuarkRemoteProtocolException('远程重定向响应无效');
        }
        final redirected = uri.resolve(location);
        if (!_uriValidator(redirected)) {
          throw const QuarkRemoteProtocolException('重定向地址不在可信范围内');
        }
        uri = redirected;
        continue;
      }
      break;
    }
    if (response == null || response.statusCode != HttpStatus.ok) {
      final statusCode = response?.statusCode;
      if (response != null) await _closeResponseConnection(response);
      if (statusCode != null) throw QuarkRemoteHttpException(statusCode);
      throw const QuarkRemoteProtocolException('远程完整响应状态无效');
    }
    final expected = _totalLength ?? response.contentLength;
    if (expected <= 0) {
      throw const QuarkRemoteProtocolException('远程完整响应缺少文件长度');
    }
    var received = 0;
    await for (final chunk in response.timeout(readTimeout)) {
      received += chunk.length;
      destination.add(chunk);
    }
    if (received != expected) {
      throw QuarkRemoteProtocolException(
        '远程完整响应长度不符：期望 $expected，实际 $received',
      );
    }
    _resource = _resource.copyWith(uri: uri, totalLength: expected);
    _totalLength = expected;
  }

  Future<void> _refreshAfterAuthenticationFailure(int statusCode) async {
    final existing = _refreshing;
    if (existing != null) return existing;
    if (_authRefreshUsed) {
      throw QuarkRemoteAuthenticationException(
        '夸克播放地址再次失效（HTTP $statusCode）',
      );
    }
    _authRefreshUsed = true;
    final future = _performRefresh(statusCode);
    _refreshing = future;
    try {
      await future;
    } finally {
      if (identical(_refreshing, future)) _refreshing = null;
    }
  }

  Future<void> _performRefresh(int statusCode) async {
    try {
      final refreshed = await _refreshResource();
      if (!_uriValidator(refreshed.uri)) {
        throw const QuarkRemoteProtocolException('刷新后的地址不在可信范围内');
      }
      if (refreshed.totalLength != null &&
          _totalLength != null &&
          refreshed.totalLength != _totalLength) {
        throw const QuarkRemoteProtocolException('刷新后的文件总长度发生变化');
      }
      _resource = refreshed;
    } on QuarkRemoteProtocolException {
      rethrow;
    } on Object {
      throw QuarkRemoteAuthenticationException(
        '夸克播放会话刷新失败（HTTP $statusCode）',
      );
    }
  }

  void _setRequestHeaders(
    HttpClientRequest request,
    Map<String, String> headers,
  ) {
    for (final entry in headers.entries) {
      final name = entry.key.toLowerCase();
      if (name == HttpHeaders.hostHeader ||
          name == HttpHeaders.rangeHeader ||
          name == HttpHeaders.contentLengthHeader ||
          name == HttpHeaders.connectionHeader) {
        continue;
      }
      request.headers.set(entry.key, entry.value);
    }
  }

  bool _isTransportError(Object error) =>
      error is SocketException ||
      error is HandshakeException ||
      error is TimeoutException ||
      error is HttpException;

  bool _isAuthenticationStatus(int statusCode) =>
      statusCode == HttpStatus.unauthorized ||
      statusCode == HttpStatus.forbidden ||
      statusCode == HttpStatus.preconditionFailed;

  bool _isRedirect(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;

  void _recordTransfer(
    ByteRange range, {
    required Duration ttfb,
    required Duration elapsed,
  }) {
    final microseconds = max(1, elapsed.inMicroseconds);
    final bytesPerSecond =
        range.length * Duration.microsecondsPerSecond / microseconds;
    _log(
      'QuarkRangeRemoteReader: stage=complete '
      'range=${range.start}-${range.endInclusive} bytes=${range.length} '
      'ttfbMs=${ttfb.inMilliseconds} '
      'throughputKiBps=${(bytesPerSecond / 1024).round()} '
      'readMs=${elapsed.inMilliseconds}',
    );
    final minReadSize = _minReadSize;
    final maxReadSize = _maxReadSize;
    if (minReadSize == null ||
        maxReadSize == null ||
        minReadSize == maxReadSize) {
      return;
    }
    if (ttfb >= const Duration(seconds: 3) || bytesPerSecond < 1024 * 1024) {
      _currentReadSize = minReadSize;
      _emitEvent(CloudRangeReaderEvent.slow);
      return;
    }
    if (ttfb <= const Duration(seconds: 1) &&
        bytesPerSecond >= 4 * 1024 * 1024) {
      _currentReadSize = maxReadSize;
      _emitEvent(CloudRangeReaderEvent.healthy);
    }
  }

  void _logFailure(
    ByteRange range, {
    required String failure,
    int? statusCode,
  }) {
    _log(
      'QuarkRangeRemoteReader: stage=failed '
      'range=${range.start}-${range.endInclusive} '
      '${statusCode == null ? "" : "status=$statusCode "}'
      'failure=$failure timeoutCount=$_timeoutCount',
    );
  }

  String _failureClass(Object error) => switch (error) {
        QuarkRemoteHttpException() => 'http_status',
        CloudRangeRemoteAuthenticationException() => 'authentication',
        CloudRangeRemoteProtocolException() => 'protocol',
        TimeoutException() => 'timeout',
        _ => 'transport',
      };

  void _emitEvent(CloudRangeReaderEvent event) {
    if (!_closed && !_events.isClosed) _events.add(event);
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  HttpClient _sharedClient() => _client ??= (_httpClientFactory()
    ..connectionTimeout = connectionTimeout
    ..idleTimeout = readTimeout
    ..maxConnectionsPerHost = maxConnectionsPerHost
    ..autoUncompress = false
    ..findProxy = (_) => 'DIRECT');

  void _resetClient() {
    _client?.close(force: true);
    _client = null;
  }

  Future<void> _closeResponseConnection(HttpClientResponse response) async {
    final socket = await response.detachSocket();
    socket.destroy();
  }

  Future<void> _close() async {
    _closed = true;
    _resetClient();
    await _events.close();
  }
}

class _AuthenticationStatusException implements Exception {
  const _AuthenticationStatusException(this.statusCode);

  final int statusCode;
}
