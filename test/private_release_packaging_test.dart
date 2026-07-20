import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('私人构建脚本使用临时 define 文件且 finally 删除', () async {
    final script =
        await File('tool/windows/build_private_release.ps1').readAsString();

    expect(script, contains('--dart-define-from-file'));
    expect(script, contains('try {'));
    expect(script, contains('finally {'));
    expect(script, contains('Remove-Item'));
    expect(script, contains('Test-Path -LiteralPath \$temporaryRoot'));
    expect(script, contains('[AllowEmptyString()][string[]]\$Lines'));
    expect(script, isNot(contains('KANYINGYIN_TMDB_API_KEY=')));
  });

  test('TMDB 构建参数导出器只写临时 JSON 且不输出 Key', () async {
    final source =
        await File('tool/export_tmdb_build_define.dart').readAsString();

    expect(source, contains("'--hive-directory'"));
    expect(source, contains("'--output'"));
    expect(source, contains("'KANYINGYIN_TMDB_API_KEY': tmdbApiKey"));
    expect(source, contains('jsonEncode'));
    expect(source, contains('已生成私密构建参数'));
    expect(source, isNot(contains('tmdbApiKey.length')));
    expect(source, isNot(contains('substring')));
  });

  test('异机安装脚本先验证清单哈希和签名再导入当前用户证书', () async {
    final script =
        await File('tool/windows/installer/安装看影音.ps1').readAsString();

    expect(script, contains(r'Cert:\CurrentUser\TrustedPeople'));
    expect(script, isNot(contains(r'Cert:\LocalMachine')));
    expect(script, contains('Get-FileHash'));
    expect(script, contains('Get-AuthenticodeSignature'));
    expect(script, contains('AppxManifest.xml'));
    expect(script, contains('com.kanyingyin.player'));
    expect(script, contains('CN=KanYingYin'));
    expect(script, contains('x64'));
    expect(script, contains('Add-AppxPackage'));

    final manifestCheck = script.indexOf('AppxManifest.xml');
    final importCertificate = script.indexOf('Import-Certificate');
    final installPackage = script.indexOf('Add-AppxPackage');
    expect(manifestCheck, lessThan(importCertificate));
    expect(importCertificate, lessThan(installPackage));
  });

  test('ZIP 固定清单不包含私钥凭据或可编辑 Key 文件', () async {
    final script =
        await File('tool/windows/build_private_release.ps1').readAsString();
    final start = script.indexOf('# ZIP清单开始');
    final end = script.indexOf('# ZIP清单结束');

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final manifest = script.substring(start, end).toLowerCase();
    for (final forbidden in <String>[
      '.pfx',
      'clientsecret',
      'accesstoken',
      'refreshtoken',
      'tmdb_api_key',
      '.json',
    ]) {
      expect(manifest, isNot(contains(forbidden)), reason: forbidden);
    }
    for (final required in <String>[
      '.msix',
      '.cer',
      '安装看影音.ps1',
      '安装看影音.cmd',
      '安装说明.txt',
      'sha256.txt',
    ]) {
      expect(manifest, contains(required), reason: required);
    }
  });

  test('CMD 从自身目录启动固定 PowerShell 安装脚本', () async {
    final script =
        await File('tool/windows/installer/安装看影音.cmd').readAsString();

    expect(script, contains('%~dp0'));
    expect(script, contains('-File'));
    expect(script, contains('安装看影音.ps1'));
    expect(script, isNot(contains('%*')));
  });
}
