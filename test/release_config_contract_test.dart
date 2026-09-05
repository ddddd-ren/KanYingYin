import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('当前正式版发布文案与版本说明一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final releaseNotes = File('RELEASE_NOTES.md').readAsStringSync();
    final packageVersion = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(packageVersion, isNotNull);
    final version = packageVersion!.group(1)!;
    final buildNumber = packageVersion.group(2)!;
    final releaseNotesStart = releaseNotes.indexOf('## $version+$buildNumber');
    expect(releaseNotesStart, isNonNegative);
    final releaseNotesEnd = releaseNotes.indexOf(
      '\n## ',
      releaseNotesStart + 1,
    );
    final currentReleaseNotes =
        releaseNotesStart >= 0 && releaseNotesEnd > releaseNotesStart
            ? releaseNotes.substring(releaseNotesStart, releaseNotesEnd)
            : '';

    expect(currentReleaseNotes, contains('Windows EXE 安装器版本：$version'));
    final isPrerelease = version.startsWith('2.1.');
    expect(
      currentReleaseNotes,
      contains(isPrerelease
          ? 'Android 手机测试版：$version ($buildNumber)'
          : 'Android 正式版：1.0.10 (10010)'),
    );
    for (final text in <String>[
      '版本',
      if (!isPrerelease) '重新刮削本季',
      isPrerelease ? 'Windows 测试版' : 'Windows 正式版',
      isPrerelease ? 'Android 手机测试版' : 'Android 正式版',
      if (!isPrerelease) '缓存目录',
      '不会修改',
    ]) {
      expect(currentReleaseNotes, contains(text));
    }
    expect(currentReleaseNotes, isNot(contains('首次正式发布')));
  });

  test('当前正式版构建版本面一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final appVersion = File('lib/core/app_version.dart').readAsStringSync();
    final releaseNotes = File('RELEASE_NOTES.md').readAsStringSync();
    final updateDialogCopy = File('UPDATE_DIALOG_COPY.md').readAsStringSync();
    final versionHistory =
        File('lib/utils/version_history.dart').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final androidScript =
        File('tool/android/build_signed_release.ps1').readAsStringSync();
    final packageVersion = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(packageVersion, isNotNull);
    final version = packageVersion!.group(1)!;
    final buildNumber = packageVersion.group(2)!;

    final isPrerelease = version.startsWith('2.1.');
    expect(pubspec, contains('msix_version: $version.0'));
    expect(appVersion, contains("current = '$version'"));
    expect(releaseNotes, contains('## $version+$buildNumber'));
    expect(updateDialogCopy, contains('应用版本：$version'));
    expect(
      updateDialogCopy,
      contains('Windows EXE 安装器版本：$version'),
    );
    expect(
      updateDialogCopy,
      contains(isPrerelease
          ? 'Android 手机测试版：$version ($buildNumber)'
          : 'Android 手机正式版：1.0.10 (10010)'),
    );
    expect(versionHistory, contains("version: '$version'"));
    expect(gradle, contains('windowsVersionName != "$version"'));
    expect(gradle, contains('windowsVersionCode != $buildNumber'));
    final androidVersion = isPrerelease ? version : '1.0.10';
    final androidCode = isPrerelease ? buildNumber : '10010';
    expect(gradle, contains('val androidVersionName = "$androidVersion"'));
    expect(gradle, contains('val androidVersionCode = $androidCode'));
    expect(androidScript, contains("pubspecVersion.Name -ne '$version'"));
    expect(androidScript, contains('pubspecVersion.Code -ne $buildNumber'));
    expect(androidScript, contains("\$androidVersion = '$androidVersion'"));
    expect(androidScript, contains('\$androidVersionCode = $androidCode'));
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
