import 'dart:io';
import 'dart:math';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/utils/app_identity.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum XunleiVerificationProfileError {
  runtimeUnavailable,
  runtimeOutdated,
  initializationFailed,
}

class XunleiVerificationProfileException implements Exception {
  const XunleiVerificationProfileException(this.type);

  final XunleiVerificationProfileError type;

  @override
  String toString() => 'XunleiVerificationProfileException(${type.name})';
}

typedef XunleiAvailableVersionLoader = Future<String?> Function();
typedef XunleiSupportDirectoryLoader = Future<Directory> Function();
typedef XunleiEnvironmentLoader = Future<WebViewEnvironment> Function(
  String userDataFolder,
);

class XunleiVerificationProfileFactory {
  static const List<int> _minimumDownloadStartingVersion = <int>[
    92,
    0,
    902,
    49,
  ];

  XunleiVerificationProfileFactory({
    XunleiAvailableVersionLoader? availableVersionLoader,
    XunleiSupportDirectoryLoader? supportDirectoryLoader,
    XunleiEnvironmentLoader? environmentLoader,
    String Function()? sessionIdGenerator,
    AppPlatformCapabilities? capabilities,
  })  : _availableVersionLoader = availableVersionLoader ??
            (() => WebViewEnvironment.getAvailableVersion()),
        _supportDirectoryLoader =
            supportDirectoryLoader ?? getApplicationSupportDirectory,
        _environmentLoader = environmentLoader ?? _createEnvironment,
        _sessionIdGenerator = sessionIdGenerator ?? _generateSessionId,
        _capabilities = capabilities ?? detectAppPlatform();

  final XunleiAvailableVersionLoader _availableVersionLoader;
  final XunleiSupportDirectoryLoader _supportDirectoryLoader;
  final XunleiEnvironmentLoader _environmentLoader;
  final String Function() _sessionIdGenerator;
  final AppPlatformCapabilities _capabilities;

  Future<XunleiVerificationProfile> create() async {
    if (_capabilities.isAndroid) {
      return XunleiVerificationProfile._(
        rootDirectory: null,
        sessionDirectory: null,
        environment: null,
      );
    }
    String? version;
    try {
      version = await _availableVersionLoader();
    } on Object {
      throw const XunleiVerificationProfileException(
        XunleiVerificationProfileError.initializationFailed,
      );
    }
    if (version == null || version.trim().isEmpty) {
      throw const XunleiVerificationProfileException(
        XunleiVerificationProfileError.runtimeUnavailable,
      );
    }
    if (!supportsDownloadStarting(version)) {
      throw const XunleiVerificationProfileException(
        XunleiVerificationProfileError.runtimeOutdated,
      );
    }

    Directory? root;
    Directory? session;
    try {
      final support = await _supportDirectoryLoader();
      root = Directory(p.join(
        support.path,
        AppIdentity.storageNamespace,
        'webview',
        'xunlei',
      ));
      final sessionId = _sessionIdGenerator();
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(sessionId)) {
        throw const FormatException('invalid session id');
      }
      session = Directory(p.join(root.path, 'session-$sessionId'));
      final existingType = await FileSystemEntity.type(
        session.path,
        followLinks: false,
      );
      if (existingType != FileSystemEntityType.notFound) {
        throw const FileSystemException('verification session already exists');
      }
      await session.create(recursive: true);
      final environment = await _environmentLoader(session.path);
      return XunleiVerificationProfile._(
        rootDirectory: root,
        sessionDirectory: session,
        environment: environment,
      );
    } on Object {
      if (root != null && session != null) {
        try {
          await deleteSessionDirectory(root: root, session: session);
        } on Object {
          // 初始化仍按脱敏错误返回，不输出会话路径或底层异常正文。
        }
      }
      throw const XunleiVerificationProfileException(
        XunleiVerificationProfileError.initializationFailed,
      );
    }
  }

  static Future<WebViewEnvironment> _createEnvironment(String path) =>
      WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: path),
      );

  static bool supportsDownloadStarting(String version) {
    final match = RegExp(
      r'^\s*(\d+)\.(\d+)\.(\d+)\.(\d+)(?:\s|$)',
    ).firstMatch(version);
    if (match == null) return false;
    for (var index = 0;
        index < _minimumDownloadStartingVersion.length;
        index++) {
      final component = int.tryParse(match.group(index + 1)!);
      if (component == null) return false;
      final minimum = _minimumDownloadStartingVersion[index];
      if (component != minimum) return component > minimum;
    }
    return true;
  }

  static String _generateSessionId() {
    final random = Random.secure();
    return List<String>.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
      growable: false,
    ).join();
  }

  static bool isSafeSessionDirectory(Directory root, Directory session) {
    final normalizedRoot = p.normalize(p.absolute(root.path));
    final normalizedSession = p.normalize(p.absolute(session.path));
    return p.equals(p.dirname(normalizedSession), normalizedRoot) &&
        RegExp(r'^session-[0-9a-f]{32}$')
            .hasMatch(p.basename(normalizedSession));
  }

  static Future<void> deleteSessionDirectory({
    required Directory root,
    required Directory session,
  }) async {
    if (!isSafeSessionDirectory(root, session)) {
      throw const FileSystemException('拒绝删除非迅雷验证会话目录');
    }
    final type = await FileSystemEntity.type(
      session.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory) {
      throw const FileSystemException('拒绝删除非目录验证会话');
    }
    await session.delete(recursive: true);
  }

  @override
  String toString() => 'XunleiVerificationProfileFactory(<redacted>)';
}

class XunleiVerificationProfile {
  XunleiVerificationProfile._({
    required this.rootDirectory,
    required this.sessionDirectory,
    required this.environment,
  });

  final Directory? rootDirectory;
  final Directory? sessionDirectory;
  final WebViewEnvironment? environment;
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final webViewEnvironment = environment;
    await _cleanup(() async {
      await CookieManager.instance(
        webViewEnvironment: webViewEnvironment,
      ).deleteAllCookies();
    });
    await _cleanup(() async {
      await InAppWebViewController.clearAllCache(includeDiskFiles: true);
    });
    if (webViewEnvironment != null) {
      await _cleanup(webViewEnvironment.dispose);
    }
    final root = rootDirectory;
    final session = sessionDirectory;
    if (root != null && session != null) {
      await _cleanup(() async {
        await XunleiVerificationProfileFactory.deleteSessionDirectory(
          root: root,
          session: session,
        );
      });
    }
  }

  Future<void> _cleanup(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // 关闭流程继续执行，不输出 WebView 会话或底层异常信息。
    }
  }

  @override
  String toString() => 'XunleiVerificationProfile(<redacted>)';
}
