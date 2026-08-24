import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _technicalBadgeCopy =
    '本地与个人网盘媒体海报现在常驻显示作品的最高规格标签，包括 4K、2K、1080P、杜比视界、HDR10+、HDR 和杜比全景声。';
const _androidDeliveryBoundaryCopy = 'Android 正式版：1.0.5 (10005)';

void main() {
  test('当前测试版发布配置与版本说明一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final releaseNotes = File('RELEASE_NOTES.md').readAsStringSync();
    final updateDialogCopy = File('UPDATE_DIALOG_COPY.md').readAsStringSync();
    final releaseNotesStart = releaseNotes.indexOf('## 1.0.9+10009');
    final releaseNotesEnd = releaseNotes.indexOf('\n## 2.1.169+20169');
    final currentReleaseNotes =
        releaseNotesStart >= 0 && releaseNotesEnd > releaseNotesStart
            ? releaseNotes.substring(releaseNotesStart, releaseNotesEnd)
            : '';

    expect(pubspec, contains('version: 2.1.173+20173'));
    expect(pubspec, contains('msix_version: 2.1.173.0'));
    expect(currentReleaseNotes, contains('Windows 正式版'));
    expect(currentReleaseNotes, contains('1.0.9'));
    expect(currentReleaseNotes, contains(_androidDeliveryBoundaryCopy));
    expect(currentReleaseNotes, contains('Windows'));
    expect(currentReleaseNotes, contains('Android 手机'));
    expect(currentReleaseNotes, contains('EXE'));
    expect(currentReleaseNotes, contains(_technicalBadgeCopy));
    expect(currentReleaseNotes, contains(_androidDeliveryBoundaryCopy));
    for (final text in <String>[
      '4K',
      '杜比视界',
      '选集',
      '播放器右侧选集',
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
    expect(updateDialogCopy, contains('Windows 正式版 EXE'));
    expect(
        updateDialogCopy, contains('本轮交付：Windows 正式版 EXE、Android 正式版 APK/AAB'));
    expect(updateDialogCopy, contains('1.0.9'));
    expect(updateDialogCopy, contains('1.0.5'));
    expect(updateDialogCopy, contains(_technicalBadgeCopy));
    expect(updateDialogCopy, contains(_androidDeliveryBoundaryCopy));
    expect(updateDialogCopy, contains('Android TV 继续暂停'));
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
