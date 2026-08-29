import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/app_identity.dart';

void main() {
  test('当前 Windows 与 Android 手机测试版文案保持一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final releaseNotes = File('RELEASE_NOTES.md').readAsStringSync();
    final readme = File('README.md').readAsStringSync();
    final versionHistory =
        File('lib/utils/version_history.dart').readAsStringSync();
    final packageVersion = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)$',
      multiLine: true,
    ).firstMatch(pubspec);
    final androidVersion = RegExp(
      r'val androidVersionName = "([^"]+)"',
    ).firstMatch(gradle);
    final androidVersionCode = RegExp(
      r'val androidVersionCode = (\d+)',
    ).firstMatch(gradle);

    expect(packageVersion, isNotNull);
    expect(androidVersion, isNotNull);
    expect(androidVersionCode, isNotNull);
    final expectedVersion = packageVersion!.group(1)!;
    final expectedBuildNumber = packageVersion.group(2)!;
    expect(expectedVersion, startsWith('2.1.'));
    expect(androidVersion!.group(1), expectedVersion);
    expect(androidVersionCode!.group(1), expectedBuildNumber);

    final readmeIdentity = RegExp(
      r'^\|\s*Windows 包标识\s*\|\s*`([^`]+)`\s*\|$',
      multiLine: true,
    ).firstMatch(readme)?.group(1);

    expect(readmeIdentity, AppIdentity.windowsIdentity);
    expect(releaseNotes, contains('## $expectedVersion+$expectedBuildNumber'));
    expect(releaseNotes, contains('Windows 测试版：$expectedVersion'));
    expect(
      releaseNotes,
      contains('Android 手机测试版：$expectedVersion ($expectedBuildNumber)'),
    );
    expect(
      readme,
      contains('| 支持平台 | Windows 10/11 x64；Android 7.0+（API 24+） |'),
    );
    expect(readme, contains('| 安装格式 | EXE / APK |'));
    expect(readme, contains('OpenList 功能仍在调试，当前不建议使用'));
    expect(versionHistory, contains("version: '$expectedVersion'"));
    final versionHistoryListStart = versionHistory.indexOf(
      'const List<VersionHistory> versionHistoryList',
    );
    expect(versionHistoryListStart, isNonNegative);

    final releaseNotesStart =
        releaseNotes.indexOf('## $expectedVersion+$expectedBuildNumber');
    expect(releaseNotesStart, isNonNegative);
    final releaseNotesEnd = releaseNotes.indexOf(
      '\n## ',
      releaseNotesStart + 1,
    );
    final currentReleaseNotes = releaseNotes.substring(
      releaseNotesStart,
      releaseNotesEnd == -1 ? releaseNotes.length : releaseNotesEnd,
    );
    final versionHistoryStart = versionHistory.indexOf(
      "version: '$expectedVersion'",
      versionHistoryListStart,
    );
    expect(versionHistoryStart, isNonNegative);
    final versionHistoryEnd = versionHistory.indexOf(
      '  VersionHistory(',
      versionHistoryStart + 1,
    );
    final currentVersionHistory = versionHistory.substring(
      versionHistoryStart,
      versionHistoryEnd == -1 ? versionHistory.length : versionHistoryEnd,
    );
    for (final currentCopy in <String>[
      currentReleaseNotes,
      currentVersionHistory
    ]) {
      for (final text in <String>[
        '版本',
        '网盘资源页',
        'Windows',
        'Android 手机',
        '不会修改',
      ]) {
        expect(currentCopy, contains(text));
      }
      expect(currentCopy, contains('不构建 AAB 或 Android TV 安装包'));
    }
    expect(currentReleaseNotes, contains('测试版'));
    expect(currentVersionHistory, contains('isPrerelease: true'));
  });
}
