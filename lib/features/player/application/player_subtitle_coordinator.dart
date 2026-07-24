import 'package:kanyingyin/features/player/application/subtitle_preferences.dart';

/// 统一字幕样式和按媒体延迟的持久化入口。
class PlayerSubtitleCoordinator {
  const PlayerSubtitleCoordinator(this._preferences);

  final SubtitlePreferences _preferences;

  SubtitleStyleSettings loadStyle() => _preferences.loadStyle();

  Future<void> saveStyle(SubtitleStyleSettings settings) =>
      _preferences.saveStyle(settings);

  double loadDelay(String? mediaKey) => mediaKey == null || mediaKey.isEmpty
      ? 0
      : _preferences.loadDelay(mediaKey);

  Future<void> saveDelay(String? mediaKey, double seconds) =>
      mediaKey == null || mediaKey.isEmpty
          ? Future<void>.value()
          : _preferences.saveDelay(mediaKey, seconds);
}
