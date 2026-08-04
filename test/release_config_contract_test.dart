import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('当前发布配置固定为 Windows 二点一零九测试版', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final releaseNotes = File('RELEASE_NOTES.md').readAsStringSync();
    final updateDialogCopy = File('UPDATE_DIALOG_COPY.md').readAsStringSync();

    expect(pubspec, contains('version: 2.1.109+20109'));
    expect(pubspec, contains('msix_version: 2.1.109.0'));
    for (final source in <String>[releaseNotes, updateDialogCopy]) {
      expect(source, contains('Windows 测试版'));
      expect(source, contains('Android'));
      expect(source, contains('2.1.109'));
      expect(source, contains('1.0.2'));
      expect(source, contains('测试版'));
    }
  });

  test('直接依赖使用与锁文件兼容的明确约束', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('synchronized: ^3.4.0'));
    expect(pubspec, contains('material_color_utilities: ^0.13.0'));
    expect(pubspec, contains('path: ^1.9.1'));
    expect(
      RegExp(
        r'^\s+(synchronized|material_color_utilities|path):\s+any\s*$',
        multiLine: true,
      ).hasMatch(pubspec),
      isFalse,
    );
  });

  test('分析器启用全部严格类型检查', () {
    final options = File('analysis_options.yaml').readAsStringSync();

    expect(options, contains('strict-casts: true'));
    expect(options, contains('strict-inference: true'));
    expect(options, contains('strict-raw-types: true'));
  });

  test('仓库不保存本机证书路径且公共签名使用受保护凭据脚本', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(pubspec, isNot(contains('certificate_path:')));
    expect(pubspec, contains('sign_msix: false'));
    expect(readme, contains('tool\\windows\\build_signed_release.ps1'));
    expect(readme, isNot(contains('--certificate-password')));
  });
}
