import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/app_shutdown_coordinator.dart';

void main() {
  test('重复退出共享同一任务并在全部清理完成后终止进程', () async {
    final events = <String>[];
    final playbackStarted = Completer<void>();
    final releasePlayback = Completer<void>();
    final coordinator = AppShutdownCoordinator(
      disposePlayback: () async {
        events.add('playback');
        playbackStarted.complete();
        await releasePlayback.future;
      },
      flushLogs: () async => events.add('logs'),
      closeStorage: () async => events.add('storage'),
      terminateProcess: (code) => events.add('exit:$code'),
    );

    final first = coordinator.shutdown();
    final second = coordinator.shutdown();

    expect(identical(first, second), isTrue);
    await playbackStarted.future;
    expect(events, <String>['playback']);

    releasePlayback.complete();
    await first;
    expect(events, <String>['playback', 'logs', 'storage', 'exit:0']);
  });

  test('单个清理步骤失败时继续完成其余清理并报告错误', () async {
    final events = <String>[];
    final errors = <Object>[];
    final coordinator = AppShutdownCoordinator(
      disposePlayback: () async => throw StateError('播放器清理失败'),
      flushLogs: () async => events.add('logs'),
      closeStorage: () async => events.add('storage'),
      terminateProcess: (code) => events.add('exit:$code'),
      onError: (error, stackTrace) => errors.add(error),
    );

    await coordinator.shutdown();

    expect(events, <String>['logs', 'storage', 'exit:0']);
    expect(errors, hasLength(1));
  });
}
