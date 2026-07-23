import 'package:kanyingyin/modules/roads/road_module.dart';
import 'package:kanyingyin/modules/video/playback_media_item.dart';

class LocalPlaybackRequest {
  final PlaybackMediaItem mediaItem;
  final String sourceLabel;
  final String title;
  final String videoPath;
  final int currentRoad;
  final int currentEpisode;
  final Road road;
  final String? subtitlePath;

  const LocalPlaybackRequest({
    required this.mediaItem,
    required this.sourceLabel,
    required this.title,
    required this.videoPath,
    required this.currentRoad,
    required this.currentEpisode,
    required this.road,
    this.subtitlePath,
  });
}
