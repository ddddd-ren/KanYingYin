import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/history/application/playback_history_controller.dart';
import 'package:kanyingyin/features/history/application/playback_history_repository.dart';
import 'package:kanyingyin/features/history/domain/playback_history_entry.dart';

PlaybackHistoryEntry _entry({
  String key = 'local|file:/media/a.mp4',
  int position = 20,
  int duration = 100,
}) {
  return PlaybackHistoryEntry(
    stableKey: key,
    source: key.startsWith('cloud|')
        ? PlaybackHistorySource.cloud
        : PlaybackHistorySource.local,
    sourceId: key.startsWith('cloud|') ? 'source-a' : 'local',
    seriesTitle: '测试剧集',
    episodeTitle: '第 1 集',
    mediaPath: key.startsWith('cloud|') ? '/anime/a.mp4' : '/media/a.mp4',
    remoteId: key.startsWith('cloud|') ? 'remote-a' : null,
    episodeIndex: 1,
    positionSeconds: position,
    durationSeconds: duration,
    updatedAt: DateTime(2026, 8, 5, 12),
  );
}

void main() {
  test('观看历史重建播放列表时沿用最终剧集标题', () {
    final source = File('lib/features/history/presentation/history_page.dart')
        .readAsStringSync();

    expect(source, contains("'title': episode.displayTitle"));
    expect(source, contains('title: candidate.displayName'));
  });

  test('观看历史记录可 JSON 往返并识别完播', () {
    final entry = _entry(position: 99, duration: 100);
    final restored = PlaybackHistoryEntry.fromJson(entry.toJson());

    expect(restored.stableKey, entry.stableKey);
    expect(restored.source, PlaybackHistorySource.local);
    expect(restored.positionSeconds, 99);
    expect(restored.isCompleted, isTrue);
    expect(restored.resumePosition, Duration.zero);
  });

  test('仓储按稳定键去重并保留最新记录', () async {
    final storage = MemoryPlaybackHistoryStorage();
    final repository = PlaybackHistoryRepository(storage: storage);
    await repository.save(_entry(position: 10));
    await repository.save(_entry(position: 30));

    final records = await repository.getAll();
    expect(records, hasLength(1));
    expect(records.single.positionSeconds, 30);
  });

  test('控制器记录、删除和清空会同步持久化', () async {
    final storage = MemoryPlaybackHistoryStorage();
    final controller = PlaybackHistoryController(
      repository: PlaybackHistoryRepository(storage: storage),
    );
    await controller.record(_entry(), forcePersist: true);
    expect(controller.entries, hasLength(1));
    expect(controller.resumePosition(_entry().stableKey),
        const Duration(seconds: 20));

    await controller.delete(_entry().stableKey);
    expect(controller.entries, isEmpty);
    await controller.record(_entry(key: 'cloud|source-a|remote-a'),
        forcePersist: true);
    await controller.clear();
    expect(await storage.read(), isEmpty);
    controller.dispose();
  });
}
