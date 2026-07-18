import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = _findProjectRoot();
  final libDirectory =
      Directory('${projectRoot.path}${Platform.pathSeparator}lib');

  test('旧 request 层已完全迁出', () {
    final requestDirectory =
        Directory('${libDirectory.path}${Platform.pathSeparator}request');
    final legacyImports = _dartFiles(libDirectory)
        .expand(_imports)
        .where(
          (import) => RegExp(r'(?:^|/)request/').hasMatch(import.uri),
        )
        .toList(growable: false);

    expect(
      requestDirectory.existsSync()
          ? _dartFiles(requestDirectory).map((file) => file.path)
          : const <String>[],
      isEmpty,
    );
    expect(legacyImports, isEmpty, reason: _formatImports(legacyImports));
  });

  test('core network 只依赖基础设施', () {
    final networkDirectory = Directory(
      '${libDirectory.path}${Platform.pathSeparator}core'
      '${Platform.pathSeparator}network',
    );
    expect(networkDirectory.existsSync(), isTrue);

    final forbidden = _dartFiles(networkDirectory)
        .expand(_imports)
        .where(
          (import) => RegExp(
            r'(?:^|/)(pages|features|modules|utils|services|repositories)/',
          ).hasMatch(import.uri),
        )
        .toList(growable: false);

    expect(forbidden, isEmpty, reason: _formatImports(forbidden));
  });

  test('modules 不依赖综合 Utils 门面', () {
    final modulesDirectory =
        Directory('${libDirectory.path}${Platform.pathSeparator}modules');
    final forbidden = _dartFiles(modulesDirectory)
        .expand(_imports)
        .where((import) => import.uri.endsWith('/utils/utils.dart'))
        .toList(growable: false);

    expect(forbidden, isEmpty, reason: _formatImports(forbidden));
  });

  test('core 不反向依赖业务和表现层', () {
    final coreDirectory =
        Directory('${libDirectory.path}${Platform.pathSeparator}core');
    final forbidden = _dartFiles(coreDirectory)
        .expand(_imports)
        .where(
          (import) => RegExp(
            r'(?:^|/)(features(?:/[^/]+)?/presentation|pages)/',
          ).hasMatch(import.uri),
        )
        .toList(growable: false);

    expect(forbidden, isEmpty, reason: _formatImports(forbidden));
  });

  test('library 和 player 表现组件不越层访问控制器与数据层', () {
    final presentationDirectories = [
      Directory(
        '${libDirectory.path}${Platform.pathSeparator}features'
        '${Platform.pathSeparator}library${Platform.pathSeparator}presentation',
      ),
      Directory(
        '${libDirectory.path}${Platform.pathSeparator}features'
        '${Platform.pathSeparator}player${Platform.pathSeparator}presentation',
      ),
    ];
    final forbidden = presentationDirectories
        .expand(_dartFiles)
        .expand(_imports)
        .where(
          (import) =>
              import.uri == 'package:flutter_modular/flutter_modular.dart' ||
              RegExp(r'/(controllers?|services|repositories)/')
                  .hasMatch(import.uri) ||
              RegExp(r'_controller\.dart$').hasMatch(import.uri),
        )
        .toList(growable: false);

    expect(forbidden, isEmpty, reason: _formatImports(forbidden));
  });
}

Directory _findProjectRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (File('${directory.path}${Platform.pathSeparator}pubspec.yaml')
        .existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('无法定位项目根目录');
    }
    directory = parent;
  }
}

Iterable<File> _dartFiles(Directory directory) sync* {
  if (!directory.existsSync()) return;
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}

Iterable<_ImportRecord> _imports(File file) sync* {
  final importPattern = RegExp(
    r'''^\s*import\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  final source = file.readAsStringSync();
  for (final match in importPattern.allMatches(source)) {
    yield _ImportRecord(file.path, match.group(1)!);
  }
}

String _formatImports(List<_ImportRecord> imports) =>
    imports.map((import) => '${import.path}: ${import.uri}').join('\n');

class _ImportRecord {
  const _ImportRecord(this.path, this.uri);

  final String path;
  final String uri;
}
