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
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_metadata_merge_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_engine.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

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

class CloudWorkTmdbService {
  CloudWorkTmdbService({
    required CloudWorkTmdbRepository repository,
    required CloudMediaIndexRepository indexRepository,
    required ITmdbClient client,
    CloudPosterCache? posterCache,
    DateTime Function()? now,
  })  : _repository = repository,
        _indexRepository = indexRepository,
        _client = client,
        _engine = TmdbScrapeEngine(client: client),
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
      year: request.queryYear,
      seasonNumbers: base.seasonNumbers,
      episodeNumbers: base.episodeNumbers,
      mediaEvidence: base.mediaEvidence,
    );
    final resolvedOptions = request.options.copyWith(
      mediaTypeMode: request.mediaTypeMode,
    );
    final plan = const TmdbScrapePolicy().build(subject, resolvedOptions);
    final query = plan.queries.firstOrNull;
    if (query == null || query.isEmpty) {
      throw ArgumentError.value(request.queryTitle, 'queryTitle');
    }
    final types = plan.mediaTypes;
    final candidates = <TmdbMetadata>[];
    for (final type in types) {
      candidates.addAll(
        await _client.search(
          query,
          type,
          language: request.options.language,
        ),
      );
    }
    return const TmdbMatcher().rank(
      queryTitle: query,
      queryYear: plan.year,
      expectedTypes: types.toSet(),
      candidates: candidates,
      minimumScore: request.options.minimumScore,
      minimumLead: request.options.minimumLead,
    );
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
    final fetched = await _client.details(
      candidate.id,
      candidate.mediaType,
      language: options.language,
    );
    var metadata = const TmdbMetadataMergePolicy().merge(
      existing: subject.existingMetadata,
      fetched: fetched,
      options: options,
      locks: subject.fieldLocks,
      matchConfidence: candidate.matchConfidence,
      existingSeasons: existingSeasons,
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

    final actualSeasons = metadata.seasons;
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
  ) async {
    final metadata = record.metadata;
    if (record.status != CloudWorkTmdbStatus.matched || metadata == null) {
      return 0;
    }
    return _syncIndex(work, metadata, record.posterCachePath);
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

  CloudMediaIndexItem _replaceMetadata(
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
      posterCachePath: posterCachePath,
    );
  }

  static String _imageUrl(String value) => value.startsWith('http')
      ? value
      : 'https://image.tmdb.org/t/p/w500$value';
}
