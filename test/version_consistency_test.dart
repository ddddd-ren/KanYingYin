import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/app_identity.dart';

void main() {
  test('一点零十 Windows 与一点零六 Android 正式版文案保持一致', () {
    const expectedVersion = '1.0.10';
    const expectedBuildNumber = '10010';
    final releaseNotes = File('RELEASE_NOTES.md').readAsStringSync();
    final readme = File('README.md').readAsStringSync();
    final updateDialogCopy = File('UPDATE_DIALOG_COPY.md').readAsStringSync();
    final versionHistory =
        File('lib/utils/version_history.dart').readAsStringSync();

    final readmeIdentity = RegExp(
      r'^\|\s*Windows 包标识\s*\|\s*`([^`]+)`\s*\|$',
      multiLine: true,
    ).firstMatch(readme)?.group(1);

    expect(readmeIdentity, AppIdentity.windowsIdentity);
    expect(releaseNotes, contains('## $expectedVersion+$expectedBuildNumber'));
    expect(releaseNotes, contains('Windows EXE 安装器版本：$expectedVersion'));
    expect(releaseNotes, contains('Android 正式版：1.0.6 (10006)'));
    expect(readme, contains('| 当前版本 | 1.0.10 |'));
    expect(
      readme,
      contains('| 支持平台 | Windows 10/11 x64；Android 7.0+（API 24+） |'),
    );
    expect(readme, contains('| 安装格式 | EXE / APK |'));
    expect(readme, contains('OpenList 功能仍在调试，当前不建议使用'));
    expect(versionHistory, contains("version: '$expectedVersion'"));
    expect(updateDialogCopy, contains('应用版本：$expectedVersion'));
    expect(
      updateDialogCopy,
      contains('Windows EXE 安装器版本：$expectedVersion'),
    );
    expect(updateDialogCopy, contains('看影音 $expectedVersion 正式版'));
    expect(updateDialogCopy, contains('Android 弹窗正文'));
    final versionHistoryListStart = versionHistory.indexOf(
      'const List<VersionHistory> versionHistoryList',
    );
    expect(versionHistoryListStart, isNonNegative);
    expect(
      versionHistory.indexOf(
        "version: '$expectedVersion'",
        versionHistoryListStart,
      ),
      lessThan(
        versionHistory.indexOf("version: '2.1.174'", versionHistoryListStart),
      ),
    );
    expect(versionHistory, contains("version: '1.0.2'"));

    final releaseNotesStart =
        releaseNotes.indexOf('## $expectedVersion+$expectedBuildNumber');
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
    final versionHistoryEnd = versionHistory.indexOf(
      '  VersionHistory(',
      versionHistoryStart + 1,
    );
    final currentVersionHistory = versionHistory.substring(
      versionHistoryStart,
      versionHistoryEnd == -1 ? versionHistory.length : versionHistoryEnd,
    );
    expect(currentReleaseNotes, contains('Windows'));
    expect(currentVersionHistory, contains('Windows'));
    for (final currentCopy in <String>[
      currentReleaseNotes,
      currentVersionHistory
    ]) {
      for (final text in <String>[
        'Windows',
        '码率',
        '字幕轨道',
        '海报',
        '不会修改、删除',
      ]) {
        expect(currentCopy, contains(text));
      }
      for (final tvOnlyText in <String>[
        'Android TV',
        'tvTest',
        '遥控器',
        '手机扫码配置',
        '海信',
      ]) {
        expect(currentCopy, isNot(contains(tvOnlyText)));
      }
    }
    expect(currentReleaseNotes, contains('正式版'));
    expect(updateDialogCopy, contains('Windows 正式版 EXE'));
    expect(
      updateDialogCopy,
      contains('本轮交付：Windows 正式版 EXE、Android 正式版 APK/AAB'),
    );
    expect(currentReleaseNotes, contains('Android 正式版'));
    for (final unsupportedClaim in <String>['已经扫描到', '保证匹配']) {
      expect(currentReleaseNotes, isNot(contains(unsupportedClaim)));
      expect(currentVersionHistory, isNot(contains(unsupportedClaim)));
    }
    expect(currentVersionHistory, isNot(contains('isPrerelease: true')));
  });
}
