import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/tmdb_metadata_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';

class TmdbScrapeResult {
  final TmdbScrapeStatus status;
  final TmdbMetadata? metadata;
  final List<TmdbMetadata> candidates;
  final Object? error;
  final int posterDownloadFailures;

  const TmdbScrapeResult({
    required this.status,
    this.metadata,
    this.candidates = const [],
    this.error,
    this.posterDownloadFailures = 0,
  });
}

class TmdbScraper {
  final ITmdbClient client;
  final ITmdbMetadataRepository repository;
  final TmdbMatcher matcher;

  const TmdbScraper({
    required this.client,
    required this.repository,
    this.matcher = const TmdbMatcher(),
  });

  Future<TmdbScrapeResult> scrape({
    required String mediaKey,
    required String title,
    required TmdbMediaType mediaType,
    int? year,
    String language = 'zh-CN',
    double minimumScore = 0.8,
    double minimumLead = 0.1,
  }) async {
    try {
      final candidates = await client.search(
        title,
        mediaType,
        language: language,
      );
      final match = matcher.choose(
        queryTitle: title,
        queryYear: year,
        expectedType: mediaType,
        candidates: candidates,
        minimumScore: minimumScore,
        minimumLead: minimumLead,
      );
      if (!match.shouldAutoMatch || match.best == null) {
        return TmdbScrapeResult(
          status: TmdbScrapeStatus.pending,
          candidates: candidates,
        );
      }
      final details = await client.details(
        match.best!.id,
        mediaType,
        language: language,
      );
      final metadata = details.copyWith(matchConfidence: match.confidence);
      await repository.save(mediaKey, metadata);
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.matched,
        metadata: metadata,
        candidates: candidates,
      );
    } catch (error) {
      return TmdbScrapeResult(
        status: TmdbScrapeStatus.failed,
        error: error,
      );
    }
  }
}
