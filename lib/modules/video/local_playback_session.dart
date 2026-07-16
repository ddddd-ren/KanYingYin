import 'package:kanyingyin/modules/local/local_episode.dart';

class LocalPlaybackSession {
  final String seriesId;
  final String seriesTitle;
  final List<LocalEpisode> episodes;
  final String currentEpisodeId;
  final String? coverPath;

  LocalPlaybackSession({
    required this.seriesId,
    required this.seriesTitle,
    required List<LocalEpisode> episodes,
    required this.currentEpisodeId,
    this.coverPath,
  }) : episodes = List<LocalEpisode>.unmodifiable(episodes) {
    if (episodes.isEmpty) {
      throw ArgumentError.value(episodes, 'episodes', '播放列表不能为空');
    }
    if (!episodes.any((episode) => episode.id == currentEpisodeId)) {
      throw ArgumentError.value(
        currentEpisodeId,
        'currentEpisodeId',
        '当前剧集不在播放列表中',
      );
    }
  }

  int get currentIndex =>
      episodes.indexWhere((episode) => episode.id == currentEpisodeId);

  LocalEpisode get currentEpisode => episodes[currentIndex];

  LocalEpisode? get previousEpisode =>
      currentIndex > 0 ? episodes[currentIndex - 1] : null;

  LocalEpisode? get nextEpisode =>
      currentIndex + 1 < episodes.length ? episodes[currentIndex + 1] : null;

  LocalPlaybackSession selectEpisode(String episodeId) {
    return LocalPlaybackSession(
      seriesId: seriesId,
      seriesTitle: seriesTitle,
      episodes: episodes,
      currentEpisodeId: episodeId,
      coverPath: coverPath,
    );
  }
}
