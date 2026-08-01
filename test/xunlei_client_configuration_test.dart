import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_client_configuration.dart';

void main() {
  test('迅雷构建配置必须四项完整才可用', () {
    expect(const XunleiClientConfiguration().isConfigured, isFalse);
    expect(
      const XunleiClientConfiguration(
        clientId: 'client-fixture',
        clientSecret: 'secret-fixture',
        webClientId: 'web-fixture',
        appKey: 'app-key-fixture',
      ).isConfigured,
      isTrue,
    );
  });

  test('迅雷构建配置字符串不会暴露字段值', () {
    const configuration = XunleiClientConfiguration(
      clientId: 'client-fixture',
      clientSecret: 'secret-fixture',
      webClientId: 'web-fixture',
      appKey: 'app-key-fixture',
    );

    expect(configuration.toString(), contains('configured: true'));
    expect(configuration.toString(), isNot(contains('secret-fixture')));
    expect(configuration.toString(), isNot(contains('app-key-fixture')));
  });
}
