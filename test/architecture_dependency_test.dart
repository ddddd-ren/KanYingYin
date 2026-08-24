import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
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
      _imports(fixture)
          .map((directive) => directive.uri)
          .toList(growable: false),
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
          .map((directive) => directive.uri)
          .toList(growable: false),
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

  test('四种网盘目录选择入口复用统一页面', () {
    for (final relativePath in const <String>[
      'pages/cloud/quark/quark_directory_picker.dart',
      'pages/cloud/baidu/baidu_directory_picker.dart',
      'pages/cloud/xunlei/xunlei_directory_picker.dart',
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
  for (final uri in _directiveUris(file)) {
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

Iterable<String> _directiveUris(File file) sync* {
  final unit = parseFile(
    path: file.absolute.path,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;
  for (final directive in unit.directives) {
    if (directive is! UriBasedDirective) continue;
    final uri = directive.uri.stringValue;
    if (uri != null) yield uri;
    if (directive is NamespaceDirective) {
      for (final configuration in directive.configurations) {
        final configuredUri = configuration.uri.stringValue;
        if (configuredUri != null) yield configuredUri;
      }
    }
  }
}

String _formatImports(List<_ImportRecord> imports) =>
    imports.map((import) => '${import.path}: ${import.uri}').join('\n');

class _ImportRecord {
  const _ImportRecord(this.path, this.uri);

  final String path;
  final String uri;
}
