import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/tmdb_metadata_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_engine.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

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

  const TmdbScraper({
    required this.client,
    required this.repository,
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
      final options = TmdbScrapeOptions(
        language: language,
        mediaTypeMode: mediaType == TmdbMediaType.movie
            ? TmdbMediaTypeMode.movie
            : TmdbMediaTypeMode.tv,
        confidenceMode: TmdbConfidenceMode.standard,
        overwriteTitle: false,
        overwriteOverview: true,
        overwritePoster: true,
        fetchPoster: true,
        fetchBackdrop: true,
      );
      final outcome = await TmdbScrapeEngine(client: client).search(
        TmdbScrapeSubject(
          stableKey: mediaKey,
          titleCandidates: <String>[title],
          year: year,
          mediaEvidence: mediaType == TmdbMediaType.movie
              ? TmdbMediaEvidence.movie
              : TmdbMediaEvidence.tv,
        ),
        options,
        minimumScore: minimumScore,
        minimumLead: minimumLead,
      );
      final candidates = outcome.ranked.candidates
          .map((candidate) => candidate.metadata)
          .toList(growable: false);
      final best = outcome.ranked.best;
      if (!outcome.ranked.shouldAutoMatch || best == null) {
        return TmdbScrapeResult(
          status: TmdbScrapeStatus.pending,
          candidates: candidates,
        );
      }
      final details = await client.details(
        best.metadata.id,
        best.metadata.mediaType,
        language: language,
      );
      final metadata = details.copyWith(matchConfidence: best.score);
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
