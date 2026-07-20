import 'dart:async';
import 'dart:io';

import 'package:kanyingyin/services/cloud/quark/quark_range_relay_protocol.dart';
import 'package:kanyingyin/services/cloud/quark/quark_request_policy.dart';

typedef QuarkRemoteResourceRefresher = Future<QuarkRemoteResource> Function();
typedef QuarkRemoteUriValidator = bool Function(Uri uri);
typedef QuarkHttpClientFactory = HttpClient Function();
typedef QuarkRetryDelay = Future<void> Function(Duration duration);

class QuarkRemoteResource {
  QuarkRemoteResource({
    required this.uri,
    Map<String, String> headers = const <String, String>{},
    this.totalLength,
    this.contentType,
  }) : headers = Map<String, String>.unmodifiable(headers);

  final Uri uri;
  final Map<String, String> headers;
  final int? totalLength;
  final String? contentType;

  QuarkRemoteResource copyWith({
    Uri? uri,
    int? totalLength,
    String? contentType,
  }) =>
      QuarkRemoteResource(
        uri: uri ?? this.uri,
        headers: headers,
        totalLength: totalLength ?? this.totalLength,
        contentType: contentType ?? this.contentType,
      );
}

class QuarkRemoteMetadata {
  const QuarkRemoteMetadata({
    required this.totalLength,
    required this.contentType,
  });

  final int totalLength;
  final String contentType;
}

class QuarkRemoteProtocolException implements Exception {
  const QuarkRemoteProtocolException(this.message);

  final String message;

  @override
  String toString() => 'QuarkRemoteProtocolException($message)';
}

class QuarkRemoteAuthenticationException implements Exception {
  const QuarkRemoteAuthenticationException(this.message);

  final String message;

  @override
  String toString() => 'QuarkRemoteAuthenticationException($message)';
}

class QuarkRemoteTransportException implements Exception {
  const QuarkRemoteTransportException(this.message);

  final String message;

  @override
  String toString() => 'QuarkRemoteTransportException($message)';
}

class QuarkRangeRemoteReader {
  QuarkRangeRemoteReader({
    required QuarkRemoteResource resource,
    required QuarkRemoteResourceRefresher refreshResource,
    QuarkRemoteUriValidator? uriValidator,
    QuarkHttpClientFactory? httpClientFactory,
    QuarkRetryDelay? delay,
    this.requestTimeout = const Duration(seconds: 15),
  })  : _resource = resource,
        _refreshResource = refreshResource,
        _uriValidator = uriValidator ??
            const QuarkRequestPolicy().isTrustedOriginalDownloadUri,
        _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _delay = delay ?? Future<void>.delayed {
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
  final Duration requestTimeout;
  final Set<HttpClient> _activeClients = <HttpClient>{};

  int? _totalLength;
  String _contentType = 'application/octet-stream';
  bool _authRefreshUsed = false;
  Future<void>? _refreshing;
  bool _closed = false;
  Future<void>? _closeFuture;

  int? get totalLength => _totalLength;
  String get contentType => _contentType;

  Future<QuarkRemoteMetadata> probe() async {
    final metadata = await _readWithRecovery(const ByteRange(0, 0), null);
    return metadata;
  }

  Future<void> readTo(ByteRange range, File destination) async {
    try {
      await _readWithRecovery(range, destination);
    } on Object {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  Future<QuarkRemoteMetadata> _readWithRecovery(
    ByteRange range,
    File? destination,
  ) async {
    var transportAttempt = 0;
    while (true) {
      if (_closed) throw StateError('远程读取器已关闭');
      try {
        return await _readOnce(range, destination);
      } on _AuthenticationStatusException {
        await _refreshAfterAuthenticationFailure();
      } on Object catch (error) {
        if (!_isTransportError(error)) rethrow;
        if (transportAttempt >= _retryDelays.length) {
          throw const QuarkRemoteTransportException('夸克远程连接重试后仍失败');
        }
        await _delay(_retryDelays[transportAttempt]);
        transportAttempt++;
      }
    }
  }

  Future<QuarkRemoteMetadata> _readOnce(
    ByteRange range,
    File? destination,
  ) async {
    final client = _httpClientFactory()
      ..connectionTimeout = requestTimeout
      ..findProxy = (_) => 'DIRECT';
    _activeClients.add(client);
    try {
      var uri = _resource.uri;
      HttpClientResponse? response;
      for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
        if (!_uriValidator(uri)) {
          throw const QuarkRemoteProtocolException('重定向地址不在可信范围内');
        }
        final request = await client.getUrl(uri).timeout(requestTimeout);
        request.followRedirects = false;
        _setRequestHeaders(request, _resource.headers);
        request.headers.set(
          HttpHeaders.rangeHeader,
          'bytes=${range.start}-${range.endInclusive}',
        );
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        response = await request.close().timeout(requestTimeout);

        if (_isRedirect(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
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
        await response.drain<void>();
        throw _AuthenticationStatusException(response.statusCode);
      }
      if (response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        throw QuarkRemoteProtocolException(
          '远程 Range 响应状态无效：${response.statusCode}',
        );
      }

      final metadata = _validateResponse(response, range);
      _resource = _resource.copyWith(
        uri: uri,
        totalLength: metadata.totalLength,
        contentType: metadata.contentType,
      );
      _totalLength = metadata.totalLength;
      _contentType = metadata.contentType;

      IOSink? sink;
      var received = 0;
      try {
        if (destination != null) sink = destination.openWrite();
        await for (final chunk in response.timeout(requestTimeout)) {
          received += chunk.length;
          sink?.add(chunk);
        }
        if (received != range.length) {
          throw QuarkRemoteProtocolException(
            '远程分段长度不符：期望 ${range.length}，实际 $received',
          );
        }
        await sink?.flush();
      } finally {
        await sink?.close();
      }
      return metadata;
    } finally {
      _activeClients.remove(client);
      client.close(force: true);
    }
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

  Future<void> _refreshAfterAuthenticationFailure() async {
    final existing = _refreshing;
    if (existing != null) return existing;
    if (_authRefreshUsed) {
      throw const QuarkRemoteAuthenticationException('夸克播放地址再次失效');
    }
    _authRefreshUsed = true;
    final future = _performRefresh();
    _refreshing = future;
    try {
      await future;
    } finally {
      if (identical(_refreshing, future)) _refreshing = null;
    }
  }

  Future<void> _performRefresh() async {
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
      throw const QuarkRemoteAuthenticationException('夸克播放会话刷新失败');
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

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    for (final client in _activeClients.toList()) {
      client.close(force: true);
    }
    _activeClients.clear();
  }
}

class _AuthenticationStatusException implements Exception {
  const _AuthenticationStatusException(this.statusCode);

  final int statusCode;
}
