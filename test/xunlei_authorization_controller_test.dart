import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_api_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_authorization_controller.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_client_configuration.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_request_policy.dart';

void main() {
  const policy = XunleiRequestPolicy(
    configuration: XunleiClientConfiguration(
      clientId: 'client-fixture',
      clientSecret: 'client-secret-fixture',
      webClientId: 'web-client-fixture',
      appKey: 'app-key-fixture',
    ),
  );

  test('登录成功只生成允许持久化的凭据', () async {
    final gateway = _FakeGateway();
    final controller = XunleiAuthorizationController(
      gateway: gateway,
      policy: policy,
      deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
    );

    await controller.login(
      identifier: '13800000000',
      password: 'password-fixture',
    );

    final credential = controller.authorizedCredential;
    expect(controller.state, XunleiAuthorizationState.authorized);
    expect(credential?.refreshToken, 'refresh-fixture');
    expect(credential?.deviceId, '0123456789abcdef0123456789abcdef');
    expect(credential?.captchaToken, 'captcha-fixture');
    expect(credential?.accountLabel, '138****0000');
    expect(credential?.password, isNull);
    expect(credential?.accessToken, isNull);
    expect(controller.toString(), isNot(contains('password-fixture')));
    controller.dispose();
  });

  test('Refresh Token 授权保存服务端轮换值和固定设备 ID', () async {
    final gateway = _RefreshGateway();
    final controller = XunleiAuthorizationController(
      gateway: gateway,
      policy: policy,
      deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
    );

    await controller.authorizeWithRefreshToken(
      refreshToken: 'refresh-old',
    );

    final credential = controller.authorizedCredential;
    expect(controller.state, XunleiAuthorizationState.authorized);
    expect(gateway.lastRefreshToken, 'refresh-old');
    expect(credential?.refreshToken, 'refresh-rotated');
    expect(credential?.deviceId, '0123456789abcdef0123456789abcdef');
    expect(credential?.accountLabel, '138****0000');
    expect(credential?.accessToken, isNull);
    controller.dispose();
  });

  test('Refresh Token 失效显示明确提示且不生成凭据', () async {
    final controller = XunleiAuthorizationController(
      gateway: _RefreshGateway(
        error: const CloudDriveException(CloudDriveErrorType.authentication),
      ),
      deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
    );

    await expectLater(
      controller.authorizeWithRefreshToken(refreshToken: 'refresh-expired'),
      throwsA(isA<CloudDriveException>()),
    );
    expect(controller.authorizedCredential, isNull);
    expect(controller.errorMessage, 'Refresh Token 无效或已过期，请重新填写');
    controller.dispose();
  });

  test('账号确认失败不接受半完成 Token 凭据', () async {
    final controller = XunleiAuthorizationController(
      gateway: _RefreshGateway(
        accountError: const CloudDriveException(CloudDriveErrorType.network),
      ),
      deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
    );

    await expectLater(
      controller.authorizeWithRefreshToken(refreshToken: 'refresh-fixture'),
      throwsA(isA<CloudDriveException>()),
    );
    expect(controller.state, XunleiAuthorizationState.failed);
    expect(controller.authorizedCredential, isNull);
    controller.dispose();
  });

  test('Refresh Token 授权区分网络超时限流和协议更新', () async {
    final cases = <(CloudDriveErrorType, String)>[
      (CloudDriveErrorType.network, '网络连接失败，请检查网络后重试'),
      (CloudDriveErrorType.timeout, '迅雷授权请求超时，请稍后重试'),
      (CloudDriveErrorType.rateLimited, '迅雷请求过于频繁，请稍后再试'),
      (
        CloudDriveErrorType.protocolUpdated,
        '迅雷登录协议已更新，请重新获取 Refresh Token',
      ),
    ];

    for (final item in cases) {
      final controller = XunleiAuthorizationController(
        gateway: _RefreshGateway(error: CloudDriveException(item.$1)),
        deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
      );
      await expectLater(
        controller.authorizeWithRefreshToken(refreshToken: 'refresh-fixture'),
        throwsA(isA<CloudDriveException>()),
      );
      expect(controller.errorMessage, item.$2, reason: item.$1.name);
      controller.dispose();
    }
  });

  test('兼容登录遇到旧签名失效时建议改用 Refresh Token', () async {
    final controller = XunleiAuthorizationController(
      gateway: _RefreshGateway(
        error: const CloudDriveException(
          CloudDriveErrorType.protocolUpdated,
        ),
      ),
      deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
    );

    await expectLater(
      controller.login(identifier: 'account', password: 'password'),
      throwsA(isA<CloudDriveException>()),
    );
    expect(controller.errorMessage, '迅雷登录协议已更新，请改用 Refresh Token');
    controller.dispose();
  });

  test('明确密码错误使用独立类型和用户提示', () async {
    final controller = XunleiAuthorizationController(
      gateway: _RefreshGateway(
        error: const CloudDriveException(
          CloudDriveErrorType.invalidPassword,
        ),
      ),
      deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
    );

    await expectLater(
      controller.login(identifier: 'account', password: 'wrong-password'),
      throwsA(isA<CloudDriveException>().having(
        (error) => error.type,
        '类型',
        CloudDriveErrorType.invalidPassword,
      )),
    );
    expect(controller.errorMessage, '迅雷密码错误，请重新输入');
    expect(controller.authorizedCredential, isNull);
    controller.dispose();
  });

  test('需要验证时取消会清除临时秘密并禁止重试', () async {
    final now = DateTime.utc(2026, 7, 28, 10);
    final gateway = _FakeGateway(challengeFirst: true);
    final controller = XunleiAuthorizationController(
      gateway: gateway,
      policy: policy,
      deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
      now: () => now,
    );

    await expectLater(
      controller.login(
        identifier: '13800000000',
        password: 'password-fixture',
      ),
      throwsA(isA<XunleiVerificationRequired>()),
    );
    expect(controller.state, XunleiAuthorizationState.verificationRequired);
    final challenge = controller.verificationChallenge;
    expect(challenge?.reviewUri.host, 'i.xunlei.com');
    expect(challenge?.creditKey, 'credit-initial');
    expect(challenge?.deviceId, '0123456789abcdef0123456789abcdef');
    expect(challenge?.deviceSign, startsWith('div101.'));
    expect(challenge?.startedAt, now);
    controller.cancelVerification();
    expect(controller.verificationChallenge, isNull);
    await expectLater(
      controller.completeVerification(creditKey: 'credit-new'),
      throwsA(isA<CloudDriveException>()),
    );
    expect(controller.toString(), isNot(contains('password-fixture')));
    controller.dispose();
  });

  test('完成验证携带临时密钥重试且十分钟后拒绝', () async {
    var now = DateTime.utc(2026, 7, 28, 10);
    final gateway = _FakeGateway(challengeFirst: true);
    final controller = XunleiAuthorizationController(
      gateway: gateway,
      policy: policy,
      deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
      now: () => now,
    );
    await expectLater(
      controller.login(
        identifier: 'user-fixture',
        password: 'password-fixture',
      ),
      throwsA(isA<XunleiVerificationRequired>()),
    );

    await controller.completeVerification(creditKey: 'credit-new');
    expect(gateway.lastCreditKey, 'credit-new');
    expect(gateway.loginCalls, 2);
    expect(controller.verificationChallenge, isNull);
    expect(controller.state, XunleiAuthorizationState.authorized);

    final expiredGateway = _FakeGateway(challengeFirst: true);
    final expired = XunleiAuthorizationController(
      gateway: expiredGateway,
      policy: policy,
      deviceIdGenerator: () => 'fedcba9876543210fedcba9876543210',
      now: () => now,
    );
    await expectLater(
      expired.login(identifier: 'user', password: 'password'),
      throwsA(isA<XunleiVerificationRequired>()),
    );
    now = now.add(const Duration(minutes: 11));
    await expectLater(
      expired.completeVerification(creditKey: 'credit-new-expired'),
      throwsA(isA<CloudDriveException>().having(
        (error) => error.type,
        '类型',
        CloudDriveErrorType.verificationRequired,
      )),
    );
    expired.dispose();
    controller.dispose();
  });

  test('验证成功必须提供不同于初始值的新 CreditKey', () async {
    final controller = XunleiAuthorizationController(
      gateway: _FakeGateway(challengeFirst: true),
      policy: policy,
      deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
    );
    await expectLater(
      controller.login(identifier: 'user', password: 'password'),
      throwsA(isA<XunleiVerificationRequired>()),
    );
    await expectLater(
      controller.completeVerification(creditKey: 'credit-initial'),
      throwsA(isA<CloudDriveException>().having(
        (error) => error.type,
        '类型',
        CloudDriveErrorType.incompatible,
      )),
    );
    expect(controller.verificationChallenge, isNull);
    expect(controller.authorizedCredential, isNull);
    controller.dispose();
  });

  test('续登再次收到挑战时停止循环并清除秘密', () async {
    final gateway = _FakeGateway(challengeEveryTime: true);
    final controller = XunleiAuthorizationController(
      gateway: gateway,
      policy: policy,
      deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
    );
    await expectLater(
      controller.login(identifier: 'user', password: 'password-secret'),
      throwsA(isA<XunleiVerificationRequired>()),
    );
    await expectLater(
      controller.completeVerification(creditKey: 'credit-new'),
      throwsA(isA<CloudDriveException>().having(
        (error) => error.type,
        '类型',
        CloudDriveErrorType.verificationRequired,
      )),
    );
    expect(gateway.loginCalls, 2);
    expect(controller.verificationChallenge, isNull);
    expect(controller.errorMessage, '迅雷再次要求设备验证，请重新登录');
    expect(controller.toString(), isNot(contains('password-secret')));
    controller.dispose();
  });

  test('页面失败会结束验证并清除挑战', () async {
    final controller = XunleiAuthorizationController(
      gateway: _FakeGateway(challengeFirst: true),
      policy: policy,
      deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
    );
    await expectLater(
      controller.login(identifier: 'user', password: 'password'),
      throwsA(isA<XunleiVerificationRequired>()),
    );
    controller.failVerification('迅雷验证页面加载失败');
    expect(controller.state, XunleiAuthorizationState.failed);
    expect(controller.verificationChallenge, isNull);
    expect(controller.errorMessage, '迅雷验证页面加载失败');
    controller.dispose();
  });
}

class _FakeGateway implements XunleiAuthGateway {
  _FakeGateway({
    this.challengeFirst = false,
    this.challengeEveryTime = false,
  });

  final bool challengeFirst;
  final bool challengeEveryTime;
  var loginCalls = 0;
  String? lastCreditKey;

  @override
  String? get captchaToken => 'captcha-fixture';

  @override
  Future<XunleiSession> login({
    required String identifier,
    required String password,
    required String deviceId,
    String? captchaToken,
    String? creditKey,
  }) async {
    loginCalls++;
    lastCreditKey = creditKey;
    if (challengeEveryTime || (challengeFirst && loginCalls == 1)) {
      throw XunleiVerificationRequired(
        uri: Uri.parse('https://i.xunlei.com/verify?ticket=fixture'),
        creditKey: 'credit-initial',
      );
    }
    return XunleiSession(
      tokenType: 'Bearer',
      accessToken: 'access-fixture',
      refreshToken: 'refresh-fixture',
      expiresAt: DateTime.utc(2026, 7, 28, 12),
      userId: 'user-fixture',
    );
  }

  @override
  Future<XunleiSession> refresh({
    required String refreshToken,
    required String deviceId,
    String? captchaToken,
  }) =>
      throw UnimplementedError();

  @override
  Future<XunleiAccount> account(XunleiSession session) async =>
      const XunleiAccount(
        userId: 'user-fixture',
        accountLabel: '138****0000',
      );

  @override
  Future<void> close() async {}
}

class _RefreshGateway implements XunleiAuthGateway {
  _RefreshGateway({this.error, this.accountError});

  final CloudDriveException? error;
  final CloudDriveException? accountError;
  String? lastRefreshToken;

  @override
  String? get captchaToken => 'captcha-fixture';

  @override
  Future<XunleiSession> refresh({
    required String refreshToken,
    required String deviceId,
    String? captchaToken,
  }) async {
    lastRefreshToken = refreshToken;
    if (error case final failure?) throw failure;
    return XunleiSession(
      tokenType: 'Bearer',
      accessToken: 'access-fixture',
      refreshToken: 'refresh-rotated',
      expiresAt: DateTime.utc(2026, 7, 29, 12),
      userId: 'user-fixture',
    );
  }

  @override
  Future<XunleiAccount> account(XunleiSession session) async {
    if (accountError case final failure?) throw failure;
    return const XunleiAccount(
      userId: 'user-fixture',
      accountLabel: '138****0000',
    );
  }

  @override
  Future<XunleiSession> login({
    required String identifier,
    required String password,
    required String deviceId,
    String? captchaToken,
    String? creditKey,
  }) async {
    if (error case final failure?) throw failure;
    return XunleiSession(
      tokenType: 'Bearer',
      accessToken: 'access-login-fixture',
      refreshToken: 'refresh-login-fixture',
      expiresAt: DateTime.utc(2026, 7, 29, 12),
      userId: 'user-fixture',
    );
  }

  @override
  Future<void> close() async {}
}
