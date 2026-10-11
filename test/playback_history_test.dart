import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/history/application/playback_history_controller.dart';
import 'package:kanyingyin/features/history/application/playback_history_repository.dart';
import 'package:kanyingyin/features/history/domain/playback_history_entry.dart';
import 'package:kanyingyin/features/history/presentation/history_page.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

PlaybackHistoryEntry _entry({
  String key = 'local|file:/media/a.mp4',
  String seriesTitle = '测试剧集',
  String episodeTitle = '第 1 集',
  String? mediaPath,
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
    mediaPath: mediaPath ??
        (key.startsWith('cloud|') ? '/anime/a.mp4' : '/media/a.mp4'),
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

MediaLibrarySeries _cloudSeries({
  String key = 'work-a',
  String sourceId = 'source-a',
  String remoteId = 'remote-a',
  String remotePath = '/anime/a.mp4',
  String title = '光阴之外',
}) =>
    MediaLibrarySeries(
      key: key,
      seriesKey: key,
      title: title,
      sourceKind: MediaSourceKind.cloud,
      sourceId: sourceId,
      sourceName: sourceId,
      isAvailable: false,
      episodes: [
        MediaLibraryEpisode.cloud(
          stableId: remoteId,
          name: 'a.mp4',
          sourceId: sourceId,
          sourceName: sourceId,
          isAvailable: false,
          remoteId: remoteId,
          remotePath: remotePath,
        ),
      ],
    );

void main() {
  test('来源与媒体库入口切换时按真实网盘文件恢复旧稳定键进度', () async {
    final old = _entry(
        key: 'cloud|source-a:remote-a:/anime/a.mp4',
        position: 37,
        duration: 100,
        posterUrl: 'https://example.invalid/old-poster.jpg');
    final storage = MemoryPlaybackHistoryStorage([old.toJson()]);
    final controller = PlaybackHistoryController(
        repository: PlaybackHistoryRepository(storage: storage));
    addTearDown(controller.dispose);
    await controller.ensureLoaded();
    expect(controller.find('source-a|source-a|remote-a'), isNull);
    final matched = controller.findCloudEntry(
        sourceId: 'source-a', remoteId: 'remote-a', mediaPath: '/anime/a.mp4');
    expect(matched?.stableKey, old.stableKey);
    expect(matched?.resumePosition, const Duration(seconds: 37));
    expect(controller.findCloudEntry(
        sourceId: 'source-b', remoteId: 'remote-a', mediaPath: '/anime/a.mp4'), isNull);
    expect(controller.findCloudEntry(
        sourceId: 'source-a', remoteId: 'remote-b', mediaPath: '/anime/a.mp4'), isNull);
    expect(controller.findCloudEntry(
        sourceId: 'source-a', remoteId: 'remote-a', mediaPath: '/other/a.mp4'), isNull);
    expect(controller.entries.single.stableKey, old.stableKey);
    final duplicated = _entry(
        key: 'cloud|new-key', position: 49, seriesTitle: '新的来源剧名');
    await controller.record(duplicated, forcePersist: true);
    expect(controller.findCloudEntry(
        sourceId: 'source-a', remoteId: 'remote-a', mediaPath: '/anime/a.mp4')?.stableKey,
        old.stableKey);
    expect(controller.entries, hasLength(1));
    expect(controller.entries.single.seriesTitle, '新的来源剧名');
    expect(controller.entries.single.posterUrl, old.posterUrl);
    expect(controller.resumePosition(old.stableKey),
        const Duration(seconds: 49));
    expect(controller.find(duplicated.stableKey), isNull);
    final reloaded = PlaybackHistoryController(
        repository: PlaybackHistoryRepository(storage: storage));
    addTearDown(reloaded.dispose);
    await reloaded.ensureLoaded();
    expect(reloaded.resumePosition(old.stableKey), const Duration(seconds: 49));
  });

  test('预存多个同文件历史不按标题或进度猜测归属', () async {
    final old = _entry(key: 'cloud|old', position: 37);
    final other = _entry(key: 'cloud|other', position: 49);
    final controller = PlaybackHistoryController(
        repository: PlaybackHistoryRepository(
            storage: MemoryPlaybackHistoryStorage([old.toJson(), other.toJson()])));
    addTearDown(controller.dispose);
    await controller.ensureLoaded();
    expect(controller.findCloudEntry(
        sourceId: 'source-a', remoteId: 'remote-a', mediaPath: '/anime/a.mp4'), isNull);
    expect(controller.resumePosition(other.stableKey), const Duration(seconds: 49));
    expect(controller.entries, hasLength(2));
  });

  test('网盘历史恢复使用来源版本的单集名称和完整播放字段', () {
    final indexed = CloudMediaIndexItem(
      sourceId: 'source-a',
      remoteId: 'remote-a',
      remotePath: '/anime/a.mp4',
      name: '旧作品 S01E01.mkv',
      size: 100,
      seriesName: '旧作品 S01',
      modifiedAt: DateTime(2026, 8, 5),
    );
    final sourceEpisode = MediaLibraryEpisode.cloud(
      stableId: 'remote-a',
      name: '第 1 集 · 来源集名',
      sourceId: 'source-a',
      sourceName: '来源',
      isAvailable: true,
      remoteId: indexed.remoteId,
      remotePath: indexed.remotePath,
      playbackVersionKey: 'source-version',
      episodeNumber: 1,
      subtitleRemoteRefs: const [
        CloudRemoteRef(id: 'subtitle-id', path: '/anime/a.ass'),
      ],
      size: 123,
      modifiedAt: DateTime(2026, 8, 6),
    );
    final otherVersion = MediaLibraryEpisode.cloud(
      stableId: 'remote-b',
      name: '另一个版本',
      sourceId: 'source-a',
      sourceName: '来源',
      isAvailable: true,
      remoteId: 'remote-b',
      remotePath: '/anime/b.mp4',
      playbackVersionKey: 'other-version',
    );
    final series = MediaLibrarySeries(
      key: 'work-a',
      seriesKey: 'work-a',
      title: '光阴之外',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'source-a',
      sourceName: '来源',
      isAvailable: true,
      tmdbPosterUrl: '/source-poster.jpg',
      posterCachePath: '/source-poster-cache.jpg',
      episodes: [sourceEpisode, otherVersion],
      versions: [
        MediaLibraryVersionGroup(
          key: 'source-version',
          label: '来源版本',
          episodes: [sourceEpisode],
        ),
        MediaLibraryVersionGroup(
          key: 'other-version',
          label: '其他版本',
          episodes: [otherVersion],
        ),
      ],
    );

    final targets = buildCloudPlaybackHistoryTargets(series, sourceEpisode);

    expect(targets, hasLength(1));
    final target = targets.single;
    expect(target.title, sourceEpisode.name);
    expect(target.title, isNot(indexed.displayName));
    expect(target.stableId, sourceEpisode.stableId);
    expect(target.sourceId, sourceEpisode.sourceId);
    expect(target.remoteId, sourceEpisode.remoteId);
    expect(target.remotePath, sourceEpisode.remotePath);
    expect(target.episodeNumber, 1);
    expect(target.subtitleRemoteId, 'subtitle-id');
    expect(target.subtitleRemotePath, '/anime/a.ass');
    expect(target.posterUrl, '/source-poster.jpg');
    expect(target.posterCachePath, '/source-poster-cache.jpg');
    expect(target.size, 123);
    expect(target.modifiedAt, DateTime(2026, 8, 6));
  });

  test('云来源与分类历史恢复保持原播放稳定身份及书签键', () {
    final series = _cloudSeries();
    final episode = series.episodes.single;
    for (final useSourcePlaybackIds in [false, true]) {
      final oldTargetId = useSourcePlaybackIds
          ? '${episode.sourceId}:${episode.remoteId}:${episode.remotePath}'
          : episode.stableId;
      final original = PlaybackHistoryEntry.fromJson({
        ..._entry(key: 'cloud|legacy', seriesTitle: '旧剧名').toJson(),
        'stableKey': '${episode.sourceId}|$oldTargetId',
      });
      final target = buildCloudPlaybackHistoryTargets(
        series,
        episode,
        useSourcePlaybackIds: original.stableKey
            .startsWith('${original.sourceId}|${original.sourceId}:'),
      ).single;

      expect('${target.sourceId}|${target.stableId}', original.stableKey);
      expect(target.title, episode.name);
      expect(original.resumePosition, const Duration(seconds: 20));
    }
  });

  test('来源快照不可用时索引回退仍保留两种历史入口的书签身份', () {
    for (final stableKey in [
      'source-a|source-a:remote-a:/anime/a.mp4',
      'source-a|source-a|remote-a',
    ]) {
      final original = PlaybackHistoryEntry.fromJson({
        ..._entry(key: 'cloud|legacy', seriesTitle: '旧剧名').toJson(),
        'stableKey': stableKey,
      });
      final targetId = cloudPlaybackHistoryIndexedStableId(
        original,
        original.remoteId!,
        original.mediaPath,
      );

      expect('${original.sourceId}|$targetId', original.stableKey);
      expect(original.seriesTitle, '旧剧名');
      expect(original.resumePosition, const Duration(seconds: 20));
    }
  });

  test('旧网盘历史从当前来源同步剧名且保留稳定键进度与时间', () {
    final original = _entry(
      key: 'cloud|source-a|remote-a',
      seriesTitle: '光阴之外 S01',
      position: 37,
    );
    final resolved = resolvePlaybackHistorySeriesTitle(
      original,
      [_cloudSeries(remotePath: '/renamed/a.mp4')],
    );

    expect(resolved.seriesTitle, '光阴之外');
    expect(resolved.stableKey, original.stableKey);
    expect(resolved.mediaPath, original.mediaPath);
    expect(resolved.positionSeconds, 37);
    expect(resolved.durationSeconds, original.durationSeconds);
    expect(resolved.updatedAt, original.updatedAt);
    expect(original.seriesTitle, '光阴之外 S01');
  });

  test('相同远程标识的不同来源不会覆盖历史剧名', () {
    final original = _entry(
      key: 'cloud|source-a|remote-a',
      seriesTitle: '旧剧名',
    );
    expect(
      resolvePlaybackHistorySeriesTitle(
        original,
        [_cloudSeries(sourceId: 'source-b', title: '另一部作品')],
      ),
      same(original),
    );
    expect(
      resolvePlaybackHistorySeriesTitle(original, [
        _cloudSeries(sourceId: 'source-b', title: '另一部作品'),
        _cloudSeries(),
      ]).seriesTitle,
      '光阴之外',
    );
  });

  test('来源缺失或远程标识属于多个来源分组时保留历史快照', () {
    final original = _entry(
      key: 'cloud|source-a|remote-a',
      seriesTitle: '旧剧名',
    );
    for (final series in <List<MediaLibrarySeries>>[
      [],
      [_cloudSeries(remoteId: 'another-id')],
      [_cloudSeries(), _cloudSeries(key: 'work-b', title: '冲突作品')],
      [_cloudSeries(title: ' ')],
    ]) {
      expect(
        resolvePlaybackHistorySeriesTitle(original, series),
        same(original),
      );
    }
  });

  test('没有远程标识的旧网盘历史仅按同来源规范化路径恢复剧名', () {
    final original = PlaybackHistoryEntry.fromJson({
      ..._entry(key: 'cloud|legacy', seriesTitle: '旧剧名').toJson(),
      'remoteId': null,
      'mediaPath': r'\anime\a.mp4',
    });
    expect(
      resolvePlaybackHistorySeriesTitle(original, [_cloudSeries()]).seriesTitle,
      '光阴之外',
    );
    expect(
      resolvePlaybackHistorySeriesTitle(original, [
        _cloudSeries(remotePath: '/anime/A.mp4'),
      ]),
      same(original),
    );
  });

  test('本地历史沿规范化文件路径取得来源剧名', () {
    final item = LocalMediaIndexItem(
      path: r'D:\媒体\光阴之外\01.mp4',
      name: '01.mp4',
      parentPath: r'D:\媒体\光阴之外',
      sourcePath: r'D:\媒体',
      size: 100,
      modified: DateTime(2026, 8, 5),
      seriesName: '光阴之外',
      indexedAt: DateTime(2026, 8, 5),
    );
    final original = _entry(
      seriesTitle: '旧剧名',
      mediaPath: r'd:/媒体/光阴之外/01.mp4',
    );
    expect(
      resolvePlaybackHistorySeriesTitle(
        original,
        [],
        localSourceTitlesByMediaId: {item.id: item.seriesName},
      ).seriesTitle,
      '光阴之外',
    );
  });

  test('Android 本地历史的文档 URI 按大小写敏感的原标识匹配', () {
    const uri = 'content://provider/document/Media%3AAbC';
    const treeUri = 'content://provider/tree/Media';
    final item = LocalMediaIndexItem(
      location: MediaLocation.document(uri: uri, treeUri: treeUri),
      name: '01.mp4',
      parentLocation: MediaLocation.document(uri: treeUri, treeUri: treeUri),
      sourceLocation: MediaLocation.document(uri: treeUri, treeUri: treeUri),
      size: 100,
      modified: DateTime(2026, 8, 5),
      seriesName: '光阴之外',
      indexedAt: DateTime(2026, 8, 5),
    );
    final original = _entry(seriesTitle: '旧剧名', mediaPath: uri);
    final titles = {item.id: item.seriesName};
    expect(
      resolvePlaybackHistorySeriesTitle(
        original,
        [],
        localSourceTitlesByMediaId: titles,
      ).seriesTitle,
      '光阴之外',
    );
    final mismatched = _entry(seriesTitle: '旧剧名', mediaPath: uri.toLowerCase());
    expect(
      resolvePlaybackHistorySeriesTitle(
        mismatched,
        [],
        localSourceTitlesByMediaId: titles,
      ),
      same(mismatched),
    );
  });

  test('本地来源缺失时保留剧名快照及播放进度', () {
    final original = _entry(seriesTitle: '上次来源剧名', position: 37);
    expect(
      resolvePlaybackHistorySeriesTitle(original, []),
      same(original),
    );
  });

  test('已加载控制器的延迟写入不覆盖新导入历史', () async {
    final repository =
        PlaybackHistoryRepository(storage: MemoryPlaybackHistoryStorage());
    final controller = PlaybackHistoryController(repository: repository);
    await controller.ensureLoaded();
    await controller.record(_entry(key: 'local|playing'));
    await repository.save(_entry(key: 'local|imported'));
    await controller.flush();
    expect((await repository.getAll()).map((entry) => entry.stableKey),
        containsAll(['local|playing', 'local|imported']));
    await controller.delete('local|playing');
    expect((await repository.getAll()).single.stableKey, 'local|imported');
    controller.dispose();
  });
  test('观看历史重建播放列表时沿用最终剧集标题', () {
    final source = File('lib/features/history/presentation/history_page.dart')
        .readAsStringSync();

    expect(
      source,
      contains("'title': episode.playbackTitleFor(resolved.seriesTitle)"),
    );
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

  test('本地历史从媒体索引补齐已有海报', () {
    final item = LocalMediaIndexItem(
      path: '/media/a.mp4',
      name: 'a.mp4',
      parentPath: '/media',
      sourcePath: '/media',
      size: 100,
      modified: DateTime(2026, 8, 5),
      seriesName: '测试剧集',
      indexedAt: DateTime(2026, 8, 5),
      cover: '/covers/a.jpg',
    );

    final resolved = resolveLocalPlaybackHistoryPoster(
      _entry(),
      <String, LocalMediaIndexItem>{item.id: item},
      (_) => 'https://image.tmdb.org/t/p/w780/poster.jpg',
    );

    expect(resolved.posterCachePath, '/covers/a.jpg');
    expect(
      resolved.posterUrl,
      'https://image.tmdb.org/t/p/w780/poster.jpg',
    );
  });

  test('本地历史仅保留实际存在的旧海报缓存', () {
    final directory = Directory.systemTemp.createTempSync('history-poster-');
    final existing = File('${directory.path}${Platform.pathSeparator}old.jpg')
      ..writeAsBytesSync(const <int>[1]);
    final item = LocalMediaIndexItem(
      path: '/media/a.mp4',
      name: 'a.mp4',
      parentPath: '/media',
      sourcePath: '/media',
      size: 100,
      modified: DateTime(2026, 8, 5),
      seriesName: '测试剧集',
      indexedAt: DateTime(2026, 8, 5),
      cover: '/covers/new.jpg',
    );

    try {
      final valid = resolveLocalPlaybackHistoryPoster(
        _entry(posterCachePath: existing.path),
        <String, LocalMediaIndexItem>{item.id: item},
        (_) => null,
      );
      final invalid = resolveLocalPlaybackHistoryPoster(
        _entry(posterCachePath: '${directory.path}/missing.jpg'),
        <String, LocalMediaIndexItem>{item.id: item},
        (_) => null,
      );

      expect(valid.posterCachePath, existing.path);
      expect(invalid.posterCachePath, '/covers/new.jpg');
    } finally {
      existing.deleteSync();
      directory.deleteSync();
    }
  });

  test('观看历史进入页面先加载本地媒体索引', () {
    final source = File('lib/features/history/presentation/history_page.dart')
        .readAsStringSync();

    expect(source, contains('_local.reloadLocalLibraryIndex();'));
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

    expect(source, contains("label: Text('继续观看')"));
    expect(source, contains("label: Text('全部历史')"));
    expect(source, contains("return '今天';"));
    expect(source, contains("return '昨天';"));
    expect(source, contains("return '更早';"));
    expect(source, contains('TimeUtils.formatTimestampToRelativeTime'));
    expect(source, contains("entry.isCompleted ? '已看完'"));
  });

  test('观看历史紧凑显示来源进度和观看时间', () {
    final entry = _entry(position: 27, duration: 100);

    expect(
      formatPlaybackHistoryMeta(entry, '1 天前'),
      '本地 · 已看 27% · 1 天前',
    );
    expect(
      formatPlaybackHistoryMeta(
        _entry(position: 100, duration: 100),
        '刚刚',
      ),
      '本地 · 已看完 · 刚刚',
    );
  });

  test('观看历史页面使用紧凑时间线和单条菜单', () {
    final source = File('lib/features/history/presentation/history_page.dart')
        .readAsStringSync();

    expect(source, contains('SegmentedButton<bool>'));
    expect(source, contains(r"'${entries.length} 条'"));
    expect(source, contains('PopupMenuButton<_HistoryMenuAction>'));
    expect(source, contains('width: 44'));
    expect(source, contains('height: 66'));
    expect(source, isNot(contains('_formatDuration(')));
    expect(
      source,
      isNot(contains('本地媒体和网盘媒体的播放进度会统一保存在这里。')),
    );
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

  test('旧观看历史优先从文件名恢复真实集数', () {
    final entry = _entry(
      seriesTitle: '古灵精探 S01',
      episodeTitle: '儿子被绑',
      mediaPath: '/media/古灵精探 S01E22 儿子被绑.mkv',
      episodeIndex: 1,
    );

    expect(
      formatPlaybackHistoryTitle(entry),
      '古灵精探 S01 · 第22集 · 儿子被绑',
    );
  });
}
