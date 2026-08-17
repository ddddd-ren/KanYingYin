import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _scanFixCopy = '修复夸克网盘季度目录内以“01 集名”“02 集名”开头的视频未被扫描为剧集的问题。';
const _androidDeliveryBoundaryCopy = 'Android 当前已交付版本：2.1.160 (20160，本轮不打包)';

void main() {
  test('当前发布配置为二点一六一 Windows 测试版', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final releaseNotes = File('RELEASE_NOTES.md').readAsStringSync();
    final updateDialogCopy = File('UPDATE_DIALOG_COPY.md').readAsStringSync();
    final releaseNotesStart = releaseNotes.indexOf('## 2.1.161+20161');
    final releaseNotesEnd = releaseNotes.indexOf('\n## 2.1.160+20160');
    final currentReleaseNotes =
        releaseNotesStart >= 0 && releaseNotesEnd > releaseNotesStart
            ? releaseNotes.substring(releaseNotesStart, releaseNotesEnd)
            : '';

    expect(pubspec, contains('version: 2.1.161+20161'));
    expect(pubspec, contains('msix_version: 2.1.161.0'));
    expect(currentReleaseNotes, contains('Windows 测试版'));
    expect(currentReleaseNotes, contains('2.1.161'));
    expect(
      currentReleaseNotes,
      contains('Android 当前已交付版本：2.1.160 (20160，本轮不打包)'),
    );
    expect(currentReleaseNotes, contains('Windows'));
    expect(currentReleaseNotes, contains('Android 手机'));
    expect(currentReleaseNotes, contains('EXE'));
    expect(currentReleaseNotes, contains(_scanFixCopy));
    expect(currentReleaseNotes, contains(_androidDeliveryBoundaryCopy));
    for (final text in <String>[
      '夸克网盘',
      '季度目录',
      '同名子目录',
      '正确集号',
      '不会修改或删除',
    ]) {
      expect(currentReleaseNotes, contains(text));
    }
    for (final unsupportedClaim in <String>[
      '已经扫描到',
      '保证匹配',
    ]) {
      expect(currentReleaseNotes, isNot(contains(unsupportedClaim)));
    }
    expect(updateDialogCopy, contains('Windows 测试版 EXE'));
    expect(
      updateDialogCopy,
      contains('本轮交付：Windows 测试版 EXE'),
    );
    expect(updateDialogCopy, contains('2.1.161'));
    expect(updateDialogCopy, contains('2.1.160'));
    expect(updateDialogCopy, contains(_scanFixCopy));
    expect(updateDialogCopy, contains(_androidDeliveryBoundaryCopy));
    expect(updateDialogCopy, contains('Android TV 继续暂停'));
    for (final tvOnlyText in <String>[
      'Android TV',
      'tvTest',
      '遥控器',
      '手机扫码配置',
      '海信',
    ]) {
      expect(currentReleaseNotes, isNot(contains(tvOnlyText)));
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

  test('仓库不保存本机证书路径且默认发布使用 EXE 构建脚本', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(pubspec, isNot(contains('certificate_path:')));
    expect(pubspec, contains('sign_msix: false'));
    expect(readme, contains('tool\\windows\\build_exe_release.ps1'));
    expect(readme, isNot(contains('--certificate-password')));
  });
}
