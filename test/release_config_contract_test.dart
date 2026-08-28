import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _androidDeliveryBoundaryCopy = 'Android 正式版：1.0.8 (10008)';

void main() {
  test('当前正式版发布文案与版本说明一致', () {
    final releaseNotes = File('RELEASE_NOTES.md').readAsStringSync();
    final releaseNotesStart = releaseNotes.indexOf('## 1.0.12+10012');
    final releaseNotesEnd = releaseNotes.indexOf(
      '\n## ',
      releaseNotesStart + 1,
    );
    final currentReleaseNotes =
        releaseNotesStart >= 0 && releaseNotesEnd > releaseNotesStart
            ? releaseNotes.substring(releaseNotesStart, releaseNotesEnd)
            : '';

    expect(currentReleaseNotes, contains('Windows 正式版'));
    expect(currentReleaseNotes, contains('1.0.12'));
    expect(currentReleaseNotes, contains(_androidDeliveryBoundaryCopy));
    expect(currentReleaseNotes, contains('Windows'));
    expect(currentReleaseNotes, contains('Android'));
    expect(currentReleaseNotes, contains('EXE'));
    expect(currentReleaseNotes, contains(_androidDeliveryBoundaryCopy));
    for (final text in <String>[
      '观看历史',
      '媒体库快照',
      '外部播放器',
      '海报',
      '不会修改、删除',
    ]) {
      expect(currentReleaseNotes, contains(text));
    }
    for (final unsupportedClaim in <String>[
      '综合',
      '首次正式发布',
      '测试版',
    ]) {
      expect(currentReleaseNotes, isNot(contains(unsupportedClaim)));
    }
    for (final tvOnlyText in <String>[
      'tvTest',
      '遥控器',
      '手机扫码配置',
      '海信',
    ]) {
      expect(currentReleaseNotes, isNot(contains(tvOnlyText)));
    }
  });

  test('Windows 一点零一二正式版构建版本面一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final appVersion = File('lib/core/app_version.dart').readAsStringSync();
    final releaseNotes = File('RELEASE_NOTES.md').readAsStringSync();
    final updateDialogCopy = File('UPDATE_DIALOG_COPY.md').readAsStringSync();
    final versionHistory =
        File('lib/utils/version_history.dart').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final androidScript =
        File('tool/android/build_signed_release.ps1').readAsStringSync();

    expect(pubspec, contains('version: 1.0.12+10012'));
    expect(pubspec, contains('msix_version: 1.0.12.0'));
    expect(appVersion, contains("current = '1.0.12'"));
    expect(releaseNotes, contains('## 1.0.12+10012'));
    expect(releaseNotes, contains('Windows EXE 安装器版本：1.0.12'));
    expect(updateDialogCopy, contains('应用版本：1.0.12'));
    expect(updateDialogCopy, contains('Windows EXE 安装器版本：1.0.12'));
    expect(versionHistory, contains("version: '1.0.12'"));
    expect(gradle, contains('windowsVersionName != "1.0.12"'));
    expect(gradle, contains('windowsVersionCode != 10012'));
    expect(gradle, contains('val androidVersionName = "1.0.8"'));
    expect(gradle, contains('val androidVersionCode = 10008'));
    expect(androidScript, contains("pubspecVersion.Name -ne '1.0.12'"));
    expect(androidScript, contains('pubspecVersion.Code -ne 10012'));
    expect(androidScript, contains("\$androidVersion = '1.0.8'"));
    expect(androidScript, contains(r'$androidVersionCode = 10008'));
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
