import 'package:kanyingyin/modules/bangumi/bangumi_item.dart';
import 'package:kanyingyin/modules/roads/road_module.dart';

class LocalPlaybackRequest {
  final BangumiItem bangumiItem;
  final String pluginName;
  final String title;
  final String videoPath;
  final int currentRoad;
  final int currentEpisode;
  final Road road;
  final String? subtitlePath;

  const LocalPlaybackRequest({
    required this.bangumiItem,
    required this.pluginName,
    required this.title,
    required this.videoPath,
    required this.currentRoad,
    required this.currentEpisode,
    required this.road,
    this.subtitlePath,
  });
}
