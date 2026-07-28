typedef AppShutdownStep = Future<void> Function();
typedef AppProcessTerminator = void Function(int code);
typedef AppShutdownErrorReporter = void Function(
  Object error,
  StackTrace stackTrace,
);

/// 协调应用退出，确保资源清理只执行一次且进程终止发生在最后。
class AppShutdownCoordinator {
  AppShutdownCoordinator({
    required AppShutdownStep disposePlayback,
    required AppShutdownStep flushLogs,
    required AppShutdownStep closeStorage,
    required AppProcessTerminator terminateProcess,
    AppShutdownErrorReporter? onError,
  })  : _disposePlayback = disposePlayback,
        _flushLogs = flushLogs,
        _closeStorage = closeStorage,
        _terminateProcess = terminateProcess,
        _onError = onError ?? _ignoreError;

  final AppShutdownStep _disposePlayback;
  final AppShutdownStep _flushLogs;
  final AppShutdownStep _closeStorage;
  final AppProcessTerminator _terminateProcess;
  final AppShutdownErrorReporter _onError;
  Future<void>? _shutdownFuture;

  Future<void> shutdown() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    for (final step in <AppShutdownStep>[
      _disposePlayback,
      _flushLogs,
      _closeStorage,
    ]) {
      try {
        await step();
      } on Object catch (error, stackTrace) {
        _onError(error, stackTrace);
      }
    }
    _terminateProcess(0);
  }

  static void _ignoreError(Object error, StackTrace stackTrace) {}
}
