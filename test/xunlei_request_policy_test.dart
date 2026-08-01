import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_client_configuration.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_request_policy.dart';

void main() {
  const configuration = XunleiClientConfiguration(
    clientId: 'client-fixture',
    clientSecret: 'secret-fixture',
    webClientId: 'web-fixture',
    appKey: 'app-key-fixture',
  );
  const policy = XunleiRequestPolicy(configuration: configuration);
  const deviceId = '0123456789abcdef0123456789abcdef';

  test('生成稳定设备签名和验证码签名', () {
    expect(policy.deviceSign(deviceId), startsWith('div101.$deviceId'));
    expect(
      policy.captchaSign(
        deviceId: deviceId,
        timestamp: '1700000000000',
      ),
      startsWith('1.'),
    );
    expect(
      policy.captchaSign(
        deviceId: deviceId,
        timestamp: '1700000000000',
      ),
      policy.captchaSign(
        deviceId: deviceId,
        timestamp: '1700000000000',
      ),
    );
  });

  test('只信任迅雷 HTTPS 验证和下载地址', () {
    expect(
      policy.isTrustedVerificationUri(
        Uri.parse('https://i.xunlei.com/verify?id=fixture'),
      ),
      isTrue,
    );
    expect(
      policy.isTrustedVerificationUri(
        Uri.parse('http://i.xunlei.com/verify'),
      ),
      isFalse,
    );
    expect(
      policy.isTrustedDownloadUri(
        Uri.parse('https://download.xunlei.com/file'),
      ),
      isTrue,
    );
    for (final uri in <Uri>[
      Uri.parse('https://127.0.0.1/file'),
      Uri.parse('https://192.168.1.2/file'),
      Uri.parse('https://xunlei.com.evil.example/file'),
      Uri.parse('http://download.xunlei.com/file'),
    ]) {
      expect(policy.isTrustedDownloadUri(uri), isFalse, reason: '$uri');
    }
  });

  test('API 请求头绑定设备 ID 与设备签名且不包含令牌和账号', () {
    for (final profile in XunleiClientProfile.values) {
      final headers = policy.apiHeaders(
        deviceId: deviceId,
        profile: profile,
      );

      expect(headers['x-device-id'], deviceId);
      expect(headers['x-device-sign'], policy.deviceSign(deviceId));
      expect(headers.keys, isNot(contains('Authorization')));
      expect(headers.toString(), isNot(contains('password')));
    }
  });

  test('缺少构建配置时签名请求会被拒绝', () {
    expect(
      () => const XunleiRequestPolicy().deviceSign(deviceId),
      throwsA(isA<StateError>()),
    );
  });
}
