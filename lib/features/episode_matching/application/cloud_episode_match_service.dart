import 'package:kanyingyin/features/episode_matching/domain/manual_episode_match.dart';
import 'package:kanyingyin/features/episode_matching/domain/manual_episode_pre_matcher.dart';
import 'package:kanyingyin/modules/cloud/cloud_episode_match_rule.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_episode_match_rule_repository.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_episode_title_resolver.dart';
import 'package:path/path.dart' as p;

final class CloudEpisodeMatchSaveOutcome {
  const CloudEpisodeMatchSaveOutcome({
    required this.rulesSaved,
    required this.indexSynced,
  });

  final bool rulesSaved;
  final bool indexSynced;
}

final class CloudEpisodeMatchService {
  CloudEpisodeMatchService({
    required CloudEpisodeMatchRuleRepository ruleRepository,
    required CloudMediaIndexRepository indexRepository,
    ManualEpisodePreMatcher preMatcher = const ManualEpisodePreMatcher(),
    DateTime Function()? now,
  })  : _ruleRepository = ruleRepository,
        _indexRepository = indexRepository,
        _preMatcher = preMatcher,
        _now = now ?? DateTime.now;

  final CloudEpisodeMatchRuleRepository _ruleRepository;
  final CloudMediaIndexRepository _indexRepository;
  final ManualEpisodePreMatcher _preMatcher;
  final DateTime Function() _now;

  Future<List<ManualEpisodeMatchItem>> loadMatchItems({
    required String sourceId,
    required Iterable<String> resourceIds,
    required String expectedSeriesName,
    int? selectedSeasonNumber,
  }) async {
    final requestedIds = resourceIds.toList(growable: false);
    final indexed = await _indexRepository.getBySource(sourceId);
    final indexedByRemoteId = <String, CloudMediaIndexItem>{
      for (final item in indexed) item.remoteId: item,
    };
    final rulesByKey = <String, CloudEpisodeMatchRule>{
      for (final rule in await _ruleRepository.getBySource(sourceId))
        rule.stableKey: rule,
    };
    final result = <ManualEpisodeMatchItem>[];
    for (final resourceId in requestedIds) {
      final item = indexedByRemoteId[resourceId];
      if (item == null) throw StateError('网盘索引中不存在资源：$resourceId');
      final parentPath = p.posix.dirname(item.remotePath);
      final automatic = _preMatcher.match(
        originalName: item.remoteName,
        parentName: p.posix.basename(parentPath),
        grandParentName: p.posix.basename(p.posix.dirname(parentPath)),
        expectedSeriesName: expectedSeriesName,
        selectedSeasonNumber: selectedSeasonNumber,
      );
      result.add(
        ManualEpisodeMatchItem(
          resourceId: item.remoteId,
          originalName: item.remoteName,
          parentName: p.posix.basename(parentPath),
          existingSeasonNumber: item.seasonNumber,
          existingEpisodeNumber: item.episodeNumber,
          automaticSeasonNumber: automatic?.seasonNumber,
          automaticEpisodeNumber: automatic?.episodeNumber,
          manualOverride: rulesByKey.containsKey(_ruleKey(item)),
        ),
      );
    }
    return List<ManualEpisodeMatchItem>.unmodifiable(result);
  }

  Future<CloudEpisodeMatchSaveOutcome> save({
    required String sourceId,
    required Iterable<String> resourceIds,
    required List<ManualEpisodeAssignment> assignments,
    required TmdbMetadata metadata,
    required int selectedSeasonNumber,
  }) async {
    if (metadata.mediaType != TmdbMediaType.tv) {
      throw StateError('剧集匹配只支持 TMDB 电视剧');
    }
    final season = metadata.seasons
        .where((item) => item.seasonNumber == selectedSeasonNumber)
        .firstOrNull;
    if (season == null || season.episodes.isEmpty) {
      throw StateError('当前季度没有可匹配的 TMDB 剧集');
    }

    final indexed = await _indexRepository.getBySource(sourceId);
    final indexedByRemoteId = <String, CloudMediaIndexItem>{
      for (final item in indexed) item.remoteId: item,
    };
    final requestedItems = <CloudMediaIndexItem>[];
    for (final remoteId in resourceIds) {
      final item = indexedByRemoteId[remoteId];
      if (item == null) throw StateError('网盘索引中不存在资源：$remoteId');
      requestedItems.add(item);
    }
    final errors = validateManualEpisodeAssignments(
      items: requestedItems
          .map(
            (item) => ManualEpisodeMatchItem(
              resourceId: item.remoteId,
              originalName: item.remoteName,
              parentName: p.posix.basename(p.posix.dirname(item.remotePath)),
              existingSeasonNumber: item.seasonNumber,
              existingEpisodeNumber: item.episodeNumber,
            ),
          )
          .toList(growable: false),
      assignments: assignments,
      selectedSeasonNumber: selectedSeasonNumber,
      validEpisodeNumbers:
          season.episodes.map((item) => item.episodeNumber).toSet(),
    );
    if (errors.isNotEmpty) throw StateError(errors.join('\n'));

    final assignmentsById = <String, ManualEpisodeAssignment>{
      for (final assignment in assignments) assignment.resourceId: assignment,
    };
    final targetKeys = <String>{};
    final replacements = <CloudEpisodeMatchRule>[];
    for (final assignment in assignments) {
      final item = indexedByRemoteId[assignment.resourceId]!;
      targetKeys.add(_ruleKey(item));
      final replacement = _buildRule(
        item: item,
        assignment: assignment,
        metadata: metadata,
      );
      if (replacement != null) replacements.add(replacement);
    }
    await _ruleRepository.replaceItems(
      targetKeys: targetKeys,
      replacements: replacements,
    );

    try {
      final updatedCount = await _indexRepository.updateMatching(
        sourceId,
        (item) => assignmentsById.containsKey(item.remoteId),
        (item) => _applyAssignment(
          item: item,
          assignment: assignmentsById[item.remoteId]!,
          metadata: metadata,
        ),
      );
      return CloudEpisodeMatchSaveOutcome(
        rulesSaved: true,
        indexSynced: updatedCount == assignmentsById.length,
      );
    } on Object {
      return const CloudEpisodeMatchSaveOutcome(
        rulesSaved: true,
        indexSynced: false,
      );
    }
  }

  CloudEpisodeMatchRule? _buildRule({
    required CloudMediaIndexItem item,
    required ManualEpisodeAssignment assignment,
    required TmdbMetadata metadata,
  }) {
    switch (assignment.mode) {
      case ManualEpisodeAssignmentMode.mapped:
        return CloudEpisodeMatchRule.mapped(
          sourceId: item.sourceId,
          remoteId: item.remoteId,
          remotePath: item.remotePath,
          tmdbId: metadata.id,
          seasonNumber: assignment.seasonNumber!,
          episodeNumber: assignment.episodeNumber!,
          updatedAt: _now(),
        );
      case ManualEpisodeAssignmentMode.keepOriginal:
        return CloudEpisodeMatchRule.keepOriginal(
          sourceId: item.sourceId,
          remoteId: item.remoteId,
          remotePath: item.remotePath,
          tmdbId: metadata.id,
          updatedAt: _now(),
        );
      case ManualEpisodeAssignmentMode.restoreAutomatic:
        return null;
    }
  }

  CloudMediaIndexItem _applyAssignment({
    required CloudMediaIndexItem item,
    required ManualEpisodeAssignment assignment,
    required TmdbMetadata metadata,
  }) {
    final enriched = item.replaceTmdb(
      tmdbId: metadata.id,
      tmdbTitle: metadata.title,
      tmdbOriginalTitle: metadata.originalTitle,
      tmdbOverview: metadata.overview,
      tmdbRating: metadata.rating,
      tmdbPosterUrl: metadata.posterUrl,
      tmdbBackdropUrl: metadata.backdropUrl,
      tmdbGenres: metadata.genres,
    );
    switch (assignment.mode) {
      case ManualEpisodeAssignmentMode.mapped:
        return _withEpisodeTitle(
          enriched.withEpisodeMapping(
            seasonNumber: assignment.seasonNumber,
            episodeNumber: assignment.episodeNumber,
            keepOriginal: false,
            tmdbId: metadata.id,
          ),
          metadata,
        );
      case ManualEpisodeAssignmentMode.keepOriginal:
        return enriched.withEpisodeMapping(
          seasonNumber: null,
          episodeNumber: null,
          keepOriginal: true,
          tmdbId: metadata.id,
        );
      case ManualEpisodeAssignmentMode.restoreAutomatic:
        final parentPath = p.posix.dirname(enriched.remotePath);
        final automatic = _preMatcher.match(
          originalName: enriched.remoteName,
          parentName: p.posix.basename(parentPath),
          grandParentName: p.posix.basename(p.posix.dirname(parentPath)),
          expectedSeriesName: enriched.seriesName,
        );
        return _withEpisodeTitle(
          enriched.withEpisodeMapping(
            seasonNumber: automatic?.seasonNumber,
            episodeNumber: automatic?.episodeNumber,
            keepOriginal: automatic == null,
            tmdbId: metadata.id,
          ),
          metadata,
        );
    }
  }

  CloudMediaIndexItem _withEpisodeTitle(
    CloudMediaIndexItem item,
    TmdbMetadata metadata,
  ) {
    final seasonNumber = item.seasonNumber;
    final episodeNumber = item.episodeNumber;
    if (seasonNumber == null || episodeNumber == null) return item;
    String? episodeName;
    for (final season in metadata.seasons) {
      if (season.seasonNumber != seasonNumber) continue;
      for (final episode in season.episodes) {
        if (episode.episodeNumber == episodeNumber) {
          episodeName = episode.name;
          break;
        }
      }
      break;
    }
    final displayName = const TmdbEpisodeTitleResolver().resolveWithExtension(
      seriesTitle: metadata.title,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      episodeName: episodeName,
      originalFileName: item.remoteName,
    );
    return item.copyWith(displayName: displayName);
  }

  String _ruleKey(CloudMediaIndexItem item) {
    return cloudEpisodeMatchRuleKey(
      sourceId: item.sourceId,
      remoteId: item.remoteId,
      remotePath: item.remotePath,
    );
  }
}
