import 'dart:async';

typedef PlayerDisposeStep = FutureOr<void> Function();

final class PlayerDisposeFailure {
  const PlayerDisposeFailure({
    required this.stepIndex,
    required this.error,
    required this.stackTrace,
  });

  final int stepIndex;
  final Object error;
  final StackTrace stackTrace;
}

/// 逐项执行播放器资源释放，并保留全部失败供调用方记录。
final class PlayerResourceDisposer {
  const PlayerResourceDisposer();

  Future<List<PlayerDisposeFailure>> dispose(
    Iterable<PlayerDisposeStep> steps,
  ) async {
    final failures = <PlayerDisposeFailure>[];
    var stepIndex = 0;
    for (final step in steps) {
      try {
        await step();
      } on Object catch (error, stackTrace) {
        failures.add(
          PlayerDisposeFailure(
            stepIndex: stepIndex,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
      stepIndex++;
    }
    return List<PlayerDisposeFailure>.unmodifiable(failures);
  }
}
