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

  test('效率档以 set 命令加载完整路径列表', () async {
    final commands = <List<String>>[];
    final executor = Anime4kShaderExecutor(
      command: (command) async => commands.add(command),
    );
    await executor.apply(
      Anime4kAction.enableEfficiency,
      shaderPaths: const <String>['a.glsl', 'b.glsl'],
    );
    expect(commands.single, <String>[
      'change-list',
      'glsl-shaders',
      'set',
      'a.glsl;b.glsl',
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

  test('加载失败后尝试清空并重新抛出原错误', () async {
    final commands = <List<String>>[];
    final error = StateError('shader failed');
    final executor = Anime4kShaderExecutor(command: (command) async {
      commands.add(command);
      if (command[2] == 'set') throw error;
    });

    await expectLater(
      executor.apply(
        Anime4kAction.enableQuality,
        shaderPaths: const <String>['quality.glsl'],
      ),
      throwsA(same(error)),
    );
    expect(commands.last[2], 'clr');
  });
}
