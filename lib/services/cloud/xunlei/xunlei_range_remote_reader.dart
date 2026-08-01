import 'dart:async';
import 'dart:io';

import 'package:kanyingyin/services/cloud/range/cloud_range_relay_protocol.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_remote_reader.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_request_policy.dart';

typedef XunleiRemoteResourceRefresher = Future<CloudRangeRemoteResource>
    Function();
typedef XunleiRemoteUriValidator = bool Function(Uri uri);
typedef XunleiHttpClientFactory = HttpClient Function();
typedef XunleiRetryDelay = Future<void> Function(Duration duration);

class XunleiRemoteMetadata extends CloudRangeRemoteMetadata {
  const XunleiRemoteMetadata({
    required super.totalLength,
    required super.contentType,
    required super.supportsRanges,
  });
}

class XunleiRangeRemoteReader implements CloudRangeRemoteReader {
  XunleiRangeRemoteReader({
    required CloudRangeRemoteResource resource,
    required XunleiRemoteResourceRefresher refreshResource,
    XunleiRemoteUriValidator? uriValidator,
    XunleiHttpClientFactory? httpClientFactory,
    XunleiRetryDelay? delay,
    this.requestTimeout = const Duration(seconds: 15),
  })  : _resource = resource,
        _refreshResource = refreshResource,
        _uriValidator =
            uriValidator ?? const XunleiRequestPolicy().isTrustedDownloadUri,
        _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _delay = delay ?? Future<void>.delayed {
    if (!_uriValidator(resource.uri)) {
      throw const CloudRangeRemoteProtocolException('迅雷下载地址不在可信范围内');
    }
    _totalLength = resource.totalLength;
    _contentType = resource.contentType ?? 'application/octet-stream';
  }

  static const List<Duration> _retryDelays = <Duration>[
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  CloudRangeRemoteResource _resource;
  final XunleiRemoteResourceRefresher _refreshResource;
  final XunleiRemoteUriValidator _uriValidator;
  final XunleiHttpClientFactory _httpClientFactory;
  final XunleiRetryDelay _delay;
  final Duration requestTimeout;
  HttpClient? _client;
  final StreamController<CloudRangeReaderEvent> _events =
      StreamController<CloudRangeReaderEvent>.broadcast(sync: true);

  int? _totalLength;
  String _contentType = 'application/octet-stream';
  Uri? _resolvedUri;
  bool _authenticationRefreshUsed = false;
  Future<void>? _refreshing;
  bool _closed = false;
  Future<void>? _closeFuture;

  @override
  int? get totalLength => _totalLength;

  @override
  String get contentType => _contentType;

  @override
  Stream<CloudRangeReaderEvent> get events => _events.stream;

  @override
  Future<XunleiRemoteMetadata> probe() =>
      _readWithRecovery(const ByteRange(0, 0), null);

  @override
  Future<void> readTo(ByteRange range, File destination) async {
    try {
      await _readWithRecovery(range, destination);
    } on Object {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  Future<XunleiRemoteMetadata> _readWithRecovery(
    ByteRange range,
    File? destination,
  ) async {
    var transportAttempt = 0;
    while (true) {
      _ensureOpen();
      try {
        return await _readRangeOnce(range, destination);
      } on _XunleiAuthenticationStatusException {
        _emit(CloudRangeReaderEvent.refreshing);
        await _refreshAfterAuthenticationFailure();
      } on Object catch (error) {
        if (_closed) throw StateError('迅雷远程读取器已关闭');
        if (!_isTransportError(error)) rethrow;
        if (transportAttempt >= _retryDelays.length) {
          throw const CloudRangeRemoteTransportException('迅雷远程连接重试后仍失败');
        }
        _emit(CloudRangeReaderEvent.reconnecting);
        await _delay(_retryDelays[transportAttempt]);
        transportAttempt++;
      }
    }
  }

  Future<XunleiRemoteMetadata> _readRangeOnce(
    ByteRange range,
    File? destination,
  ) async {
    final client = _newClient();
    final response = await _openResponse(
      client,
      rangeHeader: 'bytes=${range.start}-${range.endInclusive}',
    );
    if (response.statusCode == HttpStatus.ok &&
        destination == null &&
        range == const ByteRange(0, 0)) {
      final metadata = _metadataFromFullResponse(response);
      _rememberMetadata(metadata);
      await _closeResponseConnection(response);
      return metadata;
    }
    if (response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>();
      throw CloudRangeRemoteProtocolException(
        '迅雷远程 Range 响应状态无效：${response.statusCode}',
      );
    }
    final metadata = _validateRangeResponse(response, range);
    IOSink? sink;
    var received = 0;
    try {
      if (destination != null) sink = destination.openWrite();
      await for (final chunk in response.timeout(requestTimeout)) {
        received += chunk.length;
        sink?.add(chunk);
      }
      if (received != range.length) {
        throw CloudRangeRemoteProtocolException(
          '迅雷远程分段长度不符：期望 ${range.length}，实际 $received',
        );
      }
      await sink?.flush();
    } finally {
      await sink?.close();
    }
    _rememberMetadata(metadata);
    return metadata;
  }

  @override
  Future<void> streamAll(IOSink destination) async {
    var transportAttempt = 0;
    while (true) {
      _ensureOpen();
      try {
        await _streamAllOnce(destination);
        return;
      } on _XunleiAuthenticationStatusException {
        _emit(CloudRangeReaderEvent.refreshing);
        await _refreshAfterAuthenticationFailure();
      } on Object catch (error) {
        if (_closed) throw StateError('迅雷远程读取器已关闭');
        if (!_isTransportError(error)) rethrow;
        if (transportAttempt >= _retryDelays.length) {
          throw const CloudRangeRemoteTransportException('迅雷远程连接重试后仍失败');
        }
        _emit(CloudRangeReaderEvent.reconnecting);
        await _delay(_retryDelays[transportAttempt]);
        transportAttempt++;
      }
    }
  }

  Future<void> _streamAllOnce(IOSink destination) async {
    final client = _newClient();
    final response = await _openResponse(client);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw CloudRangeRemoteProtocolException(
        '迅雷远程完整响应状态无效：${response.statusCode}',
      );
    }
    final metadata = _metadataFromFullResponse(response);
    var received = 0;
    await for (final chunk in response.timeout(requestTimeout)) {
      received += chunk.length;
      destination.add(chunk);
    }
    if (received != metadata.totalLength) {
      throw CloudRangeRemoteProtocolException(
        '迅雷远程完整响应长度不符：期望 ${metadata.totalLength}，实际 $received',
      );
    }
    _rememberMetadata(metadata);
  }

  Future<HttpClientResponse> _openResponse(
    HttpClient client, {
    String? rangeHeader,
  }) async {
    if (!_uriValidator(_resource.uri)) {
      throw const CloudRangeRemoteProtocolException('迅雷下载地址不在可信范围内');
    }
    var uri = _resolvedUri ?? _resource.uri;
    if (!_uriValidator(uri)) {
      _resolvedUri = null;
      throw const CloudRangeRemoteProtocolException('迅雷缓存下载地址不安全');
    }
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      final request = await client.getUrl(uri).timeout(requestTimeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final userAgent = _resourceUserAgent();
      if (userAgent != null) {
        request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      }
      if (rangeHeader != null) {
        request.headers.set(HttpHeaders.rangeHeader, rangeHeader);
      }
      final response = await request.close().timeout(requestTimeout);
      if (_isAuthenticationStatus(response.statusCode)) {
        await response.drain<void>();
        throw _XunleiAuthenticationStatusException(response.statusCode);
      }
      if (!_isRedirect(response.statusCode)) {
        _resolvedUri = uri;
        return response;
      }

      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null || redirectCount == 5) {
        throw const CloudRangeRemoteProtocolException('迅雷下载重定向响应无效');
      }
      final redirected = uri.resolve(location);
      if (!_uriValidator(redirected)) {
        throw const CloudRangeRemoteProtocolException('迅雷下载重定向地址不安全');
      }
      uri = redirected;
    }
    throw const CloudRangeRemoteProtocolException('迅雷下载重定向次数过多');
  }

  XunleiRemoteMetadata _validateRangeResponse(
    HttpClientResponse response,
    ByteRange requested,
  ) {
    final value = response.headers.value(HttpHeaders.contentRangeHeader);
    final match = value == null
        ? null
        : RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value.trim());
    if (match == null) {
      throw const CloudRangeRemoteProtocolException(
        '迅雷远程 Content-Range 缺失或无效',
      );
    }
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    if (start != requested.start ||
        end != requested.endInclusive ||
        total == null ||
        total <= requested.endInclusive) {
      throw const CloudRangeRemoteProtocolException(
        '迅雷远程 Content-Range 与请求不一致',
      );
    }
    if (_totalLength != null && _totalLength != total) {
      throw const CloudRangeRemoteProtocolException('迅雷远程文件总长度发生变化');
    }
    if (response.contentLength >= 0 &&
        response.contentLength != requested.length) {
      throw const CloudRangeRemoteProtocolException(
        '迅雷远程 Content-Length 与请求不一致',
      );
    }
    return XunleiRemoteMetadata(
      totalLength: total,
      contentType: _responseContentType(response),
      supportsRanges: true,
    );
  }

  XunleiRemoteMetadata _metadataFromFullResponse(
    HttpClientResponse response,
  ) {
    final total = response.contentLength >= 0
        ? response.contentLength
        : _resource.totalLength;
    if (total == null || total <= 0) {
      throw const CloudRangeRemoteProtocolException('迅雷远程完整响应缺少文件长度');
    }
    if (_totalLength != null && _totalLength != total) {
      throw const CloudRangeRemoteProtocolException('迅雷远程文件总长度发生变化');
    }
    return XunleiRemoteMetadata(
      totalLength: total,
      contentType: _responseContentType(response),
      supportsRanges: false,
    );
  }

  String _responseContentType(HttpClientResponse response) {
    final mimeType = response.headers.contentType?.mimeType;
    return mimeType == null || mimeType.isEmpty
        ? _contentType
        : mimeType.toLowerCase();
  }

  String? _resourceUserAgent() {
    for (final entry in _resource.headers.entries) {
      if (entry.key.toLowerCase() == HttpHeaders.userAgentHeader) {
        final value = entry.value.trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  void _rememberMetadata(XunleiRemoteMetadata metadata) {
    _totalLength = metadata.totalLength;
    _contentType = metadata.contentType;
    _resource = _resource.copyWith(
      totalLength: metadata.totalLength,
      contentType: metadata.contentType,
    );
  }

  Future<void> _refreshAfterAuthenticationFailure() async {
    final existing = _refreshing;
    if (existing != null) return existing;
    if (_authenticationRefreshUsed) {
      throw const CloudRangeRemoteAuthenticationException('迅雷播放地址再次失效');
    }
    _authenticationRefreshUsed = true;
    final operation = _performRefresh();
    _refreshing = operation;
    try {
      await operation;
    } finally {
      if (identical(_refreshing, operation)) _refreshing = null;
    }
  }

  Future<void> _performRefresh() async {
    try {
      final refreshed = await _refreshResource();
      if (!_uriValidator(refreshed.uri)) {
        throw const CloudRangeRemoteProtocolException('刷新后的迅雷地址不在可信范围内');
      }
      if (refreshed.totalLength != null &&
          _totalLength != null &&
          refreshed.totalLength != _totalLength) {
        throw const CloudRangeRemoteProtocolException('刷新后的迅雷文件长度发生变化');
      }
      _resource = refreshed;
      _resolvedUri = null;
    } on CloudRangeRemoteProtocolException {
      rethrow;
    } on Object {
      throw const CloudRangeRemoteAuthenticationException('迅雷播放会话刷新失败');
    }
  }

  HttpClient _newClient() {
    return _client ??= (_httpClientFactory()
      ..connectionTimeout = requestTimeout
      ..idleTimeout = const Duration(seconds: 30)
      ..maxConnectionsPerHost = 6
      ..autoUncompress = false
      ..findProxy = (_) => 'DIRECT');
  }

  Future<void> _closeResponseConnection(HttpClientResponse response) async {
    final socket = await response.detachSocket();
    socket.destroy();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('迅雷远程读取器已关闭');
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

  void _emit(CloudRangeReaderEvent event) {
    if (!_closed && !_events.isClosed) _events.add(event);
  }

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    _client?.close(force: true);
    _client = null;
    await _events.close();
  }
}

class _XunleiAuthenticationStatusException implements Exception {
  const _XunleiAuthenticationStatusException(this.statusCode);

  final int statusCode;
}
