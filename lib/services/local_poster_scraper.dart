import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/local/poster_scrape.dart';
import 'package:kanyingyin/services/local_series_grouper.dart';
import 'package:kanyingyin/services/poster_service.dart';
import 'package:kanyingyin/utils/logger.dart';

/// Optional callback to provide a fallback cover URL for an item
/// when TMDB search fails. Returns a remote URL or null.
typedef FallbackCoverProvider = FutureOr<String?> Function(LocalFileItem item);
typedef LocalPosterApplicationRootProvider = Future<Directory> Function();

abstract class ILocalPosterScraper {
  Future<PosterScrapeResult> scrapeMissingPosters(
    List<LocalFileItem> items, {
    PosterScrapeProgressCallback? onProgress,
    FallbackCoverProvider? fallbackCover,
  });
}

class LocalPosterScraper implements ILocalPosterScraper {
  LocalPosterScraper({
    PosterService? posterService,
    LocalPosterApplicationRootProvider? applicationRootProvider,
  })  : _posterService = posterService ?? PosterService(),
        _applicationRootProvider =
            applicationRootProvider ?? getApplicationSupportDirectory;

  final PosterService _posterService;
  final LocalPosterApplicationRootProvider _applicationRootProvider;
  final LocalSeriesGrouper _seriesGrouper = const LocalSeriesGrouper();

  @override
  Future<PosterScrapeResult> scrapeMissingPosters(
    List<LocalFileItem> items, {
    PosterScrapeProgressCallback? onProgress,
    FallbackCoverProvider? fallbackCover,
  }) async {
    final videos = items.where((item) => item.isVideo).toList();
    final groups = _groupBySeries(videos);
    final targetGroups = groups.entries
        .where((entry) => entry.value.any((item) => item.needsOnlinePoster))
        .toList(growable: false);
    final skipped = groups.length - targetGroups.length;

    onProgress?.call(const PosterScrapeProgress(
      phase: PosterScrapePhase.preparing,
      current: 0,
      total: 0,
      fileName: '',
      progress: 0,
    ));

    if (targetGroups.isEmpty) {
      AppLogger().i('LocalPosterScraper: all videos already have posters');
      return PosterScrapeResult(
        success: 0,
        failed: 0,
        skipped: skipped,
        total: groups.length,
      );
    }

    var success = 0;
    var failed = 0;
    var processed = 0;
    final coversByLocationId = <String, String>{};
    final totalGroups = targetGroups.length;

    for (final entry in targetGroups) {
      final groupItems = entry.value;
      final firstItem = groupItems.first;
      final displayName = entry.key;

      processed++;
      onProgress?.call(PosterScrapeProgress(
        phase: PosterScrapePhase.searching,
        current: processed,
        total: totalGroups,
        fileName: displayName,
        progress: processed / totalGroups,
      ));

      AppLogger().i(
        'LocalPosterScraper: searching poster for series "$displayName" '
        '(${groupItems.length} episodes)',
      );

      String? effectivePosterUrl;

      // 优先复用统一 TMDB 刮削和索引结果，避免旧搜索选中不同作品。
      if (fallbackCover != null) {
        for (final item in groupItems) {
          final fallback = await fallbackCover(item);
          if (fallback != null && fallback.isNotEmpty) {
            effectivePosterUrl = fallback;
            AppLogger().i(
              'LocalPosterScraper: using indexed fallback cover for "$displayName"',
            );
            break;
          }
        }
      }

      // 统一结果不可用时，再使用旧海报搜索作为兼容兜底。
      effectivePosterUrl ??= await _searchPoster(firstItem, displayName);

      if (effectivePosterUrl == null) {
        AppLogger().w('LocalPosterScraper: no poster found for "$displayName"');
        failed++;
        continue;
      }

      final downloaded = await _downloadGroupCover(
        effectivePosterUrl,
        groupItems,
        displayName: displayName,
        onProgress: onProgress,
        current: processed,
        total: totalGroups,
      );
      coversByLocationId.addAll(downloaded.coversByLocationId);
      if (downloaded.success) {
        success++;
      } else {
        failed++;
      }
    }

    onProgress?.call(PosterScrapeProgress(
      phase: PosterScrapePhase.downloading,
      current: totalGroups,
      total: totalGroups,
      fileName: '',
      progress: 1,
    ));

    return PosterScrapeResult(
      success: success,
      failed: failed,
      skipped: skipped,
      total: groups.length,
      coversByLocationId: Map<String, String>.unmodifiable(
        coversByLocationId,
      ),
    );
  }

  /// Group items by series name for batch TMDB search.
  Map<String, List<LocalFileItem>> _groupBySeries(List<LocalFileItem> items) {
    final groups = <String, List<LocalFileItem>>{};
    for (final group in _seriesGrouper.group(items)) {
      groups.putIfAbsent(group.searchTitle, () => []).addAll(group.episodes);
    }
    return groups;
  }

  Future<String?> _searchPoster(LocalFileItem item, String displayName) async {
    try {
      return await _posterService.searchPoster(
        rawFilename: item.name,
        episodeInfo: item.episodeInfo,
        seriesName: displayName,
      );
    } catch (e, stackTrace) {
      AppLogger().w(
        'LocalPosterScraper: search failed for "$displayName"',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<_PosterDownloadResult> _downloadGroupCover(
    String posterUrl,
    List<LocalFileItem> items, {
    required String displayName,
    PosterScrapeProgressCallback? onProgress,
    required int current,
    required int total,
  }) async {
    final firstItem = items.first;
    onProgress?.call(PosterScrapeProgress(
      phase: PosterScrapePhase.downloading,
      current: current,
      total: total,
      fileName: displayName,
      progress: total <= 0 ? 0 : current / total,
    ));

    try {
      var hasFailure = false;
      final coversByLocationId = <String, String>{};
      for (final item in _itemsNeedingDirectoryCover(items)) {
        final savedPath = item.location.isDocument
            ? await _posterService.downloadPosterTo(
                posterUrl,
                await documentPosterPath(item.location.stableId),
              )
            : await _posterService.downloadPoster(
                posterUrl,
                item.path,
              );
        if (savedPath == null) {
          hasFailure = true;
        } else if (item.location.isDocument) {
          for (final documentItem in items.where(
            (candidate) => candidate.location.isDocument,
          )) {
            coversByLocationId[documentItem.location.stableId] = savedPath;
          }
        }
      }
      return _PosterDownloadResult(
        success: !hasFailure,
        coversByLocationId: coversByLocationId,
      );
    } catch (e) {
      AppLogger().w(
        'LocalPosterScraper: failed to download for "${firstItem.name}"',
        error: e,
      );
      return const _PosterDownloadResult(success: false);
    }
  }

  List<LocalFileItem> _itemsNeedingDirectoryCover(List<LocalFileItem> items) {
    final byDirectory = <String, List<LocalFileItem>>{};
    for (final item in items) {
      final groupKey = item.location.isDocument
          ? 'document:${item.episodeInfo?.seriesName ?? item.name}'
          : p.dirname(item.path);
      (byDirectory[groupKey] ??= <LocalFileItem>[]).add(item);
    }

    return byDirectory.values
        .where((itemsInDirectory) =>
            itemsInDirectory.any((item) => item.needsOnlinePoster))
        .map((itemsInDirectory) => itemsInDirectory.first)
        .toList(growable: false);
  }

  Future<String> documentPosterPath(String stableId) async {
    final root = await _applicationRootProvider();
    return p.join(
      root.path,
      'local_document_posters',
      '${_stableHash(stableId)}.jpg',
    );
  }

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class _PosterDownloadResult {
  const _PosterDownloadResult({
    required this.success,
    this.coversByLocationId = const <String, String>{},
  });

  final bool success;
  final Map<String, String> coversByLocationId;
}
