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
    expect(prWorkflow, contains('uses: actions/upload-artifact@'));
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
    expect(releaseWorkflow, contains('uses: softprops/action-gh-release@'));
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

  test('手动发布必须检出并验证用户指定的既有 tag', () {
    expect(
      releaseWorkflow,
      contains(
        '  workflow_dispatch:\n'
        '    inputs:\n'
        '      release_tag:\n'
        '        description: 发布既有标签，例如 v1.2.3\n'
        '        required: true',
      ),
    );

    final checkout = _stepBlock(releaseWorkflow, '检出代码');
    expect(checkout, contains('fetch-depth: 0'));
    expect(
      checkout,
      contains(
        r"ref: ${{ github.event_name == 'workflow_dispatch' && inputs.release_tag || github.ref }}",
      ),
    );

    final versionCheck = _stepBlock(releaseWorkflow, '校验应用版本与标签');
    expect(
      versionCheck,
      contains(
        r"RELEASE_TAG: ${{ github.event_name == 'workflow_dispatch' && inputs.release_tag || github.ref_name }}",
      ),
    );
    expect(versionCheck, contains(r'$env:RELEASE_TAG'));
    expect(versionCheck, contains('git show-ref --verify'));
    expect(versionCheck, contains('git rev-parse HEAD'));
    expect(versionCheck, contains('git rev-list -n 1'));
  });

  test('PowerShell 不直接内插 ref 且严格校验三段版本', () {
    for (final block in _powerShellStepBlocks(releaseWorkflow)) {
      expect(block, isNot(contains(r'${{ github.ref')));
    }

    final versionCheck = _stepBlock(releaseWorkflow, '校验应用版本与标签');
    expect(
      versionCheck,
      contains(r"'^v[0-9]+\.[0-9]+\.[0-9]+$'"),
    );
    expect(
      versionCheck,
      contains(r"'(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+[0-9]+)?\s*$'"),
    );
    expect(versionCheck, contains(r'$expectedMsix = "$appVersion.0"'));
    expect(versionCheck, isNot(contains(r'$parts[0..3]')));
  });

  test('GitHub Release 只能发布 SignPath 签名输出', () {
    expect(
      releaseWorkflow,
      isNot(contains('      SIGNPATH_API_TOKEN:')),
    );

    final signPath = _stepBlock(releaseWorkflow, 'SignPath 签名 MSIX');
    expect(signPath, contains('signpath/github-action-submit-signing-request'));
    expect(signPath, contains(r'api-token: ${{ secrets.SIGNPATH_API_TOKEN }}'));
    expect(signPath, isNot(contains('if:')));

    final signedOutput = _stepBlock(releaseWorkflow, '准备签名后的 MSIX');
    expect(
      signedOutput,
      contains("'build/windows/msix_signed_output'"),
    );
    expect(signedOutput, contains(r'"看影音-$env:APP_VERSION.msix"'));

    final release = _stepBlock(releaseWorkflow, '发布 GitHub Release');
    expect(release, contains(r'files: 看影音-${{ env.APP_VERSION }}.msix'));
    expect(
      releaseWorkflow.indexOf('SignPath 签名 MSIX'),
      lessThan(releaseWorkflow.indexOf('准备签名后的 MSIX')),
    );
    expect(
      releaseWorkflow.indexOf('准备签名后的 MSIX'),
      lessThan(releaseWorkflow.indexOf('发布 GitHub Release')),
    );
  });

  test('第三方 GitHub Actions 全部固定到完整提交 SHA', () {
    final references = <({String action, String version})>[
      ..._actionReferences(prWorkflow),
      ..._actionReferences(releaseWorkflow),
    ];

    expect(references, isNotEmpty);
    for (final reference in references) {
      expect(
        reference.version,
        matches(RegExp(r'^[0-9a-f]{40}$')),
        reason: '${reference.action} 必须固定到完整提交 SHA',
      );
    }
  });

  test('签名输出唯一且发布前验证签名、签名者和结构化清单', () {
    final verification = _stepBlock(releaseWorkflow, '验证签名后的 MSIX');
    expect(verification, contains(r'$signedFiles.Count -ne 1'));
    expect(verification, contains(r'& $signTool verify /pa /v'));
    expect(verification, contains('MakeAppx.exe'));
    expect(verification, contains('unpack /p'));
    expect(verification, contains(r'[xml]$manifestXml'));
    expect(verification, contains("'com.kanyingyin.player'"));
    expect(verification, contains("'CN=KanYingYin'"));
    expect(verification, contains(r'$env:MSIX_VERSION'));
    expect(verification, contains('Get-AuthenticodeSignature'));
    expect(verification, contains("Status -ne 'Valid'"));
    expect(verification, contains("Subject -ne 'CN=KanYingYin'"));
    expect(verification, isNot(contains('SIGNPATH_API_TOKEN')));
    expect(
      releaseWorkflow.indexOf('验证签名后的 MSIX'),
      lessThan(releaseWorkflow.indexOf('softprops/action-gh-release@')),
    );
  });
}

List<({String action, String version})> _actionReferences(String workflow) =>
    RegExp(
      r'^\s*uses:\s+([^@\s]+)@([^\s#]+)',
      multiLine: true,
    )
        .allMatches(workflow)
        .map(
          (match) => (
            action: match.group(1)!,
            version: match.group(2)!,
          ),
        )
        .toList(growable: false);

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

String _stepBlock(String workflow, String name) {
  final lines = const LineSplitter().convert(workflow);
  final start = lines.indexOf('      - name: $name');
  if (start < 0) {
    return '';
  }
  final end = lines.indexWhere(
    (line) => line.startsWith('      - name:'),
    start + 1,
  );
  return lines.sublist(start, end < 0 ? lines.length : end).join('\n');
}

List<String> _powerShellStepBlocks(String workflow) {
  final names = RegExp(r'^      - name: (.+)$', multiLine: true)
      .allMatches(workflow)
      .map((match) => match.group(1)!)
      .toList(growable: false);
  return names
      .map((name) => _stepBlock(workflow, name))
      .where((block) => block.contains('shell: pwsh'))
      .toList(growable: false);
}
