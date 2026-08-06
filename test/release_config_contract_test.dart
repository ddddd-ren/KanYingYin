import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('当前发布配置为 Windows 二点一三六测试版和 Android 一点零三正式版', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final releaseNotes = File('RELEASE_NOTES.md').readAsStringSync();
    final updateDialogCopy = File('UPDATE_DIALOG_COPY.md').readAsStringSync();
    final currentReleaseNotes = releaseNotes.substring(
      releaseNotes.indexOf('## 2.1.136+20136'),
      releaseNotes.indexOf('\n## 2.1.135+20135'),
    );

    expect(pubspec, contains('version: 2.1.136+20136'));
    expect(pubspec, contains('msix_version: 2.1.136.0'));
    expect(currentReleaseNotes, contains('Windows 测试版'));
    expect(currentReleaseNotes, contains('2.1.136'));
    expect(currentReleaseNotes, contains('主题色'));
    expect(currentReleaseNotes, contains('骨架屏'));
    expect(currentReleaseNotes, contains('空状态'));
    expect(currentReleaseNotes, contains('EXE'));
    expect(currentReleaseNotes, contains('本轮不再生成 MSIX'));
    expect(updateDialogCopy, contains('Windows 测试版 EXE'));
    expect(updateDialogCopy, contains('Android 正式版'));
    expect(updateDialogCopy, contains('2.1.136'));
    expect(updateDialogCopy, contains('1.0.3'));
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

  test('仓库不保存本机证书路径且默认发布使用 EXE 构建脚本', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(pubspec, isNot(contains('certificate_path:')));
    expect(pubspec, contains('sign_msix: false'));
    expect(readme, contains('tool\\windows\\build_exe_release.ps1'));
    expect(readme, isNot(contains('--certificate-password')));
  });
}
