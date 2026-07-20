import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

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
        _posterCache = posterCache,
        _now = now ?? DateTime.now;

  final CloudWorkTmdbRepository _repository;
  final CloudMediaIndexRepository _indexRepository;
  final ITmdbClient _client;
  final CloudPosterCache? _posterCache;
  final DateTime Function() _now;

  CloudResourceTmdbSearchRequest requestFor(
    CloudWorkIdentity work,
    CloudWorkTmdbRecord? record, [
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  ]) {
    final override = record?.scrapeTitleOverride?.trim();
    final fallback = work.titleCandidates.firstOrNull?.trim();
    final query = override != null && override.isNotEmpty
        ? override
        : fallback != null && fallback.isNotEmpty
            ? fallback
            : work.displayTitle.trim();
    return CloudResourceTmdbSearchRequest(
      queryTitle: query,
      queryYear: null,
      mediaTypeMode:
          work.seasons.isEmpty ? options.mediaTypeMode : TmdbMediaTypeMode.tv,
      options: options,
    );
  }

  Future<List<TmdbMetadata>> searchCandidates(
    CloudWorkIdentity work, {
    CloudWorkTmdbRecord? record,
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final queries = _queryCandidates(work, record);
    for (final query in queries) {
      final request = requestFor(work, record, options);
      final ranked = await searchPrepared(
        work,
        CloudResourceTmdbSearchRequest(
          queryTitle: query,
          queryYear: null,
          mediaTypeMode: request.mediaTypeMode,
          options: options,
        ),
      );
      if (ranked.candidates.isNotEmpty) {
        return ranked.candidates
            .map((candidate) => candidate.metadata)
            .toList(growable: false);
      }
    }
    return const <TmdbMetadata>[];
  }

  Future<TmdbRankedResult> searchPrepared(
    CloudWorkIdentity work,
    CloudResourceTmdbSearchRequest request,
  ) async {
    final query = request.queryTitle.trim();
    if (query.isEmpty) {
      throw ArgumentError.value(request.queryTitle, 'queryTitle');
    }
    final types = _typesFor(work, request.mediaTypeMode);
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
      queryYear: request.queryYear,
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
    final queries = _queryCandidates(work, record);
    TmdbRankedResult ranked = const TmdbRankedResult(
      candidates: <TmdbRankedCandidate>[],
      shouldAutoMatch: false,
    );
    for (final query in queries) {
      final base = requestFor(work, record, options);
      ranked = await searchPrepared(
        work,
        CloudResourceTmdbSearchRequest(
          queryTitle: query,
          queryYear: null,
          mediaTypeMode: base.mediaTypeMode,
          options: options,
        ),
      );
      if (ranked.candidates.isNotEmpty) break;
    }
    if (ranked.candidates.isEmpty) {
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
    final selected = await select(
      work,
      ranked.best!.metadata,
      existingSeasons:
          work.seasons.map((season) => season.seasonNumber).toSet(),
      options: options,
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
    var metadata = await _client.details(
      candidate.id,
      candidate.mediaType,
      language: options.language,
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
        .where((season) => existingSeasons.contains(season.seasonNumber))
        .toList(growable: false)
      ..sort(
        (first, second) => first.seasonNumber.compareTo(second.seasonNumber),
      );
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

    final previous = await _repository.get(work.workKey);
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

  List<String> _queryCandidates(
    CloudWorkIdentity work,
    CloudWorkTmdbRecord? record,
  ) {
    final result = <String>[];
    void add(String? value) {
      final normalized = value?.trim();
      if (normalized == null || normalized.isEmpty) return;
      if (!result.any(
        (current) => current.toLowerCase() == normalized.toLowerCase(),
      )) {
        result.add(normalized);
      }
    }

    add(record?.scrapeTitleOverride);
    for (final candidate in work.titleCandidates) {
      add(candidate);
    }
    add(work.displayTitle);
    return result;
  }

  List<TmdbMediaType> _typesFor(
    CloudWorkIdentity work,
    TmdbMediaTypeMode mode,
  ) {
    if (work.seasons.isNotEmpty || mode == TmdbMediaTypeMode.tv) {
      return const <TmdbMediaType>[TmdbMediaType.tv];
    }
    if (mode == TmdbMediaTypeMode.movie) {
      return const <TmdbMediaType>[TmdbMediaType.movie];
    }
    return const <TmdbMediaType>[
      TmdbMediaType.movie,
      TmdbMediaType.tv,
    ];
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
