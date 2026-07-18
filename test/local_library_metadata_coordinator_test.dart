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

  test('派生索引刷新复用注入仓储', () async {
    final repository = _Repository();
    final refresher = _Refresher();
    final coordinator = LocalLibraryMetadataCoordinator(
      mediaIndexRepository: repository,
      metadataRefresher: refresher,
    );

    final result = await coordinator.refreshDerivedMetadata();

    expect(result.refreshedCount, 3);
    expect(refresher.repository, same(repository));
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

    expect(result.success, 1);
    expect(progress.single.phase, PosterScrapePhase.searching);
    expect(progress.single.fileName, 'A.mkv');
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
