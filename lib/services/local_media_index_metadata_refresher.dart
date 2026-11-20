import 'dart:io';

import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:kanyingyin/services/local_subtitle_matcher.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:path/path.dart' as p;

class LocalMediaIndexMetadataRefreshResult {
  final int checkedCount;
  final int refreshedCount;
  final int skippedCount;

  const LocalMediaIndexMetadataRefreshResult({
    required this.checkedCount,
    required this.refreshedCount,
    required this.skippedCount,
  });
}

typedef LocalMediaIndexMetadataRefreshCancelChecker = bool Function();

class LocalMediaIndexMetadataRefresher {
  LocalMediaIndexMetadataRefresher({
    LocalEpisodeParser? episodeParser,
    LocalSubtitleMatcher? subtitleMatcher,
  })  : _episodeParser = episodeParser ?? LocalEpisodeParser(),
        _subtitleMatcher = subtitleMatcher ?? LocalSubtitleMatcher();

  final LocalEpisodeParser _episodeParser;
  final LocalSubtitleMatcher _subtitleMatcher;

  bool needsRefresh(LocalMediaIndexItem item) {
    return !item.hasCurrentDerivedMetadata;
  }

  Future<LocalMediaIndexItem> refreshItem(
    LocalMediaIndexItem item, {
    DateTime? indexedAt,
  }) async {
    if (!needsRefresh(item)) return item;

    final parsedInfo =
        item.manualOverride ? null : _episodeParser.parse(item.path);
    final subtitlePath = await _subtitleMatcher.findForVideo(item.path);
    return LocalMediaIndexItem(
      path: item.path,
      name: item.name,
      parentPath: item.parentPath,
      sourcePath: item.sourcePath,
      size: item.size,
      modified: item.modified,
      cover: item.cover,
      subtitlePath: subtitlePath,
      durationMillis: item.durationMillis,
      videoWidth: item.videoWidth,
      videoHeight: item.videoHeight,
      seriesName: item.manualOverride
          ? _manualSeriesNameFor(item)
          : _autoSeriesNameFor(item, parsedInfo?.seriesName),
      seasonNumber:
          item.manualOverride ? item.seasonNumber : parsedInfo?.seasonNumber,
      episodeNumber:
          item.manualOverride ? item.episodeNumber : parsedInfo?.episodeNumber,
      episodeTitle:
          item.manualOverride ? item.episodeTitle : parsedInfo?.episodeTitle,
      releaseGroup:
          item.manualOverride ? item.releaseGroup : parsedInfo?.releaseGroup,
      resolution:
          item.manualOverride ? item.resolution : parsedInfo?.resolution,
      source: item.manualOverride ? item.source : parsedInfo?.source,
      codec: item.manualOverride ? item.codec : parsedInfo?.codec,
      tmdb: item.tmdb,
      titleLocked: item.titleLocked,
      posterLocked: item.posterLocked,
      overviewLocked: item.overviewLocked,
      scrapeStatus: item.scrapeStatus,
      tmdbMatchOrigin: item.tmdbMatchOrigin,
      tmdbRuleVersion: item.tmdbRuleVersion,
      manualOverride: item.manualOverride,
      pathFingerprint: item.pathFingerprint,
      derivedMetadataVersion: LocalMediaIndexItem.currentDerivedMetadataVersion,
      indexedAt: indexedAt ?? item.indexedAt,
    );
  }

  Future<LocalMediaIndexMetadataRefreshResult> refreshRepository(
    ILocalMediaIndexRepository repository, {
    LocalMediaIndexMetadataRefreshCancelChecker? isCancelled,
  }) async {
    final items = repository.getAll();
    final staleSources = {
      for (final item in items)
        if (needsRefresh(item)) item.sourceLocation,
    };
    // 首次异步读盘前固定来源版本，期间被移除的来源不会被旧任务写回。
    final snapshots = [
      for (final source in staleSources) repository.captureSource(source),
    ];
    var refreshedCount = 0;
    var skippedCount = 0;
    final updates = <LocalMediaSourceSnapshot, List<LocalMediaIndexItem>>{};
    for (final snapshot in snapshots) {
      for (var i = 0; i < snapshot.items.length; i++) {
        final item = snapshot.items[i];
        if (!needsRefresh(item)) continue;
        try {
          if (!await File(item.path).exists()) {
            skippedCount++;
            continue;
          }
          final refreshed = await refreshItem(item, indexedAt: DateTime.now());
          final next = updates.putIfAbsent(snapshot, snapshot.items.toList);
          next[i] = refreshed;
          refreshedCount++;
        } catch (e, stackTrace) {
          skippedCount++;
          AppLogger().w(
            'LocalMediaIndexMetadataRefresher: failed to refresh ${item.path}',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }
    }
    for (final entry in updates.entries) {
      if (isCancelled?.call() ?? false) break;
      await repository.commitSource(entry.key, entry.value);
    }

    return LocalMediaIndexMetadataRefreshResult(
      checkedCount: items.length,
      refreshedCount: refreshedCount,
      skippedCount: skippedCount,
    );
  }

  String _manualSeriesNameFor(LocalMediaIndexItem item) {
    final current = item.seriesName.trim();
    if (current.isNotEmpty) return current;
    return p.basename(item.parentPath);
  }

  String _autoSeriesNameFor(
      LocalMediaIndexItem item, String? parsedSeriesName) {
    final parsed = parsedSeriesName?.trim();
    if (parsed != null && parsed.isNotEmpty) return parsed;
    return p.basename(item.parentPath);
  }
}
