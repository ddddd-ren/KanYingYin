import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_api_client.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_authorization_controller.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';

void main() {
  test('登录成功只生成允许持久化的凭据', () async {
    final gateway = _FakeGateway();
    final controller = XunleiAuthorizationController(
      gateway: gateway,
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
    final gateway = _FakeGateway(challengeFirst: true);
    final controller = XunleiAuthorizationController(
      gateway: gateway,
      deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
    );

    await expectLater(
      controller.login(
        identifier: '13800000000',
        password: 'password-fixture',
      ),
      throwsA(isA<XunleiVerificationRequired>()),
    );
    expect(controller.state, XunleiAuthorizationState.verificationRequired);
    expect(controller.verificationUri?.host, 'i.xunlei.com');
    controller.cancelVerification();
    expect(controller.verificationUri, isNull);
    await expectLater(
      controller.completeVerification(),
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

    await controller.completeVerification();
    expect(gateway.lastCreditKey, 'credit-fixture');
    expect(controller.state, XunleiAuthorizationState.authorized);

    final expiredGateway = _FakeGateway(challengeFirst: true);
    final expired = XunleiAuthorizationController(
      gateway: expiredGateway,
      deviceIdGenerator: () => 'fedcba9876543210fedcba9876543210',
      now: () => now,
    );
    await expectLater(
      expired.login(identifier: 'user', password: 'password'),
      throwsA(isA<XunleiVerificationRequired>()),
    );
    now = now.add(const Duration(minutes: 11));
    await expectLater(
      expired.completeVerification(),
      throwsA(isA<CloudDriveException>().having(
        (error) => error.type,
        '类型',
        CloudDriveErrorType.verificationRequired,
      )),
    );
    expired.dispose();
    controller.dispose();
  });
}

class _FakeGateway implements XunleiAuthGateway {
  _FakeGateway({this.challengeFirst = false});

  final bool challengeFirst;
  var _loginCalls = 0;
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
    _loginCalls++;
    lastCreditKey = creditKey;
    if (challengeFirst && _loginCalls == 1) {
      throw XunleiVerificationRequired(
        uri: Uri.parse('https://i.xunlei.com/verify?ticket=fixture'),
        creditKey: 'credit-fixture',
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
