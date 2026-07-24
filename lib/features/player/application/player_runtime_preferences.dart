import 'package:kanyingyin/features/player/application/anime4k_policy.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/utils/constants.dart';

class PlayerRuntimeSettings {
  const PlayerRuntimeSettings({
    required this.playSpeed,
    required this.aspectRatioType,
    required this.buttonSkipTime,
    required this.arrowKeySkipTime,
    required this.anime4kPreference,
    required this.hardwareAccelerationEnabled,
    required this.hardwareDecoder,
    required this.autoPlay,
    required this.lowMemoryMode,
    required this.debugMode,
    required this.proxyEnabled,
    required this.proxyUrl,
    required this.showPlayerError,
  });

  final double playSpeed;
  final int aspectRatioType;
  final int buttonSkipTime;
  final int arrowKeySkipTime;
  final Anime4kPreference anime4kPreference;
  final bool hardwareAccelerationEnabled;
  final String hardwareDecoder;
  final bool autoPlay;
  final bool lowMemoryMode;
  final bool debugMode;
  final bool proxyEnabled;
  final String proxyUrl;
  final bool showPlayerError;
}

/// 集中读取播放器启动所需设置，避免控制器直接了解持久化键。
class PlayerRuntimePreferences {
  const PlayerRuntimePreferences(this._settings);

  final TypedSettings _settings;

  PlayerRuntimeSettings load() {
    final decoder = normalizeHardwareDecoder(
      _settings.getTyped<String>(
        SettingBoxKey.hardwareDecoder,
        defaultValue: defaultHardwareDecoder,
      ),
    );
    final accelerationEnabled = _settings.getTyped<bool>(
          SettingBoxKey.hAenable,
          defaultValue: true,
        ) &&
        decoder != 'no';
    return PlayerRuntimeSettings(
      playSpeed: _settings.getTyped<double>(
        SettingBoxKey.defaultPlaySpeed,
        defaultValue: 1.0,
      ),
      aspectRatioType: _settings.getTyped<int>(
        SettingBoxKey.defaultAspectRatioType,
        defaultValue: 1,
      ),
      buttonSkipTime: _settings.getTyped<int>(
        SettingBoxKey.buttonSkipTime,
        defaultValue: 80,
      ),
      arrowKeySkipTime: _settings.getTyped<int>(
        SettingBoxKey.arrowKeySkipTime,
        defaultValue: 10,
      ),
      anime4kPreference: switch (_settings.getTyped<int>(
        SettingBoxKey.defaultSuperResolutionType,
        defaultValue: 1,
      )) {
        2 => Anime4kPreference.efficiency,
        3 => Anime4kPreference.quality,
        _ => Anime4kPreference.off,
      },
      hardwareAccelerationEnabled: accelerationEnabled,
      hardwareDecoder: decoder,
      autoPlay: _settings.getTyped<bool>(
        SettingBoxKey.autoPlay,
        defaultValue: true,
      ),
      lowMemoryMode: _settings.getTyped<bool>(
        SettingBoxKey.lowMemoryMode,
        defaultValue: false,
      ),
      debugMode: _settings.getTyped<bool>(
        SettingBoxKey.playerDebugMode,
        defaultValue: false,
      ),
      proxyEnabled: _settings.getTyped<bool>(
        SettingBoxKey.proxyEnable,
        defaultValue: false,
      ),
      proxyUrl: _settings.getTyped<String>(
        SettingBoxKey.proxyUrl,
        defaultValue: '',
      ),
      showPlayerError: _settings.getTyped<bool>(
        SettingBoxKey.showPlayerError,
        defaultValue: true,
      ),
    );
  }

  Future<void> saveButtonSkipTime(int seconds) =>
      _settings.put(SettingBoxKey.buttonSkipTime, seconds);

  Future<void> saveArrowKeySkipTime(int seconds) =>
      _settings.put(SettingBoxKey.arrowKeySkipTime, seconds);
}
