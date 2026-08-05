import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Inno Setup 使用当前用户安装并默认写入 D 盘', () {
    final source = File('tool/windows/installer/看影音测试版.iss').readAsStringSync();
    expect(source, contains('PrivilegesRequired=lowest'));
    expect(source, contains("Result := 'D:\\看影音'"));
    expect(source, contains('DefaultDirName={code:DefaultInstallDir}'));
    expect(source, contains('Excludes: "*.msix,msix_verify_*\\*"'));
    expect(source, isNot(contains('Get-AppxPackage')));
    expect(source, isNot(contains('Remove-AppxPackage')));
    expect(source, isNot(contains('是否卸载旧的 MSIX 版本')));
    expect(source, isNot(contains('Name: "{autodesktop}')));
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
}
