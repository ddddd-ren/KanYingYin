import 'package:kanyingyin/modules/bangumi/bangumi_item.dart';
import 'package:kanyingyin/modules/roads/road_module.dart';
import 'package:mobx/mobx.dart';

/// VideoPageController 的抽象接口，供 player/ 层依赖
/// 避免 player/ 直接耦合 video/ 的具体实现
abstract class IVideoPageController {
  BangumiItem get bangumiItem;
  String get title;

  ObservableList<Road> get roadList;
  int get currentEpisode;
  int get currentRoad;
  bool get loading;
  String? get errorMessage;
  bool get isFullscreen;
  bool get isPip;
  bool get showTabBody;
  int get actualEpisodeNumber;
  bool get isCloudPlayback;

  set isFullscreen(bool value);
  set isPip(bool value);
  set showTabBody(bool value);
  set currentEpisode(int value);
  set currentRoad(int value);
  set loading(bool value);
  set errorMessage(String? value);

  Future<void> changeEpisode(int episode, {int currentRoad, int offset});
  void cancelQueryRoads();
  void enterFullScreen();
  void exitFullScreen();
}
