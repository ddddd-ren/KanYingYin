import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('公共签名脚本构建、签名、验证并复制桌面安装包', () async {
    final script =
        await File('tool/windows/build_signed_release.ps1').readAsString();

    expect(script, contains("'build', 'windows', '--release', '--no-pub'"));
    expect(script, contains("'msix:create'"));
    expect(script, contains("'--build-windows', 'false'"));
    expect(script, contains('certificate.pfx'));
    expect(script, contains('certificate-password.clixml'));
    expect(script, contains("'sign', '/fd', 'SHA256'"));
    expect(script, contains("'verify', '/pa', '/v'"));
    expect(script, contains('Get-AuthenticodeSignature'));
    expect(script, contains("Status -ne 'Valid'"));
    expect(script, contains('AppxManifest.xml'));
    expect(script, contains('com.kanyingyin.player'));
    expect(script, contains('CN=KanYingYin'));
    expect(script, contains('ProcessorArchitecture'));
    expect(script, contains('Get-FileHash'));
    expect(script, contains('看影音-\$versionWithBuild.msix'));
    expect(script, contains('看影音-\$versionWithBuild-异机安装包.zip'));
  });

  test('公共签名脚本允许增量构建复用有效产物时间戳', () async {
    final script =
        await File('tool/windows/build_signed_release.ps1').readAsString();

    expect(script, contains(r'$releaseInfo.Length -le 0'));
    expect(script, isNot(contains('LastWriteTime')));
    expect(script, isNot(contains(r'$buildStartedAt')));
  });

  test('公共签名脚本忽略已退出的残留进程条目', () async {
    final script =
        await File('tool/windows/build_signed_release.ps1').readAsString();

    expect(script, contains(r'$runningProcesses'));
    expect(script, contains(r'Where-Object { -not $_.HasExited }'));
    expect(script, contains(r'$runningProcesses.Count -gt 0'));
  });

  test('公共签名脚本不依赖私人 TMDB Key 且安全清理密码', () async {
    final script =
        await File('tool/windows/build_signed_release.ps1').readAsString();
    final lower = script.toLowerCase();

    expect(lower, isNot(contains('tmdb-api-key')));
    expect(lower, isNot(contains('kanyingyin_tmdb')));
    expect(lower, isNot(contains('--dart-define')));
    expect(script, contains('[System.Security.SecureString]'));
    expect(script, contains('ZeroFreeBSTR'));
    expect(script, contains('finally {'));
    expect(script, contains('Assert-PublicTemporaryRoot'));
  });

  test('公共异机 ZIP 使用固定清单且不包含任何私钥凭据', () async {
    final script =
        await File('tool/windows/build_signed_release.ps1').readAsString();
    final start = script.indexOf('# ZIP清单开始');
    final end = script.indexOf('# ZIP清单结束');

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final manifest = script.substring(start, end).toLowerCase();
    for (final forbidden in <String>[
      '.pfx',
      'password',
      'clientsecret',
      'accesstoken',
      'refreshtoken',
      'tmdb',
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
}
