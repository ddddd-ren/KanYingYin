part of '../cloud_resources_controller.dart';

/// 剧集手动匹配：手动集数匹配与保存。
mixin _CloudEpisodeMatchMixin on _CloudResourcesControllerBase {
  Future<List<ManualEpisodeMatchItem>> manualEpisodeItemsForGroup(
    CloudResourceMediaGroup group,
  ) async {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    final resourceIds =
        group.videos.map((video) => video.id).toSet().toList(growable: false);
    if (resourceIds.isEmpty) throw StateError('当前分组没有可匹配的视频');
    return _episodeMatchService.loadMatchItems(
      sourceId: source.id,
      resourceIds: resourceIds,
      expectedSeriesName: group.seriesName,
      selectedSeasonNumber: group.seasonNumber,
    );
  }

  Future<ManualEpisodeMatchController> manualEpisodeMatchControllerForGroup({
    required CloudResourceMediaGroup group,
    required TmdbMetadata selectedSeries,
  }) async {
    final apiKey = _tmdbApiKeyProvider.read().trim();
    if (apiKey.isEmpty) {
      throw StateError('请先在设置中填写 TMDB API Key');
    }
    if (selectedSeries.mediaType != TmdbMediaType.tv) {
      throw StateError('剧集匹配只支持 TMDB 电视剧');
    }
    final client = _tmdbClientContextRegistry.contextFor(apiKey).client;
    if (client is! ITmdbClientCapabilities) {
      throw StateError('当前 TMDB 客户端不支持季度详情');
    }
    final capabilities = client as ITmdbClientCapabilities;
    return ManualEpisodeMatchController(
      selectedSeries: selectedSeries,
      items: await manualEpisodeItemsForGroup(group),
      loadDetails: (id, mediaType, language) =>
          client.details(id, mediaType, language: language),
      loadSeason: (id, seasonNumber, language) => capabilities.seasonDetails(
        id,
        seasonNumber,
        language: language,
      ),
    );
  }

  Future<CloudEpisodeMatchSaveOutcome> saveManualEpisodeAssignments({
    required CloudResourceMediaGroup group,
    required List<ManualEpisodeAssignment> assignments,
    required TmdbMetadata metadata,
    required int selectedSeasonNumber,
  }) async {
    final source = selectedSource;
    if (source == null) throw StateError('尚未选择网盘来源');
    final outcome = await _episodeMatchService.save(
      sourceId: source.id,
      resourceIds: group.videos.map((video) => video.id).toSet(),
      assignments: assignments,
      metadata: metadata,
      selectedSeasonNumber: selectedSeasonNumber,
    );
    if (selectedSource?.id != source.id) return outcome;

    final workCoordinator = _workTmdbCoordinator;
    final works = _works
        .where(
          (work) => group.workKeys.contains(work.workKey),
        )
        .toList(growable: false);
    try {
      if (workCoordinator != null && works.isNotEmpty) {
        for (final work in works) {
          await workCoordinator.selectCandidate(
            _workForManualEpisodeSelection(
              work,
              assignments: assignments,
              selectedSeasonNumber: selectedSeasonNumber,
            ),
            metadata,
            options: tmdbScrapeOptions.copyWith(
              mediaTypeMode: TmdbMediaTypeMode.tv,
            ),
          );
        }
      } else if (_tmdbCoordinator != null) {
        await _tmdbCoordinator.select(
          tmdbTargetFor(group.anchor),
          metadata,
          options: tmdbScrapeOptions.copyWith(
            mediaTypeMode: TmdbMediaTypeMode.tv,
          ),
        );
      }
    } on Object catch (error, stackTrace) {
      AppLogger().w(
        'CloudResourcesController: 作品元数据同步失败，已保留剧集匹配结果',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (selectedSource?.id != source.id) return outcome;
    await _loadSnapshot(source, _generation);
    _invalidateCollection();
    _notify();
    return outcome;
  }

  CloudWorkIdentity _workForManualEpisodeSelection(
    CloudWorkIdentity work, {
    required List<ManualEpisodeAssignment> assignments,
    required int selectedSeasonNumber,
  }) {
    if (work.seasons.length != 1) return work;
    final season = work.seasons.single;
    if (season.seasonNumber == selectedSeasonNumber ||
        season.episodes.isEmpty) {
      return work;
    }
    final assignmentsById = <String, ManualEpisodeAssignment>{
      for (final assignment in assignments) assignment.resourceId: assignment,
    };
    final remappedEpisodes = <CloudEpisodeIdentity>[];
    for (final episode in season.episodes) {
      final assignment = assignmentsById[episode.entry.id];
      if (assignment?.mode != ManualEpisodeAssignmentMode.mapped ||
          assignment?.seasonNumber != selectedSeasonNumber ||
          assignment?.episodeNumber == null) {
        return work;
      }
      remappedEpisodes.add(
        CloudEpisodeIdentity(
          entry: episode.entry,
          remoteName: episode.remoteName,
          displayName: episode.displayName,
          seasonNumber: selectedSeasonNumber,
          episodeNumber: assignment!.episodeNumber!,
          releaseTags: episode.releaseTags,
        ),
      );
    }
    return CloudWorkIdentity(
      sourceId: work.sourceId,
      workKey: work.workKey,
      root: work.root,
      remoteName: work.remoteName,
      displayTitle: work.displayTitle,
      titleCandidates: work.titleCandidates,
      seasons: <CloudSeasonIdentity>[
        CloudSeasonIdentity(
          workKey: season.workKey,
          seasonNumber: selectedSeasonNumber,
          displayName: '${work.displayTitle} 第 $selectedSeasonNumber 季',
          remoteDirectories: season.remoteDirectories,
          episodes: remappedEpisodes,
          year: season.year,
        ),
      ],
      standaloneVideos: work.standaloneVideos,
      standaloneReleaseTags: work.standaloneReleaseTags,
    );
  }
}
