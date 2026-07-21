import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

class TmdbPosterPolicy {
  const TmdbPosterPolicy();

  String? select(
    TmdbMetadata metadata, {
    required int? seasonNumber,
    required TmdbScrapeOptions options,
    TmdbFieldLocks locks = const TmdbFieldLocks(),
    String? existingPoster,
  }) {
    if (!options.fetchPoster || locks.poster || !options.overwritePoster) {
      return _normalized(existingPoster);
    }
    if (metadata.mediaType == TmdbMediaType.tv && seasonNumber != null) {
      for (final season in metadata.seasons) {
        if (season.seasonNumber != seasonNumber) continue;
        final poster = _normalized(season.posterCachePath) ??
            _normalized(season.posterUrl);
        if (poster != null) return poster;
      }
    }
    return _normalized(metadata.posterUrl);
  }

  String? _normalized(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
