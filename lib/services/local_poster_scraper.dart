import 'dart:async';
import 'package:path/path.dart' as p;

import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/local/poster_scrape.dart';
import 'package:kanyingyin/services/local_series_grouper.dart';
import 'package:kanyingyin/services/poster_service.dart';
import 'package:kanyingyin/utils/logger.dart';

/// Optional callback to provide a fallback cover URL for an item
/// when TMDB search fails. Returns a remote URL or null.
typedef FallbackCoverProvider = FutureOr<String?> Function(LocalFileItem item);

abstract class ILocalPosterScraper {
  Future<PosterScrapeResult> scrapeMissingPosters(
    List<LocalFileItem> items, {
    PosterScrapeProgressCallback? onProgress,
    FallbackCoverProvider? fallbackCover,
  });
}

class LocalPosterScraper implements ILocalPosterScraper {
  LocalPosterScraper({PosterService? posterService})
      : _posterService = posterService ?? PosterService();

  final PosterService _posterService;
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

      // Search once per series.
      final posterUrl = await _searchPoster(firstItem, displayName);

      String? effectivePosterUrl = posterUrl;

      // If TMDB failed, try Bangumi cover fallback.
      if (effectivePosterUrl == null && fallbackCover != null) {
        for (final item in groupItems) {
          final fallback = await fallbackCover(item);
          if (fallback != null && fallback.isNotEmpty) {
            effectivePosterUrl = fallback;
            AppLogger().i(
              'LocalPosterScraper: using Bangumi fallback cover for "$displayName"',
            );
            break;
          }
        }
      }

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
      if (downloaded) {
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

  Future<bool> _downloadGroupCover(
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
      for (final item in _itemsNeedingDirectoryCover(items)) {
        final savedPath = await _posterService.downloadPoster(
          posterUrl,
          item.path,
        );
        if (savedPath == null) {
          hasFailure = true;
        }
      }
      return !hasFailure;
    } catch (e) {
      AppLogger().w(
        'LocalPosterScraper: failed to download for "${firstItem.name}"',
        error: e,
      );
      return false;
    }
  }

  List<LocalFileItem> _itemsNeedingDirectoryCover(List<LocalFileItem> items) {
    final byDirectory = <String, List<LocalFileItem>>{};
    for (final item in items) {
      (byDirectory[p.dirname(item.path)] ??= <LocalFileItem>[]).add(item);
    }

    return byDirectory.values
        .where((itemsInDirectory) =>
            itemsInDirectory.any((item) => item.needsOnlinePoster))
        .map((itemsInDirectory) => itemsInDirectory.first)
        .toList(growable: false);
  }
}
