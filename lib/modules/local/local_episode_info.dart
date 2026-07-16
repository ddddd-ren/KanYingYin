class LocalEpisodeInfo {
  final String seriesName;
  final int? seasonNumber;
  final int episodeNumber;
  final String? episodeTitle;
  final String? releaseGroup;
  final String? resolution;
  final String? source;
  final String? codec;

  const LocalEpisodeInfo({
    required this.seriesName,
    required this.episodeNumber,
    this.seasonNumber,
    this.episodeTitle,
    this.releaseGroup,
    this.resolution,
    this.source,
    this.codec,
  });

  bool get hasSeriesName => seriesName.trim().isNotEmpty;

  String get episodeLabel {
    final episode = episodeNumber.toString().padLeft(2, '0');
    final season = seasonNumber;
    if (season != null && season > 0) {
      return 'S${season.toString().padLeft(2, '0')}E$episode';
    }
    return '\u7b2c $episode \u96c6';
  }

  String get displayTitle {
    final title = episodeTitle?.trim();
    if (title != null && title.isNotEmpty) {
      return '$episodeLabel  $title';
    }
    return episodeLabel;
  }

  String get technicalLabel {
    final parts = [
      releaseGroup,
      resolution,
      source,
      codec,
    ].where((part) => part != null && part.trim().isNotEmpty).cast<String>();
    return parts.join(' · ');
  }
}
