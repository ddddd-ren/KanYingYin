import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/tv_pairing/data/tv_pairing_phone_page.dart';

void main() {
  test('手机页面不依赖 template 且包含四类来源字段、倒计时和成功页面', () {
    final html = buildTvPairingPhonePage(
      token: 'pairing-token',
      expiresAt: DateTime.utc(2026, 8, 7, 12, 5),
    );

    expect(html, isNot(contains('<template')));
    expect(html, contains('id="add-source"'));
    expect(html, contains('scrollIntoView'));
    expect(html, contains('.focus()'));
    expect(html, contains('crypto.getRandomValues'));
    expect(html, contains('https://pan.quark.cn'));
    expect(html, contains('https://pan.baidu.com'));
    expect(html, contains('https://pan.xunlei.com'));
    expect(html, contains('clientSecret'));
    expect(html, contains('accessTokenExpiresAt'));
    expect(html, contains('refreshToken'));
    expect(html, contains('allowSelfSignedCertificate'));
    expect(html, contains('等待电视确认'));
    expect(html, contains('电视导入成功'));
    expect(html, contains('id="pairing-remaining"'));
    expect(html, contains('id="configuration-file"'));
    expect(html, contains('id="metadata-file"'));
    expect(html, contains('accept=".kyyconfig"'));
    expect(html, contains('accept=".kyymeta"'));
    expect(html, contains('/api/pair/file'));
    expect(html, contains('configurationFilePassword'));
    expect(html, contains('session_expired'));
    expect(html, contains('不要在公共 Wi-Fi 使用'));
    expect(html, isNot(contains('https://cdn.')));
  });

  test('令牌经过 JSON 编码且页面不包含配置秘密占位值', () {
    final html = buildTvPairingPhonePage(
      token: 'token"with-quote',
      expiresAt: DateTime.utc(2026, 8, 7, 12, 5),
    );

    expect(html, contains(r'token\"with-quote'));
    expect(html, isNot(contains('secret-tmdb-key')));
    expect(html, isNot(contains('secret-password')));
  });
}
