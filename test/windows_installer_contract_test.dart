import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Inno Setup 使用当前用户安装并默认写入 D 盘', () {
    final source = File('tool/windows/installer/看影音测试版.iss').readAsStringSync();
    expect(source, contains('PrivilegesRequired=lowest'));
    expect(source, contains("Result := 'D:\\看影音'"));
    expect(source, contains('DefaultDirName={code:DefaultInstallDir}'));
    expect(source, contains('Excludes: "*.msix,msix_verify_*\\*"'));
    expect(source, contains('com.kanyingyin.player'));
    expect(source, contains('是否卸载旧的 MSIX 版本'));
    expect(source, contains('选择“否”会保留旧版及其数据'));
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
}
