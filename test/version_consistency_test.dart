import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/app_identity.dart';

void main() {
  test('二点一六三 Windows 测试版版本文案保持一致', () {
    const expectedVersion = '2.1.163';
    const expectedBuildNumber = '20163';
    const expectedAndroidVersion = '2.1.163';
    const expectedAndroidVersionCode = '20163';
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final appVersion = File('lib/core/app_version.dart').readAsStringSync();
    final androidGradle =
        File('android/app/build.gradle.kts').readAsStringSync();
    final androidReleaseScript =
        File('tool/android/build_signed_release.ps1').readAsStringSync();
    final releaseNotes = File('RELEASE_NOTES.md').readAsStringSync();
    final readme = File('README.md').readAsStringSync();
    final updateDialogCopy = File('UPDATE_DIALOG_COPY.md').readAsStringSync();
    final versionHistory =
        File('lib/utils/version_history.dart').readAsStringSync();

    final packageVersion =
        RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)$', multiLine: true)
            .firstMatch(pubspec);
    final msixVersion = RegExp(
      r'^\s*msix_version:\s*(\d+\.\d+\.\d+)\.0$',
      multiLine: true,
    ).firstMatch(pubspec);
    final msixConfig = _yamlBlock(pubspec, 'msix_config');
    final msixIdentity = _yamlField(msixConfig, 'identity_name');
    final readmeIdentity = RegExp(
      r'^\|\s*Windows 包标识\s*\|\s*`([^`]+)`\s*\|$',
      multiLine: true,
    ).firstMatch(readme)?.group(1);

    expect(packageVersion, isNotNull);
    expect(msixVersion, isNotNull);

    final version = packageVersion!.group(1)!;
    final buildNumber = packageVersion.group(2)!;
    expect(version, expectedVersion);
    expect(buildNumber, expectedBuildNumber);
    expect(msixVersion!.group(1), version);
    expect(
      androidGradle,
      contains(
        'val androidVersionName = "$expectedAndroidVersion"',
      ),
    );
    expect(
      androidGradle,
      contains(
        'val androidVersionCode = $expectedAndroidVersionCode',
      ),
    );
    expect(androidGradle, contains('versionCode = androidVersionCode'));
    expect(androidGradle, contains('versionName = androidVersionName'));
    expect(
      androidReleaseScript,
      contains("\$androidVersion = '$expectedAndroidVersion'"),
    );
    expect(
      androidReleaseScript,
      contains('\$androidVersionCode = $expectedAndroidVersionCode'),
    );
    expect(msixIdentity, AppIdentity.windowsIdentity);
    expect(readmeIdentity, AppIdentity.windowsIdentity);
    expect(appVersion, contains("current = '$version'"));
    expect(releaseNotes, contains('## $version+$buildNumber'));
    expect(releaseNotes, contains('Windows EXE 安装器版本：$version'));
    expect(
      releaseNotes,
      contains('Android 当前已交付版本：2.1.160 (20160，本轮不打包)'),
    );
    expect(readme, contains('| 当前版本 | 1.0.8 |'));
    expect(
      readme,
      contains('| 支持平台 | Windows 10/11 x64；Android 7.0+（API 24+） |'),
    );
    expect(readme, contains('| 安装格式 | EXE / APK |'));
    expect(readme, contains('OpenList 功能仍在调试，当前不建议使用'));
    expect(versionHistory, contains("version: '$version'"));
    expect(updateDialogCopy, contains('应用版本：$version'));
    expect(updateDialogCopy, contains('Windows EXE 安装器版本：$version'));
    expect(updateDialogCopy, contains('看影音 $version 测试版'));
    expect(updateDialogCopy, contains('Android 弹窗正文'));
    expect(updateDialogCopy, contains('Android 手机本轮不发布新版本'));
    final versionHistoryListStart = versionHistory.indexOf(
      'const List<VersionHistory> versionHistoryList',
    );
    expect(versionHistoryListStart, isNonNegative);
    expect(
      versionHistory.indexOf("version: '$version'", versionHistoryListStart),
      lessThan(
        versionHistory.indexOf("version: '1.0.8'", versionHistoryListStart),
      ),
    );
    expect(versionHistory, contains("version: '1.0.2'"));

    final releaseNotesStart = releaseNotes.indexOf('## $version+$buildNumber');
    final releaseNotesEnd = releaseNotes.indexOf(
      '\n## ',
      releaseNotesStart + 1,
    );
    final currentReleaseNotes = releaseNotes.substring(
      releaseNotesStart,
      releaseNotesEnd == -1 ? releaseNotes.length : releaseNotesEnd,
    );
    final versionHistoryStart = versionHistory.indexOf(
      "version: '$version'",
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
        '手动保存剧集匹配',
        '原文件名',
        '用户确认的新季度号',
        '逐集名称',
        '重新打开选集',
        '不会修改或删除',
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
    expect(currentReleaseNotes, contains('测试版'));
    expect(updateDialogCopy, contains('Windows 测试版 EXE'));
    expect(
      updateDialogCopy,
      contains('本轮交付：Windows 测试版 EXE'),
    );
    expect(currentReleaseNotes, contains('本轮不打包'));
    for (final unsupportedClaim in <String>['已经扫描到', '保证匹配']) {
      expect(currentReleaseNotes, isNot(contains(unsupportedClaim)));
      expect(currentVersionHistory, isNot(contains(unsupportedClaim)));
    }
    expect(currentVersionHistory, contains('isPrerelease: true'));
  });
}

String _yamlBlock(String source, String key) {
  final lines = const LineSplitter().convert(source);
  final header = RegExp('^${RegExp.escape(key)}:\\s*(?:#.*)?\$');
  final start = lines.indexWhere(header.hasMatch);
  expect(start, isNonNegative, reason: '缺少 $key 配置块');
  final block = <String>[];
  for (var index = start + 1; index < lines.length; index++) {
    final line = lines[index];
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) {
      block.add(line);
      continue;
    }
    if (!line.startsWith(' ') && !line.startsWith('\t')) break;
    block.add(line);
  }
  return block.join('\n');
}

String? _yamlField(String block, String key) {
  return RegExp(
    '^[ \\t]+${RegExp.escape(key)}:\\s*([^\\s#]+)\\s*(?:#.*)?\$',
    multiLine: true,
  ).firstMatch(block)?.group(1);
}
