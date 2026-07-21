import 'package:flutter/foundation.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

@immutable
class TmdbMatchDraft {
  const TmdbMatchDraft({
    required this.originalName,
    required this.searchTitle,
    required this.mediaTypeMode,
    this.year,
    this.seasonNumber,
    this.episodeNumber,
  });

  final String originalName;
  final String searchTitle;
  final TmdbMediaTypeMode mediaTypeMode;
  final int? year;
  final int? seasonNumber;
  final int? episodeNumber;
}

@immutable
class TmdbPreparedSearchRequest {
  const TmdbPreparedSearchRequest({
    required this.queryTitle,
    required this.mediaTypeMode,
    required this.options,
    this.queryYear,
  });

  final String queryTitle;
  final int? queryYear;
  final TmdbMediaTypeMode mediaTypeMode;
  final TmdbScrapeOptions options;
}

@immutable
class TmdbPreparedSearchOutcome {
  const TmdbPreparedSearchOutcome({required this.ranked});

  final TmdbRankedResult ranked;
}
