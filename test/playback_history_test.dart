import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/history/application/playback_history_controller.dart';
import 'package:kanyingyin/features/history/application/playback_history_repository.dart';
import 'package:kanyingyin/features/history/domain/playback_history_entry.dart';
import 'package:kanyingyin/features/history/presentation/history_page.dart';

PlaybackHistoryEntry _entry({
  String key = 'local|file:/media/a.mp4',
  String seriesTitle = '测试剧集',
  String episodeTitle = '第 1 集',
  int episodeIndex = 1,
  int position = 20,
  int duration = 100,
  String? posterUrl,
  String? posterCachePath,
}) {
  return PlaybackHistoryEntry(
    stableKey: key,
    source: key.startsWith('cloud|')
        ? PlaybackHistorySource.cloud
        : PlaybackHistorySource.local,
    sourceId: key.startsWith('cloud|') ? 'source-a' : 'local',
    seriesTitle: seriesTitle,
    episodeTitle: episodeTitle,
    mediaPath: key.startsWith('cloud|') ? '/anime/a.mp4' : '/media/a.mp4',
    remoteId: key.startsWith('cloud|') ? 'remote-a' : null,
    episodeIndex: episodeIndex,
    positionSeconds: position,
    durationSeconds: duration,
    updatedAt: DateTime(2026, 8, 5, 12),
    posterUrl: posterUrl,
    posterCachePath: posterCachePath,
  );
}

class _BlockingPlaybackHistoryStorage implements PlaybackHistoryStorage {
  final Completer<void> writeStarted = Completer<void>();
  final Completer<void> allowWrite = Completer<void>();
  List<Object?> records = <Object?>[];
  bool _blocked = false;

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<List<Object?>> read() async => List<Object?>.from(records);

  @override
  Future<void> write(List<Object?> records) async {
    if (!_blocked) {
      _blocked = true;
      writeStarted.complete();
      await allowWrite.future;
    }
    this.records = List<Object?>.from(records);
  }
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

  test('加载历史时为同来源同剧集的缺图记录复用有效海报', () async {
    final storage = MemoryPlaybackHistoryStorage(<Object?>[
      _entry(
        key: 'cloud|episode-22',
        seriesTitle: '古灵精探 S01',
      ).toJson(),
      _entry(
        key: 'cloud|episode-21',
        seriesTitle: '古灵精探 S01',
        posterUrl: '/poster.jpg',
      ).toJson(),
    ]);
    final controller = PlaybackHistoryController(
      repository: PlaybackHistoryRepository(storage: storage),
    );

    await controller.ensureLoaded();

    expect(controller.entries.first.posterUrl, '/poster.jpg');
    controller.dispose();
  });

  test('更新进度时空海报不会覆盖已有海报', () async {
    final controller = PlaybackHistoryController(
      repository: PlaybackHistoryRepository(
        storage: MemoryPlaybackHistoryStorage(),
      ),
    );
    await controller.record(
      _entry(position: 10, posterUrl: '/poster.jpg'),
      forcePersist: true,
    );

    await controller.record(_entry(position: 20), forcePersist: true);

    expect(controller.entries.single.posterUrl, '/poster.jpg');
    controller.dispose();
  });

  test('新视频播放不足 10 秒不进入历史，已有记录仍可更新', () async {
    final storage = MemoryPlaybackHistoryStorage();
    final controller = PlaybackHistoryController(
      repository: PlaybackHistoryRepository(storage: storage),
    );

    await controller.record(_entry(position: 9), forcePersist: true);
    expect(controller.entries, isEmpty);

    await controller.record(_entry(position: 10), forcePersist: true);
    await controller.record(_entry(position: 5), forcePersist: true);
    expect(controller.entries.single.positionSeconds, 5);
    controller.dispose();
  });

  test('保存期间到达的新进度不会被并发写入覆盖', () async {
    final storage = _BlockingPlaybackHistoryStorage();
    final controller = PlaybackHistoryController(
      repository: PlaybackHistoryRepository(storage: storage),
    );

    await controller.record(_entry(position: 10));
    final firstFlush = controller.flush();
    await storage.writeStarted.future;
    final secondRecord = controller.record(
      _entry(key: 'local|file:/media/b.mp4', position: 20),
    );
    await Future<void>.delayed(Duration.zero);
    storage.allowWrite.complete();
    await Future.wait(<Future<void>>[firstFlush, secondRecord]);
    await controller.flush();

    final persisted =
        await PlaybackHistoryRepository(storage: storage).getAll();
    expect(
        persisted.map((entry) => entry.stableKey),
        containsAll(<String>[
          'local|file:/media/a.mp4',
          'local|file:/media/b.mp4',
        ]));
    controller.dispose();
  });

  test('同一条播放记录的每秒进度更新不会重复刷新历史页面', () async {
    final controller = PlaybackHistoryController(
      repository: PlaybackHistoryRepository(
        storage: MemoryPlaybackHistoryStorage(),
      ),
    );
    await controller.ensureLoaded();
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.record(_entry(position: 10));
    await controller.record(_entry(position: 11));
    await controller.record(_entry(position: 12), forcePersist: true);

    expect(notifications, 2);
    controller.dispose();
  });

  test('观看历史页面提供继续观看筛选、日期分组和观看时间', () {
    final source = File('lib/features/history/presentation/history_page.dart')
        .readAsStringSync();

    expect(source, contains("label: const Text('继续观看')"));
    expect(source, contains("label: const Text('全部历史')"));
    expect(source, contains("return '今天';"));
    expect(source, contains("return '昨天';"));
    expect(source, contains("return '更早';"));
    expect(source, contains('TimeUtils.formatTimestampToRelativeTime'));
    expect(source, contains("entry.isCompleted ? '已看完'"));
  });

  test('观看历史标题隐藏扩展名并保留剧名集号和集名', () {
    final entry = _entry(
      seriesTitle: '古灵精探 S01',
      episodeTitle: '古灵精探 S01E22 儿子被绑 国富大惊.mkv',
      episodeIndex: 22,
    );

    expect(
      formatPlaybackHistoryTitle(entry),
      '古灵精探 S01 · 第22集 · 儿子被绑 国富大惊',
    );
  });
}
