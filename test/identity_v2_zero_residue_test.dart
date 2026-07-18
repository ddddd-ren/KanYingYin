import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/app_identity.dart';

void main() {
  test('所有项目文本统一使用看影音产品名称', () {
    final forbiddenNames = <String>[
      String.fromCharCodes([23601, 30475]),
      String.fromCharCodes([106, 105, 117, 107, 97, 110]),
    ];
    final matches = <String>[];

    for (final path in _trackedTextPaths()) {
      final content = File(path).readAsStringSync(encoding: utf8).toLowerCase();
      if (forbiddenNames.any(content.contains)) matches.add(path);
    }

    expect(matches, isEmpty, reason: matches.join('\n'));
  });

  test('运行时代码和产品资源使用当前产品身份', () {
    final paths = _trackedTextPaths();
    const forbidden = <int>[107, 97, 122, 117, 109, 105];
    final forbiddenName = String.fromCharCodes(forbidden);
    final matches = <String>[];

    for (final path in paths) {
      if (_allowsAttribution(path)) continue;
      final file = File(path);
      final content = file.readAsStringSync(encoding: utf8).toLowerCase();
      if (content.contains(forbiddenName)) matches.add(path);
    }

    expect(matches, isEmpty, reason: matches.join('\n'));
  });

  test('当前源码、配置和测试不包含旧 v2 包标识', () {
    final paths = _trackedTextPaths().where(
      (path) => !path.startsWith('docs/'),
    );
    final forbiddenIdentity = [
      'com',
      'kanyingyin',
      'player',
      'v2',
    ].join('.');
    final matches = <String>[];

    for (final path in paths) {
      if (path.contains(forbiddenIdentity)) {
        matches.add(path);
        continue;
      }
      final content = File(path).readAsStringSync(encoding: utf8);
      if (content.contains(forbiddenIdentity)) {
        matches.add(path);
      }
    }

    expect(matches, isEmpty, reason: matches.join('\n'));
  });

  test('零残留扫描覆盖活动源码和配置', () {
    expect(
      _trackedTextPaths(),
      containsAll([
        'pubspec.yaml',
        'README.md',
        'lib/utils/app_identity.dart',
        'lib/pages/about/about_module.dart',
        '.github/workflows/pr.yaml',
        '.github/workflows/release.yaml',
        'test/identity_v2_zero_residue_test.dart',
      ]),
    );
  });

  test('工作流不再包含旧平台并保留 Windows 质量门禁', () {
    for (final workflowPath in [
      '.github/workflows/pr.yaml',
      '.github/workflows/release.yaml',
    ]) {
      final workflow = File(workflowPath).readAsStringSync();
      expect(workflow, contains('runs-on: windows-latest'));
      expect(workflow, contains('flutter analyze --no-pub'));
      expect(workflow, contains('flutter test --no-pub'));
      expect(workflow, contains('flutter build windows --release --no-pub'));
      expect(workflow, isNot(contains('ubuntu-latest')));
      expect(workflow, isNot(contains('macos-latest')));
      expect(workflow, isNot(contains('assets/linux/')));
    }
  });

  test('版本和 MSIX 身份使用独立配置', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final msixConfig = _yamlBlock(pubspec, 'msix_config');
    final packageVersion = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)$',
      multiLine: true,
    ).firstMatch(pubspec);
    final msixVersion = RegExp(
      r'^\s*msix_version:\s*(\d+\.\d+\.\d+)\.0$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(packageVersion, isNotNull);
    expect(msixVersion, isNotNull);

    final currentVersion = packageVersion!.group(1)!;
    expect(currentVersion, '2.0.12');
    expect(msixVersion!.group(1), currentVersion);
    expect(
      _yamlField(msixConfig, 'identity_name'),
      AppIdentity.windowsIdentity,
    );
    expect(_yamlField(msixConfig, 'publisher'), 'CN=KanYingYin');
    expect(_yamlField(msixConfig, 'install_certificate'), 'false');
  });
}

List<String> _trackedTextPaths() {
  final result = Process.runSync(
    'git',
    ['ls-files', '-z'],
    stdoutEncoding: null,
  );
  expect(result.exitCode, 0);
  final output = utf8.decode(result.stdout as List<int>);
  return output
      .split('\x00')
      .where(
        (path) =>
            path.isNotEmpty && _isTextPath(path) && File(path).existsSync(),
      )
      .toList(growable: false);
}

bool _isTextPath(String path) {
  const extensions = [
    '.cc',
    '.cmake',
    '.cpp',
    '.dart',
    '.desktop',
    '.gitattributes',
    '.gitignore',
    '.gitmodules',
    '.glsl',
    '.h',
    '.html',
    '.json',
    '.lock',
    '.manifest',
    '.md',
    '.metadata',
    '.patch',
    '.ps1',
    '.rc',
    '.sh',
    '.svg',
    '.txt',
    '.xml',
    '.yaml',
    '.yml',
  ];
  const knownTextFiles = [
    'CMakeLists.txt',
    'LICENSE',
    'NOTICE',
    'postinst',
    'postrm',
  ];
  final normalized = path.replaceAll('\\', '/');
  final fileName = normalized.split('/').last;
  return knownTextFiles.contains(fileName) ||
      extensions.any(normalized.endsWith);
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

bool _allowsAttribution(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized == 'README.md' ||
      normalized == 'lib/pages/about/about_page.dart' ||
      normalized == 'test/about_page_content_test.dart' ||
      normalized == 'test/version_consistency_test.dart' ||
      normalized == 'LICENSE' ||
      normalized == 'NOTICE' ||
      normalized == 'THIRD_PARTY_NOTICES.md' ||
      normalized.startsWith('docs/');
}
