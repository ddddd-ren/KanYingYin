import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/tv_pairing/data/tv_pairing_http_server.dart';
import 'package:kanyingyin/features/tv_pairing/domain/tv_pairing_models.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';

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

  test('手机页面只在有效令牌下返回、不缓存且连接通知幂等', () async {
    var connected = 0;
    final endpoint = await server.start(
      session: session,
      onPhoneConnected: () => connected++,
      onPayload: (_) async => TvPairingSubmissionResult.rejected,
    );

    final valid = await _request(endpoint.pairUri);
    final repeated = await _request(endpoint.pairUri);
    final invalid = await _request(
      endpoint.pairUri.replace(queryParameters: <String, String>{
        'token': 'wrong-token',
        'v': TvPairingPayload.currentProtocolVersion.toString(),
      }),
    );

    expect(valid.statusCode, HttpStatus.ok);
    expect(repeated.statusCode, HttpStatus.ok);
    expect(connected, 1);
    expect(valid.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
    expect(valid.body, contains('TMDB API Key'));
    expect(valid.body, contains('夸克网盘'));
    expect(valid.body, contains('百度网盘'));
    expect(valid.body, contains('迅雷网盘'));
    expect(valid.body, isNot(contains('secret-tmdb-key')));
    expect(invalid.statusCode, HttpStatus.unauthorized);
  });

  test('POST 拒绝错误令牌、非 JSON 和超大载荷', () async {
    final endpoint = await server.start(
      session: session,
      onPhoneConnected: () {},
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
      onPhoneConnected: () {},
      onPayload: (payload) {
        receivedCount++;
        if (!payloadReceived.isCompleted) payloadReceived.complete();
        expect(payload.deviceName, '手机配置');
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

  test('电视写入失败和用户拒绝返回不同稳定状态且不消费令牌', () async {
    var result = TvPairingSubmissionResult.applyFailed;
    final endpoint = await server.start(
      session: session,
      onPhoneConnected: () {},
      onPayload: (_) async => result,
    );

    final failed = await _request(
      endpoint.pairApiUri,
      method: 'POST',
      token: session.token,
      contentType: ContentType.json,
      body: _payloadBytes(),
    );
    result = TvPairingSubmissionResult.rejected;
    final rejected = await _request(
      endpoint.pairApiUri,
      method: 'POST',
      token: session.token,
      contentType: ContentType.json,
      body: _payloadBytes(),
    );

    expect(failed.statusCode, HttpStatus.internalServerError);
    expect(failed.body, contains('apply_failed'));
    expect(rejected.statusCode, HttpStatus.conflict);
    expect(rejected.body, contains('rejected_on_tv'));
    expect(session.isConsumed, isFalse);
  });

  test('四类手机网盘字段映射为强类型来源和凭据', () async {
    late TvPairingPayload received;
    final endpoint = await server.start(
      session: session,
      onPhoneConnected: () {},
      onPayload: (payload) async {
        received = payload;
        return TvPairingSubmissionResult.rejected;
      },
    );

    final response = await _request(
      endpoint.pairApiUri,
      method: 'POST',
      token: session.token,
      contentType: ContentType.json,
      body: _payloadBytes(cloudSources: _allProviderRecords()),
    );

    expect(response.statusCode, HttpStatus.conflict);
    expect(
      received.configuration.cloudSources.map((record) => record.source.type),
      CloudSourceType.values,
    );
    final records = received.configuration.cloudSources;
    expect(records[0].source.rootPaths, <String>['/影视']);
    expect(records[0].credential?.username, 'viewer');
    expect(records[1].source.baseUrl, 'https://pan.quark.cn');
    expect(records[1].credential?.cookie, 'quark-cookie');
    expect(records[2].credential?.clientSecret, 'baidu-secret');
    expect(
        records[2].credential?.accessTokenExpiresAt, DateTime.utc(2026, 8, 9));
    expect(records[3].credential?.refreshToken, 'xunlei-refresh');
    expect(
        records.where((record) => record.requiresRootSelection), hasLength(3));
  });

  test('过期令牌和取消请求都会阻止配置提交', () async {
    var cancelled = false;
    final endpoint = await server.start(
      session: session,
      onPhoneConnected: () {},
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
      onPhoneConnected: () {},
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

  test('手机可以上传配置和刮削资料文件，提交时电视端收到临时文件', () async {
    TvPairingPayload? received;
    final endpoint = await server.start(
      session: session,
      onPhoneConnected: () {},
      onPayload: (payload) async {
        received = payload;
        expect(payload.uploadedFiles, hasLength(2));
        for (final file in payload.uploadedFiles.values) {
          expect(
              await File(file.path).readAsBytes(),
              file.kind == TvPairingFileKind.configuration
                  ? <int>[1, 2, 3]
                  : <int>[4, 5, 6]);
        }
        return TvPairingSubmissionResult.accepted;
      },
    );

    final configUpload = await _request(
      endpoint.fileUploadApiUri,
      method: 'POST',
      token: session.token,
      contentType: ContentType.binary,
      headers: <String, String>{
        'X-Pairing-File-Kind': 'configuration',
        'X-Pairing-File-Name': Uri.encodeComponent('看影音配置.kyyconfig'),
      },
      body: <int>[1, 2, 3],
    );
    final metaUpload = await _request(
      endpoint.fileUploadApiUri,
      method: 'POST',
      token: session.token,
      contentType: ContentType.binary,
      headers: <String, String>{
        'X-Pairing-File-Kind': 'scrapedMetadata',
        'X-Pairing-File-Name': Uri.encodeComponent('看影音刮削资料.kyymeta'),
      },
      body: <int>[4, 5, 6],
    );

    final configId = (jsonDecode(configUpload.body) as Map)['fileId'] as String;
    final metaId = (jsonDecode(metaUpload.body) as Map)['fileId'] as String;
    final response = await _request(
      endpoint.pairApiUri,
      method: 'POST',
      token: session.token,
      contentType: ContentType.json,
      body: _payloadBytes(
        fileIds: <String, String>{
          'configuration': configId,
          'scrapedMetadata': metaId,
        },
        configurationFilePassword: 'password-secret',
      ),
    );

    expect(configUpload.statusCode, HttpStatus.created);
    expect(metaUpload.statusCode, HttpStatus.created);
    expect(response.statusCode, HttpStatus.ok);
    expect(received?.fileIds[TvPairingFileKind.configuration], configId);
  });

  test('上传文件扩展名、令牌和大小限制生效', () async {
    final endpoint = await server.start(
      session: session,
      onPhoneConnected: () {},
      onPayload: (_) async => TvPairingSubmissionResult.accepted,
    );
    final invalidExtension = await _request(
      endpoint.fileUploadApiUri,
      method: 'POST',
      token: session.token,
      contentType: ContentType.binary,
      headers: <String, String>{
        'X-Pairing-File-Kind': 'configuration',
        'X-Pairing-File-Name': 'secret.txt',
      },
      body: <int>[1],
    );
    final invalidToken = await _request(
      endpoint.fileUploadApiUri,
      method: 'POST',
      token: 'wrong-token',
      contentType: ContentType.binary,
      headers: <String, String>{
        'X-Pairing-File-Kind': 'configuration',
        'X-Pairing-File-Name': 'config.kyyconfig',
      },
      body: <int>[1],
    );

    expect(invalidExtension.statusCode, HttpStatus.badRequest);
    expect(invalidToken.statusCode, HttpStatus.unauthorized);
  });
}

List<int> _payloadBytes({
  List<Object?> cloudSources = const <Object?>[],
  Map<String, String>? fileIds,
  String? configurationFilePassword,
}) =>
    utf8.encode(jsonEncode(<String, Object?>{
      'protocolVersion': TvPairingPayload.currentProtocolVersion,
      'deviceName': '手机配置',
      'configuration': <String, Object?>{
        'formatVersion': 1,
        'exportedAt': '2026-08-07T12:00:00.000Z',
        'appVersion': 'phone-web',
        'tmdbApiKey': '',
        'cloudSources': cloudSources,
      },
      if (fileIds != null) 'fileIds': fileIds,
      if (configurationFilePassword != null)
        'configurationFilePassword': configurationFilePassword,
    }));

List<Object?> _allProviderRecords() => <Object?>[
      <String, Object?>{
        'source': <String, Object?>{
          'id': 'openlist-1',
          'type': 'openList',
          'name': 'OpenList',
          'baseUrl': 'https://drive.example.com',
          'rootPaths': <String>['/影视'],
          'enabled': true,
          'allowSelfSignedCertificate': true,
        },
        'credential': <String, Object?>{
          'username': 'viewer',
          'password': 'openlist-password',
        },
      },
      <String, Object?>{
        'source': <String, Object?>{
          'id': 'quark-1',
          'type': 'quark',
          'name': '夸克',
          'baseUrl': 'https://pan.quark.cn',
          'rootPaths': <String>[],
          'rootRefs': <Object?>[],
        },
        'credential': <String, Object?>{'cookie': 'quark-cookie'},
      },
      <String, Object?>{
        'source': <String, Object?>{
          'id': 'baidu-1',
          'type': 'baidu',
          'name': '百度',
          'baseUrl': 'https://pan.baidu.com',
          'rootPaths': <String>[],
          'rootRefs': <Object?>[],
        },
        'credential': <String, Object?>{
          'clientId': 'baidu-client',
          'clientSecret': 'baidu-secret',
          'accessToken': 'baidu-access',
          'refreshToken': 'baidu-refresh',
          'accessTokenExpiresAt': '2026-08-09T00:00:00.000Z',
        },
      },
      <String, Object?>{
        'source': <String, Object?>{
          'id': 'xunlei-1',
          'type': 'xunlei',
          'name': '迅雷',
          'baseUrl': 'https://pan.xunlei.com',
          'rootPaths': <String>[],
          'rootRefs': <Object?>[],
        },
        'credential': <String, Object?>{'refreshToken': 'xunlei-refresh'},
      },
    ];

Future<_HttpResult> _request(
  Uri uri, {
  String method = 'GET',
  String? token,
  ContentType? contentType,
  Map<String, String> headers = const <String, String>{},
  List<int>? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, uri);
    if (token != null) request.headers.set('X-Pairing-Token', token);
    headers.forEach(request.headers.set);
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
