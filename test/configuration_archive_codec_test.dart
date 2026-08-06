import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_archive_codec.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';

void main() {
  final configuration = PortableAppConfiguration.create(
    exportedAt: DateTime.utc(2026, 8, 7),
    appVersion: '2.1.142',
    tmdbApiKey: 'tmdb-secret',
    cloudSources: const <PortableCloudSourceConfiguration>[],
  );
  final codec = ConfigurationArchiveCodec();

  test('AES-GCM 配置包使用正确密码往返且每次 Salt 和 Nonce 不同', () async {
    final first = await codec.encrypt(
      configuration,
      password: 'correct-pass',
    );
    final second = await codec.encrypt(
      configuration,
      password: 'correct-pass',
    );
    final firstJson = jsonDecode(utf8.decode(first)) as Map<String, dynamic>;
    final secondJson = jsonDecode(utf8.decode(second)) as Map<String, dynamic>;

    expect(firstJson['format'], 'kyy-config');
    expect(firstJson['envelopeVersion'], 1);
    expect(firstJson['kdf']['iterations'], 600000);
    expect(firstJson['kdf']['salt'], isNot(secondJson['kdf']['salt']));
    expect(firstJson['cipher']['nonce'], isNot(secondJson['cipher']['nonce']));
    expect(
      (await codec.decrypt(first, password: 'correct-pass')).tmdbApiKey,
      'tmdb-secret',
    );
  });

  test('错误密码和密文篡改统一返回认证失败', () async {
    final bytes = await codec.encrypt(
      configuration,
      password: 'correct-pass',
    );
    expect(
      codec.decrypt(bytes, password: 'wrong-pass'),
      throwsA(isA<ConfigurationArchiveAuthenticationException>()),
    );

    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final cipher = envelope['cipher'] as Map<String, dynamic>;
    final ciphertext = base64Decode(cipher['ciphertext'] as String);
    ciphertext[0] ^= 0x01;
    cipher['ciphertext'] = base64Encode(ciphertext);

    expect(
      codec.decrypt(
        Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
        password: 'correct-pass',
      ),
      throwsA(isA<ConfigurationArchiveAuthenticationException>()),
    );
  });

  test('超大文件和不支持的信封版本在解密前失败', () async {
    expect(
      codec.decrypt(
        Uint8List(ConfigurationArchiveCodec.maxEnvelopeBytes + 1),
        password: 'correct-pass',
      ),
      throwsA(isA<ConfigurationArchiveTooLargeException>()),
    );
    final bytes = utf8.encode(jsonEncode(<String, Object>{
      'format': 'kyy-config',
      'envelopeVersion': 99,
    }));
    expect(
      codec.decrypt(
        Uint8List.fromList(bytes),
        password: 'correct-pass',
      ),
      throwsA(isA<ConfigurationArchiveUnsupportedVersionException>()),
    );
  });

  test('导入和导出都拒绝少于八个字符的密码', () {
    expect(
      codec.encrypt(configuration, password: 'short'),
      throwsA(isA<ConfigurationArchivePasswordException>()),
    );
    expect(
      codec.decrypt(Uint8List(0), password: 'short'),
      throwsA(isA<ConfigurationArchivePasswordException>()),
    );
  });
}
