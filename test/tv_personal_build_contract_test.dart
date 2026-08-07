import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('个人 TV 构建只从环境读取密码并在 finally 清理私有资源', () {
    final script = File(
      'tool/android/build_personal_tv.ps1',
    ).readAsStringSync();

    expect(script, contains('[string]\$ConfigurationPath'));
    expect(script, contains('[string]\$MetadataPath'));
    expect(script, contains("'KYY_CONFIG_PASSWORD'"));
    expect(script, contains("'KYY_TV_PRELOAD_PASSWORD='"));
    expect(script, contains('-Flavor tvTest'));
    expect(script, contains('-ApkOnly'));
    expect(script, contains('-DartDefines'));
    expect(script, contains('finally'));
    expect(script, contains('configuration.kyyconfig'));
    expect(script, contains('metadata.kyymeta'));
    expect(script, contains(r'$personalEditionLabel ='));
    expect(script, contains('0x4E2A'));
    expect(script, contains('0x7248'));
    expect(script, isNot(contains('TV个人预置测试版')));
    expect(script, isNot(contains('personal-secret-must-not-be-embedded')));
  });

  test('通用 Android 构建支持可选 Dart Define 且普通 TV 脚本不要求个人文件', () {
    final release = File(
      'tool/android/build_signed_release.ps1',
    ).readAsStringSync();
    final normalTv = File(
      'tool/android/build_tv_test.ps1',
    ).readAsStringSync();

    expect(release, contains('[string[]]\$DartDefines'));
    expect(release, contains("'--dart-define'"));
    expect(normalTv, isNot(contains('KYY_CONFIG_PASSWORD')));
    expect(normalTv, isNot(contains('configuration.kyyconfig')));
    expect(normalTv, isNot(contains('metadata.kyymeta')));
  });

  test('构建校验工具只生成清单且不包含个人密码', () {
    final entrySource = File(
      'tool/tv_preload/validate_and_write_manifest.dart',
    ).readAsStringSync();
    final validatorSource = File(
      'tool/tv_preload/preload_validator.dart',
    ).readAsStringSync();
    final source = '$entrySource\n$validatorSource';

    expect(source, contains('Pbkdf2.hmacSha256'));
    expect(source, contains('AesGcm.with256bits'));
    expect(source, contains('ZipDecoder'));
    expect(source, contains('KYY_CONFIG_PASSWORD'));
    expect(source, contains('sha256.bind'));
    expect(source, contains('configurationSha256'));
    expect(source, contains('metadataSha256'));
    expect(source, isNot(contains("import 'dart:ui'")));
    expect(source, isNot(contains("import 'package:flutter/")));
    expect(source, isNot(contains('ConfigurationArchiveCodec')));
    expect(source, isNot(contains('ScrapedMetadataArchiveCodec')));
    expect(source, isNot(contains('personal-secret-must-not-be-embedded')));
  });
}
