import 'dart:collection';

import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_media_name_parser.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

class CloudResourceTmdbTarget {
  const CloudResourceTmdbTarget({
    required this.sourceId,
    required this.remote,
    required this.displayName,
    required this.resourceKind,
    this.customTitle,
    this.matchingTitle,
    this.matchingSeasonNumber,
    this.matchingEpisodeNumber,
    this.size,
  });

  final String sourceId;
  final CloudRemoteRef remote;
  final String displayName;
  final CloudResourceKind resourceKind;
  final String? customTitle;
  final String? matchingTitle;
  final int? matchingSeasonNumber;
  final int? matchingEpisodeNumber;
  final int? size;

  String? get effectiveMatchingTitle {
    final custom = customTitle?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final indexed = matchingTitle?.trim();
    return indexed == null || indexed.isEmpty ? null : indexed;
  }

  String get queryDisplayName => effectiveMatchingTitle ?? displayName;

  String get stableKey => cloudResourceTmdbKey(
        sourceId: sourceId,
        remoteId: remote.id,
        remotePath: remote.path,
      );
}

class CloudResourceTmdbOutcome {
  const CloudResourceTmdbOutcome({required this.candidates, this.selected});

  final List<TmdbMetadata> candidates;
  final CloudResourceTmdbRecord? selected;
}

class CloudResourceTmdbService {
  CloudResourceTmdbService({
    required CloudResourceTmdbRepository repository,
    required CloudMediaIndexRepository indexRepository,
    required ITmdbClient client,
    CloudPosterCache? posterCache,
    DateTime Function()? now,
    Duration searchCacheTtl = const Duration(minutes: 10),
    int maximumCachedSearches = 50,
  })  : _repository = repository,
        _indexRepository = indexRepository,
        _client = client,
        _posterCache = posterCache,
        _now = now ?? DateTime.now,
        _searchCacheTtl = searchCacheTtl,
        _maximumCachedSearches = maximumCachedSearches {
    if (maximumCachedSearches <= 0) {
      throw ArgumentError.value(
        maximumCachedSearches,
        'maximumCachedSearches',
      );
    }
  }

  final CloudResourceTmdbRepository _repository;
  final CloudMediaIndexRepository _indexRepository;
  final ITmdbClient _client;
  final CloudPosterCache? _posterCache;
  final DateTime Function() _now;
  final Duration _searchCacheTtl;
  final int _maximumCachedSearches;
  final LinkedHashMap<String, _CachedSearch> _searchCache =
      LinkedHashMap<String, _CachedSearch>();

  Future<CloudResourceTmdbOutcome> match(
    CloudResourceTmdbTarget target, {
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final request = _requestFor(target, options);
    final search = await searchPrepared(target, request);
    if (search.ranked.candidates.isEmpty) {
      final record = CloudResourceTmdbRecord.unmatched(
        sourceId: target.sourceId,
        remoteId: target.remote.id,
        remotePath: target.remote.path,
        displayName: target.displayName,
        resourceKind: target.resourceKind,
        checkedAt: _now(),
        customTitle: target.customTitle,
      );
      await _repository.upsert(record);
      return const CloudResourceTmdbOutcome(candidates: <TmdbMetadata>[]);
    }

    if (!search.ranked.shouldAutoMatch || search.ranked.best == null) {
      return CloudResourceTmdbOutcome(
        candidates: search.ranked.candidates
            .map((candidate) => candidate.metadata)
            .toList(growable: false),
      );
    }
    final selected = await select(
      target,
      search.ranked.best!.metadata,
      options: options,
    );
    return CloudResourceTmdbOutcome(
      candidates: search.ranked.candidates
          .map((candidate) => candidate.metadata)
          .toList(growable: false),
      selected: selected,
    );
  }

  Future<CloudResourceTmdbOutcome> searchCandidates(
    CloudResourceTmdbTarget target, {
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final search = await searchPrepared(target, _requestFor(target, options));
    return CloudResourceTmdbOutcome(
      candidates: search.ranked.candidates
          .map((candidate) => candidate.metadata)
          .toList(growable: false),
    );
  }

  Future<CloudResourceTmdbSearchOutcome> searchPrepared(
    CloudResourceTmdbTarget target,
    CloudResourceTmdbSearchRequest request,
  ) async {
    final query = request.queryTitle.trim();
    if (query.isEmpty) {
      throw ArgumentError.value(request.queryTitle, 'queryTitle');
    }
    final types = switch (request.mediaTypeMode) {
      TmdbMediaTypeMode.movie => const <TmdbMediaType>[TmdbMediaType.movie],
      TmdbMediaTypeMode.tv => const <TmdbMediaType>[TmdbMediaType.tv],
      TmdbMediaTypeMode.auto =>
        target.resourceKind == CloudResourceKind.directory
            ? const <TmdbMediaType>[
                TmdbMediaType.tv,
                TmdbMediaType.movie,
              ]
            : const <TmdbMediaType>[
                TmdbMediaType.movie,
                TmdbMediaType.tv,
              ],
    };
    final candidates = await _searchWithCache(
      query,
      types,
      request.options.language,
      request.mediaTypeMode,
    );
    final ranked = const TmdbMatcher().rank(
      queryTitle: query,
      queryYear: request.queryYear,
      expectedTypes: types.toSet(),
      candidates: candidates,
      minimumScore: request.options.minimumScore,
      minimumLead: request.options.minimumLead,
    );
    return CloudResourceTmdbSearchOutcome(ranked: ranked);
  }

  Future<CloudResourceTmdbRecord> select(
    CloudResourceTmdbTarget target,
    TmdbMetadata candidate, {
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    return (await selectWithOutcome(target, candidate, options: options))
        .record;
  }

  Future<CloudResourceTmdbSelectionOutcome> selectWithOutcome(
    CloudResourceTmdbTarget target,
    TmdbMetadata candidate, {
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    var metadata = await _client.details(
      candidate.id,
      candidate.mediaType,
      language: options.language,
    );
    String? posterCachePath;
    var posterCached = true;
    if (_posterCache != null &&
        options.fetchPoster &&
        metadata.posterUrl != null) {
      final imageUrl = _imageUrl(metadata.posterUrl!);
      try {
        final resolved = await _posterCache.resolve(
          sourceId: target.sourceId,
          stableId: target.stableKey,
          url: imageUrl,
        );
        if (resolved != imageUrl) {
          posterCachePath = resolved;
        } else {
          posterCached = false;
        }
      } on Object {
        posterCached = false;
      }
    }
    if (_posterCache != null &&
        options.fetchPoster &&
        metadata.seasons.isNotEmpty) {
      final seasons = <TmdbSeasonMetadata>[];
      for (final season in metadata.seasons) {
        final posterUrl = season.posterUrl;
        if (season.seasonNumber <= 0 || posterUrl == null) {
          seasons.add(season);
          continue;
        }
        final imageUrl = _imageUrl(posterUrl);
        try {
          final resolved = await _posterCache.resolve(
            sourceId: target.sourceId,
            stableId: '${target.stableKey}|season:${season.seasonNumber}',
            url: imageUrl,
          );
          if (resolved == imageUrl) {
            posterCached = false;
            seasons.add(season);
          } else {
            seasons.add(season.copyWith(posterCachePath: resolved));
          }
        } on Object {
          posterCached = false;
          seasons.add(season);
        }
      }
      metadata = metadata.copyWith(seasons: seasons);
    }
    final record = CloudResourceTmdbRecord.matched(
      sourceId: target.sourceId,
      remoteId: target.remote.id,
      remotePath: target.remote.path,
      displayName: target.displayName,
      resourceKind: target.resourceKind,
      metadata: metadata,
      posterCachePath: posterCachePath,
      checkedAt: _now(),
      customTitle: target.customTitle,
    );
    await _repository.upsert(record);
    var indexSynced = true;
    try {
      await _syncIndex(target, metadata, posterCachePath);
    } on Object {
      indexSynced = false;
    }
    return CloudResourceTmdbSelectionOutcome(
      record: record,
      posterCached: posterCached,
      indexSynced: indexSynced,
    );
  }

  Future<bool> syncRecordToIndex(
    CloudResourceTmdbTarget target,
    CloudResourceTmdbRecord record,
  ) async {
    final id = record.tmdbId;
    final mediaType = record.mediaType;
    final title = record.title;
    if (record.status != CloudResourceTmdbStatus.matched ||
        id == null ||
        mediaType == null ||
        title == null ||
        title.trim().isEmpty) {
      return false;
    }
    final metadata = TmdbMetadata(
      id: id,
      mediaType: mediaType,
      title: title,
      originalTitle: record.originalTitle,
      overview: record.overview,
      rating: record.rating,
      posterUrl: record.posterUrl,
      backdropUrl: record.backdropUrl,
      language: 'zh-CN',
      matchedAt: record.checkedAt,
      matchConfidence: 1,
    );
    try {
      await _syncIndex(target, metadata, record.posterCachePath);
      return true;
    } on Object {
      return false;
    }
  }

  static String queryName(String displayName, {required bool isDirectory}) {
    final draft = const CloudMediaNameParser().parse(
      originalName: displayName,
      isDirectory: isDirectory,
    );
    return draft.year == null
        ? draft.searchTitle
        : '${draft.searchTitle} (${draft.year})';
  }

  CloudResourceTmdbSearchRequest _requestFor(
    CloudResourceTmdbTarget target,
    TmdbScrapeOptions options,
  ) {
    final draft = const CloudMediaNameParser().parse(
      originalName: target.displayName,
      isDirectory: target.resourceKind == CloudResourceKind.directory,
      preferredTitle: target.effectiveMatchingTitle,
    );
    return CloudResourceTmdbSearchRequest(
      queryTitle: draft.searchTitle,
      queryYear: draft.year,
      mediaTypeMode: options.mediaTypeMode,
      options: options,
    );
  }

  Future<List<TmdbMetadata>> _searchWithCache(
    String query,
    List<TmdbMediaType> types,
    String language,
    TmdbMediaTypeMode mode,
  ) async {
    final key = '${query.toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}|'
        '${mode.name}|$language';
    final cached = _searchCache.remove(key);
    if (cached != null &&
        _now().difference(cached.createdAt) < _searchCacheTtl) {
      _searchCache[key] = cached;
      return cached.candidates;
    }
    final candidates = <TmdbMetadata>[];
    for (final type in types) {
      candidates.addAll(await _client.search(
        query,
        type,
        language: language,
      ));
    }
    final result = List<TmdbMetadata>.unmodifiable(candidates);
    _searchCache[key] = _CachedSearch(
      createdAt: _now(),
      candidates: result,
    );
    while (_searchCache.length > _maximumCachedSearches) {
      _searchCache.remove(_searchCache.keys.first);
    }
    return result;
  }

  Future<void> _syncIndex(
    CloudResourceTmdbTarget target,
    TmdbMetadata metadata,
    String? posterCachePath,
  ) async {
    final targetPath = _normalizePath(target.remote.path);
    await _indexRepository.updateMatching(
      target.sourceId,
      (item) {
        final itemPath = _normalizePath(item.remotePath);
        return target.resourceKind == CloudResourceKind.directory
            ? itemPath.startsWith(targetPath == '/' ? '/' : '$targetPath/')
            : itemPath == targetPath;
      },
      (item) => _replaceMetadata(item, metadata, posterCachePath),
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
      posterCachePath: posterCachePath,
    );
  }

  static String _normalizePath(String value) {
    var path = value.trim().replaceAll('\\', '/');
    path = path.replaceAll(RegExp(r'/+'), '/');
    if (path.isEmpty) return '/';
    if (!path.startsWith('/')) path = '/$path';
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  static String _imageUrl(String value) => value.startsWith('http')
      ? value
      : 'https://image.tmdb.org/t/p/w500$value';
}

class _CachedSearch {
  const _CachedSearch({required this.createdAt, required this.candidates});

  final DateTime createdAt;
  final List<TmdbMetadata> candidates;
}
