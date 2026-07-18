import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/local_library_metadata_coordinator.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/local/poster_scrape.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/local_media_index_metadata_refresher.dart';
import 'package:kanyingyin/services/local_media_probe.dart';
import 'package:kanyingyin/services/local_poster_scraper.dart';

void main() {
  test('媒体探测提交非空结果并跳过空结果', () async {
    final first = _video('A.mkv');
    final second = _video('B.mkv');
    final applied = <LocalMediaProbeUpdate>[];
    final progress = <LocalLibraryBatchProgress>[];
    final coordinator = LocalLibraryMetadataCoordinator(
      mediaProbe: _Probe(
        infoByPath: <String, LocalMediaInfo>{
          first.path: const LocalMediaInfo(
            duration: Duration(minutes: 1),
            width: 1920,
            height: 1080,
          ),
        },
      ),
    );

    final result = await coordinator.probeMediaInfo(
      <LocalFileItem>[first, second],
      onProgress: progress.add,
      onResult: applied.add,
    );

    expect(result, const LocalLibraryBatchResult(processed: 2, updated: 1));
    expect(applied.single.item.path, first.path);
    expect(applied.single.info.width, 1920);
    expect(progress.map((value) => value.current), <int>[1, 2]);
  });

  test('媒体探测取消后不再提交旧结果', () async {
    final first = _video('A.mkv');
    final second = _video('B.mkv');
    var cancelled = false;
    final applied = <LocalMediaProbeUpdate>[];
    final coordinator = LocalLibraryMetadataCoordinator(
      mediaProbe: _Probe(
        infoByPath: <String, LocalMediaInfo>{
          first.path: const LocalMediaInfo(width: 1280, height: 720),
          second.path: const LocalMediaInfo(width: 1920, height: 1080),
        },
        afterProbe: (path) {
          if (path == first.path) cancelled = true;
        },
      ),
    );

    final result = await coordinator.probeMediaInfo(
      <LocalFileItem>[first, second],
      isCancelled: () => cancelled,
      onResult: applied.add,
    );

    expect(result.cancelled, isTrue);
    expect(result.updated, 0);
    expect(applied, isEmpty);
  });

  test('缩略图优先复用缓存并仅为未缓存项生成', () async {
    final first = _video('A.mkv');
    final second = _video('B.mkv');
    final probe = _Probe(
      thumbnailByPath: <String, String?>{second.path: 'generated.jpg'},
    );
    final applied = <LocalThumbnailUpdate>[];
    final coordinator = LocalLibraryMetadataCoordinator(
      mediaProbe: probe,
      existingThumbnailPath: (path) => path == first.path ? 'cached.jpg' : null,
      thumbnailPathForVideo: (path) => '$path.jpg',
    );

    final result = await coordinator.generateThumbnails(
      <LocalFileItem>[first, second],
      onResult: applied.add,
    );

    expect(result.updated, 2);
    expect(probe.thumbnailCalls, <String>[second.path]);
    expect(
      applied.map((value) => value.thumbnailPath),
      <String>['cached.jpg', 'generated.jpg'],
    );
  });

  test('缩略图生成 await 后取消不提交结果', () async {
    final probe = _DelayedThumbnailProbe();
    final applied = <LocalThumbnailUpdate>[];
    var cancelled = false;
    final coordinator = LocalLibraryMetadataCoordinator(
      mediaProbe: probe,
      existingThumbnailPath: (_) => null,
      thumbnailPathForVideo: (path) => '$path.jpg',
    );

    final pending = coordinator.generateThumbnails(
      <LocalFileItem>[_video('A.mkv')],
      isCancelled: () => cancelled,
      onResult: applied.add,
    );
    await probe.started.future;
    cancelled = true;
    probe.complete('generated.jpg');
    final result = await pending;

    expect(result.cancelled, isTrue);
    expect(result.updated, 0);
    expect(applied, isEmpty);
  });

  test('缩略图空结果不提交更新', () async {
    final applied = <LocalThumbnailUpdate>[];
    final coordinator = LocalLibraryMetadataCoordinator(
      mediaProbe: _Probe(),
      existingThumbnailPath: (_) => null,
      thumbnailPathForVideo: (path) => '$path.jpg',
    );

    final result = await coordinator.generateThumbnails(
      <LocalFileItem>[_video('A.mkv')],
      onResult: applied.add,
    );

    expect(result.updated, 0);
    expect(applied, isEmpty);
  });

  test('派生索引刷新复用注入仓储', () async {
    final repository = _Repository();
    final refresher = _Refresher();
    final coordinator = LocalLibraryMetadataCoordinator(
      mediaIndexRepository: repository,
      metadataRefresher: refresher,
    );

    final result = await coordinator.refreshDerivedMetadata();

    expect(result.result.refreshedCount, 3);
    expect(result.cancelled, isFalse);
    expect(refresher.repository, same(repository));
  });

  test('派生索引刷新 await 后取消返回取消状态', () async {
    final refresher = _DelayedRefresher();
    var cancelled = false;
    final coordinator = LocalLibraryMetadataCoordinator(
      mediaIndexRepository: _Repository(),
      metadataRefresher: refresher,
    );

    final pending = coordinator.refreshDerivedMetadata(
      isCancelled: () => cancelled,
    );
    await refresher.started.future;
    cancelled = true;
    refresher.complete(const LocalMediaIndexMetadataRefreshResult(
      checkedCount: 1,
      refreshedCount: 1,
      skippedCount: 0,
    ));
    final result = await pending;

    expect(result.cancelled, isTrue);
    expect(result.result.refreshedCount, 0);
  });

  test('海报批处理原样转发进度和结果', () async {
    final progress = <PosterScrapeProgress>[];
    final scraper = _PosterScraper();
    final coordinator = LocalLibraryMetadataCoordinator(
      posterScraper: scraper,
    );

    final result = await coordinator.fetchPosters(
      <LocalFileItem>[_video('A.mkv')],
      onProgress: progress.add,
    );

    expect(result.result.success, 1);
    expect(result.cancelled, isFalse);
    expect(progress.single.phase, PosterScrapePhase.searching);
    expect(progress.single.fileName, 'A.mkv');
  });

  test('海报取消后抑制进度和结果', () async {
    final scraper = _DelayedPosterScraper();
    final progress = <PosterScrapeProgress>[];
    var cancelled = false;
    final coordinator = LocalLibraryMetadataCoordinator(
      posterScraper: scraper,
    );

    final pending = coordinator.fetchPosters(
      <LocalFileItem>[_video('A.mkv')],
      isCancelled: () => cancelled,
      onProgress: progress.add,
    );
    await scraper.started.future;
    cancelled = true;
    scraper.emitProgress();
    scraper.complete(const PosterScrapeResult(
      success: 1,
      failed: 0,
      skipped: 0,
      total: 1,
    ));
    final result = await pending;

    expect(progress, isEmpty);
    expect(result.cancelled, isTrue);
    expect(result.result, same(PosterScrapeResult.empty));
  });

  test('媒体探测异常保持向上传递', () async {
    final coordinator = LocalLibraryMetadataCoordinator(
      mediaProbe: _ThrowingProbe(throwOnProbe: true),
    );

    await expectLater(
      coordinator.probeMediaInfo(<LocalFileItem>[_video('A.mkv')]),
      throwsStateError,
    );
  });

  test('缩略图异常保持向上传递', () async {
    final coordinator = LocalLibraryMetadataCoordinator(
      mediaProbe: _ThrowingProbe(throwOnThumbnail: true),
      existingThumbnailPath: (_) => null,
    );

    await expectLater(
      coordinator.generateThumbnails(<LocalFileItem>[_video('A.mkv')]),
      throwsStateError,
    );
  });

  test('海报异常保持向上传递', () async {
    final coordinator = LocalLibraryMetadataCoordinator(
      posterScraper: _ThrowingPosterScraper(),
    );

    await expectLater(
      coordinator.fetchPosters(<LocalFileItem>[_video('A.mkv')]),
      throwsStateError,
    );
  });
}

LocalFileItem _video(String name) {
  return LocalFileItem(
    path: 'D:\\Media\\$name',
    name: name,
    size: 1,
    modified: DateTime(2026),
    isDirectory: false,
    isVideo: true,
  );
}

class _Probe implements ILocalMediaProbe {
  _Probe({
    this.infoByPath = const <String, LocalMediaInfo>{},
    this.thumbnailByPath = const <String, String?>{},
    this.afterProbe,
  });

  final Map<String, LocalMediaInfo> infoByPath;
  final Map<String, String?> thumbnailByPath;
  final void Function(String path)? afterProbe;
  final List<String> thumbnailCalls = <String>[];

  @override
  Future<String?> captureThumbnail(String filePath, String outputPath) async {
    thumbnailCalls.add(filePath);
    return thumbnailByPath[filePath];
  }

  @override
  Future<LocalMediaInfo> probe(String filePath) async {
    final result = infoByPath[filePath] ?? const LocalMediaInfo();
    afterProbe?.call(filePath);
    return result;
  }
}

class _Refresher extends LocalMediaIndexMetadataRefresher {
  ILocalMediaIndexRepository? repository;

  @override
  Future<LocalMediaIndexMetadataRefreshResult> refreshRepository(
    ILocalMediaIndexRepository repository,
  ) async {
    this.repository = repository;
    return const LocalMediaIndexMetadataRefreshResult(
      checkedCount: 4,
      refreshedCount: 3,
      skippedCount: 1,
    );
  }
}

class _DelayedRefresher extends LocalMediaIndexMetadataRefresher {
  final started = Completer<void>();
  final _result = Completer<LocalMediaIndexMetadataRefreshResult>();

  @override
  Future<LocalMediaIndexMetadataRefreshResult> refreshRepository(
    ILocalMediaIndexRepository repository,
  ) {
    started.complete();
    return _result.future;
  }

  void complete(LocalMediaIndexMetadataRefreshResult result) {
    _result.complete(result);
  }
}

class _Repository implements ILocalMediaIndexRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PosterScraper implements ILocalPosterScraper {
  @override
  Future<PosterScrapeResult> scrapeMissingPosters(
    List<LocalFileItem> items, {
    PosterScrapeProgressCallback? onProgress,
    FallbackCoverProvider? fallbackCover,
  }) async {
    onProgress?.call(PosterScrapeProgress(
      phase: PosterScrapePhase.searching,
      current: 1,
      total: 1,
      fileName: items.single.name,
      progress: 1,
    ));
    return const PosterScrapeResult(
      success: 1,
      failed: 0,
      skipped: 0,
      total: 1,
    );
  }
}

class _DelayedThumbnailProbe implements ILocalMediaProbe {
  final started = Completer<void>();
  final _result = Completer<String?>();

  @override
  Future<String?> captureThumbnail(String filePath, String outputPath) {
    started.complete();
    return _result.future;
  }

  @override
  Future<LocalMediaInfo> probe(String filePath) async {
    return const LocalMediaInfo();
  }

  void complete(String? path) => _result.complete(path);
}

class _DelayedPosterScraper implements ILocalPosterScraper {
  final started = Completer<void>();
  final _result = Completer<PosterScrapeResult>();
  PosterScrapeProgressCallback? _onProgress;

  @override
  Future<PosterScrapeResult> scrapeMissingPosters(
    List<LocalFileItem> items, {
    PosterScrapeProgressCallback? onProgress,
    FallbackCoverProvider? fallbackCover,
  }) {
    _onProgress = onProgress;
    started.complete();
    return _result.future;
  }

  void emitProgress() {
    _onProgress?.call(const PosterScrapeProgress(
      phase: PosterScrapePhase.searching,
      current: 1,
      total: 1,
      fileName: 'A.mkv',
      progress: 1,
    ));
  }

  void complete(PosterScrapeResult result) => _result.complete(result);
}

class _ThrowingProbe implements ILocalMediaProbe {
  const _ThrowingProbe({
    this.throwOnProbe = false,
    this.throwOnThumbnail = false,
  });

  final bool throwOnProbe;
  final bool throwOnThumbnail;

  @override
  Future<String?> captureThumbnail(String filePath, String outputPath) async {
    if (throwOnThumbnail) throw StateError('缩略图失败');
    return null;
  }

  @override
  Future<LocalMediaInfo> probe(String filePath) async {
    if (throwOnProbe) throw StateError('探测失败');
    return const LocalMediaInfo();
  }
}

class _ThrowingPosterScraper implements ILocalPosterScraper {
  @override
  Future<PosterScrapeResult> scrapeMissingPosters(
    List<LocalFileItem> items, {
    PosterScrapeProgressCallback? onProgress,
    FallbackCoverProvider? fallbackCover,
  }) {
    throw StateError('海报失败');
  }
}
