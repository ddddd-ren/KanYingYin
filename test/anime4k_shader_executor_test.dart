import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/anime4k_policy.dart';
import 'package:kanyingyin/features/player/application/anime4k_shader_executor.dart';

void main() {
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
