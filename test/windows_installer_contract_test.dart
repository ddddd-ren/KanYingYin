import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Inno Setup 使用当前用户安装并允许完全自选目录', () {
    final source = File('tool/windows/installer/看影音测试版.iss').readAsStringSync();
    final instructions =
        File('tool/windows/installer/安装说明.txt').readAsStringSync();
    expect(source, contains('PrivilegesRequired=lowest'));
    expect(source,
        contains("Result := ExpandConstant('{localappdata}\\Programs\\看影音')"));
    expect(source, isNot(contains("Result := 'D:\\看影音'")));
    expect(source, contains('DefaultDirName={code:DefaultInstallDir}'));
    expect(source, contains('DisableDirPage=no'));
    expect(source, contains('AppendDefaultDirName=no'));
    expect(source, contains('Excludes: "*.msix,msix_verify_*\\*"'));
    expect(source, isNot(contains('Get-AppxPackage')));
    expect(source, isNot(contains('Remove-AppxPackage')));
    expect(source, isNot(contains('是否卸载旧的 MSIX 版本')));
    expect(source, isNot(contains('Name: "{autodesktop}')));
    expect(instructions, contains('安装向导始终显示目录选择页'));
    expect(instructions, contains('选择的目录就是程序实际安装目录'));
    expect(instructions, isNot(contains(r'D:\看影音')));
    expect(instructions, isNot(contains('MSIX')));
  });

  test('构建脚本强制预检 ISCC 并输出桌面哈希', () {
    final source =
        File('tool/windows/installer/build_inno_setup.ps1').readAsStringSync();
    expect(source, contains('ISCC.exe'));
    expect(
      source,
      contains('Inno Setup 6 compiler ISCC.exe was not found'),
    );
    expect(source, contains('Get-FileHash'));
    expect(source, contains('Get-AuthenticodeSignature'));
    expect(source, contains("'Desktop'"));
    expect(source, contains("-Filter '*.iss'"));
    expect(
        source, isNot(contains("'\u770b\u5f71\u97f3\u6d4b\u8bd5\u7248.iss'")));
  });

  test('默认 EXE 发布脚本构建 Release 并验证安装器版本', () {
    final source =
        File('tool/windows/build_exe_release.ps1').readAsStringSync();
    expect(source, contains("'build', 'windows', '--release', '--no-pub'"));
    expect(source, contains('build_inno_setup.ps1'));
    expect(source, contains('ReleaseProductVersion'));
    expect(source, contains('InstallerProductVersion'));
    expect(source, contains('Get-FileHash'));
    expect(source, contains('Get-AuthenticodeSignature'));
    expect(source, contains(r'-Filter "*$version*.exe"'));
    expect(source, contains('ProductVersion.StartsWith'));
    expect(source.toLowerCase(), isNot(contains('msix:create')));
  });

  test('Windows 测试版构建固定校验 worktree 内的 NuGet', () {
    final prepareScript = File(
      'tool/windows/prepare_nuget.ps1',
    ).readAsStringSync();
    final buildScript =
        File('tool/windows/build_exe_release.ps1').readAsStringSync();

    expect(
      prepareScript,
      contains(
        '751EE5E79481626A428C1241DC7F94BCA2739B32588E669715BC5FB54D8FB8A2',
      ),
    );
    expect(prepareScript, contains('Get-AuthenticodeSignature'));
    expect(prepareScript, contains('Microsoft Corporation'));
    expect(prepareScript, contains('https://dist.nuget.org/'));
    expect(buildScript, contains('prepare_nuget.ps1'));
    expect(
      buildScript,
      contains(r'$env:PATH = "$nuGetDirectory;$originalPath"'),
    );
    expect(buildScript, contains(r'$env:PATH = $originalPath'));
    expect(buildScript, contains(r'$cmakeCachePath'));
    expect(buildScript, contains(r'$releaseDirectory'));
    expect(buildScript, contains(r'$buildStartedAt'));
    expect(buildScript, contains(r'$flutterApp'));
    expect(buildScript, contains('Get-FileHash'));
    expect(buildScript, contains('data\\app.so'));
  });

  test('Windows 测试版构建在项目根目录执行并恢复调用者目录', () {
    final source =
        File('tool/windows/build_exe_release.ps1').readAsStringSync();

    expect(source, contains(r'Push-Location -LiteralPath $projectRoot'));
    expect(source, contains(r'$locationPushed = $true'));
    expect(source, contains(r'if ($locationPushed)'));
    expect(source, contains('Pop-Location'));
  });

  test('Windows 主程序和安装器使用相同的三段版本号', () {
    final runner = File('windows/runner/Runner.rc').readAsStringSync();
    final buildScript =
        File('tool/windows/build_exe_release.ps1').readAsStringSync();

    expect(
      runner,
      contains(
        '#define VERSION_AS_NUMBER '
        'FLUTTER_VERSION_MAJOR,FLUTTER_VERSION_MINOR,'
        'FLUTTER_VERSION_PATCH,0',
      ),
    );
    expect(runner, contains('#define VERSION_AS_STRING VERSION_TRIPLE'));
    expect(
        runner, isNot(contains('#define VERSION_AS_STRING FLUTTER_VERSION')));
    expect(buildScript, contains(r'$releaseVersion -ne $version'));
    expect(
      buildScript,
      isNot(contains('releaseVersion.StartsWith')),
    );
  });
}
