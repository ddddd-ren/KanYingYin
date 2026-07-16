enum CloudMediaType { movie, series, episode, special, unknown }

class CloudMediaIndexItem {
  const CloudMediaIndexItem({
    required this.sourceId,
    required this.remoteId,
    required this.remotePath,
    required this.name,
    required this.size,
    required this.modifiedAt,
    required this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    this.mediaType = CloudMediaType.unknown,
    this.subtitlePaths = const <String>[],
    this.tmdbId,
    this.tmdbTitle,
    this.tmdbOriginalTitle,
    this.tmdbOverview,
    this.tmdbRating,
    this.tmdbPosterUrl,
    this.tmdbBackdropUrl,
    this.posterCachePath,
  });

  final String sourceId;
  final String remoteId;
  final String remotePath;
  final String name;
  final int size;
  final DateTime? modifiedAt;
  final String seriesName;
  final int? seasonNumber;
  final int? episodeNumber;
  final CloudMediaType mediaType;
  final List<String> subtitlePaths;
  final int? tmdbId;
  final String? tmdbTitle;
  final String? tmdbOriginalTitle;
  final String? tmdbOverview;
  final double? tmdbRating;
  final String? tmdbPosterUrl;
  final String? tmdbBackdropUrl;
  final String? posterCachePath;

  CloudMediaIndexItem copyWith({
    int? tmdbId,
    String? tmdbTitle,
    String? tmdbOriginalTitle,
    String? tmdbOverview,
    double? tmdbRating,
    String? tmdbPosterUrl,
    String? tmdbBackdropUrl,
    String? posterCachePath,
  }) =>
      CloudMediaIndexItem(
        sourceId: sourceId,
        remoteId: remoteId,
        remotePath: remotePath,
        name: name,
        size: size,
        modifiedAt: modifiedAt,
        seriesName: seriesName,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        mediaType: mediaType,
        subtitlePaths: subtitlePaths,
        tmdbId: tmdbId ?? this.tmdbId,
        tmdbTitle: tmdbTitle ?? this.tmdbTitle,
        tmdbOriginalTitle: tmdbOriginalTitle ?? this.tmdbOriginalTitle,
        tmdbOverview: tmdbOverview ?? this.tmdbOverview,
        tmdbRating: tmdbRating ?? this.tmdbRating,
        tmdbPosterUrl: tmdbPosterUrl ?? this.tmdbPosterUrl,
        tmdbBackdropUrl: tmdbBackdropUrl ?? this.tmdbBackdropUrl,
        posterCachePath: posterCachePath ?? this.posterCachePath,
      );

  CloudMediaIndexItem replaceTmdb({
    required int tmdbId,
    required String tmdbTitle,
    String? tmdbOriginalTitle,
    String? tmdbOverview,
    double? tmdbRating,
    String? tmdbPosterUrl,
    String? tmdbBackdropUrl,
    String? posterCachePath,
  }) =>
      CloudMediaIndexItem(
        sourceId: sourceId,
        remoteId: remoteId,
        remotePath: remotePath,
        name: name,
        size: size,
        modifiedAt: modifiedAt,
        seriesName: seriesName,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        mediaType: mediaType,
        subtitlePaths: subtitlePaths,
        tmdbId: tmdbId,
        tmdbTitle: tmdbTitle,
        tmdbOriginalTitle: tmdbOriginalTitle,
        tmdbOverview: tmdbOverview,
        tmdbRating: tmdbRating,
        tmdbPosterUrl: tmdbPosterUrl,
        tmdbBackdropUrl: tmdbBackdropUrl,
        posterCachePath: posterCachePath,
      );
}
