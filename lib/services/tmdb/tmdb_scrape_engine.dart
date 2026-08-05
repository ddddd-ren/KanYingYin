import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client_capabilities.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

class TmdbScrapeSearchOutcome {
  const TmdbScrapeSearchOutcome({
    required this.queryTitle,
    required this.ranked,
  });

  final String? queryTitle;
  final TmdbRankedResult ranked;
}

class TmdbScrapeEngine {
  const TmdbScrapeEngine({
    required ITmdbClient client,
    TmdbScrapePolicy policy = const TmdbScrapePolicy(),
    TmdbMatcher matcher = const TmdbMatcher(),
  })  : _client = client,
        _policy = policy,
        _matcher = matcher;

  final ITmdbClient _client;
  final TmdbScrapePolicy _policy;
  final TmdbMatcher _matcher;

  /// 只为实际存在的季度补充逐集资料；详情失败时保留已有摘要。
  Future<TmdbMetadata> hydrateSeasons(
    TmdbMetadata metadata, {
    Iterable<int> seasonNumbers = const <int>[],
    TmdbScrapeSubject? subject,
    String language = 'zh-CN',
  }) async {
    if (metadata.mediaType != TmdbMediaType.tv ||
        _client is! ITmdbClientCapabilities) {
      return metadata;
    }
    final requested = <int>{
      ...seasonNumbers.where((number) => number > 0),
      ...?subject?.seasonNumbers.where((number) => number > 0),
    };
    if (requested.isEmpty) return metadata;
    final capabilities = _client as ITmdbClientCapabilities;
    final existingByNumber = <int, TmdbSeasonMetadata>{
      for (final season in metadata.seasons) season.seasonNumber: season,
    };
    final loaded = <int, TmdbSeasonMetadata>{};
    await _forEachWithLimit(requested, 4, (seasonNumber) async {
      try {
        loaded[seasonNumber] = await capabilities.seasonDetails(
          metadata.id,
          seasonNumber,
          language: language,
        );
      } on Object {
        final summary = existingByNumber[seasonNumber];
        if (summary != null) loaded[seasonNumber] = summary;
      }
    });
    if (loaded.isEmpty) return metadata;
    final merged = <TmdbSeasonMetadata>[
      ...metadata.seasons,
    ];
    for (final season in loaded.values) {
      final index = merged.indexWhere(
        (item) => item.seasonNumber == season.seasonNumber,
      );
      if (index < 0) {
        merged.add(season);
      } else {
        merged[index] = _mergeSeasonDetails(merged[index], season);
      }
    }
    merged.sort(
      (first, second) => first.seasonNumber.compareTo(second.seasonNumber),
    );
    return metadata.copyWith(seasons: merged);
  }

  Future<TmdbScrapeSearchOutcome> search(
    TmdbScrapeSubject subject,
    TmdbScrapeOptions options, {
    double? minimumScore,
    double? minimumLead,
  }) async {
    final plan = _policy.build(subject, options);
    TmdbScrapeSearchOutcome? fallback;
    for (final query in plan.queries) {
      final candidates = await _searchCandidates(
        query,
        plan.mediaTypes,
        options,
      );
      if (candidates.isEmpty) continue;
      final enriched = await _enrichAliases(candidates, options);
      final ranked = _matcher.rank(
        queryTitle: query,
        queryYear: plan.year,
        expectedTypes: plan.mediaTypes.toSet(),
        seasonEvidence: subject.seasonNumbers.isNotEmpty ||
            subject.episodeNumbers.isNotEmpty,
        candidates: enriched,
        minimumScore: minimumScore ?? options.minimumScore,
        minimumLead: minimumLead ?? options.minimumLead,
      );
      final current = TmdbScrapeSearchOutcome(
        queryTitle: query,
        ranked: ranked,
      );
      if (ranked.shouldAutoMatch) return current;
      final currentScore = ranked.best?.score ?? 0;
      final fallbackScore = fallback?.ranked.best?.score ?? -1;
      if (fallback == null || currentScore > fallbackScore) {
        fallback = current;
      }
    }
    return fallback ??
        const TmdbScrapeSearchOutcome(
          queryTitle: null,
          ranked: TmdbRankedResult(
            candidates: <TmdbRankedCandidate>[],
            shouldAutoMatch: false,
          ),
        );
  }

  Future<List<TmdbMetadata>> _searchCandidates(
    String query,
    List<TmdbMediaType> mediaTypes,
    TmdbScrapeOptions options,
  ) async {
    final candidates = <TmdbMetadata>[];
    final seen = <String>{};
    final capabilities = _client is ITmdbClientCapabilities
        ? _client as ITmdbClientCapabilities
        : null;
    for (final mediaType in mediaTypes) {
      if (capabilities == null) {
        final found = await _client.search(
          query,
          mediaType,
          language: options.language,
        );
        _appendUnique(candidates, seen, found);
        continue;
      }

      final first = await capabilities.searchPage(
        query,
        mediaType,
        language: options.language,
        page: 1,
      );
      _appendUnique(candidates, seen, first.results);
      final lastPage = first.totalPages < options.maximumSearchPages
          ? first.totalPages
          : options.maximumSearchPages;
      for (var page = 2; page <= lastPage; page += 1) {
        final next = await capabilities.searchPage(
          query,
          mediaType,
          language: options.language,
          page: page,
        );
        _appendUnique(candidates, seen, next.results);
      }
    }
    return candidates;
  }

  void _appendUnique(
    List<TmdbMetadata> target,
    Set<String> seen,
    Iterable<TmdbMetadata> values,
  ) {
    for (final candidate in values) {
      final key = '${candidate.mediaType.name}:${candidate.id}';
      if (seen.add(key)) target.add(candidate);
    }
  }

  Future<List<TmdbMetadata>> _enrichAliases(
    List<TmdbMetadata> candidates,
    TmdbScrapeOptions options,
  ) async {
    final capabilities = _client is ITmdbClientCapabilities
        ? _client as ITmdbClientCapabilities
        : null;
    if (capabilities == null || options.maximumAliasCandidates <= 0) {
      return candidates;
    }
    final limit = candidates.length < options.maximumAliasCandidates
        ? candidates.length
        : options.maximumAliasCandidates;
    final enriched = List<TmdbMetadata>.from(candidates);
    await _forEachWithLimit(
      Iterable<int>.generate(limit),
      4,
      (index) async {
        final candidate = candidates[index];
        try {
          final aliases = await capabilities.alternativeTitles(
            candidate.id,
            candidate.mediaType,
            language: options.language,
          );
          if (aliases.isEmpty) return;
          final merged = <String>[];
          for (final value in <String>[...candidate.aliases, ...aliases]) {
            final title = value.trim();
            if (title.isNotEmpty && !merged.contains(title)) merged.add(title);
          }
          enriched[index] = candidate.copyWith(aliases: merged);
        } on Object {
          // 别名只是评分补充，失败时保留主搜索结果。
        }
      },
    );
    return List<TmdbMetadata>.unmodifiable(enriched);
  }

  Future<void> _forEachWithLimit<T>(
    Iterable<T> values,
    int poolSize,
    Future<void> Function(T value) action,
  ) async {
    final list = values.toList(growable: false);
    if (list.isEmpty) return;
    var cursor = 0;
    Future<void> worker() async {
      while (true) {
        final index = cursor;
        cursor += 1;
        if (index >= list.length) return;
        await action(list[index]);
      }
    }
    final workers = <Future<void>>[
      for (var index = 0; index < poolSize && index < list.length; index += 1)
        worker(),
    ];
    await Future.wait(workers);
  }

  TmdbSeasonMetadata _mergeSeasonDetails(
    TmdbSeasonMetadata previous,
    TmdbSeasonMetadata fetched,
  ) {
    final episodes = <int, TmdbEpisodeMetadata>{
      for (final episode in previous.episodes) episode.episodeNumber: episode,
    };
    for (final episode in fetched.episodes) {
      final old = episodes[episode.episodeNumber];
      episodes[episode.episodeNumber] = old == null
          ? episode
          : episode.copyWith(
              name: old.name.trim().isNotEmpty ? old.name : episode.name,
              overview: old.overview?.trim().isNotEmpty == true
                  ? old.overview
                  : episode.overview,
              airDate: old.airDate?.trim().isNotEmpty == true
                  ? old.airDate
                  : episode.airDate,
              stillUrl: old.stillUrl?.trim().isNotEmpty == true
                  ? old.stillUrl
                  : episode.stillUrl,
              rating: episode.rating ?? old.rating,
            );
    }
    final orderedEpisodes = episodes.values.toList(growable: false)
      ..sort(
        (first, second) => first.episodeNumber.compareTo(second.episodeNumber),
      );
    return fetched.copyWith(
      name: fetched.name.trim().isNotEmpty ? fetched.name : previous.name,
      episodeCount: fetched.episodeCount > 0
          ? fetched.episodeCount
          : previous.episodeCount,
      overview: fetched.overview?.trim().isNotEmpty == true
          ? fetched.overview
          : previous.overview,
      airDate: fetched.airDate?.trim().isNotEmpty == true
          ? fetched.airDate
          : previous.airDate,
      posterUrl: fetched.posterUrl ?? previous.posterUrl,
      posterCachePath: previous.posterCachePath ?? fetched.posterCachePath,
      episodes: orderedEpisodes,
    );
  }
}
