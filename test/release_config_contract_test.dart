import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _technicalBadgeCopy =
    '根据视频文件名补充识别流媒体来源、码率、帧率、位深、版本、发布组、音频声道和字幕轨道，并在海报上显示对应标签。';
const _androidDeliveryBoundaryCopy = 'Android 正式版：1.0.6 (10006)';

void main() {
  test('当前正式版发布配置与版本说明一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final releaseNotes = File('RELEASE_NOTES.md').readAsStringSync();
    final updateDialogCopy = File('UPDATE_DIALOG_COPY.md').readAsStringSync();
    final releaseNotesStart = releaseNotes.indexOf('## 1.0.10+10010');
    final releaseNotesEnd = releaseNotes.indexOf('\n## 2.1.174+20174');
    final currentReleaseNotes =
        releaseNotesStart >= 0 && releaseNotesEnd > releaseNotesStart
            ? releaseNotes.substring(releaseNotesStart, releaseNotesEnd)
            : '';

    expect(pubspec, contains('version: 1.0.10+10010'));
    expect(pubspec, contains('msix_version: 1.0.10.0'));
    expect(currentReleaseNotes, contains('Windows 正式版'));
    expect(currentReleaseNotes, contains('1.0.10'));
    expect(currentReleaseNotes, contains(_androidDeliveryBoundaryCopy));
    expect(currentReleaseNotes, contains('Windows'));
    expect(currentReleaseNotes, contains('Android'));
    expect(currentReleaseNotes, contains('EXE'));
    expect(currentReleaseNotes, contains(_technicalBadgeCopy));
    expect(currentReleaseNotes, contains(_androidDeliveryBoundaryCopy));
    for (final text in <String>[
      '码率',
      '字幕轨道',
      '空白窗口',
      '海报',
      '不会修改、删除',
    ]) {
      expect(currentReleaseNotes, contains(text));
    }
    for (final unsupportedClaim in <String>[
      '已经扫描到',
      '保证匹配',
    ]) {
      expect(currentReleaseNotes, isNot(contains(unsupportedClaim)));
    }
    expect(updateDialogCopy, contains('Windows 正式版 EXE'));
    expect(
        updateDialogCopy, contains('本轮交付：Windows 正式版 EXE、Android 正式版 APK/AAB'));
    expect(updateDialogCopy, contains('1.0.10'));
    expect(updateDialogCopy, contains('1.0.6'));
    expect(updateDialogCopy, contains(_technicalBadgeCopy));
    expect(updateDialogCopy, contains(_androidDeliveryBoundaryCopy));
    expect(updateDialogCopy, isNot(contains('Android TV')));
    for (final tvOnlyText in <String>[
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
