import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/local_media_source.dart';
import 'package:kanyingyin/modules/local/poster_scrape.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/local_media_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/local_media_indexer.dart';
import 'package:kanyingyin/services/local_media_scanner.dart';
import 'package:kanyingyin/services/local_media_probe.dart';
import 'package:kanyingyin/services/local_poster_scraper.dart';
import 'package:kanyingyin/services/local_thumbnail_cache.dart';

void main() {
  test('LocalController ignores stale navigation results', () async {
    final firstDir = await Directory.systemTemp.createTemp('kanyingyin_first_');
    final secondDir =
        await Directory.systemTemp.createTemp('kanyingyin_second_');
    addTearDown(() async {
      if (await firstDir.exists()) {
        await firstDir.delete(recursive: true);
      }
      if (await secondDir.exists()) {
        await secondDir.delete(recursive: true);
      }
    });

    final scanner = _DelayedScanner();
    final controller = LocalController(
      scanner: scanner,
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      saveLastDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );

    final firstNavigation = controller.navigateTo(firstDir.path);
    final secondNavigation = controller.navigateTo(secondDir.path);

    await scanner.waitFor(firstDir.path);
    await scanner.waitFor(secondDir.path);

    scanner.complete(
      secondDir.path,
      [_item(path: '${secondDir.path}${Platform.pathSeparator}second.mkv')],
    );
    await secondNavigation;

    expect(controller.currentPath, secondDir.path);
    expect(controller.items.single.name, 'second.mkv');
    expect(controller.isLoading, isFalse);

    scanner.complete(
      firstDir.path,
      [_item(path: '${firstDir.path}${Platform.pathSeparator}first.mkv')],
    );
    await firstNavigation;

    expect(controller.currentPath, secondDir.path);
    expect(controller.items.single.name, 'second.mkv');
    expect(controller.isLoading, isFalse);
  });

  test('LocalController still scans when saving last directory fails',
      () async {
    final dir = await Directory.systemTemp.createTemp('kanyingyin_save_fail_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final scanner = _ImmediateScanner([
      _item(path: '${dir.path}${Platform.pathSeparator}video.mkv'),
    ]);
    final controller = LocalController(
      scanner: scanner,
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      saveLastDirectory: (_) => throw Exception('storage unavailable'),
      saveRecentDirectories: (_) {},
    );

    await controller.navigateTo(dir.path);

    expect(controller.currentPath, dir.path);
    expect(controller.items.single.name, 'video.mkv');
    expect(controller.errorMessage, isNull);
    expect(controller.isLoading, isFalse);
  });

  test('LocalController sets root directory when saving default path fails',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('kanyingyin_default_fail_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final scanner = _ImmediateScanner([
      _item(path: '${dir.path}${Platform.pathSeparator}root.mkv'),
    ]);
    final controller = LocalController(
      scanner: scanner,
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      saveLastDirectory: (_) {},
      saveDefaultDirectory: (_) => throw Exception('settings unavailable'),
      saveRecentDirectories: (_) {},
    );

    final selected = await controller.setRootDirectory(dir.path);

    expect(selected, isTrue);
    expect(controller.currentPath, dir.path);
    expect(controller.items.single.name, 'root.mkv');
    expect(controller.errorMessage, isNull);
  });

  test('LocalController records selected root directory as media source',
      () async {
    final dir = await Directory.systemTemp.createTemp('kanyingyin_source_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final sourceRepository = _MemoryMediaSourceRepository();
    final controller = LocalController(
      scanner: _ImmediateScanner(const []),
      mediaSourceRepository: sourceRepository,
      saveLastDirectory: (_) {},
      saveDefaultDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );

    final selected = await controller.setRootDirectory(dir.path);

    expect(selected, isTrue);
    expect(sourceRepository.upsertedPaths, [dir.path]);
    expect(controller.mediaSources.single.path, dir.path);
  });

  test('LocalController stores scan summary for current directory', () async {
    final dir =
        await Directory.systemTemp.createTemp('kanyingyin_scan_summary_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final sourceRepository = _MemoryMediaSourceRepository();
    final controller = LocalController(
      scanner: _ImmediateResultScanner(LocalScanResult(
        currentPath: dir.path,
        items: [
          _dirItem(path: '${dir.path}${Platform.pathSeparator}Season 1'),
          _item(path: '${dir.path}${Platform.pathSeparator}video.mkv'),
        ],
        skippedCount: 3,
      )),
      mediaSourceRepository: sourceRepository,
      saveLastDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );

    await controller.navigateTo(dir.path);

    expect(sourceRepository.scanSummaries.single.path, dir.path);
    expect(sourceRepository.scanSummaries.single.fileCount, 2);
    expect(sourceRepository.scanSummaries.single.videoCount, 1);
    expect(sourceRepository.scanSummaries.single.directoryCount, 1);
    expect(sourceRepository.scanSummaries.single.skippedCount, 3);
    expect(controller.mediaSources.single.path, dir.path);
    expect(controller.mediaSources.single.fileCount, 2);
    expect(controller.mediaSources.single.videoCount, 1);
    expect(controller.mediaSources.single.directoryCount, 1);
    expect(controller.mediaSources.single.skippedCount, 3);
    expect(controller.mediaSources.single.lastScannedAt, isNotNull);
  });

  test('LocalController removes media source from list', () async {
    final dir =
        await Directory.systemTemp.createTemp('kanyingyin_source_remove_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final controller = LocalController(
      scanner: _ImmediateScanner(const []),
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      saveLastDirectory: (_) {},
      saveDefaultDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );

    await controller.setRootDirectory(dir.path);
    final removed = await controller.removeMediaSource(dir.path);

    expect(removed, isTrue);
    expect(controller.mediaSources, isEmpty);
  });

  test('LocalController removes unavailable media sources', () async {
    final dir =
        await Directory.systemTemp.createTemp('kanyingyin_source_stale_');

    final controller = LocalController(
      scanner: _ImmediateScanner(const []),
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      saveLastDirectory: (_) {},
      saveDefaultDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );

    await controller.setRootDirectory(dir.path);
    await dir.delete(recursive: true);

    expect(controller.unavailableMediaSourceCount(), 1);

    final removedCount = await controller.removeUnavailableMediaSources();

    expect(removedCount, 1);
    expect(controller.mediaSources, isEmpty);
  });

  test('LocalController does not duplicate path history on refresh', () async {
    final dir = await Directory.systemTemp.createTemp('kanyingyin_history_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final controller = LocalController(
      scanner: _ImmediateScanner([
        _item(path: '${dir.path}${Platform.pathSeparator}video.mkv'),
      ]),
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      saveLastDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );

    await controller.navigateTo(dir.path);
    await controller.refresh();

    expect(controller.pathHistory, [dir.path]);
  });

  test('LocalController persists recent directories in latest-first order',
      () async {
    final firstDir =
        await Directory.systemTemp.createTemp('kanyingyin_recent_a_');
    final secondDir =
        await Directory.systemTemp.createTemp('kanyingyin_recent_b_');
    addTearDown(() async {
      if (await firstDir.exists()) {
        await firstDir.delete(recursive: true);
      }
      if (await secondDir.exists()) {
        await secondDir.delete(recursive: true);
      }
    });

    final saved = <List<String>>[];
    final controller = LocalController(
      scanner: _ImmediateScanner(const []),
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      saveLastDirectory: (_) {},
      saveRecentDirectories: (paths) {
        saved.add(List<String>.of(paths));
      },
    );

    await controller.navigateTo(firstDir.path);
    await controller.navigateTo(secondDir.path);
    await controller.navigateTo(firstDir.path);
    await Future<void>.delayed(Duration.zero);

    expect(controller.pathHistory, [firstDir.path, secondDir.path]);
    expect(saved.last, [firstDir.path, secondDir.path]);
  });

  test('LocalController waits for refresh when toggling sort', () async {
    final dir = await Directory.systemTemp.createTemp('kanyingyin_sort_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final scanner = _SortingScanner(dir.path);
    final controller = LocalController(
      scanner: scanner,
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      saveLastDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );

    await controller.navigateTo(dir.path);
    await controller.toggleSort(LocalSortMode.size.value);

    expect(controller.sortBy, LocalSortMode.size.value);
    expect(controller.sortAscending, isTrue);
    expect(scanner.calls.last.sortMode, LocalSortMode.size);
    expect(scanner.calls.last.ascending, isTrue);
    expect(controller.items.single.name, 'size-sort.mkv');

    await controller.toggleSort(LocalSortMode.size.value);

    expect(controller.sortAscending, isFalse);
    expect(scanner.calls.last.sortMode, LocalSortMode.size);
    expect(scanner.calls.last.ascending, isFalse);
    expect(controller.items.single.name, 'size-sort-desc.mkv');
  });

  test('LocalController ignores stale poster refresh after navigation',
      () async {
    final firstDir =
        await Directory.systemTemp.createTemp('kanyingyin_poster_a_');
    final secondDir =
        await Directory.systemTemp.createTemp('kanyingyin_poster_b_');
    addTearDown(() async {
      if (await firstDir.exists()) {
        await firstDir.delete(recursive: true);
      }
      if (await secondDir.exists()) {
        await secondDir.delete(recursive: true);
      }
    });

    final scanner = _PathScanner({
      firstDir.path: [
        _item(path: '${firstDir.path}${Platform.pathSeparator}a.mkv'),
      ],
      secondDir.path: [
        _item(path: '${secondDir.path}${Platform.pathSeparator}b.mkv'),
      ],
    });
    final posterScraper = _DelayedPosterScraper();
    final controller = LocalController(
      scanner: scanner,
      posterScraper: posterScraper,
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      saveLastDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );

    await controller.navigateTo(firstDir.path);
    final posterFetch = controller.fetchPosters();
    await posterScraper.started.future;

    await controller.navigateTo(secondDir.path);
    posterScraper.complete(const PosterScrapeResult(
      success: 1,
      failed: 0,
      skipped: 0,
      total: 1,
    ));
    await posterFetch;

    expect(controller.currentPath, secondDir.path);
    expect(controller.items.single.name, 'b.mkv');
    expect(controller.isFetchingPosters, isFalse);
    expect(scanner.scannedPaths, [
      firstDir.path,
      secondDir.path,
    ]);
  });

  test('LocalController updates media info for current directory videos',
      () async {
    final dir = await Directory.systemTemp.createTemp('kanyingyin_media_info_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final videoPath = '${dir.path}${Platform.pathSeparator}video.mkv';
    final controller = LocalController(
      scanner: _ImmediateScanner([
        _item(path: videoPath),
      ]),
      mediaProbe: _FakeMediaProbe({
        videoPath: const LocalMediaInfo(
          duration: Duration(minutes: 24, seconds: 12),
          width: 1920,
          height: 1080,
        ),
      }),
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      saveLastDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );

    await controller.navigateTo(dir.path);
    final updated = await controller.fetchMediaInfo();

    expect(updated, 1);
    expect(controller.items.single.formattedDuration, '24:12');
    expect(controller.items.single.formattedResolution, '1920x1080');
    expect(controller.isFetchingMediaInfo, isFalse);
  });

  test('LocalController captures thumbnails for videos without cover',
      () async {
    final dir = await Directory.systemTemp.createTemp('kanyingyin_thumbnail_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final videoPath = '${dir.path}${Platform.pathSeparator}video.mkv';
    final controller = LocalController(
      scanner: _ImmediateScanner([
        _item(path: videoPath),
      ]),
      mediaProbe: _FakeMediaProbe(const {}),
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      saveLastDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );

    await controller.navigateTo(dir.path);
    final updated = await controller.fetchThumbnails();
    final thumbnailPath = LocalThumbnailCache.pathForVideo(videoPath);

    expect(updated, 1);
    expect(controller.items.single.cover, thumbnailPath);
    expect(File(thumbnailPath).existsSync(), isTrue);
    expect(controller.isFetchingThumbnails, isFalse);
  });

  test('LocalController refreshes local library index for media sources',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('kanyingyin_library_index_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final video = File('${dir.path}${Platform.pathSeparator}Show S01E01.mkv');
    await video.writeAsString('video');
    final indexRepository = _MemoryMediaIndexRepository();
    final sourceRepository = _MemoryMediaSourceRepository();
    final controller = LocalController(
      scanner: _ImmediateScanner(const []),
      mediaIndexer: _FakeMediaIndexer(indexRepository),
      mediaIndexRepository: indexRepository,
      mediaSourceRepository: sourceRepository,
      saveLastDirectory: (_) {},
      saveDefaultDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );

    await controller.setRootDirectory(dir.path);
    final result = await controller.refreshLocalLibraryIndex();

    expect(result['sources'], 1);
    expect(result['total'], 1);
    expect(result['added'], 1);
    expect(controller.localLibraryVideoCount, 1);
    expect(controller.localLibrarySeriesCount, 1);
    expect(controller.libraryIndexSummary, contains('1 个视频'));
    expect(controller.isIndexingLibrary, isFalse);
    expect(sourceRepository.scanSummaries.last.videoCount, 1);
  });

  test('严格刷新本地媒体库时拒绝复用正在进行的扫描', () async {
    final controller = LocalController(
      scanner: _ImmediateScanner(const []),
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      saveLastDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );
    controller.isIndexingLibrary = true;

    await expectLater(
      controller.refreshLocalLibraryIndex(throwOnFailure: true),
      throwsA(isA<LocalLibraryScanInProgressException>()),
    );
  });

  test('严格刷新本地媒体库时向上传递索引异常', () async {
    final dir = await Directory.systemTemp.createTemp('strict_local_index_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final sourceRepository = _MemoryMediaSourceRepository();
    final controller = LocalController(
      scanner: _ImmediateScanner(const []),
      mediaIndexer: _ThrowingMediaIndexer(),
      mediaSourceRepository: sourceRepository,
      saveLastDirectory: (_) {},
      saveDefaultDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );
    await controller.setRootDirectory(dir.path);

    await expectLater(
      controller.refreshLocalLibraryIndex(throwOnFailure: true),
      throwsA(isA<StateError>()),
    );
    expect(controller.libraryIndexSummary, '媒体库索引失败');
    expect(controller.isIndexingLibrary, isFalse);
  });

  test('严格刷新本地媒体库时向上传递索引取消状态', () async {
    final dir = await Directory.systemTemp.createTemp('cancelled_local_index_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final controller = LocalController(
      scanner: _ImmediateScanner(const []),
      mediaIndexer: _CancelledMediaIndexer(),
      mediaIndexRepository: _MemoryMediaIndexRepository(),
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      saveLastDirectory: (_) {},
      saveDefaultDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );
    await controller.setRootDirectory(dir.path);

    await expectLater(
      controller.refreshLocalLibraryIndex(throwOnFailure: true),
      throwsA(isA<LocalLibraryScanCancelledException>()),
    );
    expect(controller.libraryIndexSummary, contains('媒体库扫描已取消'));
    expect(controller.isIndexingLibrary, isFalse);
  });

  test('严格重载网盘媒体库时向上传递仓储异常', () async {
    final controller = LocalController(
      scanner: _ImmediateScanner(const []),
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      cloudSourceRepository: CloudSourceRepository(
        storage: _ThrowingCloudSourceStorage(),
        credentialStore: MemoryCloudCredentialStore(),
      ),
      saveLastDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );

    await expectLater(
      controller.reloadCloudLibraryIndex(throwOnFailure: true),
      throwsA(isA<StateError>()),
    );
  });

  test('LocalController repairs stale local library metadata', () async {
    final dir =
        await Directory.systemTemp.createTemp('kanyingyin_init_repair_');
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    final video = File('${dir.path}${Platform.pathSeparator}Movie 2024 4K.mkv');
    final subtitle =
        File('${dir.path}${Platform.pathSeparator}Movie 2024 4K.ass');
    await video.writeAsString('video');
    await subtitle.writeAsString('subtitle');
    final stat = await video.stat();
    final indexRepository = _MemoryMediaIndexRepository();
    await indexRepository.saveForSource(dir.path, [
      LocalMediaIndexItem(
        path: video.path,
        name: video.path.split(Platform.pathSeparator).last,
        parentPath: dir.path,
        sourcePath: dir.path,
        size: stat.size,
        modified: stat.modified,
        seriesName: 'Movie 2024',
        episodeNumber: 4,
        pathFingerprint:
            LocalMediaIndexItem.buildPathFingerprint(video.path, stat),
        derivedMetadataVersion: 0,
        indexedAt: DateTime(2026),
      ),
    ]);
    final controller = LocalController(
      scanner: _ImmediateScanner(const []),
      mediaIndexRepository: indexRepository,
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      loadRecentDirectories: () => const <String>[],
      saveLastDirectory: (_) {},
      saveDefaultDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );

    final refreshed = await controller.refreshLocalLibraryDerivedMetadata();

    expect(refreshed, 1);
    final item = controller.localLibraryItems.single;
    expect(item.hasCurrentDerivedMetadata, isTrue);
    expect(item.episodeNumber, isNull);
    expect(item.subtitlePath, subtitle.path);
  });

  test('LocalController resolves indexed series name from video paths',
      () async {
    final repository = _MemoryMediaIndexRepository();
    final item = LocalMediaIndexItem(
      path: r'D:\Video\Movie.mkv',
      name: 'Movie.mkv',
      parentPath: r'D:\Video',
      sourcePath: r'D:\Video',
      size: 100,
      modified: DateTime(2026),
      seriesName: '电影名称',
      indexedAt: DateTime(2026),
    );
    await repository.saveForSource(item.sourcePath, [item]);
    final controller = LocalController(
      scanner: _ImmediateScanner(const []),
      mediaIndexRepository: repository,
      mediaSourceRepository: _MemoryMediaSourceRepository(),
      saveLastDirectory: (_) {},
      saveDefaultDirectory: (_) {},
      saveRecentDirectories: (_) {},
    );
    await controller.refreshLocalLibraryDerivedMetadata();

    expect(
      controller.indexedSeriesNameForPaths([r'd:\video\movie.mkv']),
      '电影名称',
    );
    expect(controller.indexedSeriesNameForPaths([r'D:\Other.mkv']), isNull);
  });
}

LocalFileItem _item({required String path}) {
  return LocalFileItem(
    path: path,
    name: path.split(Platform.pathSeparator).last,
    size: 1024,
    modified: DateTime(2026),
    isDirectory: false,
    isVideo: true,
  );
}

LocalFileItem _dirItem({required String path}) {
  return LocalFileItem(
    path: path,
    name: path.split(Platform.pathSeparator).last,
    size: 0,
    modified: DateTime(2026),
    isDirectory: true,
    isVideo: false,
  );
}

class _DelayedScanner implements ILocalMediaScanner {
  final _pending = <String, Completer<LocalScanResult>>{};
  final _started = <String, Completer<void>>{};

  @override
  Future<LocalScanResult> scan(
    String path, {
    required LocalSortMode sortMode,
    required bool ascending,
  }) {
    final completer = Completer<LocalScanResult>();
    _pending[path] = completer;
    _started.putIfAbsent(path, Completer<void>.new).complete();
    return completer.future;
  }

  Future<void> waitFor(String path) {
    return _started.putIfAbsent(path, Completer<void>.new).future;
  }

  void complete(String path, List<LocalFileItem> items) {
    _pending.remove(path)!.complete(LocalScanResult(
          currentPath: path,
          items: items,
          skippedCount: 0,
        ));
  }
}

class _ImmediateScanner implements ILocalMediaScanner {
  _ImmediateScanner(this.items);

  final List<LocalFileItem> items;

  @override
  Future<LocalScanResult> scan(
    String path, {
    required LocalSortMode sortMode,
    required bool ascending,
  }) async {
    return LocalScanResult(
      currentPath: path,
      items: items,
      skippedCount: 0,
    );
  }
}

class _ImmediateResultScanner implements ILocalMediaScanner {
  _ImmediateResultScanner(this.result);

  final LocalScanResult result;

  @override
  Future<LocalScanResult> scan(
    String path, {
    required LocalSortMode sortMode,
    required bool ascending,
  }) async {
    return result;
  }
}

class _SortingScanner implements ILocalMediaScanner {
  _SortingScanner(this.rootPath);

  final String rootPath;
  final List<_ScanCall> calls = [];

  @override
  Future<LocalScanResult> scan(
    String path, {
    required LocalSortMode sortMode,
    required bool ascending,
  }) async {
    calls.add(_ScanCall(sortMode, ascending));
    final suffix = sortMode == LocalSortMode.size
        ? ascending
            ? 'size-sort.mkv'
            : 'size-sort-desc.mkv'
        : 'name-sort.mkv';
    return LocalScanResult(
      currentPath: path,
      items: [_item(path: '$rootPath${Platform.pathSeparator}$suffix')],
      skippedCount: 0,
    );
  }
}

class _PathScanner implements ILocalMediaScanner {
  _PathScanner(this.itemsByPath);

  final Map<String, List<LocalFileItem>> itemsByPath;
  final List<String> scannedPaths = [];

  @override
  Future<LocalScanResult> scan(
    String path, {
    required LocalSortMode sortMode,
    required bool ascending,
  }) async {
    scannedPaths.add(path);
    return LocalScanResult(
      currentPath: path,
      items: itemsByPath[path] ?? const [],
      skippedCount: 0,
    );
  }
}

class _DelayedPosterScraper implements ILocalPosterScraper {
  final started = Completer<void>();
  final _result = Completer<PosterScrapeResult>();

  @override
  Future<PosterScrapeResult> scrapeMissingPosters(
    List<LocalFileItem> items, {
    PosterScrapeProgressCallback? onProgress,
    FallbackCoverProvider? fallbackCover,
  }) {
    if (!started.isCompleted) {
      started.complete();
    }
    onProgress?.call(PosterScrapeProgress(
      phase: PosterScrapePhase.searching,
      current: 1,
      total: items.length,
      fileName: items.isEmpty ? '' : items.first.name,
      progress: 0.5,
    ));
    return _result.future;
  }

  void complete(PosterScrapeResult result) {
    _result.complete(result);
  }
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
    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsBytes([1, 2, 3]);
    return outputFile.path;
  }
}

class _ScanCall {
  const _ScanCall(this.sortMode, this.ascending);

  final LocalSortMode sortMode;
  final bool ascending;
}

class _MemoryMediaSourceRepository implements ILocalMediaSourceRepository {
  final List<String> upsertedPaths = [];
  final List<_ScanSummaryCall> scanSummaries = [];
  final List<LocalMediaSource> _sources = [];

  @override
  List<LocalMediaSource> getAll() {
    final sources = List<LocalMediaSource>.of(_sources);
    sources.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sources;
  }

  @override
  LocalMediaSource? getByPath(String path) {
    final id = LocalMediaSource.idForPath(path);
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  @override
  Future<LocalMediaSource> upsertPath(String path) async {
    upsertedPaths.add(path);
    final source = LocalMediaSource.fromPath(path);
    final index = _sources.indexWhere((item) => item.id == source.id);
    if (index >= 0) {
      _sources[index] = _sources[index].copyWith(
        updatedAt: source.updatedAt,
        enabled: true,
      );
      return _sources[index];
    }
    _sources.insert(0, source);
    return source;
  }

  @override
  Future<bool> removePath(String path) async {
    final id = LocalMediaSource.idForPath(path);
    final before = _sources.length;
    _sources.removeWhere((source) => source.id == id);
    return _sources.length != before;
  }

  @override
  Future<void> updateScanSummary({
    required String path,
    required int fileCount,
    required int videoCount,
    required int directoryCount,
    required int skippedCount,
  }) async {
    scanSummaries.add(_ScanSummaryCall(
      path: path,
      fileCount: fileCount,
      videoCount: videoCount,
      directoryCount: directoryCount,
      skippedCount: skippedCount,
    ));
    final now = DateTime.now();
    final id = LocalMediaSource.idForPath(path);
    final index = _sources.indexWhere((source) => source.id == id);
    final source = index >= 0
        ? _sources[index].copyWith(
            updatedAt: now,
            lastScannedAt: now,
            fileCount: fileCount,
            videoCount: videoCount,
            directoryCount: directoryCount,
            skippedCount: skippedCount,
          )
        : LocalMediaSource.fromPath(path).copyWith(
            updatedAt: now,
            lastScannedAt: now,
            fileCount: fileCount,
            videoCount: videoCount,
            directoryCount: directoryCount,
            skippedCount: skippedCount,
          );
    if (index >= 0) {
      _sources[index] = source;
    } else {
      _sources.insert(0, source);
    }
  }
}

class _ScanSummaryCall {
  const _ScanSummaryCall({
    required this.path,
    required this.fileCount,
    required this.videoCount,
    required this.directoryCount,
    required this.skippedCount,
  });

  final String path;
  final int fileCount;
  final int videoCount;
  final int directoryCount;
  final int skippedCount;
}

class _FakeMediaIndexer implements ILocalMediaIndexer {
  _FakeMediaIndexer(this.repository);

  final _MemoryMediaIndexRepository repository;

  @override
  Future<LocalMediaIndexResult> indexSource(
    String sourcePath, {
    LocalMediaIndexProgressCallback? onProgress,
    bool enrichMediaInfo = false,
    bool generateThumbnails = false,
    LocalMediaIndexCancelChecker? isCancelled,
  }) async {
    final file = Directory(sourcePath)
        .listSync()
        .whereType<File>()
        .firstWhere((file) => file.path.endsWith('.mkv'));
    final stat = await file.stat();
    onProgress?.call(LocalMediaIndexProgress(
      sourcePath: sourcePath,
      currentPath: file.path,
      current: 1,
      total: 1,
      phase: LocalMediaIndexPhase.indexing,
    ));
    final item = LocalMediaIndexItem.fromFile(
      file: file,
      stat: stat,
      sourcePath: sourcePath,
      indexedAt: DateTime(2026),
    );
    await repository.saveForSource(sourcePath, [item]);
    return LocalMediaIndexResult(
      sourcePath: sourcePath,
      items: [item],
      addedCount: 1,
      updatedCount: 0,
      reusedCount: 0,
      removedCount: 0,
      skippedCount: 0,
    );
  }
}

class _ThrowingMediaIndexer implements ILocalMediaIndexer {
  @override
  Future<LocalMediaIndexResult> indexSource(
    String sourcePath, {
    LocalMediaIndexProgressCallback? onProgress,
    bool enrichMediaInfo = false,
    bool generateThumbnails = false,
    LocalMediaIndexCancelChecker? isCancelled,
  }) async {
    throw StateError('模拟索引失败');
  }
}

class _CancelledMediaIndexer implements ILocalMediaIndexer {
  @override
  Future<LocalMediaIndexResult> indexSource(
    String sourcePath, {
    LocalMediaIndexProgressCallback? onProgress,
    bool enrichMediaInfo = false,
    bool generateThumbnails = false,
    LocalMediaIndexCancelChecker? isCancelled,
  }) async {
    return LocalMediaIndexResult(
      sourcePath: sourcePath,
      items: const <LocalMediaIndexItem>[],
      addedCount: 0,
      updatedCount: 0,
      reusedCount: 0,
      removedCount: 0,
      skippedCount: 0,
      cancelled: true,
    );
  }
}

class _ThrowingCloudSourceStorage implements CloudSourceStorage {
  @override
  Object get synchronizationIdentity => this;

  @override
  Future<List<Map<String, dynamic>>> read() async {
    throw StateError('模拟网盘索引重载失败');
  }

  @override
  Future<void> write(List<Map<String, dynamic>> sources) async {}
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
