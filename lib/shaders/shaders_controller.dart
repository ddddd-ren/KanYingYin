import 'dart:io';

import 'package:mobx/mobx.dart';
import 'package:kanyingyin/shaders/shader_asset_installer.dart';
import 'package:kanyingyin/utils/logger.dart';

part 'shaders_controller.g.dart';

// ignore: library_private_types_in_public_api
class ShadersController = _ShadersController with _$ShadersController;

typedef ShaderInstallErrorHandler = void Function(
  Object error,
  StackTrace? stackTrace,
);

abstract class _ShadersController with Store {
  _ShadersController({
    ShaderAssetInstaller? installer,
    ShaderInstallErrorHandler? onInstallError,
  })  : _installer = installer ?? ShaderAssetInstaller(),
        _onInstallError = onInstallError ?? _logInstallError;

  final ShaderAssetInstaller _installer;
  final ShaderInstallErrorHandler _onInstallError;
  Future<void>? _preparationFuture;

  Directory? shadersDirectory;

  Future<void> copyShadersToExternalDirectory() =>
      _preparationFuture ??= _prepareShaders();

  Future<void> _prepareShaders() async {
    final result = await _installer.install();
    final error = result.error;
    if (error != null) {
      shadersDirectory = null;
      _onInstallError(error, result.stackTrace);
      return;
    }

    shadersDirectory = result.directory;
    final directory = shadersDirectory;
    if (directory != null) {
      AppLogger().i('ShaderManager: GLSL 着色器已准备：${directory.path}');
    }
  }

  static void _logInstallError(Object error, StackTrace? stackTrace) =>
      AppLogger().e(
        'ShaderManager: 着色器准备失败，Anime4K 将不可用',
        error: error,
        stackTrace: stackTrace,
      );
}
