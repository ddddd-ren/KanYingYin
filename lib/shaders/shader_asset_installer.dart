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
      for (final assetPath in assetPaths.where(_isAllowedShaderAsset)) {
        try {
          final target = File(
            p.join(directory.path, p.posix.basename(assetPath)),
          );
          await _installAsset(target, await _assetReader(assetPath));
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

  bool _isAllowedShaderAsset(String assetPath) {
    const prefix = 'assets/shaders/';
    if (!assetPath.startsWith(prefix) || !assetPath.endsWith('.glsl')) {
      return false;
    }
    final relative = assetPath.substring(prefix.length);
    return relative.isNotEmpty &&
        !relative.contains('/') &&
        !relative.contains('\\') &&
        relative != '.' &&
        relative != '..';
  }

  Future<void> _installAsset(File target, List<int> bytes) async {
    final temporary = File('${target.path}.installing');
    final previous = File('${target.path}.previous');
    if (!await target.exists() && await previous.exists()) {
      await previous.rename(target.path);
    }
    if (await target.exists()) {
      final current = await target.readAsBytes();
      if (_sameBytes(current, bytes)) return;
    }
    if (await temporary.exists()) await temporary.delete();
    if (await previous.exists()) await previous.delete();
    await temporary.writeAsBytes(bytes, flush: true);

    final hadPrevious = await target.exists();
    if (hadPrevious) await target.rename(previous.path);
    try {
      await temporary.rename(target.path);
      if (await previous.exists()) await previous.delete();
    } on Object {
      if (!await target.exists() && await previous.exists()) {
        await previous.rename(target.path);
      }
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  bool _sameBytes(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}
