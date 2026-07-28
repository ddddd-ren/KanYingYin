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
