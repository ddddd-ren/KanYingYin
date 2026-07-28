import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';

void main() {
  test('迅雷来源和凭据安全往返且不包含登录秘密', () {
    const source = CloudSource(
      id: 'xunlei-a',
      type: CloudSourceType.xunlei,
      name: '迅雷网盘',
      baseUrl: 'https://pan.xunlei.com',
      rootPaths: <String>['/影视'],
    );
    const credential = CloudCredential(
      refreshToken: 'refresh-fixture',
      deviceId: '0123456789abcdef0123456789abcdef',
      captchaToken: 'captcha-fixture',
      userId: 'user-fixture',
      accountLabel: '138****0000',
    );

    expect(CloudSource.fromJson(source.toJson()), source);
    expect(credential.toJson(), isNot(contains('password')));
    expect(credential.toJson(), isNot(contains('accessToken')));
    expect(credential.toJson(), isNot(contains('creditKey')));
    final restored = CloudCredential.fromJson(credential.toJson());
    expect(restored.refreshToken, credential.refreshToken);
    expect(restored.deviceId, credential.deviceId);
    expect(restored.captchaToken, credential.captchaToken);
    expect(restored.userId, credential.userId);
    expect(restored.accountLabel, credential.accountLabel);
  });

  test('迅雷凭据字符串不会暴露敏感字段', () {
    const credential = CloudCredential(
      refreshToken: 'refresh-secret',
      deviceId: '0123456789abcdef0123456789abcdef',
      captchaToken: 'captcha-secret',
      userId: 'user-fixture',
      accountLabel: 'user***',
    );

    final description = credential.toString();
    expect(description, isNot(contains('refresh-secret')));
    expect(description, isNot(contains('captcha-secret')));
    expect(description, isNot(contains('0123456789abcdef')));
  });
}
