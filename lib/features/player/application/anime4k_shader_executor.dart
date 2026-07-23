import 'package:kanyingyin/features/player/application/anime4k_policy.dart';

typedef Anime4kMpvCommand = Future<void> Function(List<String> command);

final class Anime4kShaderExecutor {
  const Anime4kShaderExecutor({required Anime4kMpvCommand command})
      : _command = command;

  final Anime4kMpvCommand _command;

  Future<void> apply(
    Anime4kAction action, {
    List<String> shaderPaths = const <String>[],
  }) async {
    if (action == Anime4kAction.clear) {
      await _clear();
      return;
    }
    try {
      await _command(<String>[
        'change-list',
        'glsl-shaders',
        'set',
        shaderPaths.join(';'),
      ]);
    } on Object catch (error, stackTrace) {
      try {
        await _clear();
      } on Object {
        // 清空失败不能覆盖首次着色器错误。
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _clear() => _command(
        const <String>['change-list', 'glsl-shaders', 'clr', ''],
      );
}
