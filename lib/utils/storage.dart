// ignore_for_file: avoid_print

import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/utils/legacy_history_data_cleaner.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kanyingyin/legacy/hive/legacy_bangumi_tag_adapter.dart';
import 'package:kanyingyin/legacy/hive/legacy_playback_media_item_adapter.dart';
import 'package:kanyingyin/utils/app_identity.dart';

class GStorage {
  static late final Box<Object?> setting;

  /// Hive directory path, initialized during init()
  static String? _hivePath;

  static Future<void> init() async {
    _hivePath =
        '${(await getApplicationSupportDirectory()).path}/${AppIdentity.storageNamespace}/hive';

    try {
      await LegacyHistoryDataCleaner.deleteFrom(Directory(_hivePath!));
    } catch (error, stackTrace) {
      AppLogger().w(
        'GStorage: failed to delete legacy history data',
        error: error,
        stackTrace: stackTrace,
      );
    }

    Hive.registerAdapter(LegacyPlaybackMediaItemAdapter());
    Hive.registerAdapter(LegacyBangumiTagAdapter());

    // Open each box with automatic recovery on corruption
    setting = await _openBoxSafe<Object?>('setting');
  }

  /// Open a Hive box with automatic recovery on corruption.
  /// If the box is corrupted, delete it and create a new empty one.
  static Future<Box<T>> _openBoxSafe<T>(String boxName) async {
    try {
      return await Hive.openBox<T>(boxName);
    } catch (e) {
      AppLogger().e('GStorage: Box "$boxName" corrupted, attempting recovery',
          error: e);

      // Delete the corrupted box files
      await _deleteBoxFiles(boxName);

      // Try to open again (will create a new empty box)
      try {
        final box = await Hive.openBox<T>(boxName);
        AppLogger()
            .i('GStorage: Box "$boxName" recovered successfully (data lost)');
        return box;
      } catch (e2) {
        AppLogger().e('GStorage: Failed to recover box "$boxName"', error: e2);
        rethrow;
      }
    }
  }

  /// Delete Hive box files for a given box name
  static Future<void> _deleteBoxFiles(String boxName) async {
    if (_hivePath == null) return;

    final boxFile = File('$_hivePath/$boxName.hive');
    final lockFile = File('$_hivePath/$boxName.lock');

    try {
      if (await boxFile.exists()) {
        await boxFile.delete();
        AppLogger().i('GStorage: Deleted corrupted box file: $boxName.hive');
      }
      if (await lockFile.exists()) {
        await lockFile.delete();
        AppLogger().i('GStorage: Deleted lock file: $boxName.lock');
      }
    } catch (e) {
      AppLogger()
          .e('GStorage: Failed to delete box files for "$boxName"', error: e);
    }
  }

  // Prevent instantiation
  GStorage._();
}

extension TypedSettingsBox on Box<Object?> {
  T getTyped<T>(Object? key, {required T defaultValue}) {
    final value = get(key, defaultValue: defaultValue);
    return value is T ? value : defaultValue;
  }

  List<T> getTypedList<T>(Object? key, {required List<T> defaultValue}) {
    final value = get(key, defaultValue: defaultValue);
    if (value is! List<Object?>) return defaultValue;
    final typedValues = value.whereType<T>().toList();
    return typedValues.length == value.length ? typedValues : defaultValue;
  }
}

class SettingBoxKey {
  static const String hAenable = 'hAenable',
      hardwareDecoder = 'hardwareDecoder',
      searchEnhanceEnable = 'searchEnhanceEnable',
      autoUpdate = 'autoUpdate',
      alwaysOntop = 'alwaysOntop',
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
      enableGitProxy = 'enableGitProxy',
      enableSystemProxy = 'enableSystemProxy',
      defaultStartupPage = 'defaultStartupPage',

      /// Deprecated
      isWideScreen = 'isWideScreen',
      webDavEnable = 'webDavEnable',
      webDavEnableHistory = 'webDavEnableHistory',
      webDavEnableCollect = 'webDavEnableCollect',
      webDavURL = 'webDavURL',
      webDavUsername = 'webDavUsername',
      webDavPassword = 'webDavPasswd',
      lowMemoryMode = 'lowMemoryMode',
      showWindowButton = 'showWindowButton',
      exitBehavior = 'exitBehavior',
      playerDebugMode = 'playerDebugMode',
      syncPlayEndPoint = 'syncPlayEndPoint',
      defaultSuperResolutionType = 'defaultSuperResolutionType',
      superResolutionWarn = 'superResolutionWarn',
      playerDisableAnimations = 'playerDisableAnimations',
      playerLogLevel = 'playerLogLevel',
      searchNotShowWatchedBangumis = 'searchNotShowWatchedBangumis',
      searchNotShowAbandonedBangumis = 'searchNotShowAbandonedBangumis',
      timelineNotShowAbandonedBangumis = 'timelineNotShowAbandonedBangumis',
      timelineNotShowWatchedBangumis = 'timelineNotShowWatchedBangumis',
      timelineOnlyShowWatchingBangumis = 'timelineOnlyShowWatchingBangumis',
      useSystemFont = 'useSystemFont',
      forceAdBlocker = 'forceAdBlocker',
      backgroundPlayback = 'backgroundPlayback',
      proxyEnable = 'proxyEnable',
      proxyConfigured = 'proxyConfigured',
      proxyUrl = 'proxyUrl',
      proxyTestUrl = 'proxyTestUrl',
      showRating = 'showRating',
      downloadParallelEpisodes = 'downloadParallelEpisodes',
      downloadParallelSegments = 'downloadParallelSegments',
      shortcutDialogShown = 'shortcutDialogShown',
      bangumiSyncEnable = 'bangumiSyncEnable',
      bangumiAccessToken = 'bangumiAccessToken',
      bangumiSyncPriority = 'bangumiSyncPriority',
      bangumiImmediateSyncToastEnable = 'bangumiImmediateSyncToastEnable',
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
