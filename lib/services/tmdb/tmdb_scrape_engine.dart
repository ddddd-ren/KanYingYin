import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
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

  Future<TmdbScrapeSearchOutcome> search(
    TmdbScrapeSubject subject,
    TmdbScrapeOptions options, {
    double? minimumScore,
    double? minimumLead,
  }) async {
    final plan = _policy.build(subject, options);
    TmdbScrapeSearchOutcome? fallback;
    for (final query in plan.queries) {
      final candidates = <TmdbMetadata>[];
      final seen = <String>{};
      for (final mediaType in plan.mediaTypes) {
        final found = await _client.search(
          query,
          mediaType,
          language: options.language,
        );
        for (final candidate in found) {
          final key = '${candidate.mediaType.name}:${candidate.id}';
          if (seen.add(key)) candidates.add(candidate);
        }
      }
      if (candidates.isEmpty) continue;
      final ranked = _matcher.rank(
        queryTitle: query,
        queryYear: plan.year,
        expectedTypes: plan.mediaTypes.toSet(),
        candidates: candidates,
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
}
