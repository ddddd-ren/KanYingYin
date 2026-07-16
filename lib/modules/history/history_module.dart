import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/modules/bangumi/bangumi_item.dart';

part 'history_module.g.dart';

enum HistorySourceType {
  online('online'),
  local('local'),
  cloud('cloud');

  const HistorySourceType(this.value);

  final String value;

  static HistorySourceType fromValue(String value) {
    return HistorySourceType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => HistorySourceType.online,
    );
  }
}

@HiveType(typeId: 1)
class History {
  @HiveField(0)
  Map<int, Progress> progresses = {};

  @HiveField(1)
  int lastWatchEpisode;

  @HiveField(2)
  String adapterName;

  @HiveField(3)
  BangumiItem bangumiItem;

  @HiveField(4)
  DateTime lastWatchTime;

  @HiveField(5)
  String lastSrc;

  @HiveField(6, defaultValue: '')
  String lastWatchEpisodeName;

  @HiveField(7, defaultValue: 'online')
  String sourceType;

  String get key => adapterName + bangumiItem.id.toString();

  bool get isLocal =>
      HistorySourceType.fromValue(sourceType) == HistorySourceType.local;

  History(
    this.bangumiItem,
    this.lastWatchEpisode,
    this.adapterName,
    this.lastWatchTime,
    this.lastSrc,
    this.lastWatchEpisodeName, {
    this.sourceType = 'online',
  });

  static String getKey(String n, BangumiItem s) => n + s.id.toString();

  @override
  String toString() {
    return 'Adapter: $adapterName, anime: ${bangumiItem.name}';
  }
}

@HiveType(typeId: 2)
class Progress {
  @HiveField(0)
  int episode;

  @HiveField(1)
  int road;

  @HiveField(2)
  int _progressInMilli;

  Duration get progress => Duration(milliseconds: _progressInMilli);

  set progress(Duration d) => _progressInMilli = d.inMilliseconds;

  Progress(this.episode, this.road, this._progressInMilli);

  @override
  String toString() {
    return 'Episode ${episode.toString()}, progress $progress';
  }
}
