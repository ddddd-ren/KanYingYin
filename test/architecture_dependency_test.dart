import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = _findProjectRoot();
  final libDirectory =
      Directory('${projectRoot.path}${Platform.pathSeparator}lib');

  test('directive 解析覆盖多行、条件分支、export 和 part', () {
    final fixtureDirectory = Directory.systemTemp.createTempSync(
      'kanyingyin-architecture-parser-',
    );
    addTearDown(() => fixtureDirectory.deleteSync(recursive: true));
    final fixture = File(
      '${fixtureDirectory.path}${Platform.pathSeparator}fixture.dart',
    )..writeAsStringSync(r'''
import
  'package:kanyingyin/core/network/network_config.dart'
  if (dart.library.io) '../../utils/logger.dart'
  if (dart.library.html) 'package:flutter_modular/flutter_modular.dart';

export
  'package:kanyingyin/core/app_version.dart'
  if (dart.library.io) '../pages/init_page.dart';

part
  '../../modules/bangumi/bangumi_item.g.dart';

part of 'package:kanyingyin/example.dart';

/* 外层注释
  /* 嵌套注释 */
  export 'package:flutter_modular/flutter_modular.dart';
*/

export 'package:kanyingyin/\u0070ages/init_page.dart';
''');

    expect(
      _imports(fixture).map((directive) => directive.uri),
      [
        'package:kanyingyin/core/network/network_config.dart',
        '../../utils/logger.dart',
        'package:flutter_modular/flutter_modular.dart',
        'package:kanyingyin/core/app_version.dart',
        '../pages/init_page.dart',
        '../../modules/bangumi/bangumi_item.g.dart',
        'package:kanyingyin/pages/init_page.dart',
      ],
    );
  });

  test('相对 URI 按文件目录归一到 lib 路径，外部 URI 保留', () {
    final fixtureRoot = Directory.systemTemp.createTempSync(
      'kanyingyin-architecture-resolution-',
    );
    addTearDown(() => fixtureRoot.deleteSync(recursive: true));
    final fixtureDirectory = Directory(
      '${fixtureRoot.path}${Platform.pathSeparator}lib'
      '${Platform.pathSeparator}core${Platform.pathSeparator}network',
    )..createSync(recursive: true);
    final fixture = File(
      '${fixtureDirectory.path}${Platform.pathSeparator}fixture.dart',
    )..writeAsStringSync('''
import '../../pages/init_page.dart';
part '../../modules/bangumi/bangumi_item.g.dart';
import 'dart:io';
import 'package:flutter_modular/flutter_modular.dart';
''');

    expect(
      _imports(fixture, projectRoot: fixtureRoot)
          .map((directive) => directive.uri),
      [
        'lib/pages/init_page.dart',
        'lib/modules/bangumi/bangumi_item.g.dart',
        'dart:io',
        'package:flutter_modular/flutter_modular.dart',
      ],
    );
  });

  test('外部依赖默认忽略但 flutter_modular 按包名拦截', () {
    expect(_isProjectUri('dart:io'), isFalse);
    expect(_isProjectUri('package:flutter/material.dart'), isFalse);
    expect(
      _isFlutterModularUri('package:flutter_modular/src/module.dart'),
      isTrue,
    );
  });

  test('core 依赖只允许 core 内部，network 外部依赖限定基础包白名单', () {
    expect(_isForbiddenCoreUri('lib/core/network/dio_factory.dart'), isFalse);
    expect(_isForbiddenCoreUri('lib/services/tmdb/tmdb_client.dart'), isTrue);
    expect(_isForbiddenCoreUri('lib/repositories/cache.dart'), isTrue);
    expect(
        _isForbiddenCoreUri('lib/modules/bangumi/bangumi_item.dart'), isTrue);
    expect(_isForbiddenCoreUri('lib/providers/theme_provider.dart'), isTrue);
    expect(_isForbiddenCoreUri('lib/pages/about/about_page.dart'), isTrue);
    expect(_isForbiddenCoreUri('lib/features/player/presentation/player.dart'),
        isTrue);

    expect(_isAllowedCoreNetworkUri('lib/core/app_version.dart'), isTrue);
    expect(_isAllowedCoreNetworkUri('dart:io'), isTrue);
    expect(_isAllowedCoreNetworkUri('package:dio/dio.dart'), isTrue);
    expect(_isAllowedCoreNetworkUri('package:dio/io.dart'), isTrue);
    expect(_isAllowedCoreNetworkUri('package:flutter/material.dart'), isFalse);
    expect(_isAllowedCoreNetworkUri('package:provider/provider.dart'), isFalse);
    expect(
        _isAllowedCoreNetworkUri(
            'package:flutter_modular/flutter_modular.dart'),
        isFalse);
    expect(
        _isAllowedCoreNetworkUri('package:unknown_ui/widgets.dart'), isFalse);
  });

  test('旧 request 层已完全迁出', () {
    final requestDirectory =
        Directory('${libDirectory.path}${Platform.pathSeparator}request');
    final legacyImports = _dartFiles(libDirectory)
        .expand((file) => _imports(file, projectRoot: projectRoot))
        .where(
          (import) =>
              _isProjectUri(import.uri) &&
              RegExp(r'(?:^|/)request/').hasMatch(import.uri),
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
        .expand((file) => _imports(file, projectRoot: projectRoot))
        .where((import) => !_isAllowedCoreNetworkUri(import.uri))
        .toList(growable: false);

    expect(forbidden, isEmpty, reason: _formatImports(forbidden));
  });

  test('modules 不依赖综合 Utils 门面', () {
    final modulesDirectory =
        Directory('${libDirectory.path}${Platform.pathSeparator}modules');
    final forbidden = _dartFiles(modulesDirectory)
        .expand((file) => _imports(file, projectRoot: projectRoot))
        .where(
          (import) =>
              _isProjectUri(import.uri) &&
              import.uri.endsWith('/utils/utils.dart'),
        )
        .toList(growable: false);

    expect(forbidden, isEmpty, reason: _formatImports(forbidden));
  });

  test('业务与表现层不反向依赖 legacy 兼容实现', () {
    final guardedDirectories = [
      Directory('${libDirectory.path}${Platform.pathSeparator}modules'),
      Directory('${libDirectory.path}${Platform.pathSeparator}pages'),
      Directory('${libDirectory.path}${Platform.pathSeparator}features'),
    ];
    final forbidden = guardedDirectories
        .expand(_dartFiles)
        .expand((file) => _imports(file, projectRoot: projectRoot))
        .where(
          (import) =>
              _isProjectUri(import.uri) &&
              RegExp(r'^lib/legacy/').hasMatch(import.uri),
        )
        .toList(growable: false);

    expect(forbidden, isEmpty, reason: _formatImports(forbidden));
  });

  test('core 不反向依赖业务和表现层', () {
    final coreDirectory =
        Directory('${libDirectory.path}${Platform.pathSeparator}core');
    final forbidden = _dartFiles(coreDirectory)
        .expand((file) => _imports(file, projectRoot: projectRoot))
        .where((import) => _isForbiddenCoreUri(import.uri))
        .toList(growable: false);

    expect(forbidden, isEmpty, reason: _formatImports(forbidden));
  });

  test('IndexModule 只组合路由与应用级依赖注册', () {
    final indexModule = File(
      '${libDirectory.path}${Platform.pathSeparator}pages'
      '${Platform.pathSeparator}index_module.dart',
    );
    final imports = _imports(indexModule, projectRoot: projectRoot).toList();
    final forbidden = imports
        .where(
          (import) =>
              _isProjectUri(import.uri) &&
              (RegExp(r'^lib/(repositories|providers)/').hasMatch(import.uri) ||
                  RegExp(r'^lib/services/(?!tmdb/tmdb_credential_manager\.dart$)')
                      .hasMatch(import.uri) ||
                  RegExp(r'^lib/pages/.+_controller\.dart$')
                      .hasMatch(import.uri) ||
                  RegExp(r'^lib/features/.+/(application|presentation)/')
                      .hasMatch(import.uri)),
        )
        .toList(growable: false);

    expect(forbidden, isEmpty, reason: _formatImports(forbidden));
    expect(
      imports.map((import) => import.uri),
      contains('lib/app/bindings/app_bindings.dart'),
    );
  });

  test('pages 只通过强类型设置边界访问应用设置', () {
    final pagesDirectory =
        Directory('${libDirectory.path}${Platform.pathSeparator}pages');
    final forbiddenImports = _dartFiles(pagesDirectory)
        .expand((file) => _imports(file, projectRoot: projectRoot))
        .where(
          (import) => import.uri == 'lib/utils/storage.dart',
        )
        .toList(growable: false);
    final forbiddenAccess = _dartFiles(pagesDirectory)
        .where((file) => file.readAsStringSync().contains('GStorage.setting'))
        .map((file) => file.path)
        .toList(growable: false);

    expect(
      forbiddenImports,
      isEmpty,
      reason: _formatImports(forbiddenImports),
    );
    expect(forbiddenAccess, isEmpty, reason: forbiddenAccess.join('\n'));
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
        .expand((file) => _imports(file, projectRoot: projectRoot))
        .where(
          (import) =>
              _isFlutterModularUri(import.uri) ||
              _isProjectUri(import.uri) &&
                  (RegExp(r'/(controllers?|services|repositories)/')
                          .hasMatch(import.uri) ||
                      RegExp(r'_controller\.dart$').hasMatch(import.uri)),
        )
        .toList(growable: false);

    expect(forbidden, isEmpty, reason: _formatImports(forbidden));
  });

  test('目录导航表现组件不直接依赖控制器、仓储或全局装配', () {
    final component = File(
      '${libDirectory.path}${Platform.pathSeparator}features'
      '${Platform.pathSeparator}library${Platform.pathSeparator}presentation'
      '${Platform.pathSeparator}directory_address_dropdown.dart',
    );
    final forbidden = _imports(component, projectRoot: projectRoot)
        .where(
          (import) =>
              _isFlutterModularUri(import.uri) ||
              _isProjectUri(import.uri) &&
                  RegExp(r'/(providers|repositories|services)/')
                      .hasMatch(import.uri),
        )
        .toList(growable: false);

    expect(forbidden, isEmpty, reason: _formatImports(forbidden));
  });

  test('三种网盘目录选择入口复用统一页面', () {
    for (final relativePath in const <String>[
      'pages/cloud/quark/quark_directory_picker.dart',
      'pages/cloud/baidu/baidu_directory_picker.dart',
      'pages/cloud/openlist_directory_picker.dart',
    ]) {
      final source = File(
        '${libDirectory.path}${Platform.pathSeparator}'
        '${relativePath.replaceAll('/', Platform.pathSeparator)}',
      ).readAsStringSync();
      expect(source, contains('CloudDirectoryPickerPage<'),
          reason: relativePath);
      expect(source, isNot(contains('ListView.builder')), reason: relativePath);
      expect(source, isNot(contains('_directories')), reason: relativePath);
    }
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

Iterable<_ImportRecord> _imports(
  File file, {
  Directory? projectRoot,
}) sync* {
  final source = file.readAsStringSync();
  for (final uri in _directiveUris(source)) {
    yield _ImportRecord(
      file.path,
      projectRoot == null ? uri : _normalizeUri(file, uri, projectRoot),
    );
  }
}

String _normalizeUri(File sourceFile, String uri, Directory projectRoot) {
  const projectPackagePrefix = 'package:kanyingyin/';
  if (uri.startsWith(projectPackagePrefix)) {
    return 'lib/${uri.substring(projectPackagePrefix.length)}';
  }
  if (uri.startsWith('dart:') || uri.startsWith('package:')) return uri;

  final parsedUri = Uri.tryParse(uri);
  if (parsedUri == null || parsedUri.hasScheme) return uri;

  final sourceDirectoryUri = Uri.directory(sourceFile.parent.absolute.path);
  final resolvedPath = File.fromUri(
    sourceDirectoryUri.resolveUri(parsedUri).normalizePath(),
  ).absolute.path;
  final libPath = Directory(
    '${projectRoot.absolute.path}${Platform.pathSeparator}lib',
  ).absolute.path;
  final resolvedComparable = _comparablePath(resolvedPath);
  final libComparable = '${_comparablePath(libPath)}/';
  if (!resolvedComparable.startsWith(libComparable)) {
    return resolvedPath.replaceAll(Platform.pathSeparator, '/');
  }

  final relativePath = resolvedPath.substring(libPath.length + 1);
  return 'lib/${relativePath.replaceAll(Platform.pathSeparator, '/')}';
}

String _comparablePath(String path) {
  final normalized = path.replaceAll(Platform.pathSeparator, '/');
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

bool _isProjectUri(String uri) => uri.startsWith('lib/');

bool _isFlutterModularUri(String uri) =>
    uri.startsWith('package:flutter_modular/');

bool _isForbiddenCoreUri(String uri) =>
    _isProjectUri(uri) && !uri.startsWith('lib/core/');

bool _isAllowedCoreNetworkUri(String uri) =>
    uri.startsWith('lib/core/') ||
    uri.startsWith('dart:') ||
    uri.startsWith('package:dio/');

Iterable<String> _directiveUris(String source) sync* {
  var index = 0;
  while (index < source.length) {
    index = _skipWhitespaceAndComments(source, index);
    if (index >= source.length) return;

    final identifier = _readIdentifier(source, index);
    if (identifier == null) {
      final string = _readStringLiteral(source, index);
      index = string?.end ?? index + 1;
      continue;
    }

    index = identifier.end;
    if (identifier.value != 'import' &&
        identifier.value != 'export' &&
        identifier.value != 'part') {
      continue;
    }

    if (identifier.value == 'part') {
      final nextIndex = _skipWhitespaceAndComments(source, index);
      final nextIdentifier = _readIdentifier(source, nextIndex);
      if (nextIdentifier?.value == 'of') {
        index = nextIdentifier!.end;
        continue;
      }
    }

    while (index < source.length) {
      index = _skipWhitespaceAndComments(source, index);
      if (index >= source.length || source.codeUnitAt(index) == 0x3b) {
        index++;
        break;
      }
      final string = _readStringLiteral(source, index);
      if (string != null) {
        yield string.value;
        index = string.end;
      } else {
        index++;
      }
    }
  }
}

int _skipWhitespaceAndComments(String source, int start) {
  var index = start;
  while (index < source.length) {
    final codeUnit = source.codeUnitAt(index);
    if (codeUnit == 0x20 ||
        codeUnit == 0x09 ||
        codeUnit == 0x0a ||
        codeUnit == 0x0d) {
      index++;
      continue;
    }
    if (source.startsWith('//', index)) {
      final lineEnd = source.indexOf('\n', index + 2);
      return lineEnd == -1 ? source.length : lineEnd + 1;
    }
    if (source.startsWith('/*', index)) {
      index = _skipBlockComment(source, index);
      continue;
    }
    break;
  }
  return index;
}

int _skipBlockComment(String source, int start) {
  var depth = 1;
  var index = start + 2;
  while (index < source.length && depth > 0) {
    if (source.startsWith('/*', index)) {
      depth++;
      index += 2;
    } else if (source.startsWith('*/', index)) {
      depth--;
      index += 2;
    } else {
      index++;
    }
  }
  return index;
}

_Lexeme? _readIdentifier(String source, int start) {
  if (start >= source.length || !_isIdentifierStart(source.codeUnitAt(start))) {
    return null;
  }
  var end = start + 1;
  while (end < source.length && _isIdentifierPart(source.codeUnitAt(end))) {
    end++;
  }
  return _Lexeme(source.substring(start, end), end);
}

bool _isIdentifierStart(int codeUnit) =>
    codeUnit == 0x5f ||
    codeUnit == 0x24 ||
    codeUnit >= 0x41 && codeUnit <= 0x5a ||
    codeUnit >= 0x61 && codeUnit <= 0x7a;

bool _isIdentifierPart(int codeUnit) =>
    _isIdentifierStart(codeUnit) || codeUnit >= 0x30 && codeUnit <= 0x39;

_Lexeme? _readStringLiteral(String source, int start) {
  if (start >= source.length) return null;
  var quoteIndex = start;
  var raw = false;
  if ((source.codeUnitAt(start) == 0x72 || source.codeUnitAt(start) == 0x52) &&
      start + 1 < source.length) {
    raw = true;
    quoteIndex++;
  }
  final quote = source.codeUnitAt(quoteIndex);
  if (quote != 0x27 && quote != 0x22) return null;

  final triple = quoteIndex + 2 < source.length &&
      source.codeUnitAt(quoteIndex + 1) == quote &&
      source.codeUnitAt(quoteIndex + 2) == quote;
  final contentStart = quoteIndex + (triple ? 3 : 1);
  var index = contentStart;
  while (index < source.length) {
    if (!raw && source.codeUnitAt(index) == 0x5c) {
      index += 2;
      continue;
    }
    if (triple) {
      if (index + 2 < source.length &&
          source.codeUnitAt(index) == quote &&
          source.codeUnitAt(index + 1) == quote &&
          source.codeUnitAt(index + 2) == quote) {
        final content = source.substring(contentStart, index);
        return _Lexeme(raw ? content : _decodeDartString(content), index + 3);
      }
    } else if (source.codeUnitAt(index) == quote) {
      final content = source.substring(contentStart, index);
      return _Lexeme(raw ? content : _decodeDartString(content), index + 1);
    }
    index++;
  }
  final content = source.substring(contentStart);
  return _Lexeme(raw ? content : _decodeDartString(content), source.length);
}

String _decodeDartString(String source) {
  final result = StringBuffer();
  var index = 0;
  while (index < source.length) {
    if (source.codeUnitAt(index) != 0x5c || index + 1 >= source.length) {
      result.writeCharCode(source.codeUnitAt(index));
      index++;
      continue;
    }

    final escape = source.codeUnitAt(index + 1);
    final simpleEscape = switch (escape) {
      0x6e => 0x0a,
      0x72 => 0x0d,
      0x66 => 0x0c,
      0x62 => 0x08,
      0x74 => 0x09,
      0x76 => 0x0b,
      _ => null,
    };
    if (simpleEscape != null) {
      result.writeCharCode(simpleEscape);
      index += 2;
      continue;
    }

    if (escape == 0x78 && index + 3 < source.length) {
      final value = int.tryParse(
        source.substring(index + 2, index + 4),
        radix: 16,
      );
      if (value != null) {
        result.writeCharCode(value);
        index += 4;
        continue;
      }
    }

    if (escape == 0x75) {
      final braced =
          index + 2 < source.length && source.codeUnitAt(index + 2) == 0x7b;
      final digitsStart = index + (braced ? 3 : 2);
      final digitsEnd = braced
          ? source.indexOf('}', digitsStart)
          : digitsStart + 4 <= source.length
              ? digitsStart + 4
              : -1;
      if (digitsEnd != -1) {
        final value = int.tryParse(
          source.substring(digitsStart, digitsEnd),
          radix: 16,
        );
        if (value != null && value <= 0x10ffff) {
          result.writeCharCode(value);
          index = digitsEnd + (braced ? 1 : 0);
          continue;
        }
      }
    }

    result.writeCharCode(escape);
    index += 2;
  }
  return result.toString();
}

String _formatImports(List<_ImportRecord> imports) =>
    imports.map((import) => '${import.path}: ${import.uri}').join('\n');

class _ImportRecord {
  const _ImportRecord(this.path, this.uri);

  final String path;
  final String uri;
}

class _Lexeme {
  const _Lexeme(this.value, this.end);

  final String value;
  final int end;
}
