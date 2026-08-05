import 'package:kanyingyin/features/episode_matching/domain/manual_episode_match.dart';
import 'package:kanyingyin/features/episode_matching/domain/manual_episode_pre_matcher.dart';
import 'package:kanyingyin/modules/cloud/cloud_episode_match_rule.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_episode_match_rule_repository.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
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
    switch (assignment.mode) {
      case ManualEpisodeAssignmentMode.mapped:
        return item.withEpisodeMapping(
          seasonNumber: assignment.seasonNumber,
          episodeNumber: assignment.episodeNumber,
          keepOriginal: false,
          tmdbId: metadata.id,
        );
      case ManualEpisodeAssignmentMode.keepOriginal:
        return item.withEpisodeMapping(
          seasonNumber: null,
          episodeNumber: null,
          keepOriginal: true,
          tmdbId: metadata.id,
        );
      case ManualEpisodeAssignmentMode.restoreAutomatic:
        final parentPath = p.posix.dirname(item.remotePath);
        final automatic = _preMatcher.match(
          originalName: item.remoteName,
          parentName: p.posix.basename(parentPath),
          grandParentName: p.posix.basename(p.posix.dirname(parentPath)),
          expectedSeriesName: item.seriesName,
        );
        return item.withEpisodeMapping(
          seasonNumber: automatic?.seasonNumber,
          episodeNumber: automatic?.episodeNumber,
          keepOriginal: automatic == null,
          tmdbId: metadata.id,
        );
    }
  }

  String _ruleKey(CloudMediaIndexItem item) {
    return cloudEpisodeMatchRuleKey(
      sourceId: item.sourceId,
      remoteId: item.remoteId,
      remotePath: item.remotePath,
    );
  }
}
