import 'package:kanyingyin/features/episode_matching/domain/manual_episode_match.dart';
import 'package:kanyingyin/features/episode_matching/domain/manual_episode_pre_matcher.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';
import 'package:path/path.dart' as p;

final class LocalEpisodeMatchService {
  LocalEpisodeMatchService({
    required ILocalMediaIndexRepository repository,
    ManualEpisodePreMatcher preMatcher = const ManualEpisodePreMatcher(),
  })  : _repository = repository,
        _preMatcher = preMatcher;

  final ILocalMediaIndexRepository _repository;
  final ManualEpisodePreMatcher _preMatcher;

  Future<void> save({
    required Iterable<String> resourceIds,
    required List<ManualEpisodeAssignment> assignments,
    required TmdbMetadata metadata,
    required int selectedSeasonNumber,
    String? seriesNameOverride,
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

    final indexedById = <String, LocalMediaIndexItem>{
      for (final item in _repository.getAll()) item.id: item,
    };
    final requestedItems = <LocalMediaIndexItem>[];
    for (final id in resourceIds) {
      final item = indexedById[id];
      if (item == null) throw StateError('本地媒体索引中不存在资源：$id');
      requestedItems.add(item);
    }
    final matchItems = requestedItems
        .map(
          (item) => ManualEpisodeMatchItem(
            resourceId: item.id,
            originalName: item.name,
            parentName: p.basename(item.parentPath),
            existingSeasonNumber: item.seasonNumber,
            existingEpisodeNumber: item.episodeNumber,
            manualOverride: item.manualOverride,
          ),
        )
        .toList(growable: false);
    final errors = validateManualEpisodeAssignments(
      items: matchItems,
      assignments: assignments,
      selectedSeasonNumber: selectedSeasonNumber,
      validEpisodeNumbers:
          season.episodes.map((item) => item.episodeNumber).toSet(),
    );
    if (errors.isNotEmpty) throw StateError(errors.join('\n'));

    final snapshot = <String, LocalMediaIndexItem>{
      for (final item in requestedItems) item.id: item,
    };
    final updates = <String, LocalMediaIndexItem>{};
    for (final assignment in assignments) {
      final item = indexedById[assignment.resourceId]!;
      updates[item.id] = _applyAssignment(
        item: item,
        assignment: assignment,
        metadata: metadata,
        seriesNameOverride: seriesNameOverride,
      );
    }
    try {
      await _repository.updateItems(updates);
    } on Object catch (error, stackTrace) {
      try {
        await _repository.updateItems(snapshot);
      } on Object {
        // 保留首次批量保存错误，调用方可明确提示本次操作失败。
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  LocalMediaIndexItem _applyAssignment({
    required LocalMediaIndexItem item,
    required ManualEpisodeAssignment assignment,
    required TmdbMetadata metadata,
    String? seriesNameOverride,
  }) {
    switch (assignment.mode) {
      case ManualEpisodeAssignmentMode.mapped:
        return item.withEpisodeMapping(
          seasonNumber: assignment.seasonNumber,
          episodeNumber: assignment.episodeNumber,
          manualOverride: true,
          metadata: metadata,
          matchOrigin: TmdbMatchOrigin.manual,
          seriesName: seriesNameOverride,
        );
      case ManualEpisodeAssignmentMode.keepOriginal:
        return item.withEpisodeMapping(
          seasonNumber: null,
          episodeNumber: null,
          manualOverride: true,
          metadata: metadata,
          matchOrigin: TmdbMatchOrigin.manual,
          seriesName: seriesNameOverride,
        );
      case ManualEpisodeAssignmentMode.restoreAutomatic:
        final parentName = p.basename(item.parentPath);
        final grandParentName = p.basename(p.dirname(item.parentPath));
        final automatic = _preMatcher.match(
          originalName: item.name,
          parentName: parentName,
          grandParentName: grandParentName,
          expectedSeriesName: item.seriesName,
        );
        return item.withEpisodeMapping(
          seasonNumber: automatic?.seasonNumber,
          episodeNumber: automatic?.episodeNumber,
          manualOverride: false,
          metadata: metadata,
          matchOrigin: TmdbMatchOrigin.manual,
          seriesName: seriesNameOverride,
        );
    }
  }
}
