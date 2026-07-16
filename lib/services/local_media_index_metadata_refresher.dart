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

  LocalMediaIndexItem refreshItem(
    LocalMediaIndexItem item, {
    DateTime? indexedAt,
  }) {
    if (!needsRefresh(item)) return item;

    final parsedInfo =
        item.manualOverride ? null : _episodeParser.parse(item.path);
    final subtitlePath = _subtitleMatcher.findForVideo(item.path);
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
      bangumiId: item.bangumiId,
      bangumiName: item.bangumiName,
      bangumiNameCn: item.bangumiNameCn,
      bangumiRatingScore: item.bangumiRatingScore,
      bangumiAirDate: item.bangumiAirDate,
      bangumiSummary: item.bangumiSummary,
      bangumiCoverUrl: item.bangumiCoverUrl,
      manualOverride: item.manualOverride,
      pathFingerprint: item.pathFingerprint,
      derivedMetadataVersion: LocalMediaIndexItem.currentDerivedMetadataVersion,
      indexedAt: indexedAt ?? item.indexedAt,
    );
  }

  Future<LocalMediaIndexMetadataRefreshResult> refreshRepository(
    ILocalMediaIndexRepository repository,
  ) async {
    final items = repository.getAll();
    var refreshedCount = 0;
    var skippedCount = 0;
    final bySourcePath = <String, List<LocalMediaIndexItem>>{};

    for (final item in items) {
      if (!needsRefresh(item)) {
        bySourcePath.putIfAbsent(item.sourcePath, () => []).add(item);
        continue;
      }

      try {
        if (!File(item.path).existsSync()) {
          skippedCount++;
          bySourcePath.putIfAbsent(item.sourcePath, () => []).add(item);
          continue;
        }
        final refreshed = refreshItem(item, indexedAt: DateTime.now());
        bySourcePath.putIfAbsent(refreshed.sourcePath, () => []).add(refreshed);
        refreshedCount++;
      } catch (e, stackTrace) {
        skippedCount++;
        bySourcePath.putIfAbsent(item.sourcePath, () => []).add(item);
        AppLogger().w(
          'LocalMediaIndexMetadataRefresher: failed to refresh ${item.path}',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    if (refreshedCount > 0) {
      for (final entry in bySourcePath.entries) {
        await repository.saveForSource(entry.key, entry.value);
      }
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
