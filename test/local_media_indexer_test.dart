import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/local_media_indexer.dart';
import 'package:kanyingyin/services/local_media_library_builder.dart';
import 'package:kanyingyin/services/local_media_probe.dart';
import 'package:path/path.dart' as p;

void main() {
  test('LocalMediaIndexer recursively indexes videos with metadata', () async {
    final tempDir = await Directory.systemTemp.createTemp('kanyingyin_index_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final seasonDir = Directory('${tempDir.path}${Platform.pathSeparator}Show');
    await seasonDir.create();
    const videoName = '[SubGroup] Show S01E02 [1080p][Web-DL][HEVC]';
    final video =
        File('${seasonDir.path}${Platform.pathSeparator}$videoName.mkv');
    final subtitle =
        File('${seasonDir.path}${Platform.pathSeparator}$videoName.ass');
    final poster =
        File('${seasonDir.path}${Platform.pathSeparator}$videoName.jpg');
    await video.writeAsString('video');
    await subtitle.writeAsString('subtitle');
    await poster.writeAsString('poster');
    await File('${seasonDir.path}${Platform.pathSeparator}note.txt')
        .writeAsString('note');

    final repository = _MemoryMediaIndexRepository();
    final indexer = _testIndexer(
      repository: repository,
      mediaProbe: const _FakeMediaProbe({}),
    );

    final result = await indexer.indexSource(tempDir.path);

    expect(result.totalCount, 1);
    expect(result.addedCount, 1);
    expect(result.skippedCount, 0);
    expect(repository.getAll(), hasLength(1));
    final item = repository.getAll().single;
    expect(item.path, video.path);
    expect(item.cover, poster.path);
    expect(item.subtitlePath, subtitle.path);
    expect(item.episodeInfo, isNotNull);
    expect(item.episodeInfo!.seriesName, 'Show');
    expect(item.episodeInfo!.seasonNumber, 1);
    expect(item.episodeInfo!.episodeNumber, 2);
    expect(item.releaseGroup, 'SubGroup');
    expect(item.resolution, '1080p');
    expect(item.source, 'Web-DL');
    expect(item.codec, 'HEVC');
  });

  test('LocalMediaIndexer reuses unchanged index items', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_index_reuse_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final video =
        File('${tempDir.path}${Platform.pathSeparator}Show S01E01.mkv');
    await video.writeAsString('video');

    final repository = _MemoryMediaIndexRepository();
    final indexer = _testIndexer(
      repository: repository,
      mediaProbe: const _FakeMediaProbe({}),
    );

    final first = await indexer.indexSource(tempDir.path);
    final oldIndexedAt = repository.getAll().single.indexedAt;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final second = await indexer.indexSource(tempDir.path);

    expect(first.addedCount, 1);
    expect(second.reusedCount, 1);
    expect(second.addedCount, 0);
    expect(second.updatedCount, 0);
    expect(repository.getAll().single.indexedAt.isAfter(oldIndexedAt), isTrue);
  });

  test('LocalMediaIndexer reuses unchanged directory index items', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_index_dir_reuse_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final seasonDir = Directory('${tempDir.path}${Platform.pathSeparator}Show');
    await seasonDir.create();
    final video =
        File('${seasonDir.path}${Platform.pathSeparator}Show S01E01.mkv');
    await video.writeAsString('video');

    final repository = _MemoryMediaIndexRepository();
    final indexer = _testIndexer(
      repository: repository,
      mediaProbe: const _FakeMediaProbe({}),
    );

    await indexer.indexSource(tempDir.path);
    final second = await indexer.indexSource(tempDir.path);

    expect(second.reusedCount, 1);
    expect(second.addedCount, 0);
    expect(second.updatedCount, 0);
    expect(repository.getDirectoryFingerprints(tempDir.path), isNotEmpty);
  });

  test('LocalMediaIndexer refreshes stale derived metadata on unchanged files',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_index_refresh_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final video =
        File('${tempDir.path}${Platform.pathSeparator}Movie 2024 4K-kc.mkv');
    final subtitle =
        File('${tempDir.path}${Platform.pathSeparator}Movie 2024 4K-kc.ass');
    await video.writeAsString('video');
    await subtitle.writeAsString('subtitle');
    final stat = await video.stat();
    final stale = LocalMediaIndexItem(
      path: video.path,
      name: p.basename(video.path),
      parentPath: tempDir.path,
      sourcePath: tempDir.path,
      size: stat.size,
      modified: stat.modified,
      seriesName: 'Movie 2024',
      episodeNumber: 4,
      episodeTitle: 'kc',
      pathFingerprint: LocalMediaIndexItem.buildPathFingerprint(
        video.path,
        stat,
      ),
      derivedMetadataVersion: 0,
      indexedAt: DateTime(2026),
    );

    final repository = _MemoryMediaIndexRepository();
    await repository.saveForSource(tempDir.path, [stale]);
    final indexer = _testIndexer(
      repository: repository,
      mediaProbe: const _FakeMediaProbe({}),
    );

    final result = await indexer.indexSource(tempDir.path);

    expect(result.updatedCount, 1);
    expect(result.reusedCount, 0);
    final item = repository.getAll().single;
    expect(item.hasCurrentDerivedMetadata, isTrue);
    expect(item.seriesName, p.basename(tempDir.path));
    expect(item.episodeNumber, isNull);
    expect(item.episodeTitle, isNull);
    expect(item.subtitlePath, subtitle.path);
  });

  test('LocalMediaIndexer can cancel before saving partial results', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_index_cancel_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    await File('${tempDir.path}${Platform.pathSeparator}Show S01E01.mkv')
        .writeAsString('video');
    final repository = _MemoryMediaIndexRepository();
    final indexer = _testIndexer(
      repository: repository,
      mediaProbe: const _FakeMediaProbe({}),
    );

    final result = await indexer.indexSource(
      tempDir.path,
      isCancelled: () => true,
    );

    expect(result.cancelled, isTrue);
    expect(repository.getAll(), isEmpty);
  });

  test('LocalMediaIndexer removes deleted videos from index', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_index_delete_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final first =
        File('${tempDir.path}${Platform.pathSeparator}Show S01E01.mkv');
    final second =
        File('${tempDir.path}${Platform.pathSeparator}Show S01E02.mkv');
    await first.writeAsString('first');
    await second.writeAsString('second');

    final repository = _MemoryMediaIndexRepository();
    final indexer = _testIndexer(
      repository: repository,
      mediaProbe: const _FakeMediaProbe({}),
    );

    await indexer.indexSource(tempDir.path);
    await second.delete();
    final result = await indexer.indexSource(tempDir.path);

    expect(result.removedCount, 1);
    expect(repository.getAll(), hasLength(1));
    expect(repository.getAll().single.path, first.path);
  });

  test('LocalMediaIndexer enriches media info when requested', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_index_probe_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final video =
        File('${tempDir.path}${Platform.pathSeparator}Show S01E03.mkv');
    await video.writeAsString('video');
    final repository = _MemoryMediaIndexRepository();
    final indexer = _testIndexer(
      repository: repository,
      mediaProbe: _FakeMediaProbe({
        video.path: const LocalMediaInfo(
          duration: Duration(minutes: 24),
          width: 1920,
          height: 1080,
        ),
      }),
    );

    await indexer.indexSource(tempDir.path, enrichMediaInfo: true);

    final item = repository.getAll().single;
    expect(item.durationMillis, const Duration(minutes: 24).inMilliseconds);
    expect(item.videoWidth, 1920);
    expect(item.videoHeight, 1080);
  });

  test('LocalMediaSeries groups indexed episodes', () {
    final now = DateTime(2026);
    final items = [
      LocalMediaIndexItem(
        path: 'Show S01E02.mkv',
        name: 'Show S01E02.mkv',
        parentPath: '.',
        sourcePath: '.',
        size: 1,
        modified: now,
        seriesName: 'Show',
        seasonNumber: 1,
        episodeNumber: 2,
        indexedAt: now,
      ),
      LocalMediaIndexItem(
        path: 'Show S01E01.mkv',
        name: 'Show S01E01.mkv',
        parentPath: '.',
        sourcePath: '.',
        size: 1,
        modified: now,
        seriesName: 'Show',
        seasonNumber: 1,
        episodeNumber: 1,
        indexedAt: now,
      ),
    ];

    final series = const LocalMediaLibraryBuilder().buildSeries(items);

    expect(series, hasLength(1));
    expect(series.single.title, 'Show S01');
    expect(series.single.episodeCount, 2);
    expect(series.single.episodes.map((item) => item.episodeNumber), [1, 2]);
  });

  test('LocalMediaSeries separates seasons, OVA and movie folders', () {
    final now = DateTime(2026);
    final items = [
      LocalMediaIndexItem(
        path: r'D:\a TV\中二病也要谈恋爱\第1季\01.mkv',
        name: '01.mkv',
        parentPath: r'D:\a TV\中二病也要谈恋爱\第1季',
        sourcePath: r'D:\a TV',
        size: 1,
        modified: now,
        seriesName: '中二病也要谈恋爱',
        seasonNumber: 1,
        episodeNumber: 1,
        indexedAt: now,
      ),
      LocalMediaIndexItem(
        path: r'D:\a TV\中二病也要谈恋爱\第2季\01.mkv',
        name: '01.mkv',
        parentPath: r'D:\a TV\中二病也要谈恋爱\第2季',
        sourcePath: r'D:\a TV',
        size: 1,
        modified: now,
        seriesName: '中二病也要谈恋爱',
        seasonNumber: 2,
        episodeNumber: 1,
        indexedAt: now,
      ),
      LocalMediaIndexItem(
        path: r'D:\a TV\中二病也要谈恋爱\剧场版\movie.mkv',
        name: 'movie.mkv',
        parentPath: r'D:\a TV\中二病也要谈恋爱\剧场版',
        sourcePath: r'D:\a TV',
        size: 1,
        modified: now,
        seriesName: '剧场版 中二病也要谈恋爱 Take On Me',
        episodeNumber: 1,
        indexedAt: now,
      ),
      LocalMediaIndexItem(
        path: r'D:\a TV\中二病也要谈恋爱\第1季\OVA.mkv',
        name: 'OVA.mkv',
        parentPath: r'D:\a TV\中二病也要谈恋爱\第1季',
        sourcePath: r'D:\a TV',
        size: 1,
        modified: now,
        seriesName: '第1季',
        indexedAt: now,
      ),
    ];

    final series = const LocalMediaLibraryBuilder().buildSeries(items);

    expect(series, hasLength(4));
    expect(series.map((item) => item.title), [
      '中二病也要谈恋爱 S01',
      '中二病也要谈恋爱 S01 OVA',
      '中二病也要谈恋爱 S02',
      '中二病也要谈恋爱 剧场版',
    ]);
    expect(series.map((item) => item.episodeCount), [1, 1, 1, 1]);
  });

  test('LocalMediaIndexer skips videos below the recognized size', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_index_small_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final small =
        File('${tempDir.path}${Platform.pathSeparator}Small S01E01.mkv');
    final large =
        File('${tempDir.path}${Platform.pathSeparator}Large S01E01.mkv');
    await small.writeAsBytes(List<int>.filled(16, 0));
    await large.writeAsBytes(List<int>.filled(32, 0));

    final repository = _MemoryMediaIndexRepository();
    final indexer = LocalMediaIndexer(
      repository: repository,
      mediaProbe: const _FakeMediaProbe({}),
      minRecognizedVideoSizeBytes: 16,
    );

    final result = await indexer.indexSource(tempDir.path);

    expect(result.totalCount, 1);
    expect(result.skippedCount, 1);
    expect(repository.getAll().single.path, large.path);
  });

  test('LocalMediaIndexer 降低动态限制后重新索引未变化目录', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_dynamic_index_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final small = File(p.join(tempDir.path, 'Small S01E01.mkv'));
    final large = File(p.join(tempDir.path, 'Large S01E01.mkv'));
    await small.writeAsBytes(List<int>.filled(24, 0));
    await large.writeAsBytes(List<int>.filled(48, 0));
    final repository = _MemoryMediaIndexRepository();
    var minSizeBytes = 32;
    var providerCalls = 0;
    final indexer = LocalMediaIndexer(
      repository: repository,
      mediaProbe: const _FakeMediaProbe({}),
      minRecognizedVideoSizeBytesProvider: () {
        providerCalls++;
        return minSizeBytes;
      },
    );

    final first = await indexer.indexSource(tempDir.path);
    minSizeBytes = 16;
    final second = await indexer.indexSource(tempDir.path);

    expect(first.items.map((item) => item.path), <String>[large.path]);
    expect(second.items.map((item) => item.path),
        unorderedEquals(<String>[small.path, large.path]));
    expect(second.addedCount, 1);
    expect(providerCalls, 2);
  });

  test('LocalMediaIndexer 主动跳过 Windows 系统目录', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_system_dirs_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    final valid = File(p.join(tempDir.path, 'Show S01E01.mkv'));
    await valid.writeAsString('video');
    for (final name in const <String>[
      'System Volume Information',
      r'$RECYCLE.BIN'
    ]) {
      final directory = Directory(p.join(tempDir.path, name));
      await directory.create();
      await File(p.join(directory.path, 'Hidden S01E01.mkv'))
          .writeAsString('video');
    }
    final repository = _MemoryMediaIndexRepository();

    final result = await _testIndexer(
      repository: repository,
      mediaProbe: const _FakeMediaProbe({}),
    ).indexSource(tempDir.path);

    expect(result.items.map((item) => item.path), <String>[valid.path]);
    expect(result.failures, isEmpty);
    expect(result.skippedCount, 2);
  });

  test('LocalMediaIndexer 对大量文件节流索引进度通知', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_progress_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    for (var index = 0; index < 120; index++) {
      await File(p.join(tempDir.path, 'Show S01E${index + 1}.mkv'))
          .writeAsString('video');
    }
    final progress = <LocalMediaIndexProgress>[];

    await _testIndexer(
      repository: _MemoryMediaIndexRepository(),
      mediaProbe: const _FakeMediaProbe({}),
    ).indexSource(tempDir.path, onProgress: progress.add);

    final indexing = progress
        .where((item) => item.phase == LocalMediaIndexPhase.indexing)
        .toList();
    expect(indexing.length, lessThan(20));
    expect(indexing.last.current, 120);
  });
}

LocalMediaIndexer _testIndexer({
  required ILocalMediaIndexRepository repository,
  required ILocalMediaProbe mediaProbe,
}) {
  return LocalMediaIndexer(
    repository: repository,
    mediaProbe: mediaProbe,
    minRecognizedVideoSizeBytes: 0,
  );
}

class _FakeMediaProbe implements ILocalMediaProbe {
  const _FakeMediaProbe(this.infoByPath);

  final Map<String, LocalMediaInfo> infoByPath;

  @override
  Future<LocalMediaInfo> probe(String filePath) async {
    return infoByPath[filePath] ?? const LocalMediaInfo();
  }

  @override
  Future<String?> captureThumbnail(String filePath, String outputPath) async {
    return null;
  }
}

class _MemoryMediaIndexRepository implements ILocalMediaIndexRepository {
  final _items = <String, LocalMediaIndexItem>{};
  final _fingerprints = <String, Map<String, String>>{};

  @override
  List<LocalMediaIndexItem> getAll() {
    return _items.values.toList();
  }

  @override
  List<LocalMediaIndexItem> getBySourcePath(String sourcePath) {
    final sourceId = LocalMediaIndexItem.normalizePath(sourcePath);
    return _items.values
        .where((item) =>
            LocalMediaIndexItem.normalizePath(item.sourcePath) == sourceId)
        .toList(growable: false);
  }

  @override
  LocalMediaIndexItem? getByPath(String path) {
    return _items[LocalMediaIndexItem.normalizePath(path)];
  }

  @override
  Map<String, String> getDirectoryFingerprints(String sourcePath) {
    return Map<String, String>.from(
      _fingerprints[LocalMediaIndexItem.normalizePath(sourcePath)] ??
          const <String, String>{},
    );
  }

  @override
  Future<void> saveForSource(
    String sourcePath,
    List<LocalMediaIndexItem> items,
  ) async {
    final sourceId = LocalMediaIndexItem.normalizePath(sourcePath);
    _items.removeWhere(
      (_, item) =>
          LocalMediaIndexItem.normalizePath(item.sourcePath) == sourceId,
    );
    for (final item in items) {
      _items[item.id] = item;
    }
  }

  @override
  Future<void> updateItem(LocalMediaIndexItem item) async {
    _items[item.id] = item;
  }

  @override
  Future<void> saveDirectoryFingerprints(
    String sourcePath,
    Map<String, String> fingerprints,
  ) async {
    _fingerprints[LocalMediaIndexItem.normalizePath(sourcePath)] =
        Map<String, String>.from(fingerprints);
  }

  @override
  Future<void> removeSource(String sourcePath) async {
    final sourceId = LocalMediaIndexItem.normalizePath(sourcePath);
    _items.removeWhere(
      (_, item) =>
          LocalMediaIndexItem.normalizePath(item.sourcePath) == sourceId,
    );
    _fingerprints.remove(sourceId);
  }

  @override
  Future<void> clear() async {
    _items.clear();
    _fingerprints.clear();
  }
}
