class LocalEpisode {
  final String id;
  final String path;
  final String title;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? subtitlePath;
  final Duration? duration;

  const LocalEpisode({
    required this.id,
    required this.path,
    required this.title,
    this.seasonNumber,
    this.episodeNumber,
    this.subtitlePath,
    this.duration,
  });
}
