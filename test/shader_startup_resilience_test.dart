import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/init_page.dart';
import 'package:kanyingyin/shaders/shader_asset_installer.dart';
import 'package:kanyingyin/shaders/shaders_controller.dart';
import 'package:path/path.dart' as p;

void main() {
  test('着色器控制器以显式零参数工厂注册以兼容 Release 注入器', () {
    final bindings = File(
      'lib/app/bindings/infrastructure_bindings.dart',
    ).readAsStringSync();

    expect(
      bindings,
      contains(
        'i.addSingleton<ShadersController>(() => ShadersController());',
      ),
    );
    expect(
      bindings,
      isNot(contains('addSingleton<ShadersController>(ShadersController.new)')),
    );
  });

  test('目录提供器抛出文件系统异常时返回失败结果且不向上抛出', () async {
    final error = FileSystemException('无法访问应用支持目录');
    final installer = ShaderAssetInstaller(
      directoryProvider: () async => throw error,
      assetPathsProvider: () async => const <String>[],
      assetReader: (_) async => const <int>[],
    );

    final result = await installer.install();

    expect(result.directory, isNull);
    expect(result.error, same(error));
  });

  test('资产清单读取失败时返回目标目录和原始错误', () async {
    final target = await Directory.systemTemp.createTemp('shader-manifest-');
    final error = StateError('资产清单不可用');
    addTearDown(() => target.delete(recursive: true));
    final installer = ShaderAssetInstaller(
      directoryProvider: () async => target,
      assetPathsProvider: () async => throw error,
      assetReader: (_) async => const <int>[],
    );

    final result = await installer.install();

    expect(result.directory?.path, target.path);
    expect(result.error, same(error));
  });

  test('单个着色器读取失败时返回目标目录和原始错误', () async {
    final target = await Directory.systemTemp.createTemp('shader-copy-');
    final error = FileSystemException('无法读取着色器资产');
    addTearDown(() => target.delete(recursive: true));
    final installer = ShaderAssetInstaller(
      directoryProvider: () async => target,
      assetPathsProvider: () async => const <String>[
        'assets/shaders/Anime4K_Test.glsl',
      ],
      assetReader: (_) async => throw error,
    );

    final result = await installer.install();

    expect(result.directory?.path, target.path);
    expect(result.error, same(error));
  });

  test('安装器只复制着色器目录中的 GLSL 资产', () async {
    final target = await Directory.systemTemp.createTemp('shader-success-');
    addTearDown(() => target.delete(recursive: true));
    final readAssets = <String>[];
    final installer = ShaderAssetInstaller(
      directoryProvider: () async => target,
      assetPathsProvider: () async => const <String>[
        'assets/images/poster.png',
        'assets/shaders/Anime4K_Test.glsl',
      ],
      assetReader: (assetPath) async {
        readAssets.add(assetPath);
        return const <int>[1, 2, 3];
      },
    );

    final result = await installer.install();

    expect(result.error, isNull);
    expect(readAssets, const <String>['assets/shaders/Anime4K_Test.glsl']);
    expect(
      await File(p.join(target.path, 'Anime4K_Test.glsl')).readAsBytes(),
      const <int>[1, 2, 3],
    );
  });

  test('着色器控制器准备失败时只尝试和记录一次并保持不可用', () async {
    final error = FileSystemException('着色器目录不可用');
    final loggedErrors = <Object>[];
    var attempts = 0;
    final controller = ShadersController(
      installer: ShaderAssetInstaller(
        directoryProvider: () async {
          attempts++;
          throw error;
        },
        assetPathsProvider: () async => const <String>[],
        assetReader: (_) async => const <int>[],
      ),
      onInstallError: (error, _) => loggedErrors.add(error),
    );

    await controller.copyShadersToExternalDirectory();
    await controller.copyShadersToExternalDirectory();

    expect(controller.shadersDirectory, isNull);
    expect(attempts, 1);
    expect(loggedErrors, hasLength(1));
    expect(loggedErrors.single, same(error));
  });

  test('着色器准备抛出异常后仍检查快捷方式并导航默认页面', () async {
    final error = StateError('着色器准备失败');
    final events = <String>[];
    final loggedErrors = <Object>[];

    await runInitStartupSequence(
      prepareShaders: () async => throw error,
      checkShortcut: () async => events.add('shortcut'),
      navigateToDefaultPage: () => events.add('navigate'),
      onShaderError: (error, _) => loggedErrors.add(error),
    );

    expect(events, const <String>['shortcut', 'navigate']);
    expect(loggedErrors, hasLength(1));
    expect(loggedErrors.single, same(error));
  });
}
