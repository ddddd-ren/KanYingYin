import 'dart:io';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef ShaderDirectoryProvider = Future<Directory> Function();
typedef ShaderAssetPathsProvider = Future<List<String>> Function();
typedef ShaderAssetReader = Future<List<int>> Function(String assetPath);

final class ShaderInstallResult {
  const ShaderInstallResult({
    required this.directory,
    this.error,
    this.stackTrace,
  });

  final Directory? directory;
  final Object? error;
  final StackTrace? stackTrace;
}

final class ShaderAssetInstaller {
  ShaderAssetInstaller({
    ShaderDirectoryProvider? directoryProvider,
    ShaderAssetPathsProvider? assetPathsProvider,
    ShaderAssetReader? assetReader,
  })  : _directoryProvider = directoryProvider ?? _defaultDirectoryProvider,
        _assetPathsProvider = assetPathsProvider ?? _defaultAssetPathsProvider,
        _assetReader = assetReader ?? _defaultAssetReader;

  final ShaderDirectoryProvider _directoryProvider;
  final ShaderAssetPathsProvider _assetPathsProvider;
  final ShaderAssetReader _assetReader;

  static Future<Directory> _defaultDirectoryProvider() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(p.join(supportDirectory.path, 'anime_shaders'));
  }

  static Future<List<String>> _defaultAssetPathsProvider() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest.listAssets();
  }

  static Future<List<int>> _defaultAssetReader(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<ShaderInstallResult> install() async {
    Directory? directory;
    try {
      directory = await _directoryProvider();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final assetPaths = await _assetPathsProvider();
      Object? firstError;
      StackTrace? firstStackTrace;
      for (final assetPath in assetPaths.where(
        (assetPath) =>
            assetPath.startsWith('assets/shaders/') &&
            assetPath.endsWith('.glsl'),
      )) {
        try {
          final target = File(
            p.join(directory.path, p.posix.basename(assetPath)),
          );
          if (await target.exists()) continue;
          await target.writeAsBytes(await _assetReader(assetPath));
        } on Object catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
      }
      return ShaderInstallResult(
        directory: directory,
        error: firstError,
        stackTrace: firstStackTrace,
      );
    } on Object catch (error, stackTrace) {
      return ShaderInstallResult(
        directory: directory,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
