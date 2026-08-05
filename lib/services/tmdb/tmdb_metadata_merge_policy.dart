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
    final resolvedSeasons = _mergeSeasons(
      seasons,
      existing?.seasons ?? const <TmdbSeasonMetadata>[],
      preservePosters: !options.fetchPoster || preservePoster,
      scrapeEpisodeNames: options.scrapeEpisodeNames,
      allowedSeasonNumbers: existingSeasons,
    );

    return TmdbMetadata(
      id: fetched.id,
      mediaType: fetched.mediaType,
      title: preserveTitle ? existing.title : fetched.title,
      originalTitle:
          preserveTitle ? existing.originalTitle : fetched.originalTitle,
      overview: preserveOverview ? existing.overview : fetched.overview,
      releaseDate: fetched.releaseDate,
      rating: fetched.rating ?? existing?.rating,
      aliases:
          _mergeStrings(existing?.aliases ?? const <String>[], fetched.aliases),
      popularity: fetched.popularity ?? existing?.popularity,
      voteCount: fetched.voteCount ?? existing?.voteCount,
      posterUrl: options.fetchPoster
          ? (preservePoster ? existing.posterUrl : fetched.posterUrl)
          : existing?.posterUrl,
      backdropUrl:
          options.fetchBackdrop ? fetched.backdropUrl : existing?.backdropUrl,
      language: fetched.language,
      matchedAt: fetched.matchedAt,
      matchConfidence: matchConfidence,
      genres: fetched.genres,
      seasons: resolvedSeasons,
    );
  }

  List<TmdbSeasonMetadata> _mergeSeasons(
    List<TmdbSeasonMetadata> fetched,
    List<TmdbSeasonMetadata> existing, {
    required bool preservePosters,
    required bool scrapeEpisodeNames,
    required Set<int> allowedSeasonNumbers,
  }) {
    final byNumber = <int, TmdbSeasonMetadata>{
      for (final season in existing)
        if (allowedSeasonNumbers.isEmpty ||
            allowedSeasonNumbers.contains(season.seasonNumber))
          season.seasonNumber: season,
    };
    for (final season in fetched) {
      if (allowedSeasonNumbers.isNotEmpty &&
          !allowedSeasonNumbers.contains(season.seasonNumber)) {
        continue;
      }
      final previous = byNumber[season.seasonNumber];
      if (previous == null) {
        final episodes = _mergeEpisodes(
          season.episodes,
          const <TmdbEpisodeMetadata>[],
          scrapeEpisodeNames: scrapeEpisodeNames,
        );
        byNumber[season.seasonNumber] = preservePosters
            ? TmdbSeasonMetadata(
                id: season.id,
                seasonNumber: season.seasonNumber,
                name: season.name,
                episodeCount: season.episodeCount,
                overview: season.overview,
                airDate: season.airDate,
                episodes: episodes,
              )
            : season.copyWith(episodes: episodes);
        continue;
      }
      byNumber[season.seasonNumber] = _mergeSeason(
        season,
        previous,
        preservePosters: preservePosters,
        scrapeEpisodeNames: scrapeEpisodeNames,
      );
    }
    final result = byNumber.values.toList(growable: false)
      ..sort(
        (first, second) => first.seasonNumber.compareTo(second.seasonNumber),
      );
    return result;
  }

  TmdbSeasonMetadata _mergeSeason(
    TmdbSeasonMetadata fetched,
    TmdbSeasonMetadata existing, {
    required bool preservePosters,
    required bool scrapeEpisodeNames,
  }) {
    final posterUrl = preservePosters
        ? existing.posterUrl
        : (fetched.posterUrl ?? existing.posterUrl);
    final posterCachePath = preservePosters
        ? existing.posterCachePath
        : (fetched.posterCachePath ?? existing.posterCachePath);
    return TmdbSeasonMetadata(
      id: fetched.id,
      seasonNumber: fetched.seasonNumber,
      name: existing.name.trim().isNotEmpty ? existing.name : fetched.name,
      episodeCount: fetched.episodeCount > 0
          ? fetched.episodeCount
          : existing.episodeCount,
      overview: existing.overview?.trim().isNotEmpty == true
          ? existing.overview
          : fetched.overview,
      airDate: existing.airDate?.trim().isNotEmpty == true
          ? existing.airDate
          : fetched.airDate,
      posterUrl: posterUrl,
      posterCachePath: posterCachePath,
      episodes: _mergeEpisodes(
        fetched.episodes,
        existing.episodes,
        scrapeEpisodeNames: scrapeEpisodeNames,
      ),
    );
  }

  List<TmdbEpisodeMetadata> _mergeEpisodes(
      List<TmdbEpisodeMetadata> fetched, List<TmdbEpisodeMetadata> existing,
      {required bool scrapeEpisodeNames}) {
    final byNumber = <int, TmdbEpisodeMetadata>{
      for (final episode in existing) episode.episodeNumber: episode,
    };
    for (final episode in fetched) {
      final previous = byNumber[episode.episodeNumber];
      if (previous == null) {
        byNumber[episode.episodeNumber] = episode.copyWith(
          name: scrapeEpisodeNames ? episode.name : '',
        );
        continue;
      }
      byNumber[episode.episodeNumber] = episode.copyWith(
        name: scrapeEpisodeNames ? episode.name : '',
        overview: previous.overview?.trim().isNotEmpty == true
            ? previous.overview
            : episode.overview,
        airDate: previous.airDate?.trim().isNotEmpty == true
            ? previous.airDate
            : episode.airDate,
        stillUrl: previous.stillUrl?.trim().isNotEmpty == true
            ? previous.stillUrl
            : episode.stillUrl,
        rating: episode.rating ?? previous.rating,
      );
    }
    if (!scrapeEpisodeNames) {
      for (final entry in byNumber.entries) {
        byNumber[entry.key] = entry.value.copyWith(name: '');
      }
    }
    final result = byNumber.values.toList(growable: false)
      ..sort(
        (first, second) => first.episodeNumber.compareTo(second.episodeNumber),
      );
    return result;
  }

  List<String> _mergeStrings(List<String> first, List<String> second) {
    final result = <String>[];
    for (final value in <String>[...first, ...second]) {
      final normalized = value.trim();
      if (normalized.isNotEmpty && !result.contains(normalized)) {
        result.add(normalized);
      }
    }
    return List<String>.unmodifiable(result);
  }
}
