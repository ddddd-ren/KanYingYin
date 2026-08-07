import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/shaders/shader_asset_installer.dart';
import 'package:path/path.dart' as p;

void main() {
  test('应用更新后使用内置 GLSL 原子替换旧版本', () async {
    final target = await Directory.systemTemp.createTemp('shader-update-');
    addTearDown(() => target.delete(recursive: true));
    final shader = File(p.join(target.path, 'Anime4K_Test.glsl'));
    await shader.writeAsBytes(<int>[1, 2, 3]);
    final installer = ShaderAssetInstaller(
      directoryProvider: () async => target,
      assetPathsProvider: () async => const <String>[
        'assets/shaders/Anime4K_Test.glsl',
      ],
      assetReader: (_) async => const <int>[4, 5, 6],
    );

    final result = await installer.install();

    expect(result.error, isNull);
    expect(await shader.readAsBytes(), <int>[4, 5, 6]);
    expect(File('${shader.path}.installing').existsSync(), isFalse);
    expect(File('${shader.path}.previous').existsSync(), isFalse);
  });

  test('内置着色器读取失败时保留上一版本', () async {
    final target = await Directory.systemTemp.createTemp('shader-rollback-');
    addTearDown(() => target.delete(recursive: true));
    final shader = File(p.join(target.path, 'Anime4K_Test.glsl'));
    await shader.writeAsBytes(<int>[1, 2, 3]);
    final installer = ShaderAssetInstaller(
      directoryProvider: () async => target,
      assetPathsProvider: () async => const <String>[
        'assets/shaders/Anime4K_Test.glsl',
      ],
      assetReader: (_) async => throw const FileSystemException('模拟读取中断'),
    );

    final result = await installer.install();

    expect(result.error, isA<FileSystemException>());
    expect(await shader.readAsBytes(), <int>[1, 2, 3]);
  });

  test('只允许着色器目录直属 GLSL 文件', () async {
    final target = await Directory.systemTemp.createTemp('shader-policy-');
    addTearDown(() => target.delete(recursive: true));
    final readAssets = <String>[];
    final installer = ShaderAssetInstaller(
      directoryProvider: () async => target,
      assetPathsProvider: () async => const <String>[
        'assets/shaders/../escape.glsl',
        'assets/shaders/update.lua',
        'assets/shaders/plugin.dll',
        'assets/shaders/valid.glsl',
      ],
      assetReader: (path) async {
        readAssets.add(path);
        return const <int>[1];
      },
    );

    final result = await installer.install();

    expect(result.error, isNull);
    expect(readAssets, <String>['assets/shaders/valid.glsl']);
    expect(File(p.join(target.path, 'escape.glsl')).existsSync(), isFalse);
    expect(File(p.join(target.path, 'update.lua')).existsSync(), isFalse);
    expect(File(p.join(target.path, 'plugin.dll')).existsSync(), isFalse);
  });
}
