import 'dart:async';

import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/local/poster_scrape.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/local_media_index_metadata_refresher.dart';
import 'package:kanyingyin/services/local_media_probe.dart';
import 'package:kanyingyin/services/local_poster_scraper.dart';
import 'package:kanyingyin/services/local_thumbnail_cache.dart';

typedef LocalLibraryCancellationCheck = bool Function();
typedef LocalLibraryProgressCallback = void Function(
  LocalLibraryBatchProgress progress,
);
typedef LocalMediaProbeResultCallback = void Function(
  LocalMediaProbeUpdate update,
);
typedef LocalThumbnailResultCallback = void Function(
  LocalThumbnailUpdate update,
);
typedef ExistingThumbnailPath = String? Function(String videoPath);
typedef ThumbnailPathForVideo = String Function(String videoPath);

final class LocalLibraryBatchProgress {
  const LocalLibraryBatchProgress({
    required this.current,
    required this.total,
    required this.fileName,
  });

  final int current;
  final int total;
  final String fileName;
}

final class LocalLibraryBatchResult {
  const LocalLibraryBatchResult({
    required this.processed,
    required this.updated,
    this.cancelled = false,
  });

  final int processed;
  final int updated;
  final bool cancelled;

  @override
  bool operator ==(Object other) {
    return other is LocalLibraryBatchResult &&
        other.processed == processed &&
        other.updated == updated &&
        other.cancelled == cancelled;
  }

  @override
  int get hashCode => Object.hash(processed, updated, cancelled);
}

final class LocalMediaProbeUpdate {
  const LocalMediaProbeUpdate({required this.item, required this.info});

  final LocalFileItem item;
  final LocalMediaInfo info;
}

final class LocalThumbnailUpdate {
  const LocalThumbnailUpdate({
    required this.item,
    required this.thumbnailPath,
  });

  final LocalFileItem item;
  final String thumbnailPath;
}

final class LocalPosterBatchResult {
  const LocalPosterBatchResult({
    required this.result,
    this.cancelled = false,
  });

  final PosterScrapeResult result;
  final bool cancelled;

  static const cancelledResult = LocalPosterBatchResult(
    result: PosterScrapeResult.empty,
    cancelled: true,
  );
}

final class LocalDerivedMetadataBatchResult {
  const LocalDerivedMetadataBatchResult({
    required this.result,
    this.cancelled = false,
  });

  final LocalMediaIndexMetadataRefreshResult result;
  final bool cancelled;

  static const cancelledResult = LocalDerivedMetadataBatchResult(
    result: LocalMediaIndexMetadataRefreshResult(
      checkedCount: 0,
      refreshedCount: 0,
      skippedCount: 0,
    ),
    cancelled: true,
  );
}

final class LocalLibraryMetadataCoordinator {
  LocalLibraryMetadataCoordinator({
    ILocalMediaProbe? mediaProbe,
    ILocalPosterScraper? posterScraper,
    ILocalMediaIndexRepository? mediaIndexRepository,
    LocalMediaIndexMetadataRefresher? metadataRefresher,
    ExistingThumbnailPath? existingThumbnailPath,
    ThumbnailPathForVideo? thumbnailPathForVideo,
  })  : _mediaProbe = mediaProbe ?? MediaKitLocalMediaProbe(),
        _posterScraper = posterScraper ?? LocalPosterScraper(),
        _mediaIndexRepository = mediaIndexRepository,
        _metadataRefresher =
            metadataRefresher ?? LocalMediaIndexMetadataRefresher(),
        _existingThumbnailPath =
            existingThumbnailPath ?? LocalThumbnailCache.existingPathForVideo,
        _thumbnailPathForVideo =
            thumbnailPathForVideo ?? LocalThumbnailCache.pathForVideo;

  final ILocalMediaProbe _mediaProbe;
  final ILocalPosterScraper _posterScraper;
  final ILocalMediaIndexRepository? _mediaIndexRepository;
  final LocalMediaIndexMetadataRefresher _metadataRefresher;
  final ExistingThumbnailPath _existingThumbnailPath;
  final ThumbnailPathForVideo _thumbnailPathForVideo;

  Future<LocalLibraryBatchResult> probeMediaInfo(
    List<LocalFileItem> items, {
    LocalLibraryProgressCallback? onProgress,
    LocalMediaProbeResultCallback? onResult,
    LocalLibraryCancellationCheck? isCancelled,
  }) async {
    var processed = 0;
    var updated = 0;
    for (var index = 0; index < items.length; index++) {
      if (isCancelled?.call() ?? false) {
        return LocalLibraryBatchResult(
          processed: processed,
          updated: updated,
          cancelled: true,
        );
      }
      final item = items[index];
      onProgress?.call(LocalLibraryBatchProgress(
        current: index + 1,
        total: items.length,
        fileName: item.name,
      ));
      final info = await _mediaProbe.probe(item.path);
      processed++;
      if (isCancelled?.call() ?? false) {
        return LocalLibraryBatchResult(
          processed: processed,
          updated: updated,
          cancelled: true,
        );
      }
      if (info.isEmpty) continue;
      onResult?.call(LocalMediaProbeUpdate(item: item, info: info));
      updated++;
    }
    return LocalLibraryBatchResult(processed: processed, updated: updated);
  }

  Future<LocalLibraryBatchResult> generateThumbnails(
    List<LocalFileItem> items, {
    LocalLibraryProgressCallback? onProgress,
    LocalThumbnailResultCallback? onResult,
    LocalLibraryCancellationCheck? isCancelled,
  }) async {
    var processed = 0;
    var updated = 0;
    for (var index = 0; index < items.length; index++) {
      if (isCancelled?.call() ?? false) {
        return LocalLibraryBatchResult(
          processed: processed,
          updated: updated,
          cancelled: true,
        );
      }
      final item = items[index];
      onProgress?.call(LocalLibraryBatchProgress(
        current: index + 1,
        total: items.length,
        fileName: item.name,
      ));
      final cachedPath = _existingThumbnailPath(item.path);
      final thumbnailPath = cachedPath ??
          await _mediaProbe.captureThumbnail(
            item.path,
            _thumbnailPathForVideo(item.path),
          );
      processed++;
      if (isCancelled?.call() ?? false) {
        return LocalLibraryBatchResult(
          processed: processed,
          updated: updated,
          cancelled: true,
        );
      }
      if (thumbnailPath == null || thumbnailPath.isEmpty) continue;
      onResult?.call(LocalThumbnailUpdate(
        item: item,
        thumbnailPath: thumbnailPath,
      ));
      updated++;
    }
    return LocalLibraryBatchResult(processed: processed, updated: updated);
  }

  Future<LocalPosterBatchResult> fetchPosters(
    List<LocalFileItem> items, {
    PosterScrapeProgressCallback? onProgress,
    FallbackCoverProvider? fallbackCover,
    LocalLibraryCancellationCheck? isCancelled,
  }) async {
    if (isCancelled?.call() ?? false) {
      return LocalPosterBatchResult.cancelledResult;
    }
    final result = await _posterScraper.scrapeMissingPosters(
      items,
      onProgress: onProgress == null
          ? null
          : (progress) {
              if (!(isCancelled?.call() ?? false)) {
                onProgress(progress);
              }
            },
      fallbackCover: fallbackCover == null
          ? null
          : (item) async {
              if (isCancelled?.call() ?? false) return null;
              final result = await fallbackCover(item);
              if (isCancelled?.call() ?? false) return null;
              return result;
            },
    );
    if (isCancelled?.call() ?? false) {
      return LocalPosterBatchResult.cancelledResult;
    }
    return LocalPosterBatchResult(result: result);
  }

  Future<LocalDerivedMetadataBatchResult> refreshDerivedMetadata({
    LocalLibraryCancellationCheck? isCancelled,
  }) async {
    if (isCancelled?.call() ?? false) {
      return LocalDerivedMetadataBatchResult.cancelledResult;
    }
    final repository = _mediaIndexRepository;
    if (repository == null) {
      throw StateError('未配置本地媒体索引仓储');
    }
    final result = await _metadataRefresher.refreshRepository(
      repository,
      isCancelled: isCancelled,
    );
    if (isCancelled?.call() ?? false) {
      return LocalDerivedMetadataBatchResult.cancelledResult;
    }
    return LocalDerivedMetadataBatchResult(result: result);
  }
}
