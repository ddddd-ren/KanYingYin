import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

class TmdbMetadataMergePolicy {
  const TmdbMetadataMergePolicy();

  TmdbMetadata merge({
    TmdbMetadata? existing,
    required TmdbMetadata fetched,
    required TmdbScrapeOptions options,
    TmdbFieldLocks locks = const TmdbFieldLocks(),
    required double matchConfidence,
    Set<int> existingSeasons = const <int>{},
  }) {
    final preserveTitle =
        existing != null && (locks.title || !options.overwriteTitle);
    final preserveOverview =
        existing != null && (locks.overview || !options.overwriteOverview);
    final preservePoster =
        existing != null && (locks.poster || !options.overwritePoster);
    final seasons = fetched.seasons
        .where(
          (season) =>
              existingSeasons.isEmpty ||
              existingSeasons.contains(season.seasonNumber),
        )
        .toList(growable: false)
      ..sort(
        (first, second) => first.seasonNumber.compareTo(second.seasonNumber),
      );
    final resolvedSeasons = !options.fetchPoster || preservePoster
        ? _preserveSeasonPosters(seasons, existing?.seasons ?? const [])
        : seasons;

    return TmdbMetadata(
      id: fetched.id,
      mediaType: fetched.mediaType,
      title: preserveTitle ? existing.title : fetched.title,
      originalTitle:
          preserveTitle ? existing.originalTitle : fetched.originalTitle,
      overview: preserveOverview ? existing.overview : fetched.overview,
      releaseDate: fetched.releaseDate,
      rating: fetched.rating,
      posterUrl: options.fetchPoster
          ? (preservePoster ? existing.posterUrl : fetched.posterUrl)
          : existing?.posterUrl,
      backdropUrl:
          options.fetchBackdrop ? fetched.backdropUrl : existing?.backdropUrl,
      language: fetched.language,
      matchedAt: fetched.matchedAt,
      matchConfidence: matchConfidence,
      seasons: resolvedSeasons,
    );
  }

  List<TmdbSeasonMetadata> _preserveSeasonPosters(
    List<TmdbSeasonMetadata> fetched,
    List<TmdbSeasonMetadata> existing,
  ) {
    final existingByNumber = <int, TmdbSeasonMetadata>{
      for (final season in existing) season.seasonNumber: season,
    };
    return fetched.map((season) {
      final previous = existingByNumber[season.seasonNumber];
      if (previous == null) {
        return TmdbSeasonMetadata(
          id: season.id,
          seasonNumber: season.seasonNumber,
          name: season.name,
          episodeCount: season.episodeCount,
          overview: season.overview,
          airDate: season.airDate,
        );
      }
      return TmdbSeasonMetadata(
        id: season.id,
        seasonNumber: season.seasonNumber,
        name: season.name,
        episodeCount: season.episodeCount,
        overview: season.overview,
        airDate: season.airDate,
        posterUrl: previous.posterUrl,
        posterCachePath: previous.posterCachePath,
      );
    }).toList(growable: false);
  }
}
