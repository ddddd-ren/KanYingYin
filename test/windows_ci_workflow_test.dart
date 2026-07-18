import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String prWorkflow;
  late String releaseWorkflow;

  setUpAll(() {
    prWorkflow = File(
      '.github/workflows/pr.yaml',
    ).readAsStringSync(encoding: utf8);
    releaseWorkflow = File(
      '.github/workflows/release.yaml',
    ).readAsStringSync(encoding: utf8);
  });

  test('PR 工作流提供 Windows 单作业质量门禁', () {
    expect(prWorkflow, contains('pull_request:'));
    expect(prWorkflow, contains('workflow_dispatch:'));
    expect(prWorkflow, contains('runs-on: windows-latest'));
    expect(prWorkflow, contains('contents: read'));
    expect(prWorkflow, contains('flutter-version-file: pubspec.yaml'));
    expect(prWorkflow, contains('flutter pub get'));
    expect(prWorkflow,
        contains('dart format --output=none --set-exit-if-changed .'));
    expect(prWorkflow, contains('flutter analyze --no-pub'));
    expect(prWorkflow, contains('flutter test --no-pub'));
    expect(
      prWorkflow,
      contains('flutter build windows --release --no-pub'),
    );
    expect(prWorkflow, contains('actions/upload-artifact@v4'));
    expect(_topLevelJobNames(prWorkflow), hasLength(1));
  });

  test('发布工作流仅构建并发布版本一致的 Windows MSIX', () {
    expect(releaseWorkflow, contains("- 'v*'"));
    expect(releaseWorkflow, contains('workflow_dispatch:'));
    expect(releaseWorkflow, contains('runs-on: windows-latest'));
    expect(releaseWorkflow, contains('flutter-version-file: pubspec.yaml'));
    expect(releaseWorkflow, contains('flutter pub get'));
    expect(
      releaseWorkflow,
      contains('dart format --output=none --set-exit-if-changed .'),
    );
    expect(releaseWorkflow, contains('flutter analyze --no-pub'));
    expect(releaseWorkflow, contains('flutter test --no-pub'));
    expect(
      releaseWorkflow,
      contains('flutter build windows --release --no-pub'),
    );
    expect(releaseWorkflow, contains('dart run msix:create'));
    expect(releaseWorkflow, contains('--sign-msix=false'));
    expect(
      releaseWorkflow,
      contains(r'--certificate-path="$placeholderCertificate"'),
    );
    expect(
      releaseWorkflow.toLowerCase(),
      isNot(contains(r'c:\users\asus')),
    );
    expect(releaseWorkflow, contains('com.kanyingyin.player'));
    expect(releaseWorkflow, contains('AppxManifest.xml'));
    expect(releaseWorkflow, contains('看影音-'));
    expect(releaseWorkflow, contains('.msix'));
    expect(releaseWorkflow, contains('softprops/action-gh-release@v2'));
    expect(_topLevelJobNames(releaseWorkflow), hasLength(1));

    for (final obsolete in <String>[
      'android',
      'ios',
      'linux',
      'macos',
      'DANDAN',
      'mortis.dart',
      'Predidit',
    ]) {
      expect(
        releaseWorkflow.toLowerCase(),
        isNot(contains(obsolete.toLowerCase())),
        reason: '发布工作流不应再引用 $obsolete',
      );
    }
  });
}

List<String> _topLevelJobNames(String workflow) {
  final lines = const LineSplitter().convert(workflow);
  final jobsLine = lines.indexWhere((line) => line.trim() == 'jobs:');
  if (jobsLine < 0) {
    return const <String>[];
  }

  return lines
      .skip(jobsLine + 1)
      .where((line) => RegExp(r'^  [A-Za-z0-9_-]+:\s*$').hasMatch(line))
      .map((line) => line.trim().replaceFirst(RegExp(r':$'), ''))
      .toList(growable: false);
}
