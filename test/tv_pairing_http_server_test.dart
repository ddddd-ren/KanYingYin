import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/tv_pairing/data/tv_pairing_http_server.dart';
import 'package:kanyingyin/features/tv_pairing/domain/tv_pairing_models.dart';

void main() {
  late DateTime now;
  late TvPairingSession session;
  late TvPairingHttpServer server;

  setUp(() {
    now = DateTime.utc(2026, 8, 6, 12);
    session = TvPairingSession.issue(now: now);
    server = TvPairingHttpServer(
      bindAddress: InternetAddress.loopbackIPv4,
      advertisedHostResolver: () async => InternetAddress.loopbackIPv4.address,
      now: () => now,
    );
  });

  tearDown(() async {
    await server.stop();
  });

  test('手机页面只在有效令牌下返回且不缓存', () async {
    final endpoint = await server.start(
      session: session,
      onPayload: (_) async => TvPairingSubmissionResult.rejected,
    );

    final valid = await _request(endpoint.pairUri);
    final invalid = await _request(
      endpoint.pairUri.replace(queryParameters: <String, String>{
        'token': 'wrong-token',
        'v': '1',
      }),
    );

    expect(valid.statusCode, HttpStatus.ok);
    expect(valid.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
    expect(valid.body, contains('TMDB API Key'));
    expect(valid.body, isNot(contains('secret-tmdb-key')));
    expect(invalid.statusCode, HttpStatus.unauthorized);
  });

  test('POST 拒绝错误令牌、非 JSON 和超大载荷', () async {
    final endpoint = await server.start(
      session: session,
      onPayload: (_) async => TvPairingSubmissionResult.accepted,
    );
    final payload = _payloadBytes();

    final wrongToken = await _request(
      endpoint.pairApiUri,
      method: 'POST',
      token: 'wrong-token',
      contentType: ContentType.json,
      body: payload,
    );
    final nonJson = await _request(
      endpoint.pairApiUri,
      method: 'POST',
      token: session.token,
      contentType: ContentType.text,
      body: payload,
    );
    final tooLarge = await _request(
      endpoint.pairApiUri,
      method: 'POST',
      token: session.token,
      contentType: ContentType.json,
      body: List<int>.filled(TvPairingPayload.maxPayloadBytes + 1, 65),
    );

    expect(wrongToken.statusCode, HttpStatus.unauthorized);
    expect(nonJson.statusCode, HttpStatus.unsupportedMediaType);
    expect(tooLarge.statusCode, HttpStatus.requestEntityTooLarge);
    expect(session.isConsumed, isFalse);
  });

  test('TV 确认并完成导入后才消费令牌且并发请求只能成功一次', () async {
    final confirmation = Completer<TvPairingSubmissionResult>();
    final payloadReceived = Completer<void>();
    var receivedCount = 0;
    final endpoint = await server.start(
      session: session,
      onPayload: (payload) {
        receivedCount++;
        if (!payloadReceived.isCompleted) payloadReceived.complete();
        expect(payload.deviceName, '客厅电视');
        return confirmation.future;
      },
    );

    final first = _request(
      endpoint.pairApiUri,
      method: 'POST',
      token: session.token,
      contentType: ContentType.json,
      body: _payloadBytes(),
    );
    await payloadReceived.future;
    expect(session.isConsumed, isFalse);
    final second = _statusCodeOrClosed(_request(
      endpoint.pairApiUri,
      method: 'POST',
      token: session.token,
      contentType: ContentType.json,
      body: _payloadBytes(),
    ));

    confirmation.complete(TvPairingSubmissionResult.accepted);
    final responses = await Future.wait(<Future<int>>[
      first.then((response) => response.statusCode),
      second,
    ]);

    expect(responses.where((status) => status == HttpStatus.ok), hasLength(1));
    expect(responses.last, isNot(HttpStatus.ok));
    expect(receivedCount, 1);
    expect(session.isConsumed, isTrue);
  });

  test('过期令牌和取消请求都会阻止配置提交', () async {
    var cancelled = false;
    final endpoint = await server.start(
      session: session,
      onPayload: (_) async => TvPairingSubmissionResult.accepted,
      onCancelled: () async => cancelled = true,
    );

    final cancelResponse = await _request(
      endpoint.cancelApiUri,
      method: 'POST',
      token: session.token,
      contentType: ContentType.json,
      body: utf8.encode('{}'),
    );

    expect(cancelResponse.statusCode, HttpStatus.ok);
    expect(cancelled, isTrue);
    expect(session.isCancelled, isTrue);

    await server.stop();
    session = TvPairingSession.issue(now: now);
    final expiredEndpoint = await server.start(
      session: session,
      onPayload: (_) async => TvPairingSubmissionResult.accepted,
    );
    now = now.add(const Duration(minutes: 5));
    final expiredResponse = await _request(
      expiredEndpoint.pairApiUri,
      method: 'POST',
      token: session.token,
      contentType: ContentType.json,
      body: _payloadBytes(),
    );
    expect(expiredResponse.statusCode, HttpStatus.gone);
    expect(session.isConsumed, isFalse);
  });
}

List<int> _payloadBytes() => utf8.encode(jsonEncode(<String, Object>{
      'protocolVersion': TvPairingPayload.currentProtocolVersion,
      'deviceName': '客厅电视',
      'tmdbApiKey': '',
      'cloudSources': <Object>[],
    }));

Future<_HttpResult> _request(
  Uri uri, {
  String method = 'GET',
  String? token,
  ContentType? contentType,
  List<int>? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, uri);
    if (token != null) request.headers.set('X-Pairing-Token', token);
    if (contentType != null) request.headers.contentType = contentType;
    if (body != null) request.add(body);
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    return _HttpResult(
      statusCode: response.statusCode,
      headers: response.headers,
      body: utf8.decode(bytes, allowMalformed: true),
    );
  } finally {
    client.close(force: true);
  }
}

class _HttpResult {
  const _HttpResult({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final HttpHeaders headers;
  final String body;
}

Future<int> _statusCodeOrClosed(Future<_HttpResult> request) async {
  try {
    return (await request).statusCode;
  } on SocketException {
    return -1;
  } on HttpException {
    return -1;
  }
}
