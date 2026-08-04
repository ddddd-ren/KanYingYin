import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../tool/export_tmdb_build_define.dart' as tmdb_export;

void main() {
  test('私人签名脚本使用 RFC3161 SHA256 时间戳', () async {
    final script =
        await File('tool/windows/build_private_release.ps1').readAsString();

    expect(script, contains("'http://timestamp.digicert.com'"));
    expect(script, contains("'/tr', \$TimestampUrl, '/td', 'SHA256'"));
    expect(script, contains('TimeStamperCertificate'));
  });

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

  test('TMDB 构建参数导出器只写指定的临时 JSON', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'kanyingyin-tmdb-export-test-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final output = File('${temporaryDirectory.path}/private/tmdb.json');

    await tmdb_export.exportTmdbBuildDefine(
      key: ' private-key ',
      outputPath: output.path,
    );

    expect(
      jsonDecode(await output.readAsString()),
      <String, String>{'KANYINGYIN_TMDB_API_KEY': 'private-key'},
    );
  });

  test('TMDB 构建参数导出器拒绝空 Key', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'kanyingyin-tmdb-export-empty-test-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    await expectLater(
      tmdb_export.exportTmdbBuildDefine(
        key: '  ',
        outputPath: '${temporaryDirectory.path}/tmdb.json',
      ),
      throwsStateError,
    );
  });

  test('TMDB 构建参数导出器从环境变量读取且不依赖 Hive', () async {
    final source =
        await File('tool/export_tmdb_build_define.dart').readAsString();

    expect(source, contains("'KANYINGYIN_TMDB_PRIVATE_BUILD_KEY'"));
    expect(source, contains("'--output'"));
    expect(source, isNot(contains("'--hive-directory'")));
    expect(source, isNot(contains('package:hive_ce/hive.dart')));
    expect(source, contains('jsonEncode'));
    expect(source, contains('已生成私密构建参数'));
    expect(source, isNot(contains('privateBuildKey.length')));
    expect(source, isNot(contains('substring')));
  });

  test('私人构建脚本通过当前用户保护文件短暂传递 TMDB Key', () async {
    final script =
        await File('tool/windows/build_private_release.ps1').readAsString();

    expect(script, contains('tmdb-api-key.clixml'));
    expect(script, contains('[System.Security.SecureString]'));
    expect(script, contains('KANYINGYIN_TMDB_PRIVATE_BUILD_KEY'));
    expect(script, contains('ZeroFreeBSTR'));
    expect(script, isNot(contains('--hive-directory')));
    expect(script, isNot(contains('setting.hive')));
  });

  test('私人构建脚本短暂解密四项迅雷配置并在构建前清零', () async {
    final script =
        await File('tool/windows/build_private_release.ps1').readAsString();

    for (final fileName in <String>[
      'xunlei-client-id.clixml',
      'xunlei-client-secret.clixml',
      'xunlei-web-client-id.clixml',
      'xunlei-app-key.clixml',
    ]) {
      expect(script, contains("Join-Path \$SigningDirectory '$fileName'"));
    }
    for (final argument in <String>[
      '--client-id',
      '--client-secret',
      '--web-client-id',
      '--app-key',
      '--output',
    ]) {
      expect(script, contains("'$argument'"), reason: argument);
    }
    expect(script, contains('tool/export_xunlei_build_define.dart'));
    expect(
      script,
      contains('"--dart-define-from-file=\$xunleiDefineFile"'),
    );

    final buildIndex = script.indexOf("'build',");
    expect(buildIndex, greaterThanOrEqualTo(0));
    for (final pointer in <String>[
      'xunleiClientIdPointer',
      'xunleiClientSecretPointer',
      'xunleiWebClientIdPointer',
      'xunleiAppKeyPointer',
    ]) {
      final immediateCleanup = script.indexOf('ZeroFreeBSTR(\$$pointer)');
      expect(immediateCleanup, greaterThanOrEqualTo(0), reason: pointer);
      expect(immediateCleanup, lessThan(buildIndex), reason: pointer);
    }

    final conversions = RegExp(
      r'Marshal\]::SecureStringToBSTR',
    ).allMatches(script).length;
    final zeroFrees = RegExp(
      r'Marshal\]::ZeroFreeBSTR',
    ).allMatches(script).length;
    expect(conversions, greaterThanOrEqualTo(6));
    expect(zeroFrees, greaterThanOrEqualTo(conversions));
  });

  test('私人构建脚本在最外层 finally 删除全部临时 JSON 和目录', () async {
    final script =
        await File('tool/windows/build_private_release.ps1').readAsString();
    final outerFinally = script.lastIndexOf('} finally {');

    expect(outerFinally, greaterThanOrEqualTo(0));
    final cleanup = script.substring(outerFinally);
    for (final pointer in <String>[
      'xunleiClientIdPointer',
      'xunleiClientSecretPointer',
      'xunleiWebClientIdPointer',
      'xunleiAppKeyPointer',
    ]) {
      expect(cleanup, contains('ZeroFreeBSTR(\$$pointer)'), reason: pointer);
    }
    for (final defineFile in <String>[
      'tmdbDefineFile',
      'xunleiDefineFile',
    ]) {
      expect(
        cleanup,
        contains('Test-Path -LiteralPath \$$defineFile'),
        reason: defineFile,
      );
      expect(
        cleanup,
        contains('Remove-Item -LiteralPath \$$defineFile'),
        reason: defineFile,
      );
    }
    expect(cleanup, contains('Remove-Item -LiteralPath \$temporaryRoot'));
  });

  test('异机安装脚本提权后把证书导入本机受信任人', () async {
    final script =
        await File('tool/windows/installer/安装看影音.ps1').readAsString();

    expect(script, contains('WindowsBuiltInRole]::Administrator'));
    expect(script, contains("-Verb 'RunAs'"));
    expect(script, contains(r'Cert:\LocalMachine\TrustedPeople'));
    expect(script, isNot(contains(r'Cert:\CurrentUser\TrustedPeople')));
    expect(script, isNot(contains(r'Cert:\LocalMachine\Root')));
    expect(script, contains('Get-FileHash'));
    expect(script, contains('Get-AuthenticodeSignature'));
    expect(script, contains('AppxManifest.xml'));
    expect(script, contains('com.kanyingyin.player'));
    expect(script, contains('CN=KanYingYin'));
    expect(script, contains('x64'));
    expect(script, contains('Add-AppxPackage'));

    final manifestCheck = script.indexOf('AppxManifest.xml');
    final elevation = script.indexOf("-Verb 'RunAs'");
    final importCertificate = script.indexOf('Import-Certificate');
    final installPackage = script.indexOf('Add-AppxPackage');
    expect(elevation, lessThan(importCertificate));
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
      'xunlei',
      '.clixml',
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

  test('异机安装说明告知管理员授权和本机证书范围', () async {
    final publicScript =
        await File('tool/windows/build_signed_release.ps1').readAsString();
    final privateInstructions =
        await File('tool/windows/installer/安装说明.txt').readAsString();

    for (final instructions in <String>[publicScript, privateInstructions]) {
      expect(instructions, contains('管理员权限'));
      expect(instructions, contains('本机'));
      expect(instructions, contains('TrustedPeople'));
      expect(instructions, isNot(contains('导入当前用户')));
    }
  });
}
