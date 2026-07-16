import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('应用版本、MSIX 版本和更新日志保持一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final apiEndpoints =
        File('lib/request/config/api_endpoints.dart').readAsStringSync();
    final releaseNotes = File('RELEASE_NOTES.md').readAsStringSync();
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

    expect(packageVersion, isNotNull);
    expect(msixVersion, isNotNull);

    final version = packageVersion!.group(1)!;
    final buildNumber = packageVersion.group(2)!;
    expect(msixVersion!.group(1), version);
    expect(apiEndpoints, contains("version = '$version'"));
    expect(releaseNotes, contains('## $version+$buildNumber'));
    expect(releaseNotes, contains('MSIX 版本：$version.0'));
    expect(versionHistory, contains("version: '$version'"));
    expect(updateDialogCopy, contains('应用版本：$version'));
    expect(updateDialogCopy, contains('安装包版本：$version.0'));
    expect(updateDialogCopy, contains('看影音 $version 更新'));
    expect(
      versionHistory.indexOf("version: '$version'"),
      lessThan(versionHistory.indexOf("version: '1.4.6'")),
    );
    for (final text in ['TrueHD', 'PGS 字幕', '诊断日志', '访问凭据']) {
      expect(versionHistory, contains(text));
      expect(releaseNotes, contains(text));
    }
  });
}
