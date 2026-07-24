import 'package:hive_ce/hive.dart';

/// 为应用设置提供可注入的强类型读写边界。
class TypedSettings {
  const TypedSettings(this._box);

  final Box<Object?> _box;

  T read<T>(String key, {required T defaultValue}) {
    final value = _box.get(key, defaultValue: defaultValue);
    return value is T ? value : defaultValue;
  }

  Object? readRaw(String key, {Object? defaultValue}) =>
      _box.get(key, defaultValue: defaultValue);

  List<T> readList<T>(String key, {required List<T> defaultValue}) {
    final value = _box.get(key, defaultValue: defaultValue);
    if (value is! List<Object?>) return defaultValue;
    final typedValues = value.whereType<T>().toList();
    return typedValues.length == value.length ? typedValues : defaultValue;
  }

  T getTyped<T>(String key, {required T defaultValue}) =>
      read<T>(key, defaultValue: defaultValue);

  List<T> getTypedList<T>(String key, {required List<T> defaultValue}) =>
      readList<T>(key, defaultValue: defaultValue);

  Object? get(String key, {Object? defaultValue}) =>
      readRaw(key, defaultValue: defaultValue);

  Future<void> write<T>(String key, T value) => _box.put(key, value);

  Future<void> put<T>(String key, T value) => write<T>(key, value);

  Future<void> delete(String key) => _box.delete(key);
}

class SettingBoxKey {
  static const String hAenable = 'hAenable',
      hardwareDecoder = 'hardwareDecoder',
      defaultPlaySpeed = 'defaultPlaySpeed',
      defaultShortcutForwardPlaySpeed = 'defaultShortcutForwardPlaySpeed',
      defaultAspectRatioType = 'defaultAspectRatioType',
      buttonSkipTime = 'buttonSkipTime',
      arrowKeySkipTime = 'arrowKeySkipTime',
      themeMode = 'themeMode',
      themeColor = 'themeColor',
      autoPlay = 'autoPlay',
      autoPlayNext = 'autoPlayNext',
      playResume = 'playResume',
      showPlayerError = 'showPlayerError',
      oledEnhance = 'oledEnhance',
      enableSystemProxy = 'enableSystemProxy',
      defaultStartupPage = 'defaultStartupPage',
      lowMemoryMode = 'lowMemoryMode',
      showWindowButton = 'showWindowButton',
      exitBehavior = 'exitBehavior',
      playerDebugMode = 'playerDebugMode',
      defaultSuperResolutionType = 'defaultSuperResolutionType',
      superResolutionWarn = 'superResolutionWarn',
      playerDisableAnimations = 'playerDisableAnimations',
      useSystemFont = 'useSystemFont',
      backgroundPlayback = 'backgroundPlayback',
      proxyEnable = 'proxyEnable',
      proxyConfigured = 'proxyConfigured',
      proxyUrl = 'proxyUrl',
      shortcutDialogShown = 'shortcutDialogShown',
      brightnessVolumeGesture = 'brightnessVolumeGesture',
      localAutoLoadSubtitle = 'localAutoLoadSubtitle',
      subtitleFontSize = 'subtitleFontSize',
      subtitleColor = 'subtitleColor',
      subtitleBorderColor = 'subtitleBorderColor',
      subtitleBorderSize = 'subtitleBorderSize',
      subtitleShadowEnabled = 'subtitleShadowEnabled',
      subtitleShadowOffset = 'subtitleShadowOffset',
      subtitlePosition = 'subtitlePosition',
      subtitleForceStyle = 'subtitleForceStyle',
      subtitleDelayByVideo = 'subtitleDelayByVideo',
      embeddedTrackLanguageOverrides = 'embeddedTrackLanguageOverrides',
      lastLocalDirectory = 'lastLocalDirectory',
      localRecentDirectories = 'localRecentDirectories',
      localMediaSources = 'localMediaSources',
      localMediaIndex = 'localMediaIndex',
      localMediaDirectoryFingerprints = 'localMediaDirectoryFingerprints',
      localSeriesTitleOverrides = 'localSeriesTitleOverrides',
      cloudSources = 'cloudSources',
      cloudMediaIndex = 'cloudMediaIndex',
      cloudResourceTmdbRecords = 'cloudResourceTmdbRecords',
      cloudWorkTmdbRecords = 'cloudWorkTmdbRecords',
      cloudSeriesMatchRules = 'cloudSeriesMatchRules',
      quarkImportHistory = 'quarkImportHistory',
      localDefaultPath = 'localDefaultPath',
      localMinRecognizedVideoSizeBytes = 'localMinRecognizedVideoSizeBytes',
      cloudMinRecognizedVideoSizeBytes = 'cloudMinRecognizedVideoSizeBytes',
      lastSeenVersion = 'lastSeenVersion';
}
