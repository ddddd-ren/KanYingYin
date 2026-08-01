import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_api_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_client_configuration.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_request_policy.dart';

void main() {
  const deviceId = '0123456789abcdef0123456789abcdef';
  const configuration = XunleiClientConfiguration(
    clientId: 'client-fixture',
    clientSecret: 'client-secret-fixture',
    webClientId: 'web-client-fixture',
    appKey: 'app-key-fixture',
  );
  const policy = XunleiRequestPolicy(configuration: configuration);

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
      policy: policy,
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
    final captchaRequest = adapter.requests[1].data as Map<Object?, Object?>;
    final captchaMeta = captchaRequest['meta'] as Map<Object?, Object?>;
    expect(captchaMeta, containsPair('phone_number', '13800000000'));
    expect(captchaMeta, isNot(contains('timestamp')));
    expect(captchaMeta, isNot(contains('captcha_sign')));
    expect(session.refreshToken, 'refresh-fixture');
    expect(client.captchaToken, 'captcha-fixture');
    expect(client.toString(), isNot(contains('password-fixture')));
    await client.close();
  });

  test('账号接口已授权但缺少展示字段时复用令牌会话身份', () async {
    final adapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(
        200,
        '{"token_type":"Bearer","access_token":"access-fixture","refresh_token":"refresh-fixture","expires_in":3600,"user_id":"user-fixture"}',
      ),
      const _FakeResponse(200, '{}'),
    ]);
    final client = XunleiApiClient(
      deviceId: deviceId,
      policy: policy,
      dio: Dio()..httpClientAdapter = adapter,
    );

    final session = await client.refresh(
      refreshToken: 'refresh-fixture',
      deviceId: deviceId,
    );
    final account = await client.account(session);

    expect(account.userId, 'user-fixture');
    expect(account.accountLabel, '迅雷账号');
    await client.close();
  });

  test('验证码签名失效映射为协议更新且日志不含秘密', () async {
    final logs = <String>[];
    final adapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(200, '{"sessionID":"session-fixture"}'),
      const _FakeResponse(
        400,
        '{"error":"invalid_argument","error_code":3,"error_description":"invalid captcha_sign secret-body"}',
      ),
    ]);
    final client = XunleiApiClient(
      deviceId: deviceId,
      policy: policy,
      dio: Dio()..httpClientAdapter = adapter,
      requestLog: logs.add,
    );

    await expectLater(
      client.login(
        identifier: 'account-secret',
        password: 'password-secret',
        deviceId: deviceId,
      ),
      throwsA(
        isA<CloudDriveException>().having(
          (error) => error.type,
          '错误类型',
          CloudDriveErrorType.protocolUpdated,
        ),
      ),
    );

    final text = logs.join('\n');
    expect(text, contains('captchaInit'));
    expect(text, contains('protocolUpdated'));
    for (final secret in <String>[
      'account-secret',
      'password-secret',
      'session-fixture',
      'secret-body',
      deviceId,
    ]) {
      expect(text, isNot(contains(secret)));
    }
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
    final client = XunleiApiClient(
      deviceId: deviceId,
      policy: policy,
      dio: dio,
    );

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

  test('安卓参数拒绝网页 Refresh Token 后按网页客户端参数重试', () async {
    final logs = <String>[];
    final adapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(
        400,
        '{"error":"unauthorized_client","error_description":"client mismatch"}',
      ),
      const _FakeResponse(
        200,
        '{"token_type":"Bearer","access_token":"access-web","refresh_token":"refresh-web-next","expires_in":3600,"user_id":"user-web"}',
      ),
      const _FakeResponse(
        200,
        '{"captcha_token":"captcha-web","expires_in":3600}',
      ),
      const _FakeResponse(
        200,
        '{"user_id":"user-web","name":"网页账号"}',
      ),
    ]);
    final client = XunleiApiClient(
      deviceId: deviceId,
      policy: policy,
      dio: Dio()..httpClientAdapter = adapter,
      requestLog: logs.add,
    );

    final session = await client.refresh(
      refreshToken: 'refresh-web-secret',
      deviceId: deviceId,
    );
    final account = await client.account(session);

    expect(session.refreshToken, 'refresh-web-next');
    expect(account.accountLabel, '网页账号');
    expect(adapter.requests, hasLength(4));
    final androidBody = adapter.requests[0].data as Map<Object?, Object?>;
    final webBody = adapter.requests[1].data as Map<Object?, Object?>;
    expect(androidBody['client_id'], configuration.clientId);
    expect(androidBody, contains('client_secret'));
    expect(webBody['client_id'], configuration.webClientId);
    expect(webBody, isNot(contains('client_secret')));
    expect(
      adapter.requests[1].headers['x-client-id'],
      configuration.webClientId,
    );
    expect(adapter.requests[1].headers['x-sdk-version'], '3.4.20');
    expect(adapter.requests[1].headers['x-action'], '401');
    expect(adapter.requests[1].headers['x-device-id'], deviceId);
    expect(
      adapter.requests[2].headers['x-client-id'],
      configuration.webClientId,
    );
    expect(adapter.requests[2].headers['x-sdk-version'], '3.4.20');
    expect(
      adapter.requests[3].headers['x-client-id'],
      configuration.webClientId,
    );
    expect(adapter.requests[3].headers['x-sdk-version'], '3.4.20');
    expect(adapter.requests[3].headers['x-captcha-token'], 'captcha-web');
    expect(logs.join('\n'), isNot(contains('refresh-web-secret')));
    await client.close();
  });

  test('网页 Refresh Token 授权后先获取 Shield Token 再请求账号', () async {
    final adapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(
        400,
        '{"error":"unauthorized_client","error_description":"client mismatch"}',
      ),
      const _FakeResponse(
        200,
        '{"token_type":"Bearer","access_token":"access-web","refresh_token":"refresh-web-next","expires_in":3600,"user_id":"user-web"}',
      ),
      const _FakeResponse(
        200,
        '{"captcha_token":"captcha-web","expires_in":3600}',
      ),
      const _FakeResponse(
        200,
        '{"user_id":"user-web","name":"网页账号"}',
      ),
    ]);
    final client = XunleiApiClient(
      deviceId: deviceId,
      policy: policy,
      dio: Dio()..httpClientAdapter = adapter,
    );

    final session = await client.refresh(
      refreshToken: 'refresh-web-secret',
      deviceId: deviceId,
    );
    final account = await client.account(session);

    expect(account.accountLabel, '网页账号');
    expect(
      adapter.requests.map((request) => request.uri.path),
      <String>[
        '/v1/auth/token',
        '/v1/auth/token',
        '/v1/shield/captcha/init',
        '/v1/user/me',
      ],
    );
    final shieldBody = adapter.requests[2].data as Map<Object?, Object?>;
    expect(shieldBody['client_id'], configuration.webClientId);
    expect(shieldBody['device_id'], deviceId);
    expect(shieldBody['action'], 'GET:/v1/user/me');
    expect(shieldBody['captcha_token'], '');
    expect(shieldBody['meta'], <String, String>{
      'username': '',
      'phone_number': '',
      'email': '',
    });
    expect(
      adapter.requests[2].headers['x-client-id'],
      configuration.webClientId,
    );
    expect(adapter.requests[3].headers['x-captcha-token'], 'captcha-web');
    expect(client.captchaToken, 'captcha-web');
    await client.close();
  });

  test('网页目录请求遇到 Captcha 失效时刷新 Shield Token 并仅重试一次', () async {
    final adapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(
        400,
        '{"error":"unauthorized_client","error_description":"client mismatch"}',
      ),
      const _FakeResponse(
        200,
        '{"token_type":"Bearer","access_token":"access-web","refresh_token":"refresh-web-next","expires_in":3600,"user_id":"user-web"}',
      ),
      const _FakeResponse(
        200,
        '{"captcha_token":"captcha-old","expires_in":3600}',
      ),
      const _FakeResponse(200, '{"user_id":"user-web"}'),
      const _FakeResponse(
        400,
        '{"error":"captcha_required"}',
      ),
      const _FakeResponse(
        200,
        '{"captcha_token":"captcha-new","expires_in":3600}',
      ),
      const _FakeResponse(200, '{"files":[],"next_page_token":""}'),
    ]);
    final client = XunleiApiClient(
      deviceId: deviceId,
      policy: policy,
      dio: Dio()..httpClientAdapter = adapter,
    );

    final session = await client.refresh(
      refreshToken: 'refresh-web-secret',
      deviceId: deviceId,
    );
    await client.account(session);
    final page = await client.listDirectoryPage(directoryId: '0');

    expect(page.files, isEmpty);
    expect(
      adapter.requests.map((request) => request.uri.path),
      <String>[
        '/v1/auth/token',
        '/v1/auth/token',
        '/v1/shield/captcha/init',
        '/v1/user/me',
        '/drive/v1/files',
        '/v1/shield/captcha/init',
        '/drive/v1/files',
      ],
    );
    final renewedShieldBody = adapter.requests[5].data as Map<Object?, Object?>;
    expect(renewedShieldBody['action'], 'GET:/drive/v1/files');
    expect(renewedShieldBody['captcha_token'], 'captcha-old');
    expect(adapter.requests[6].headers['x-captcha-token'], 'captcha-new');
    expect(client.captchaToken, 'captcha-new');
    await client.close();
  });

  test('安卓令牌目录请求遇到 Captcha 失效时按当前客户端刷新并重试', () async {
    final now = DateTime.utc(2026, 7, 30, 4, 50);
    final adapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(
        200,
        '{"token_type":"Bearer","access_token":"access-android","refresh_token":"refresh-android-next","expires_in":3600,"user_id":"user-android"}',
      ),
      const _FakeResponse(200, '{"user_id":"user-android"}'),
      const _FakeResponse(400, '{"error":"captcha_required"}'),
      const _FakeResponse(
        200,
        '{"captcha_token":"captcha-android","expires_in":3600}',
      ),
      const _FakeResponse(200, '{"files":[],"next_page_token":""}'),
    ]);
    final client = XunleiApiClient(
      deviceId: deviceId,
      policy: policy,
      dio: Dio()..httpClientAdapter = adapter,
      now: () => now,
    );

    final session = await client.refresh(
      refreshToken: 'refresh-android-secret',
      deviceId: deviceId,
    );
    await client.account(session);
    final page = await client.listDirectoryPage(directoryId: '0');

    expect(page.files, isEmpty);
    final shieldRequest = adapter.requests[3];
    final shieldBody = shieldRequest.data as Map<Object?, Object?>;
    expect(shieldRequest.headers['x-client-id'], configuration.clientId);
    expect(shieldBody['client_id'], configuration.clientId);
    expect(shieldBody['action'], 'GET:/drive/v1/files');
    final timestamp = '${now.millisecondsSinceEpoch}';
    expect(shieldBody['meta'], <String, String>{
      'client_version': XunleiRequestPolicy.clientVersion,
      'package_name': XunleiRequestPolicy.packageName,
      'user_id': 'user-android',
      'timestamp': timestamp,
      'captcha_sign': policy.captchaSign(
        deviceId: deviceId,
        timestamp: timestamp,
      ),
    });
    expect(
      adapter.requests[4].headers['x-captcha-token'],
      'captcha-android',
    );
    await client.close();
  });

  test('核心登录验证响应修复短信页地址并绑定当前设备', () async {
    final adapter = _QueueAdapter(<_FakeResponse>[
      const _FakeResponse(
        200,
        '{"error":"review_panel","creditkey":"credit-secret","reviewurl":"https://i.xunlei.com/xlcaptcha/verifyPhone.html?mobile=138****0000&userID=user-fixture&creditkey=url-credit-fixture"}',
      ),
    ]);
    final client = XunleiApiClient(
      deviceId: deviceId,
      policy: policy,
      dio: Dio()..httpClientAdapter = adapter,
    );

    Object? captured;
    try {
      await client.login(
        identifier: 'user-fixture',
        password: 'password-fixture',
        deviceId: deviceId,
      );
    } on Object catch (error) {
      captured = error;
    }

    expect(captured, isA<XunleiVerificationRequired>());
    final challenge = captured! as XunleiVerificationRequired;
    expect(challenge.uri.host, 'i.xunlei.com');
    expect(challenge.uri.path, '/xlcaptcha/vertifyPhone.html');
    expect(challenge.uri.queryParameters['mobile'], '138****0000');
    expect(challenge.uri.queryParameters['userID'], 'user-fixture');
    expect(
      challenge.uri.queryParameters['deviceid'],
      startsWith('div101.$deviceId'),
    );
    await client.close();
  });

  test('只有核心登录明确密码错误才映射 invalidPassword', () async {
    final cases = <(int, String, CloudDriveErrorType)>[
      (
        401,
        '{"error":"invalid_password"}',
        CloudDriveErrorType.invalidPassword,
      ),
      (
        400,
        '{"error":"password_error"}',
        CloudDriveErrorType.invalidPassword,
      ),
      (
        400,
        '{"error":"invalid_argument","error_description":"密码错误"}',
        CloudDriveErrorType.invalidPassword,
      ),
      (
        401,
        '{"error":"authentication_failed","error_description":"bad credentials"}',
        CloudDriveErrorType.authentication,
      ),
      (
        400,
        '{"error":"invalid_argument","error_description":"invalid captcha_sign"}',
        CloudDriveErrorType.protocolUpdated,
      ),
    ];

    for (final item in cases) {
      final client = XunleiApiClient(
        deviceId: deviceId,
        policy: policy,
        dio: Dio()
          ..httpClientAdapter = _QueueAdapter(<_FakeResponse>[
            _FakeResponse(item.$1, item.$2),
          ]),
      );
      await expectLater(
        client.login(
          identifier: 'account-fixture',
          password: 'password-fixture',
          deviceId: deviceId,
        ),
        throwsA(
          isA<CloudDriveException>().having(
            (error) => error.type,
            '错误类型',
            item.$3,
          ),
        ),
      );
      await client.close();
    }
  });

  test('Refresh Token 接口的密码字样不会误报账号密码错误', () async {
    final client = XunleiApiClient(
      deviceId: deviceId,
      policy: policy,
      dio: Dio()
        ..httpClientAdapter = _QueueAdapter(<_FakeResponse>[
          const _FakeResponse(
            401,
            '{"error":"invalid_password","error_description":"wrong password"}',
          ),
        ]),
    );

    await expectLater(
      client.refresh(
        refreshToken: 'refresh-fixture',
        deviceId: deviceId,
      ),
      throwsA(isA<CloudDriveException>().having(
        (error) => error.type,
        '错误类型',
        CloudDriveErrorType.authentication,
      )),
    );
    await client.close();
  });

  test('Refresh Token 接口的 HTTP 400 参数错误映射为令牌无效', () async {
    final client = XunleiApiClient(
      deviceId: deviceId,
      policy: policy,
      dio: Dio()
        ..httpClientAdapter = _QueueAdapter(<_FakeResponse>[
          const _FakeResponse(
            400,
            '{"error":"invalid_argument","error_code":3,"error_description":"invalid refresh token"}',
          ),
        ]),
    );

    await expectLater(
      client.refresh(
        refreshToken: 'refresh-fixture',
        deviceId: deviceId,
      ),
      throwsA(isA<CloudDriveException>().having(
        (error) => error.type,
        '错误类型',
        CloudDriveErrorType.authentication,
      )),
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
