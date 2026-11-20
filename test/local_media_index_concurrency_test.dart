import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/file_system_media_entry_provider.dart';
import 'package:kanyingyin/services/local_media_entry_provider.dart';
import 'package:kanyingyin/services/local_media_indexer.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/features/history/application/playback_history_repository.dart';
import 'package:kanyingyin/features/history/domain/playback_history_entry.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/modules/local/tmdb_image_override.dart';
import 'package:kanyingyin/repositories/tmdb_metadata_repository.dart';
import 'package:kanyingyin/services/tmdb/local_tmdb_scrape_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/local_tmdb_image_selection_service.dart';
import 'package:kanyingyin/modules/local/tmdb_image_metadata.dart';

void main() {
  test('空增量不读取或写入本地索引', () async {
    final storage = _Storage([_item('a')])..failReads = true;
    final repository = LocalMediaIndexRepository(storage: storage);
    await repository.patchItems({}, originals: {});
    expect(storage.started.isCompleted, isFalse);
    expect(storage.values[SettingBoxKey.localMediaIndex], hasLength(1));
  });

  test('阈值调高再调低保留人工匹配且真实删除仍移除', () async {
    final directory = await Directory.systemTemp.createTemp('scan_threshold_');
    addTearDown(() => directory.delete(recursive: true));
    final file =
        await File('${directory.path}/Show S01E01.mkv').writeAsString('video');
    var threshold = 0;
    final repository = LocalMediaIndexRepository(storage: _Storage([]));
    final indexer = LocalMediaIndexer(
        repository: repository,
        minRecognizedVideoSizeBytesProvider: () => threshold);
    await indexer.indexSource(directory.path);
    final original = repository.getAll().single;
    await repository.patchItem(
        original,
        original.copyWith(
            seriesName: '人工匹配',
            manualOverride: true,
            episodeNumber: 7,
            cover: 'manual.jpg',
            tmdb: _metadata()));
    final controller = LocalController(
        mediaIndexRepository: repository,
        localMinSizeBytesProvider: () => threshold);
    threshold = 10;
    final filtered = await indexer.indexSource(directory.path);
    expect(filtered.items, isEmpty);
    expect(filtered.filteredBySizeCount, 1);
    expect(filtered.removedCount, 0);
    expect(repository.getAll().single.manualOverride, isTrue);
    await controller.reloadAvailableLocalLibraryIndex();
    expect(controller.localLibraryItems, isEmpty);
    threshold = 0;
    final restored = await indexer.indexSource(directory.path);
    expect(restored.items.single.id, original.id);
    expect(restored.items.single.seriesName, '人工匹配');
    expect(restored.items.single.episodeNumber, 7);
    expect(restored.items.single.cover, 'manual.jpg');
    await controller.reloadAvailableLocalLibraryIndex();
    expect(controller.localLibraryItems.single.id, original.id);
    await file.delete();
    await indexer.indexSource(directory.path);
    expect(repository.getAll(), isEmpty);
  });

  test('目录暂失效后重试保留人工匹配及原观看记录', () async {
    final directory = await Directory.systemTemp.createTemp('scan_recover_');
    addTearDown(() => directory.delete(recursive: true));
    final file =
        await File('${directory.path}/Show S01E01.mkv').writeAsString('video');
    final repository = LocalMediaIndexRepository(storage: _Storage([]));
    final indexer = LocalMediaIndexer(
        repository: repository, minRecognizedVideoSizeBytes: 0);
    await indexer.indexSource(directory.path);
    final original = repository.getAll().single;
    await repository.patchItem(
        original,
        original.copyWith(
            seriesName: '人工剧名',
            manualOverride: true,
            seasonNumber: 3,
            episodeNumber: 8,
            cover: 'poster.jpg',
            tmdb: _metadata()));
    final history =
        PlaybackHistoryRepository(storage: MemoryPlaybackHistoryStorage());
    await history.save(PlaybackHistoryEntry(
        stableKey: original.id,
        source: PlaybackHistorySource.local,
        sourceId: directory.path,
        seriesTitle: '人工剧名',
        episodeTitle: '第8集',
        mediaPath: file.path,
        episodeIndex: 7,
        positionSeconds: 123,
        durationSeconds: 600,
        updatedAt: DateTime(2026)));
    final moved = await directory.rename('${directory.path}_offline');
    try {
      final unavailable = await indexer.indexSource(directory.path);
      expect(unavailable.sourceAccessible, isFalse);
      expect(repository.getAll().single.manualOverride, isTrue);
    } finally {
      await moved.rename(directory.path);
    }
    await indexer.indexSource(directory.path);
    final restored = repository.getAll().single;
    expect(restored.id, original.id);
    expect(restored.seriesName, '人工剧名');
    expect(restored.episodeNumber, 8);
    expect(restored.tmdb!.id, 1);
    expect((await history.getAll()).single.positionSeconds, 123);
    expect((await history.getAll()).single.stableKey, restored.id);
  });

  test('图片选择真实调用并发改海报背景后索引和元数据缓存均保留', () async {
    final repository = LocalMediaIndexRepository(
        storage: _Storage([
      _item('a').copyWith(tmdb: _metadata()),
    ]));
    final metadataRepository = _MetadataRepository();
    final service = LocalTmdbImageSelectionService(
      indexRepository: repository,
      metadataRepository: metadataRepository,
      client: _PausedTmdbClient(),
    );
    await Future.wait([
      service.selectSeriesImage(
          seriesName: 'a', kind: TmdbImageKind.poster, filePath: '/poster.jpg'),
      service.selectSeriesImage(
          seriesName: 'a',
          kind: TmdbImageKind.backdrop,
          filePath: '/backdrop.jpg'),
    ]);
    for (final metadata in [
      repository.getAll().single.tmdb!,
      metadataRepository.get('a')!
    ]) {
      expect(metadata.imageOverride.poster, '/poster.jpg');
      expect(metadata.imageOverride.backdrop, '/backdrop.jpg');
    }
  });

  test('同一 TMDB 作品并发更新海报背景标题都保留', () async {
    final repository = LocalMediaIndexRepository(
        storage: _Storage([
      _item('a').copyWith(tmdb: _metadata()),
    ]));
    final original = repository.getAll().single;
    await Future.wait([
      repository.patchItem(
          original,
          original.copyWith(
              tmdb: original.tmdb!.copyWith(
            imageOverride: const TmdbImageOverride(poster: 'poster.jpg'),
          ))),
      repository.patchItem(
          original,
          original.copyWith(
              tmdb: original.tmdb!.copyWith(
            title: '人工标题',
            imageOverride: const TmdbImageOverride(backdrop: 'backdrop.jpg'),
          ))),
    ]);
    final metadata = repository.getAll().single.tmdb!;
    expect(metadata.title, '人工标题');
    expect(metadata.imageOverride.poster, 'poster.jpg');
    expect(metadata.imageOverride.backdrop, 'backdrop.jpg');
  });

  test('TMDB 身份改变后保留完整新作品，不能混入旧作品图片', () async {
    final repository = LocalMediaIndexRepository(
        storage: _Storage([
      _item('a').copyWith(tmdb: _metadata()),
    ]));
    final original = repository.getAll().single;
    final replacement = TmdbMetadata(
      id: 2,
      mediaType: TmdbMediaType.tv,
      title: '新作品',
      overview: '新的简介',
      language: 'zh-CN',
      matchedAt: DateTime(2026),
      matchConfidence: 1,
    );
    await repository.patchItem(original, original.copyWith(tmdb: replacement));
    await repository.patchItem(
        original,
        original.copyWith(
            tmdb: original.tmdb!.copyWith(
          imageOverride: const TmdbImageOverride(poster: 'old.jpg'),
        )));
    final metadata = repository.getAll().single.tmdb!;
    expect(metadata.id, 2);
    expect(metadata.mediaType, TmdbMediaType.tv);
    expect(metadata.title, '新作品');
    expect(metadata.imageOverride.isEmpty, isTrue);
  });

  test('不同存储不共享缓存或来源删除代次', () async {
    final first = LocalMediaIndexRepository(storage: _Storage([_item('a')]));
    final second = LocalMediaIndexRepository(storage: _Storage([_item('b')]));
    final snapshot = second.captureSource(_item('b').sourceLocation);
    await first.clear();
    expect(await second.commitSource(snapshot, snapshot.items), isTrue);
    expect(second.getAll().single.name, 'b.mkv');
    expect(first.getAll(), isEmpty);
  });

  test('真实刮削调用在等待详情时删除来源，不复活旧条目', () async {
    final repository =
        LocalMediaIndexRepository(storage: _Storage([_item('a')]));
    final client = _PausedTmdbClient();
    final service = LocalTmdbScrapeService(
      indexRepository: repository,
      metadataRepository: _MetadataRepository(),
      clientFactory: (_) => client,
      posterDownloader: (url, path) async => null,
    );
    final scraping = service.selectItemCandidate(
      apiKey: 'fixture',
      itemId: _item('a').id,
      candidate: _metadata(),
    );
    await client.started.future;
    await repository.removeSource('D:/Media');
    client.resume.complete();
    await scraping;
    expect(repository.getAll(), isEmpty);
  });

  test('扫描提交指纹可重复读取，移除来源清除兼容键', () async {
    final storage = _Storage([_item('a')]);
    final repository = LocalMediaIndexRepository(storage: storage);
    final source = _item('a').sourceLocation;
    final snapshot = repository.captureSource(source);
    await repository.commitSource(snapshot, snapshot.items,
        fingerprints: {'dir': 'current'});
    expect(repository.getDirectoryFingerprintsForLocation(source),
        {'dir': 'current'});
    await repository.removeSourceLocation(source);
    expect(repository.getDirectoryFingerprintsForLocation(source), isEmpty);
    expect(
        storage.values[SettingBoxKey.localMediaDirectoryFingerprints], isEmpty);
  });

  test('读取失败不能缓存空库或让后续修改覆盖原数据', () async {
    final storage = _Storage([_item('a')])..failReads = true;
    final repository = LocalMediaIndexRepository(storage: storage);
    expect(repository.getAll, throwsStateError);
    await expectLater(
        repository.saveForSource('D:/Other', [_item('b')]), throwsStateError);
    await expectLater(repository.updateItem(_item('a')), throwsStateError);
    expect(storage.started.isCompleted, isFalse);
    storage.failReads = false;
    expect(repository.getAll().single.name, 'a.mkv');
  });

  test('损坏的索引条目不能被当成空库覆盖', () async {
    final storage = _Storage([_item('a')]);
    (storage.values[SettingBoxKey.localMediaIndex] as List).add({'path': ''});
    final repository = LocalMediaIndexRepository(storage: storage);
    await expectLater(repository.saveForSource('D:/Other', [_item('b')]),
        throwsA(isA<Object>()));
    expect(storage.started.isCompleted, isFalse);
    expect((storage.values[SettingBoxKey.localMediaIndex] as List).length, 2);
  });

  test('共享存储的仓库并发更新不同条目，不覆盖彼此且共享缓存', () async {
    final a = _item('a');
    final b = _item('b');
    final storage = _Storage([a, b]);
    final first = LocalMediaIndexRepository(storage: storage);
    final second = LocalMediaIndexRepository(storage: storage);
    first.getAll();
    second.getAll();
    final gate = Completer<void>();
    storage.gate = gate;
    final writeA = first.updateItem(a.copyWith(cover: 'a.jpg'));
    await storage.started.future;
    final writeB = second.updateItem(b.copyWith(cover: 'b.jpg'));
    gate.complete();
    await Future.wait([writeA, writeB]);
    expect(first.getByPath(a.path)!.cover, 'a.jpg');
    expect(second.getByPath(b.path)!.cover, 'b.jpg');
    expect(identical(first.getAll(), second.getAll()), isTrue);
    expect((storage.values[SettingBoxKey.localMediaIndex] as List).length, 2);
  });

  test('同一条目的异步封面与人工匹配合并，保留两边结果', () async {
    final repository =
        LocalMediaIndexRepository(storage: _Storage([_item('a')]));
    final original = repository.getAll().single;
    await Future.wait([
      repository.patchItem(original, original.copyWith(cover: 'poster.jpg')),
      repository.patchItem(
          original,
          original.copyWith(
            seriesName: '人工匹配',
            seasonNumber: 2,
            episodeNumber: 3,
            manualOverride: true,
          )),
    ]);
    final current = repository.getAll().single;
    expect(current.cover, 'poster.jpg');
    expect(current.seriesName, '人工匹配');
    expect(current.episodeNumber, 3);
    expect(current.manualOverride, isTrue);
  });

  test('移除再添加相同来源后旧扫描和刮削仍然失效', () async {
    final repository =
        LocalMediaIndexRepository(storage: _Storage([_item('a')]));
    final original = repository.getAll().single;
    final snapshot = repository.captureSource(original.sourceLocation);
    await repository.removeSourceLocation(original.sourceLocation);
    await repository.updateItem(original);
    expect(repository.getAll(), isEmpty);
    final replacement = _item('a').copyWith(seriesName: '新来源');
    await repository
        .saveForSourceLocation(original.sourceLocation, [replacement]);
    expect(
        await repository
            .commitSource(snapshot, [original], fingerprints: {'old': 'old'}),
        isFalse);
    await repository.patchItem(original, original.copyWith(cover: 'old.jpg'));
    expect(repository.getAll().single.seriesName, '新来源');
    expect(repository.getAll().single.cover, isNull);
    expect(
        repository.getDirectoryFingerprintsForLocation(original.sourceLocation),
        isEmpty);
  });

  test('清空使旧扫描失效且写失败不会污染缓存', () async {
    final storage = _Storage([_item('a')]);
    final repository = LocalMediaIndexRepository(storage: storage);
    final snapshot = repository.captureSource(_item('a').sourceLocation);
    storage.failNextWrite = true;
    await expectLater(
        repository.updateItem(_item('a').copyWith(cover: 'failed.jpg')),
        throwsStateError);
    expect(repository.getAll().single.cover, isNull);
    await repository.clear();
    expect(await repository.commitSource(snapshot, snapshot.items), isFalse);
    expect(repository.getAll(), isEmpty);
  });

  test('扫描等待期间改封面与人工匹配，完成后保留并返回最新索引', () async {
    final directory = await Directory.systemTemp.createTemp('kyy_index_race_');
    addTearDown(() => directory.delete(recursive: true));
    final file =
        await File('${directory.path}/Show S01E01.mkv').writeAsString('video');
    final original = LocalMediaIndexItem.fromFile(
      file: file,
      stat: await file.stat(),
      sourcePath: directory.path,
    );
    final repository = LocalMediaIndexRepository(storage: _Storage([original]));
    final provider = _PausedProvider();
    final indexer = LocalMediaIndexer(
        repository: repository,
        entryProviders: [provider],
        minRecognizedVideoSizeBytes: 0);
    final scanning = indexer.indexSource(directory.path);
    await provider.started.future;
    final current = repository.getAll().single;
    await repository.patchItem(
        current,
        current.copyWith(
          cover: 'manual.jpg',
          seriesName: '手动剧名',
          seasonNumber: 4,
          episodeNumber: 8,
          manualOverride: true,
        ));
    provider.resume.complete();
    final result = await scanning;
    expect(result.cancelled, isFalse);
    expect(result.items.single.cover, 'manual.jpg');
    expect(result.items.single.seriesName, '手动剧名');
    expect(result.items.single.episodeNumber, 8);
    expect(repository.getAll().single.manualOverride, isTrue);
    expect(await file.exists(), isTrue);
  });

  test('扫描等待期间移除来源，旧扫描不写回索引或指纹', () async {
    final directory =
        await Directory.systemTemp.createTemp('kyy_index_delete_');
    addTearDown(() => directory.delete(recursive: true));
    final file =
        await File('${directory.path}/Movie.mkv').writeAsString('video');
    final repository = LocalMediaIndexRepository(storage: _Storage([]));
    final provider = _PausedProvider();
    final indexer = LocalMediaIndexer(
        repository: repository,
        entryProviders: [provider],
        minRecognizedVideoSizeBytes: 0);
    final scanning = indexer.indexSource(directory.path);
    await provider.started.future;
    await repository.removeSource(directory.path);
    provider.resume.complete();
    final result = await scanning;
    expect(result.cancelled, isTrue);
    expect(repository.getAll(), isEmpty);
    expect(repository.getDirectoryFingerprints(directory.path), isEmpty);
    expect(await file.exists(), isTrue);
  });
}

LocalMediaIndexItem _item(String name) => LocalMediaIndexItem(
      path: 'D:/Media/$name.mkv',
      name: '$name.mkv',
      parentPath: 'D:/Media',
      sourcePath: 'D:/Media',
      size: 10,
      modified: DateTime(2026),
      indexedAt: DateTime(2026),
      seriesName: name,
    );

class _Storage implements LocalMediaIndexStorage {
  _Storage(List<LocalMediaIndexItem> items)
      : values = {
          SettingBoxKey.localMediaIndex:
              items.map((item) => item.toJson()).toList(),
        };
  final Map<String, Object?> values;
  final started = Completer<void>();
  Completer<void>? gate;
  bool failNextWrite = false;
  bool failReads = false;
  @override
  Object? read(String key, {Object? defaultValue}) {
    if (failReads) throw StateError('模拟读取失败');
    return values[key] ?? defaultValue;
  }

  @override
  Future<void> write(String key, Object? value) async {
    if (!started.isCompleted) started.complete();
    final waiting = gate;
    gate = null;
    if (waiting != null) await waiting.future;
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('模拟写入失败');
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _PausedProvider implements LocalMediaEntryProvider {
  final started = Completer<void>();
  final resume = Completer<void>();
  final delegate = const FileSystemMediaEntryProvider();
  @override
  bool supports(MediaLocation location) => delegate.supports(location);
  @override
  Future<bool> canAccess(MediaLocation location) async {
    started.complete();
    await resume.future;
    return delegate.canAccess(location);
  }

  @override
  Future<List<LocalMediaEntry>> listChildren(MediaLocation directory) =>
      delegate.listChildren(directory);
}

TmdbMetadata _metadata() => TmdbMetadata(
      id: 1,
      mediaType: TmdbMediaType.movie,
      title: '影片',
      overview: '',
      language: 'zh-CN',
      matchedAt: DateTime(2026),
      matchConfidence: 1,
    );

class _PausedTmdbClient implements ITmdbClient {
  final started = Completer<void>();
  final resume = Completer<void>();
  @override
  Future<TmdbMetadata> details(int id, TmdbMediaType mediaType,
      {String language = 'zh-CN'}) async {
    started.complete();
    await resume.future;
    return _metadata();
  }

  @override
  Future<List<TmdbMetadata>> search(String query, TmdbMediaType mediaType,
          {String language = 'zh-CN'}) async =>
      [_metadata()];
}

class _MetadataRepository implements ITmdbMetadataRepository {
  final values = <String, TmdbMetadata>{};
  @override
  TmdbMetadata? get(String mediaKey) => values[mediaKey];
  @override
  Future<void> remove(String mediaKey) async {
    values.remove(mediaKey);
  }

  @override
  Future<void> save(String mediaKey, TmdbMetadata metadata) async {
    values[mediaKey] = metadata;
  }
}
