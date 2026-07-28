import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_api_client.dart';

void main() {
  const deviceId = '0123456789abcdef0123456789abcdef';

  test('登录依次请求核心登录、验证码和令牌接口', () async {
    final adapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(200, '{"sessionID":"session-fixture"}'),
      const _FakeResponse(
        200,
        '{"captcha_token":"captcha-fixture","expires_in":3600,"url":""}',
      ),
      const _FakeResponse(
        200,
        '{"token_type":"Bearer","access_token":"access-fixture","refresh_token":"refresh-fixture","expires_in":3600,"user_id":"user-fixture"}',
      ),
    ]);
    final client = XunleiApiClient(
      deviceId: deviceId,
      dio: Dio()..httpClientAdapter = adapter,
      now: () => DateTime.utc(2026, 7, 28),
    );

    final session = await client.login(
      identifier: '13800000000',
      password: 'password-fixture',
      deviceId: deviceId,
    );

    expect(adapter.requests.map((request) => request.uri.path), <String>[
      '/xluser.core.login/v3/login',
      '/v1/shield/captcha/init',
      '/v1/auth/signin/token',
    ]);
    expect(
        adapter.requests.first.data, containsPair('userName', '13800000000'));
    expect(adapter.requests.first.data,
        containsPair('passWord', 'password-fixture'));
    expect(session.refreshToken, 'refresh-fixture');
    expect(client.captchaToken, 'captcha-fixture');
    expect(client.toString(), isNot(contains('password-fixture')));
    await client.close();
  });

  test('刷新令牌使用受限超时且异常不泄漏响应内容', () async {
    final dio = Dio();
    final adapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(
        200,
        '{"token_type":"Bearer","access_token":"access-next","refresh_token":"refresh-next","expires_in":3600,"user_id":"user-fixture"}',
      ),
      const _FakeResponse(
        401,
        '{"error_code":16,"error":"refresh-secret-fixture"}',
      ),
    ]);
    dio.httpClientAdapter = adapter;
    final client = XunleiApiClient(deviceId: deviceId, dio: dio);

    final session = await client.refresh(
      refreshToken: 'refresh-fixture',
      deviceId: deviceId,
    );
    expect(session.refreshToken, 'refresh-next');
    expect(dio.options.connectTimeout, const Duration(seconds: 10));
    expect(dio.options.sendTimeout, const Duration(seconds: 15));
    expect(dio.options.receiveTimeout, const Duration(seconds: 30));

    Object? captured;
    try {
      await client.refresh(
        refreshToken: 'refresh-secret-fixture',
        deviceId: deviceId,
      );
    } catch (error) {
      captured = error;
    }
    expect(captured, isA<CloudDriveException>());
    expect(
      (captured! as CloudDriveException).type,
      CloudDriveErrorType.authentication,
    );
    expect(captured.toString(), isNot(contains('refresh-secret-fixture')));
    await client.close();
  });

  test('核心登录验证响应转换为脱敏挑战', () async {
    final adapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(
        200,
        '{"error":"review_panel","creditkey":"credit-secret","reviewurl":"https://i.xunlei.com/verify?ticket=secret"}',
      ),
    ]);
    final client = XunleiApiClient(
      deviceId: deviceId,
      dio: Dio()..httpClientAdapter = adapter,
    );

    await expectLater(
      client.login(
        identifier: 'user-fixture',
        password: 'password-fixture',
        deviceId: deviceId,
      ),
      throwsA(
        isA<XunleiVerificationRequired>().having(
          (challenge) => challenge.uri.host,
          '验证主机',
          'i.xunlei.com',
        ),
      ),
    );
    await client.close();
  });
}

class _FakeResponse {
  const _FakeResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this.responses);

  final List<_FakeResponse> responses;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = responses.removeAt(0);
    return ResponseBody.fromString(
      response.body,
      response.statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
