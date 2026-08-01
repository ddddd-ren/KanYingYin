import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../tool/export_xunlei_build_define.dart' as xunlei_export;

void main() {
  test('迅雷构建参数导出器只写指定的临时 JSON', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'kanyingyin-xunlei-export-test-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final output = File(
      '${temporaryDirectory.path}/private/xunlei.build.json',
    );

    await xunlei_export.exportXunleiBuildDefine(
      clientId: ' client-id-fixture ',
      clientSecret: ' client-secret-fixture ',
      webClientId: ' web-client-id-fixture ',
      appKey: ' app-key-fixture ',
      outputPath: output.path,
    );

    expect(
      jsonDecode(await output.readAsString()),
      <String, String>{
        'KANYINGYIN_XUNLEI_CLIENT_ID': 'client-id-fixture',
        'KANYINGYIN_XUNLEI_CLIENT_SECRET': 'client-secret-fixture',
        'KANYINGYIN_XUNLEI_WEB_CLIENT_ID': 'web-client-id-fixture',
        'KANYINGYIN_XUNLEI_APP_KEY': 'app-key-fixture',
      },
    );
    final writtenFiles = await temporaryDirectory
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    expect(writtenFiles, hasLength(1));
    expect(
      await writtenFiles.single.resolveSymbolicLinks(),
      await output.resolveSymbolicLinks(),
    );
  });

  test('迅雷构建参数导出器拒绝任一空参数', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'kanyingyin-xunlei-export-empty-test-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    Future<void> expectRejected({
      String clientId = 'client-id-fixture',
      String clientSecret = 'client-secret-fixture',
      String webClientId = 'web-client-id-fixture',
      String appKey = 'app-key-fixture',
    }) async {
      await expectLater(
        xunlei_export.exportXunleiBuildDefine(
          clientId: clientId,
          clientSecret: clientSecret,
          webClientId: webClientId,
          appKey: appKey,
          outputPath: '${temporaryDirectory.path}/xunlei.build.json',
        ),
        throwsStateError,
      );
    }

    await expectRejected(clientId: '  ');
    await expectRejected(clientSecret: '  ');
    await expectRejected(webClientId: '  ');
    await expectRejected(appKey: '  ');
  });

  test('迅雷构建参数导出器接受固定参数且不回显字段值', () async {
    final source =
        await File('tool/export_xunlei_build_define.dart').readAsString();

    for (final argument in <String>[
      '--client-id',
      '--client-secret',
      '--web-client-id',
      '--app-key',
      '--output',
    ]) {
      expect(source, contains("'$argument'"), reason: argument);
    }
    expect(source, contains('jsonEncode'));
    expect(source, contains('已生成迅雷构建参数'));
    expect(source, isNot(contains('arguments.join')));
    expect(source, isNot(contains('stdout.writeln(client')));
    expect(source, isNot(contains('stdout.writeln(webClient')));
    expect(source, isNot(contains('stdout.writeln(appKey')));
  });

  test('Release 工作流从四项 Secret 构建并在 finally 清理临时 JSON', () async {
    final workflow =
        await File('.github/workflows/release.yaml').readAsString();
    final buildStart = workflow.indexOf('- name: 构建 Windows Release');
    final buildEnd = workflow.indexOf('- name:', buildStart + 1);

    expect(buildStart, greaterThanOrEqualTo(0));
    expect(buildEnd, greaterThan(buildStart));
    final buildStep = workflow.substring(buildStart, buildEnd);
    for (final name in <String>[
      'KANYINGYIN_XUNLEI_CLIENT_ID',
      'KANYINGYIN_XUNLEI_CLIENT_SECRET',
      'KANYINGYIN_XUNLEI_WEB_CLIENT_ID',
      'KANYINGYIN_XUNLEI_APP_KEY',
    ]) {
      expect(
        buildStep,
        contains(r'${{ secrets.' + name + r' }}'),
        reason: name,
      );
      expect(buildStep, contains(r'$env:' + name), reason: name);
    }
    expect(buildStep, contains('export_xunlei_build_define.dart'));
    expect(buildStep, contains('--dart-define-from-file'));
    expect(buildStep, contains('IsNullOrWhiteSpace'));
    expect(buildStep, contains('迅雷 Release 构建缺少必要 Secret'));
    expect(buildStep, contains('try {'));
    expect(buildStep, contains('finally {'));
    expect(buildStep, contains('RUNNER_TEMP'));
    expect(
      buildStep,
      contains('[System.IO.Path]::GetFullPath(\$env:RUNNER_TEMP)'),
    );
    expect(buildStep, contains('StartsWith('));
    expect(buildStep, contains('OrdinalIgnoreCase'));
    expect(buildStep, contains('Remove-Item'));
  });

  test('PR 工作流仍允许不带迅雷凭据构建', () async {
    final workflow = await File('.github/workflows/pr.yaml').readAsString();

    expect(workflow, contains('flutter build windows --release --no-pub'));
    expect(workflow, isNot(contains('KANYINGYIN_XUNLEI_')));
    expect(workflow, isNot(contains('--dart-define-from-file')));
  });
}
