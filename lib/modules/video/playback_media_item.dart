class PlaybackMediaItem {
  const PlaybackMediaItem({
    required this.id,
    required this.title,
    required this.displayTitle,
    this.summary = '',
    this.artworkUrl,
  });

  final int id;
  final String title;
  final String displayTitle;
  final String summary;
  final String? artworkUrl;

  String get effectiveTitle =>
      displayTitle.trim().isNotEmpty ? displayTitle : title;

  @override
  bool operator ==(Object other) =>
      other is PlaybackMediaItem &&
      id == other.id &&
      title == other.title &&
      displayTitle == other.displayTitle &&
      summary == other.summary &&
      artworkUrl == other.artworkUrl;

  @override
  int get hashCode => Object.hash(id, title, displayTitle, summary, artworkUrl);
}
