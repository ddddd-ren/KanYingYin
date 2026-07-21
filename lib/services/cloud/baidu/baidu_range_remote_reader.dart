import 'dart:async';
import 'dart:io';

import 'package:kanyingyin/services/cloud/baidu/baidu_request_policy.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_relay_protocol.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_remote_reader.dart';

typedef BaiduAccessTokenProvider = Future<String> Function();
typedef BaiduRemoteResourceRefresher = Future<CloudRangeRemoteResource>
    Function();
typedef BaiduRemoteUriValidator = bool Function(Uri uri);
typedef BaiduHttpClientFactory = HttpClient Function();
typedef BaiduRetryDelay = Future<void> Function(Duration duration);

class BaiduRangeRemoteReader implements CloudRangeRemoteReader {
  BaiduRangeRemoteReader({
    required CloudRangeRemoteResource resource,
    required BaiduAccessTokenProvider accessTokenProvider,
    required BaiduRemoteResourceRefresher refreshResource,
    BaiduHttpClientFactory? httpClientFactory,
    BaiduRetryDelay? delay,
    BaiduRemoteUriValidator? initialUriValidator,
    BaiduRemoteUriValidator? redirectUriValidator,
    this.requestTimeout = const Duration(seconds: 15),
  })  : _resource = resource,
        _accessTokenProvider = accessTokenProvider,
        _refreshResource = refreshResource,
        _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _delay = delay ?? Future<void>.delayed,
        _initialUriValidator = initialUriValidator ??
            const BaiduRequestPolicy().isOfficialDownloadUri,
        _redirectUriValidator = redirectUriValidator ??
            const BaiduRequestPolicy().isSafeDownloadRedirectUri {
    if (!_initialUriValidator(resource.uri)) {
      throw const CloudRangeRemoteProtocolException('百度下载地址不在官方范围内');
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
  final BaiduAccessTokenProvider _accessTokenProvider;
  final BaiduRemoteResourceRefresher _refreshResource;
  final BaiduHttpClientFactory _httpClientFactory;
  final BaiduRetryDelay _delay;
  final BaiduRemoteUriValidator _initialUriValidator;
  final BaiduRemoteUriValidator _redirectUriValidator;
  final Duration requestTimeout;
  final Set<HttpClient> _activeClients = <HttpClient>{};
  final StreamController<CloudRangeReaderEvent> _events =
      StreamController<CloudRangeReaderEvent>.broadcast(sync: true);

  int? _totalLength;
  String _contentType = 'application/octet-stream';
  bool _authRefreshUsed = false;
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
  Future<CloudRangeRemoteMetadata> probe() =>
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

  Future<CloudRangeRemoteMetadata> _readWithRecovery(
    ByteRange range,
    File? destination,
  ) async {
    var transportAttempt = 0;
    while (true) {
      if (_closed) throw StateError('百度远程读取器已关闭');
      try {
        return await _readRangeOnce(range, destination);
      } on _BaiduAuthenticationStatusException {
        _emit(CloudRangeReaderEvent.refreshing);
        await _refreshAfterAuthenticationFailure();
      } on Object catch (error) {
        if (_closed) throw StateError('百度远程读取器已关闭');
        if (!_isTransportError(error)) rethrow;
        if (transportAttempt >= _retryDelays.length) {
          throw const CloudRangeRemoteTransportException('百度远程连接重试后仍失败');
        }
        _emit(CloudRangeReaderEvent.reconnecting);
        await _delay(_retryDelays[transportAttempt]);
        transportAttempt++;
      }
    }
  }

  Future<CloudRangeRemoteMetadata> _readRangeOnce(
    ByteRange range,
    File? destination,
  ) async {
    final client = _newClient();
    try {
      final opened = await _openResponse(
        client,
        rangeHeader: 'bytes=${range.start}-${range.endInclusive}',
      );
      final response = opened.response;
      if (response.statusCode == HttpStatus.ok &&
          destination == null &&
          range.start == 0 &&
          range.endInclusive == 0) {
        final metadata = _metadataFromFullResponse(response);
        _rememberMetadata(metadata);
        return metadata;
      }
      if (response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        throw CloudRangeRemoteProtocolException(
          '百度远程 Range 响应状态无效：${response.statusCode}',
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
            '百度远程分段长度不符：期望 ${range.length}，实际 $received',
          );
        }
        await sink?.flush();
      } finally {
        await sink?.close();
      }
      _rememberMetadata(metadata);
      return metadata;
    } finally {
      _disposeClient(client);
    }
  }

  @override
  Future<void> streamAll(IOSink destination) async {
    if (_closed) throw StateError('百度远程读取器已关闭');
    try {
      await _streamAllOnce(destination);
    } on _BaiduAuthenticationStatusException {
      _emit(CloudRangeReaderEvent.refreshing);
      await _refreshAfterAuthenticationFailure();
      await _streamAllOnce(destination);
    }
  }

  Future<void> _streamAllOnce(IOSink destination) async {
    final client = _newClient();
    try {
      final opened = await _openResponse(client);
      final response = opened.response;
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw CloudRangeRemoteProtocolException(
          '百度远程完整响应状态无效：${response.statusCode}',
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
          '百度远程完整响应长度不符：期望 ${metadata.totalLength}，实际 $received',
        );
      }
      _rememberMetadata(metadata);
    } finally {
      _disposeClient(client);
    }
  }

  Future<({HttpClientResponse response, Uri finalUri})> _openResponse(
    HttpClient client, {
    String? rangeHeader,
  }) async {
    if (!_initialUriValidator(_resource.uri)) {
      throw const CloudRangeRemoteProtocolException('百度下载地址不在官方范围内');
    }
    final token = (await _accessTokenProvider()).trim();
    if (token.isEmpty) {
      throw const CloudRangeRemoteAuthenticationException('百度授权无效');
    }
    var uri = _resource.uri.replace(
      queryParameters: <String, String>{
        ..._resource.uri.queryParameters,
        'access_token': token,
      },
    );
    for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
      final request = await client.getUrl(uri).timeout(requestTimeout);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        BaiduRequestPolicy.downloadUserAgent,
      );
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (rangeHeader != null) {
        request.headers.set(HttpHeaders.rangeHeader, rangeHeader);
      }
      final response = await request.close().timeout(requestTimeout);
      if (_isAuthenticationStatus(response.statusCode)) {
        await response.drain<void>();
        throw _BaiduAuthenticationStatusException(response.statusCode);
      }
      if (!_isRedirect(response.statusCode)) {
        return (response: response, finalUri: uri);
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null || redirectCount == 5) {
        throw const CloudRangeRemoteProtocolException('百度下载重定向响应无效');
      }
      final redirected = uri.resolve(location);
      if (!_redirectUriValidator(redirected)) {
        throw const CloudRangeRemoteProtocolException('百度下载重定向地址不安全');
      }
      uri = redirected;
    }
    throw const CloudRangeRemoteProtocolException('百度下载重定向次数过多');
  }

  CloudRangeRemoteMetadata _validateRangeResponse(
    HttpClientResponse response,
    ByteRange requested,
  ) {
    final value = response.headers.value(HttpHeaders.contentRangeHeader);
    final match = value == null
        ? null
        : RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value.trim());
    if (match == null) {
      throw const CloudRangeRemoteProtocolException(
        '百度远程 Content-Range 缺失或无效',
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
        '百度远程 Content-Range 与请求不一致',
      );
    }
    if (_totalLength != null && _totalLength != total) {
      throw const CloudRangeRemoteProtocolException('百度远程文件总长度发生变化');
    }
    if (response.contentLength >= 0 &&
        response.contentLength != requested.length) {
      throw const CloudRangeRemoteProtocolException(
        '百度远程 Content-Length 与请求不一致',
      );
    }
    return CloudRangeRemoteMetadata(
      totalLength: total,
      contentType: _responseContentType(response),
      supportsRanges: true,
    );
  }

  CloudRangeRemoteMetadata _metadataFromFullResponse(
    HttpClientResponse response,
  ) {
    final total = response.contentLength >= 0
        ? response.contentLength
        : _resource.totalLength;
    if (total == null || total <= 0) {
      throw const CloudRangeRemoteProtocolException('百度远程完整响应缺少文件长度');
    }
    if (_totalLength != null && _totalLength != total) {
      throw const CloudRangeRemoteProtocolException('百度远程文件总长度发生变化');
    }
    return CloudRangeRemoteMetadata(
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

  void _rememberMetadata(CloudRangeRemoteMetadata metadata) {
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
    if (_authRefreshUsed) {
      throw const CloudRangeRemoteAuthenticationException('百度播放地址再次失效');
    }
    _authRefreshUsed = true;
    final task = _performRefresh();
    _refreshing = task;
    try {
      await task;
    } finally {
      if (identical(_refreshing, task)) _refreshing = null;
    }
  }

  Future<void> _performRefresh() async {
    try {
      final refreshed = await _refreshResource();
      if (!_initialUriValidator(refreshed.uri)) {
        throw const CloudRangeRemoteProtocolException('刷新后的百度地址不在官方范围内');
      }
      if (refreshed.totalLength != null &&
          _totalLength != null &&
          refreshed.totalLength != _totalLength) {
        throw const CloudRangeRemoteProtocolException('刷新后的百度文件长度发生变化');
      }
      _resource = refreshed;
    } on CloudRangeRemoteProtocolException {
      rethrow;
    } on Object {
      throw const CloudRangeRemoteAuthenticationException('百度播放会话刷新失败');
    }
  }

  HttpClient _newClient() {
    final client = _httpClientFactory()
      ..connectionTimeout = requestTimeout
      ..findProxy = (_) => 'DIRECT';
    _activeClients.add(client);
    return client;
  }

  void _disposeClient(HttpClient client) {
    _activeClients.remove(client);
    client.close(force: true);
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
    for (final client in _activeClients.toList()) {
      client.close(force: true);
    }
    _activeClients.clear();
    await _events.close();
  }
}

class _BaiduAuthenticationStatusException implements Exception {
  const _BaiduAuthenticationStatusException(this.statusCode);

  final int statusCode;
}
