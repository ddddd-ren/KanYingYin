import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kanyingyin/features/tv_pairing/data/tv_pairing_phone_page.dart';
import 'package:kanyingyin/features/tv_pairing/domain/tv_pairing_models.dart';
import 'package:synchronized/synchronized.dart';

enum TvPairingSubmissionResult { accepted, rejected, applyFailed }

typedef TvPairingPhoneConnectedHandler = void Function();
typedef TvPairingPayloadHandler = Future<TvPairingSubmissionResult> Function(
  TvPairingPayload payload,
);
typedef TvPairingCancelledHandler = Future<void> Function();
typedef TvPairingHostResolver = Future<String> Function();

class TvPairingServerEndpoint {
  const TvPairingServerEndpoint({
    required this.host,
    required this.port,
    required this.pairingToken,
  });

  final String host;
  final int port;
  final String pairingToken;

  Uri get pairUri => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/pair',
        queryParameters: <String, String>{
          'token': pairingToken,
          'v': TvPairingPayload.currentProtocolVersion.toString(),
        },
      );

  Uri get pairApiUri => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/api/pair',
      );

  Uri get cancelApiUri => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/api/cancel',
      );

  @override
  String toString() => 'TvPairingServerEndpoint(host: $host, port: $port)';
}

abstract interface class TvPairingServer {
  bool get isRunning;

  Future<TvPairingServerEndpoint> start({
    required TvPairingSession session,
    required TvPairingPhoneConnectedHandler onPhoneConnected,
    required TvPairingPayloadHandler onPayload,
    TvPairingCancelledHandler? onCancelled,
  });

  Future<void> stop();
}

class TvPairingHttpServer implements TvPairingServer {
  TvPairingHttpServer({
    InternetAddress? bindAddress,
    TvPairingHostResolver? advertisedHostResolver,
    DateTime Function()? now,
  })  : _bindAddress = bindAddress ?? InternetAddress.anyIPv4,
        _advertisedHostResolver =
            advertisedHostResolver ?? _resolveLanIpv4Address,
        _now = now ?? DateTime.now;

  final InternetAddress _bindAddress;
  final TvPairingHostResolver _advertisedHostResolver;
  final DateTime Function() _now;
  final Lock _requestLock = Lock();

  HttpServer? _server;
  TvPairingSession? _session;
  TvPairingPhoneConnectedHandler? _onPhoneConnected;
  TvPairingPayloadHandler? _onPayload;
  TvPairingCancelledHandler? _onCancelled;
  bool _phoneConnectedNotified = false;

  @override
  bool get isRunning => _server != null;

  @override
  Future<TvPairingServerEndpoint> start({
    required TvPairingSession session,
    required TvPairingPhoneConnectedHandler onPhoneConnected,
    required TvPairingPayloadHandler onPayload,
    TvPairingCancelledHandler? onCancelled,
  }) async {
    if (_server != null) {
      throw StateError('TV 配对服务已启动');
    }
    if (!session.isActive(_now().toUtc())) {
      throw StateError('TV 配对会话已失效');
    }

    final advertisedHost = await _advertisedHostResolver();
    final server = await HttpServer.bind(_bindAddress, 0, shared: false);
    _server = server;
    _session = session;
    _onPhoneConnected = onPhoneConnected;
    _onPayload = onPayload;
    _onCancelled = onCancelled;
    _phoneConnectedNotified = false;
    server.listen(
      (request) => unawaited(_handleRequest(request)),
      onError: (_) {},
      cancelOnError: false,
    );
    return TvPairingServerEndpoint(
      host: advertisedHost,
      port: server.port,
      pairingToken: session.token,
    );
  }

  @override
  Future<void> stop() async {
    final server = _server;
    _clearState();
    if (server != null) await server.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final session = _session;
    final onPayload = _onPayload;
    final onCancelled = _onCancelled;
    if (session == null || onPayload == null) {
      await _respondJson(
        request.response,
        HttpStatus.serviceUnavailable,
        <String, Object>{'status': 'stopped'},
      );
      return;
    }

    try {
      if (request.method == 'GET' && request.uri.path == '/pair') {
        await _handlePairPage(request, session);
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/api/pair') {
        await _requestLock.synchronized(
          () => _handlePairSubmission(request, session, onPayload),
        );
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/api/cancel') {
        await _requestLock.synchronized(
          () => _handleCancellation(request, session, onCancelled),
        );
        return;
      }
      await _respondJson(
        request.response,
        HttpStatus.notFound,
        <String, Object>{'status': 'not_found'},
      );
    } on Object {
      try {
        await _respondJson(
          request.response,
          HttpStatus.internalServerError,
          <String, Object>{'status': 'request_failed'},
        );
      } on Object {
        await request.response.close();
      }
    }
  }

  Future<void> _handlePairPage(
    HttpRequest request,
    TvPairingSession session,
  ) async {
    final tokenStatus = _tokenStatus(
      session,
      request.uri.queryParameters['token'],
    );
    if (tokenStatus != _TokenStatus.valid) {
      await _respondTokenError(request.response, tokenStatus);
      return;
    }
    if (request.uri.queryParameters['v'] !=
        TvPairingPayload.currentProtocolVersion.toString()) {
      await _respondJson(
        request.response,
        HttpStatus.badRequest,
        <String, Object>{'status': 'unsupported_version'},
      );
      return;
    }
    if (!_phoneConnectedNotified) {
      _phoneConnectedNotified = true;
      _onPhoneConnected?.call();
    }

    final response = request.response;
    _setNoStoreHeaders(response);
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.html;
    response.headers.set(
      'Content-Security-Policy',
      "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; form-action 'self'; base-uri 'none'",
    );
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.write(
      buildTvPairingPhonePage(
        token: session.token,
        expiresAt: session.expiresAt,
      ),
    );
    await response.close();
  }

  Future<void> _handlePairSubmission(
    HttpRequest request,
    TvPairingSession session,
    TvPairingPayloadHandler onPayload,
  ) async {
    final tokenStatus = _tokenStatus(
      session,
      request.headers.value('X-Pairing-Token'),
    );
    if (tokenStatus != _TokenStatus.valid) {
      await request.drain<void>();
      await _respondTokenError(request.response, tokenStatus);
      return;
    }
    if (!_isJsonRequest(request)) {
      await request.drain<void>();
      await _respondJson(
        request.response,
        HttpStatus.unsupportedMediaType,
        <String, Object>{'status': 'json_required'},
      );
      return;
    }

    try {
      final bytes = await _readLimitedBody(request);
      final payload = TvPairingPayload.decode(bytes);
      final decision = await onPayload(payload);
      if (decision == TvPairingSubmissionResult.rejected) {
        await _respondJson(
          request.response,
          HttpStatus.conflict,
          <String, Object>{'status': 'rejected_on_tv'},
        );
        return;
      }
      if (decision == TvPairingSubmissionResult.applyFailed) {
        await _respondJson(
          request.response,
          HttpStatus.internalServerError,
          <String, Object>{'status': 'apply_failed'},
        );
        return;
      }
      if (!session.consume(session.token, now: _now().toUtc())) {
        await _respondJson(
          request.response,
          HttpStatus.gone,
          <String, Object>{'status': 'session_expired'},
        );
        return;
      }
      await _respondJson(
        request.response,
        HttpStatus.ok,
        <String, Object>{'status': 'paired'},
      );
      unawaited(_stopAcceptingNewRequests(session));
    } on TvPairingPayloadTooLargeException {
      await _respondJson(
        request.response,
        HttpStatus.requestEntityTooLarge,
        <String, Object>{'status': 'payload_too_large'},
      );
    } on TvPairingInvalidPayloadException {
      await _respondJson(
        request.response,
        HttpStatus.badRequest,
        <String, Object>{'status': 'invalid_payload'},
      );
    }
  }

  Future<void> _handleCancellation(
    HttpRequest request,
    TvPairingSession session,
    TvPairingCancelledHandler? onCancelled,
  ) async {
    final tokenStatus = _tokenStatus(
      session,
      request.headers.value('X-Pairing-Token'),
    );
    if (tokenStatus != _TokenStatus.valid) {
      await request.drain<void>();
      await _respondTokenError(request.response, tokenStatus);
      return;
    }
    if (!_isJsonRequest(request)) {
      await request.drain<void>();
      await _respondJson(
        request.response,
        HttpStatus.unsupportedMediaType,
        <String, Object>{'status': 'json_required'},
      );
      return;
    }
    try {
      await _readLimitedBody(request);
    } on TvPairingPayloadTooLargeException {
      await _respondJson(
        request.response,
        HttpStatus.requestEntityTooLarge,
        <String, Object>{'status': 'payload_too_large'},
      );
      return;
    }

    session.cancel();
    await onCancelled?.call();
    await _respondJson(
      request.response,
      HttpStatus.ok,
      <String, Object>{'status': 'cancelled'},
    );
    unawaited(_stopAcceptingNewRequests(session));
  }

  _TokenStatus _tokenStatus(TvPairingSession session, String? token) {
    final now = _now().toUtc();
    if (!session.isActive(now)) return _TokenStatus.inactive;
    if (token == null || !session.matches(token, now: now)) {
      return _TokenStatus.invalid;
    }
    return _TokenStatus.valid;
  }

  bool _isJsonRequest(HttpRequest request) =>
      request.headers.contentType?.mimeType == ContentType.json.mimeType;

  Future<List<int>> _readLimitedBody(HttpRequest request) async {
    if (request.contentLength > TvPairingPayload.maxPayloadBytes) {
      await request.drain<void>();
      throw TvPairingPayloadTooLargeException(request.contentLength);
    }
    final bytes = <int>[];
    var actualBytes = 0;
    await for (final chunk in request) {
      actualBytes += chunk.length;
      if (actualBytes <= TvPairingPayload.maxPayloadBytes) {
        bytes.addAll(chunk);
      }
    }
    if (actualBytes > TvPairingPayload.maxPayloadBytes) {
      throw TvPairingPayloadTooLargeException(actualBytes);
    }
    return bytes;
  }

  Future<void> _stopAcceptingNewRequests(
    TvPairingSession completedSession,
  ) async {
    if (!identical(_session, completedSession)) return;
    final server = _server;
    _clearState();
    if (server != null) await server.close(force: false);
  }

  void _clearState() {
    _server = null;
    _session = null;
    _onPhoneConnected = null;
    _onPayload = null;
    _onCancelled = null;
    _phoneConnectedNotified = false;
  }

  static Future<void> _respondTokenError(
    HttpResponse response,
    _TokenStatus status,
  ) =>
      _respondJson(
        response,
        status == _TokenStatus.inactive
            ? HttpStatus.gone
            : HttpStatus.unauthorized,
        <String, Object>{
          'status': status == _TokenStatus.inactive
              ? 'session_expired'
              : 'invalid_token',
        },
      );

  static Future<void> _respondJson(
    HttpResponse response,
    int statusCode,
    Map<String, Object> body,
  ) async {
    _setNoStoreHeaders(response);
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  static void _setNoStoreHeaders(HttpResponse response) {
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
  }

  static Future<String> _resolveLanIpv4Address() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
      includeLoopback: false,
    );
    final addresses = interfaces
        .expand((interface) => interface.addresses)
        .where((address) => address.type == InternetAddressType.IPv4)
        .toList(growable: false);
    for (final address in addresses) {
      if (_isPrivateIpv4(address.address)) return address.address;
    }
    if (addresses.isNotEmpty) return addresses.first.address;
    throw const TvPairingNetworkUnavailableException();
  }

  static bool _isPrivateIpv4(String value) {
    final parts = value.split('.').map(int.tryParse).toList(growable: false);
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final first = parts[0]!;
    final second = parts[1]!;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }
}

enum _TokenStatus { valid, invalid, inactive }

class TvPairingNetworkUnavailableException implements Exception {
  const TvPairingNetworkUnavailableException();

  @override
  String toString() => 'TvPairingNetworkUnavailableException';
}
