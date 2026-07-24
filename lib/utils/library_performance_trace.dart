import 'package:kanyingyin/utils/logger.dart';

enum LibraryPerformanceStage {
  localIndexRead('local-index-read'),
  cloudIndexRead('cloud-index-read');

  const LibraryPerformanceStage(this.label);

  final String label;
}

typedef LibraryPerformanceLog = void Function(String message);

/// 记录媒体库关键阶段的数量和耗时，不接收路径或凭据等敏感上下文。
class LibraryPerformanceTrace {
  LibraryPerformanceTrace({LibraryPerformanceLog? log})
      : _log = log ?? _defaultLog;

  final LibraryPerformanceLog _log;

  T measure<T>(
    LibraryPerformanceStage stage,
    T Function() action, {
    required int Function(T result) count,
  }) {
    final stopwatch = Stopwatch()..start();
    final result = action();
    stopwatch.stop();
    _record(stage, count(result), stopwatch.elapsedMilliseconds);
    return result;
  }

  Future<T> measureAsync<T>(
    LibraryPerformanceStage stage,
    Future<T> Function() action, {
    required int Function(T result) count,
  }) async {
    final stopwatch = Stopwatch()..start();
    final result = await action();
    stopwatch.stop();
    _record(stage, count(result), stopwatch.elapsedMilliseconds);
    return result;
  }

  void _record(LibraryPerformanceStage stage, int count, int elapsedMs) {
    _log(
      'LibraryPerformance: stage=${stage.label} '
      'count=$count elapsedMs=$elapsedMs',
    );
  }

  static void _defaultLog(String message) => AppLogger().i(message);
}
