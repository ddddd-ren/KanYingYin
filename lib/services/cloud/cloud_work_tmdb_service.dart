import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/cloud/cloud_tmdb_subject_builder.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client_capabilities.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_metadata_merge_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_engine.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_cache.dart';

class CloudWorkTmdbOutcome {
  const CloudWorkTmdbOutcome({required this.candidates, this.selected});

  final List<TmdbMetadata> candidates;
  final CloudWorkTmdbRecord? selected;
}

class CloudWorkTmdbSelectionOutcome {
  const CloudWorkTmdbSelectionOutcome({
    required this.record,
    required this.updatedIndexItems,
    required this.posterCached,
    required this.indexSynced,
  });

  final CloudWorkTmdbRecord record;
  final int updatedIndexItems;
  final bool posterCached;
  final bool indexSynced;
}

class CloudWorkTmdbIdentityChangeException extends StateError {
  CloudWorkTmdbIdentityChangeException() : super('更换 TMDB 剧目会影响整部剧，请确认整剧更新');
}

class CloudWorkTmdbService {
  CloudWorkTmdbService({
    required CloudWorkTmdbRepository repository,
    required CloudMediaIndexRepository indexRepository,
    required ITmdbClient client,
    CloudPosterCache? posterCache,
    DateTime Function()? now,
    TmdbScrapeEngine? engine,
    TmdbScrapeCache? cache,
  })  : _repository = repository,
        _indexRepository = indexRepository,
        _client = client,
        _engine = engine ?? TmdbScrapeEngine(client: client, cache: cache),
        _posterCache = posterCache,
        _now = now ?? DateTime.now;

  final CloudWorkTmdbRepository _repository;
  final CloudMediaIndexRepository _indexRepository;
  final ITmdbClient _client;
  final TmdbScrapeEngine _engine;
  final CloudPosterCache? _posterCache;
  final DateTime Function() _now;

  CloudResourceTmdbSearchRequest requestFor(
    CloudWorkIdentity work,
    CloudWorkTmdbRecord? record, [
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  ]) {
    final subject = const CloudTmdbSubjectBuilder().forWork(
      work,
      record: record,
    );
    final plan = const TmdbScrapePolicy().build(subject, options);
    return CloudResourceTmdbSearchRequest(
      queryTitle: plan.queries.firstOrNull ?? work.displayTitle.trim(),
      queryYear: plan.year,
      mediaTypeMode: plan.mediaTypes.length == 1
          ? plan.mediaTypes.single == TmdbMediaType.tv
              ? TmdbMediaTypeMode.tv
              : TmdbMediaTypeMode.movie
          : options.mediaTypeMode,
      options: options,
    );
  }

  Future<List<TmdbMetadata>> searchCandidates(
    CloudWorkIdentity work, {
    CloudWorkTmdbRecord? record,
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final subject = const CloudTmdbSubjectBuilder().forWork(
      work,
      record: record,
    );
    final search = await _engine.search(subject, options);
    return search.ranked.candidates
        .map((candidate) => candidate.metadata)
        .toList(growable: false);
  }

  Future<TmdbRankedResult> searchPrepared(
    CloudWorkIdentity work,
    CloudResourceTmdbSearchRequest request,
  ) async {
    final base = const CloudTmdbSubjectBuilder().forWork(work);
    final subject = TmdbScrapeSubject(
      stableKey: base.stableKey,
      titleCandidates: <String>[request.queryTitle],
      manualSearchTitle: request.queryTitle,
      year: request.queryYear,
      seasonNumbers: base.seasonNumbers,
      episodeNumbers: base.episodeNumbers,
      mediaEvidence: base.mediaEvidence,
    );
    final resolvedOptions = request.options.copyWith(
      mediaTypeMode: request.mediaTypeMode,
    );
    if (request.queryTitle.trim().isEmpty) {
      throw ArgumentError.value(request.queryTitle, 'queryTitle');
    }
    final outcome = await _engine.search(
      subject,
      resolvedOptions,
      minimumScore: request.options.minimumScore,
      minimumLead: request.options.minimumLead,
    );
    return outcome.ranked;
  }

  Future<CloudWorkTmdbOutcome> match(
    CloudWorkIdentity work, {
    CloudWorkTmdbRecord? record,
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final existing = record ?? await _repository.get(work.workKey);
    final subject = const CloudTmdbSubjectBuilder().forWork(
      work,
      record: existing,
    );
    final search = await _engine.search(subject, options);
    final ranked = search.ranked;
    if (ranked.candidates.isEmpty) {
      if (existing?.status == CloudWorkTmdbStatus.matched ||
          existing?.status == CloudWorkTmdbStatus.conflict) {
        return const CloudWorkTmdbOutcome(candidates: <TmdbMetadata>[]);
      }
      await _repository.upsert(
        CloudWorkTmdbRecord.unmatched(
          sourceId: work.sourceId,
          workKey: work.workKey,
          workRootId: work.root.id,
          workRootPath: work.root.remotePath,
          remoteName: work.remoteName,
          checkedAt: _now(),
          scrapeTitleOverride: record?.scrapeTitleOverride,
          tmdbRuleVersion: currentTmdbRuleVersion,
        ),
      );
      return const CloudWorkTmdbOutcome(candidates: <TmdbMetadata>[]);
    }
    final candidates = ranked.candidates
        .map((candidate) => candidate.metadata)
        .toList(growable: false);
    if (!ranked.shouldAutoMatch || ranked.best == null) {
      return CloudWorkTmdbOutcome(candidates: candidates);
    }
    final best = ranked.best!;
    if (existing?.metadata != null &&
        existing!.metadata!.id != best.metadata.id) {
      await _repository.upsert(existing.asConflict(_now()));
      return CloudWorkTmdbOutcome(candidates: candidates);
    }
    final selected = await _select(
      work,
      best.metadata,
      existingSeasons:
          work.seasons.map((season) => season.seasonNumber).toSet(),
      options: options,
      origin: TmdbMatchOrigin.automatic,
      existing: existing,
    );
    return CloudWorkTmdbOutcome(
      candidates: candidates,
      selected: selected.record,
    );
  }

  Future<CloudWorkTmdbSelectionOutcome> select(
    CloudWorkIdentity work,
    TmdbMetadata candidate, {
    required Set<int> existingSeasons,
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    return _select(
      work,
      candidate,
      existingSeasons: existingSeasons,
      options: options,
      origin: TmdbMatchOrigin.manual,
    );
  }

  Future<CloudWorkTmdbSelectionOutcome> selectSeason(
    CloudWorkIdentity work,
    TmdbMetadata candidate, {
    required int seasonNumber,
    required TmdbScrapeOptions options,
  }) async {
    if (seasonNumber <= 0 || candidate.mediaType != TmdbMediaType.tv) {
      throw CloudWorkTmdbIdentityChangeException();
    }
    final previous = await _repository.get(work.workKey);
    if (previous?.metadata == null && work.seasons.length > 1) {
      throw CloudWorkTmdbIdentityChangeException();
    }
    void checkIdentity(CloudWorkTmdbRecord? record) {
      final metadata = record?.metadata;
      if (metadata != null &&
          (metadata.id != candidate.id ||
              metadata.mediaType != candidate.mediaType)) {
        throw CloudWorkTmdbIdentityChangeException();
      }
    }

    checkIdentity(previous);

    // 手动重刮直接读取最新目标季；不复用自动刮削的摘要兜底或整剧缓存。
    final fetched = await _client.details(candidate.id, candidate.mediaType,
        language: options.language);
    if (fetched.id != candidate.id ||
        fetched.mediaType != candidate.mediaType) {
      throw StateError('TMDB 返回的剧目与当前选择不一致');
    }
    final mapping = _singleSeasonNumberMapping(work, fetched);
    final tmdbSeasonNumber = mapping?.localSeasonNumber == seasonNumber
        ? mapping!.tmdbSeasonNumber
        : seasonNumber;
    final client = _client;
    final fetchedSeason = client is ITmdbClientCapabilities
        ? await (client as ITmdbClientCapabilities).seasonDetails(
            candidate.id, tmdbSeasonNumber,
            language: options.language)
        : fetched.seasons.firstWhere(
            (season) => season.seasonNumber == tmdbSeasonNumber,
            orElse: () => throw StateError('TMDB 未返回当前季度资料'),
          );
    if (fetchedSeason.seasonNumber != tmdbSeasonNumber) {
      throw StateError('TMDB 返回的季度与当前选择不一致');
    }
    final normalized =
        fetched.copyWith(seasons: <TmdbSeasonMetadata>[fetchedSeason]);
    final seasonal = mapping?.localSeasonNumber == seasonNumber
        ? _remapSeasonNumber(normalized, mapping!)
        : normalized;
    var season = const TmdbMetadataMergePolicy()
        .merge(
          existing: previous?.metadata,
          fetched: seasonal,
          options: options,
          matchConfidence: candidate.matchConfidence,
          existingSeasons: <int>{seasonNumber},
        )
        .seasons
        .singleWhere((season) => season.seasonNumber == seasonNumber);
    final posterUrl = season.posterUrl;
    if (_posterCache != null && options.fetchPoster && posterUrl != null) {
      final imageUrl = _imageUrl(posterUrl);
      // 新地址写入独立缓存文件，保存成功前保留旧图及其解码缓存。
      final resolved = await _posterCache.resolve(
        sourceId: work.sourceId,
        stableId: '${work.workKey}|season:$seasonNumber|$posterUrl',
        url: imageUrl,
      );
      if (resolved == imageUrl) throw StateError('本季海报下载失败，已保留原资料');
      season = season.copyWith(posterCachePath: resolved);
    }

    final record = await _repository.update(work.workKey, (current) {
      if (previous != null && current == null) {
        throw StateError('作品已被移除，请重新加载媒体库');
      }
      checkIdentity(current);
      final base = current?.metadata ??
          fetched.copyWith(seasons: const <TmdbSeasonMetadata>[]);
      final seasons = <TmdbSeasonMetadata>[
        for (final existing in base.seasons)
          if (existing.seasonNumber != seasonNumber) existing,
        season,
      ]..sort(
          (first, second) => first.seasonNumber.compareTo(second.seasonNumber));
      final metadata = base.copyWith(seasons: seasons);
      return CloudWorkTmdbRecord.matched(
        sourceId: work.sourceId,
        workKey: work.workKey,
        workRootId: work.root.id,
        workRootPath: work.root.remotePath,
        remoteName: work.remoteName,
        metadata: metadata,
        checkedAt: _now(),
        scrapeTitleOverride: current?.scrapeTitleOverride,
        posterCachePath: current?.posterCachePath,
        tmdbMatchOrigin: TmdbMatchOrigin.manual,
        tmdbRuleVersion: currentTmdbRuleVersion,
      );
    });
    var updatedIndexItems = 0;
    var indexSynced = true;
    try {
      updatedIndexItems = await _indexRepository.updateMatching(
        work.sourceId,
        (item) =>
            item.workKey == work.workKey && item.seasonNumber == seasonNumber,
        (item) => _replaceMetadata(
          item.withEffectiveWorkTitle(record.metadata!.title),
          record.metadata!,
          record.posterCachePath,
        ),
      );
    } on Object {
      indexSynced = false;
    }
    return CloudWorkTmdbSelectionOutcome(
      record: record,
      updatedIndexItems: updatedIndexItems,
      posterCached: true,
      indexSynced: indexSynced,
    );
  }

  Future<CloudWorkTmdbSelectionOutcome> _select(
    CloudWorkIdentity work,
    TmdbMetadata candidate, {
    required Set<int> existingSeasons,
    required TmdbScrapeOptions options,
    required TmdbMatchOrigin origin,
    CloudWorkTmdbRecord? existing,
  }) async {
    final previous = existing ?? await _repository.get(work.workKey);
    final subject = const CloudTmdbSubjectBuilder().forWork(
      work,
      record: previous,
    );
    final fetched = await _engine.details(
      candidate.id,
      candidate.mediaType,
      language: options.language,
    );
    final seasonNumberMapping = _singleSeasonNumberMapping(work, fetched);
    final hydrated = await _engine.hydrateSeasons(
      fetched,
      seasonNumbers: seasonNumberMapping == null
          ? subject.seasonNumbers
          : <int>[seasonNumberMapping.tmdbSeasonNumber],
      language: options.language,
    );
    final normalizedHydrated = seasonNumberMapping == null
        ? hydrated
        : _remapSeasonNumber(hydrated, seasonNumberMapping);
    final existingMetadata = seasonNumberMapping != null &&
            subject.existingMetadata?.id == normalizedHydrated.id
        ? _remapSeasonNumber(subject.existingMetadata!, seasonNumberMapping)
        : subject.existingMetadata;
    var metadata = const TmdbMetadataMergePolicy().merge(
      existing: existingMetadata,
      fetched: normalizedHydrated,
      options: options,
      locks: subject.fieldLocks,
      matchConfidence: candidate.matchConfidence,
      // 作品记录需要保留完整季度资料，海报墙才能在跨目录归并后显示
      // 任意季度的 TMDB 海报；当前作品实际包含哪些季度由索引项决定。
      existingSeasons: normalizedHydrated.mediaType == TmdbMediaType.tv
          ? const <int>{}
          : existingSeasons,
    );
    var posterCached = true;
    String? posterCachePath;
    final posterUrl = metadata.posterUrl;
    if (_posterCache != null && options.fetchPoster && posterUrl != null) {
      final imageUrl = _imageUrl(posterUrl);
      try {
        final resolved = await _posterCache.resolve(
          sourceId: work.sourceId,
          stableId: work.workKey,
          url: imageUrl,
        );
        if (resolved == imageUrl) {
          posterCached = false;
        } else {
          posterCachePath = resolved;
        }
      } on Object {
        posterCached = false;
      }
    }

    final actualSeasons = metadata.seasons
        .where((season) => season.seasonNumber > 0)
        .toList(growable: false);
    if (_posterCache != null && options.fetchPoster) {
      final cachedSeasons = <TmdbSeasonMetadata>[];
      for (final season in actualSeasons) {
        final seasonPosterUrl = season.posterUrl;
        if (seasonPosterUrl == null) {
          cachedSeasons.add(season);
          continue;
        }
        final imageUrl = _imageUrl(seasonPosterUrl);
        try {
          final resolved = await _posterCache.resolve(
            sourceId: work.sourceId,
            stableId: '${work.workKey}|season:${season.seasonNumber}',
            url: imageUrl,
          );
          if (resolved == imageUrl) {
            posterCached = false;
            cachedSeasons.add(season);
          } else {
            cachedSeasons.add(season.copyWith(posterCachePath: resolved));
          }
        } on Object {
          posterCached = false;
          cachedSeasons.add(season);
        }
      }
      metadata = metadata.copyWith(seasons: cachedSeasons);
    } else {
      metadata = metadata.copyWith(seasons: actualSeasons);
    }

    final record = CloudWorkTmdbRecord.matched(
      sourceId: work.sourceId,
      workKey: work.workKey,
      workRootId: work.root.id,
      workRootPath: work.root.remotePath,
      remoteName: work.remoteName,
      metadata: metadata,
      checkedAt: _now(),
      scrapeTitleOverride: previous?.scrapeTitleOverride,
      posterCachePath: posterCachePath,
      tmdbMatchOrigin: origin,
      tmdbRuleVersion: currentTmdbRuleVersion,
    );
    await _repository.upsert(record);

    var updatedIndexItems = 0;
    var indexSynced = true;
    try {
      updatedIndexItems = await _syncIndex(
        work,
        metadata,
        posterCachePath,
      );
    } on Object {
      indexSynced = false;
    }
    return CloudWorkTmdbSelectionOutcome(
      record: record,
      updatedIndexItems: updatedIndexItems,
      posterCached: posterCached,
      indexSynced: indexSynced,
    );
  }

  Future<int> syncRecordToIndex(
    CloudWorkIdentity work,
    CloudWorkTmdbRecord record,
  ) {
    return syncMatchedRecordToIndex(
      indexRepository: _indexRepository,
      work: work,
      record: record,
    );
  }

  static Future<int> syncMatchedRecordToIndex({
    required CloudMediaIndexRepository indexRepository,
    required CloudWorkIdentity work,
    required CloudWorkTmdbRecord record,
  }) {
    final metadata = record.metadata;
    if (record.status != CloudWorkTmdbStatus.matched || metadata == null) {
      return Future<int>.value(0);
    }
    return indexRepository.updateMatching(
      work.sourceId,
      (item) => item.workKey == work.workKey,
      (item) => _replaceMetadata(
        item.withEffectiveWorkTitle(metadata.title),
        metadata,
        record.posterCachePath,
      ),
    );
  }

  Future<int> _syncIndex(
    CloudWorkIdentity work,
    TmdbMetadata metadata,
    String? posterCachePath,
  ) {
    return _indexRepository.updateMatching(
      work.sourceId,
      (item) => item.workKey == work.workKey,
      (item) => _replaceMetadata(
        item.withEffectiveWorkTitle(metadata.title),
        metadata,
        posterCachePath,
      ),
    );
  }

  static CloudMediaIndexItem _replaceMetadata(
    CloudMediaIndexItem item,
    TmdbMetadata metadata,
    String? posterCachePath,
  ) {
    return item.replaceTmdb(
      tmdbId: metadata.id,
      tmdbTitle: metadata.title,
      tmdbOriginalTitle: metadata.originalTitle,
      tmdbOverview: metadata.overview,
      tmdbRating: metadata.rating,
      tmdbPosterUrl: metadata.posterUrl,
      tmdbBackdropUrl: metadata.backdropUrl,
      tmdbGenres: metadata.genres,
      posterCachePath: posterCachePath,
    );
  }

  static String _imageUrl(String value) => value.startsWith('http')
      ? value
      : 'https://image.tmdb.org/t/p/w500$value';
}

_SeasonNumberMapping? _singleSeasonNumberMapping(
  CloudWorkIdentity work,
  TmdbMetadata metadata,
) {
  if (metadata.mediaType != TmdbMediaType.tv || work.seasons.length != 1) {
    return null;
  }
  final tmdbSeasons = metadata.seasons
      .where((season) => season.seasonNumber > 0)
      .toList(growable: false);
  if (tmdbSeasons.length != 1) return null;

  final localSeason = work.seasons.single;
  final tmdbSeason = tmdbSeasons.single;
  if (localSeason.seasonNumber <= 0 ||
      localSeason.seasonNumber == tmdbSeason.seasonNumber) {
    return null;
  }
  final localEpisodeCount = localSeason.episodes
      .map((episode) => episode.episodeNumber)
      .where((number) => number > 0)
      .toSet()
      .length;
  if (localEpisodeCount == 0 ||
      tmdbSeason.episodeCount <= 0 ||
      localEpisodeCount != tmdbSeason.episodeCount) {
    return null;
  }
  return _SeasonNumberMapping(
    tmdbSeasonNumber: tmdbSeason.seasonNumber,
    localSeasonNumber: localSeason.seasonNumber,
  );
}

TmdbMetadata _remapSeasonNumber(
  TmdbMetadata metadata,
  _SeasonNumberMapping mapping,
) {
  return metadata.copyWith(
    seasons: metadata.seasons.map((season) {
      if (season.seasonNumber != mapping.tmdbSeasonNumber) return season;
      return TmdbSeasonMetadata(
        id: season.id,
        seasonNumber: mapping.localSeasonNumber,
        name: season.name,
        episodeCount: season.episodeCount,
        overview: season.overview,
        airDate: season.airDate,
        posterUrl: season.posterUrl,
        posterCachePath: season.posterCachePath,
        episodes: season.episodes,
      );
    }).toList(growable: false),
  );
}

class _SeasonNumberMapping {
  const _SeasonNumberMapping({
    required this.tmdbSeasonNumber,
    required this.localSeasonNumber,
  });

  final int tmdbSeasonNumber;
  final int localSeasonNumber;
}
