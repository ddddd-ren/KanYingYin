import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

class CloudTmdbMatchOutcome {
  const CloudTmdbMatchOutcome({required this.candidates, this.selected});
  final List<TmdbMetadata> candidates;
  final TmdbMetadata? selected;
}

class CloudTmdbMetadataService {
  const CloudTmdbMetadataService({
    required CloudMediaIndexRepository repository,
    required ITmdbClient client,
    CloudPosterCache? posterCache,
  })  : _repository = repository,
        _client = client,
        _posterCache = posterCache;

  final CloudMediaIndexRepository _repository;
  final ITmdbClient _client;
  final CloudPosterCache? _posterCache;

  Future<CloudTmdbMatchOutcome> match({
    required String sourceId,
    required String seriesName,
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final type = options.mediaTypeMode == TmdbMediaTypeMode.movie
        ? TmdbMediaType.movie
        : TmdbMediaType.tv;
    final candidates =
        await _client.search(seriesName, type, language: options.language);
    final result = const TmdbMatcher().choose(
      queryTitle: seriesName,
      expectedType: type,
      candidates: candidates,
      minimumScore: options.minimumScore,
      minimumLead: options.minimumLead,
    );
    if (!result.shouldAutoMatch || result.best == null) {
      return CloudTmdbMatchOutcome(candidates: candidates);
    }
    final selected = await select(
      sourceId: sourceId,
      seriesName: seriesName,
      candidate: result.best!,
      options: options,
    );
    return CloudTmdbMatchOutcome(candidates: candidates, selected: selected);
  }

  Future<CloudTmdbMatchOutcome> searchCandidates({
    required String seriesName,
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final type = options.mediaTypeMode == TmdbMediaTypeMode.movie
        ? TmdbMediaType.movie
        : TmdbMediaType.tv;
    return CloudTmdbMatchOutcome(
      candidates:
          await _client.search(seriesName, type, language: options.language),
    );
  }

  Future<TmdbMetadata> select({
    required String sourceId,
    required String seriesName,
    required TmdbMetadata candidate,
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  }) async {
    final metadata = await _client.details(candidate.id, candidate.mediaType,
        language: options.language);
    String? cachePath;
    final poster = metadata.posterUrl;
    if (_posterCache != null && options.fetchPoster && poster != null) {
      cachePath = await _posterCache.resolve(
        sourceId: sourceId,
        stableId: seriesName.toLowerCase(),
        url: _imageUrl(poster),
      );
      if (cachePath == _imageUrl(poster)) {
        cachePath = null;
      }
    }
    final normalizedSeries = seriesName.trim().toLowerCase();
    final matchedCount = await _repository.updateMatching(
      sourceId,
      (item) => item.seriesName.trim().toLowerCase() == normalizedSeries,
      (item) => item.replaceTmdb(
        tmdbId: metadata.id,
        tmdbTitle: metadata.title,
        tmdbOriginalTitle: metadata.originalTitle,
        tmdbOverview: metadata.overview,
        tmdbRating: metadata.rating,
        tmdbPosterUrl: metadata.posterUrl,
        tmdbBackdropUrl: metadata.backdropUrl,
        posterCachePath: cachePath,
      ),
    );
    if (matchedCount == 0) {
      throw StateError('网盘系列已变化，请刷新媒体库后重试');
    }
    return metadata;
  }

  static String _imageUrl(String value) => value.startsWith('http')
      ? value
      : 'https://image.tmdb.org/t/p/w500$value';
}
