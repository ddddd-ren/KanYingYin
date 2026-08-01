import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/anime4k_policy.dart';
import 'package:kanyingyin/features/player/application/anime4k_shader_executor.dart';
import 'package:kanyingyin/utils/constants.dart';

void main() {
  test('效率档使用官方 Mode A Fast 组合', () {
    expect(mpvAnime4KShadersLite, const <String>[
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_M.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_AutoDownscalePre_x4.glsl',
      'Anime4K_Upscale_CNN_x2_S.glsl',
    ]);
  });

  test('质量档保持官方 Mode A HQ 组合', () {
    expect(mpvAnime4KShaders, const <String>[
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_VL.glsl',
      'Anime4K_Upscale_CNN_x2_VL.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_AutoDownscalePre_x4.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ]);
  });

  test('Android 路径先清空并按顺序逐条追加', () async {
    final commands = <List<String>>[];
    final executor = Anime4kShaderExecutor(
      command: (command) async => commands.add(command),
    );

    await executor.apply(
      Anime4kAction.enableEfficiency,
      shaderPaths: const <String>[
        '/data/user/0/com.kanyingyin.player/files/anime_shaders/a.glsl',
        '/data/user/0/com.kanyingyin.player/files/anime_shaders/b.glsl',
      ],
    );

    expect(commands, <List<String>>[
      <String>['change-list', 'glsl-shaders', 'clr', ''],
      <String>[
        'change-list',
        'glsl-shaders',
        'append',
        '/data/user/0/com.kanyingyin.player/files/anime_shaders/a.glsl',
      ],
      <String>[
        'change-list',
        'glsl-shaders',
        'append',
        '/data/user/0/com.kanyingyin.player/files/anime_shaders/b.glsl',
      ],
    ]);
  });

  test('Windows 盘符路径逐条追加且不会按冒号拆分', () async {
    final commands = <List<String>>[];
    final executor = Anime4kShaderExecutor(
      command: (command) async => commands.add(command),
    );

    await executor.apply(
      Anime4kAction.enableQuality,
      shaderPaths: const <String>[r'C:\anime shaders\quality.glsl'],
    );

    expect(commands.last, <String>[
      'change-list',
      'glsl-shaders',
      'append',
      r'C:\anime shaders\quality.glsl',
    ]);
  });

  test('关闭使用 clr 命令', () async {
    final commands = <List<String>>[];
    final executor = Anime4kShaderExecutor(
      command: (command) async => commands.add(command),
    );
    await executor.apply(Anime4kAction.clear);
    expect(
      commands.single,
      <String>['change-list', 'glsl-shaders', 'clr', ''],
    );
  });

  test('第二个着色器追加失败后清空并重新抛出首次错误', () async {
    final commands = <List<String>>[];
    final error = StateError('shader failed');
    final executor = Anime4kShaderExecutor(command: (command) async {
      commands.add(command);
      if (command[2] == 'append' && command[3] == 'b.glsl') throw error;
    });

    await expectLater(
      executor.apply(
        Anime4kAction.enableQuality,
        shaderPaths: const <String>['a.glsl', 'b.glsl'],
      ),
      throwsA(same(error)),
    );
    expect(commands, <List<String>>[
      <String>['change-list', 'glsl-shaders', 'clr', ''],
      <String>['change-list', 'glsl-shaders', 'append', 'a.glsl'],
      <String>['change-list', 'glsl-shaders', 'append', 'b.glsl'],
      <String>['change-list', 'glsl-shaders', 'clr', ''],
    ]);
  });

  test('首次清空失败后再次清空并保留首次错误', () async {
    final commands = <List<String>>[];
    final error = StateError('initial clear failed');
    var clearCalls = 0;
    final executor = Anime4kShaderExecutor(command: (command) async {
      commands.add(command);
      if (command[2] == 'clr') {
        clearCalls++;
        if (clearCalls == 1) throw error;
      }
    });

    await expectLater(
      executor.apply(
        Anime4kAction.enableQuality,
        shaderPaths: const <String>['quality.glsl'],
      ),
      throwsA(same(error)),
    );
    expect(commands, <List<String>>[
      <String>['change-list', 'glsl-shaders', 'clr', ''],
      <String>['change-list', 'glsl-shaders', 'clr', ''],
    ]);
  });

  test('回滚清空失败时不会覆盖首次追加错误', () async {
    final commands = <List<String>>[];
    final appendError = StateError('append failed');
    final cleanupError = StateError('cleanup failed');
    var clearCalls = 0;
    final executor = Anime4kShaderExecutor(command: (command) async {
      commands.add(command);
      if (command[2] == 'clr') {
        clearCalls++;
        if (clearCalls == 2) throw cleanupError;
      }
      if (command[2] == 'append') throw appendError;
    });

    await expectLater(
      executor.apply(
        Anime4kAction.enableQuality,
        shaderPaths: const <String>['quality.glsl'],
      ),
      throwsA(same(appendError)),
    );
    expect(commands, <List<String>>[
      <String>['change-list', 'glsl-shaders', 'clr', ''],
      <String>['change-list', 'glsl-shaders', 'append', 'quality.glsl'],
      <String>['change-list', 'glsl-shaders', 'clr', ''],
    ]);
  });
}
