// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mobx/mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:kanyingyin/utils/proxy_utils.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:kanyingyin/utils/constants.dart';
import 'package:kanyingyin/shaders/shaders_controller.dart';
import 'package:kanyingyin/services/local_subtitle_importer.dart';
import 'package:kanyingyin/services/local_subtitle_matcher.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/features/player/application/subtitle_preferences.dart';
import 'package:kanyingyin/features/player/application/truehd_fallback_policy.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';
import 'package:kanyingyin/utils/external_player.dart';
import 'package:kanyingyin/utils/media_uri_utils.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher_string.dart';
import 'package:synchronized/synchronized.dart';

part 'player_controller.g.dart';

class _PlayerInitializationCancelled implements Exception {
  const _PlayerInitializationCancelled();
}

bool shouldApplyPlayerProxy({
  required bool proxyEnabled,
  required PlaybackNetworkRoute networkRoute,
}) =>
    proxyEnabled && networkRoute == PlaybackNetworkRoute.inheritProxy;

class PlaybackInitParams {
  final String videoUrl;
  final int offset;
  final bool isLocalPlayback;
  final int bangumiId;
  final String pluginName;
  final int episode;
  final Map<String, String> httpHeaders;
  final bool adBlockerEnabled;
  final String episodeTitle;
  final String referer;
  final int currentRoad;
  final String? coverUrl;
  final String? bangumiName;
  final String? subtitlePath;
  final String? subtitleStorageKey;
  final String? stableMediaKey;
  final PlaybackNetworkRoute networkRoute;
  final String? cloudProviderName;
  final Future<PlaybackInitParams> Function()? refreshCloudPlayback;

  const PlaybackInitParams({
    required this.videoUrl,
    required this.offset,
    required this.isLocalPlayback,
    required this.bangumiId,
    required this.pluginName,
    required this.episode,
    required this.httpHeaders,
    required this.adBlockerEnabled,
    required this.episodeTitle,
    required this.referer,
    required this.currentRoad,
    this.coverUrl,
    this.bangumiName,
    this.subtitlePath,
    this.subtitleStorageKey,
    this.stableMediaKey,
    this.networkRoute = PlaybackNetworkRoute.inheritProxy,
    this.cloudProviderName,
    this.refreshCloudPlayback,
  });

  PlaybackInitParams withOffset(int value) => PlaybackInitParams(
        videoUrl: videoUrl,
        offset: value,
        isLocalPlayback: isLocalPlayback,
        bangumiId: bangumiId,
        pluginName: pluginName,
        episode: episode,
        httpHeaders: httpHeaders,
        adBlockerEnabled: adBlockerEnabled,
        episodeTitle: episodeTitle,
        referer: referer,
        currentRoad: currentRoad,
        coverUrl: coverUrl,
        bangumiName: bangumiName,
        subtitlePath: subtitlePath,
        subtitleStorageKey: subtitleStorageKey,
        stableMediaKey: stableMediaKey,
        networkRoute: networkRoute,
        cloudProviderName: cloudProviderName,
        refreshCloudPlayback: refreshCloudPlayback,
      );
}

PlaybackInitParams mergeRefreshedCloudPlayback({
  required PlaybackInitParams previous,
  required PlaybackInitParams refreshed,
  required Duration position,
}) =>
    PlaybackInitParams(
      videoUrl: refreshed.videoUrl,
      offset: position.inSeconds,
      isLocalPlayback: refreshed.isLocalPlayback,
      bangumiId: refreshed.bangumiId,
      pluginName: refreshed.pluginName,
      episode: refreshed.episode,
      httpHeaders: refreshed.httpHeaders,
      adBlockerEnabled: refreshed.adBlockerEnabled,
      episodeTitle: refreshed.episodeTitle,
      referer: refreshed.referer,
      currentRoad: refreshed.currentRoad,
      coverUrl: refreshed.coverUrl,
      bangumiName: refreshed.bangumiName,
      subtitlePath: refreshed.subtitlePath ?? previous.subtitlePath,
      subtitleStorageKey:
          refreshed.subtitleStorageKey ?? previous.subtitleStorageKey,
      stableMediaKey: refreshed.stableMediaKey ?? previous.stableMediaKey,
      networkRoute: refreshed.networkRoute,
      cloudProviderName:
          refreshed.cloudProviderName ?? previous.cloudProviderName,
      refreshCloudPlayback:
          refreshed.refreshCloudPlayback ?? previous.refreshCloudPlayback,
    );

class CloudPlaybackRefreshTransaction {
  const CloudPlaybackRefreshTransaction({
    required this.previous,
    required this.position,
    required this.wasPlaying,
  });

  final PlaybackInitParams previous;
  final Duration position;
  final bool wasPlaying;

  bool get shouldPauseAfterRefresh => !wasPlaying;

  PlaybackInitParams merge(PlaybackInitParams refreshed) =>
      mergeRefreshedCloudPlayback(
        previous: previous,
        refreshed: refreshed,
        position: position,
      );
}

// ignore: library_private_types_in_public_api
class PlayerController = _PlayerController with _$PlayerController;

abstract class _PlayerController with Store {
  _PlayerController({
    SubtitlePreferences? subtitlePreferences,
    TrueHdFallbackPolicy? trueHdFallbackPolicy,
  })  : _subtitlePreferences = subtitlePreferences ?? SubtitlePreferences(),
        _trueHdFallbackPolicy =
            trueHdFallbackPolicy ?? const TrueHdFallbackPolicy();

  static const Duration _playerOpenTimeout = Duration(seconds: 25);

  final SubtitlePreferences _subtitlePreferences;
  final TrueHdFallbackPolicy _trueHdFallbackPolicy;

  final ShadersController shadersController = Modular.get<ShadersController>();

  late int bangumiId;
  late int currentEpisode;
  late int currentRoad;
  late String referer;
  String? coverUrl;

  /// 视频比例类型
  /// 1. AUTO
  /// 2. COVER
  /// 3. FILL
  @observable
  int aspectRatioType = 1;

  /// 视频超分
  /// 1. OFF
  /// 2. Anime4K Efficiency
  /// 3. Anime4K Quality
  @observable
  int superResolutionType = 1;

  // 视频音量/亮度
  @observable
  double volume = -1;
  @observable
  double brightness = 0;

  // 播放器界面控制
  @observable
  bool lockPanel = false;
  @observable
  bool showVideoController = true;
  @observable
  bool showSeekTime = false;
  @observable
  bool showBrightness = false;
  @observable
  bool showVolume = false;
  @observable
  bool showPlaySpeed = false;
  @observable
  bool brightnessSeeking = false;
  @observable
  bool volumeSeeking = false;
  @observable
  bool canHidePlayerPanel = true;

  // 视频地址
  String videoUrl = '';

  // 播放器实体
  Player? mediaPlayer;
  VideoController? videoController;

  PlaybackInitParams? _lastInitParams;
  final PlayerMediaOperationCoordinator _mediaOperations =
      PlayerMediaOperationCoordinator();
  final PlayerLifecycleCoordinator _lifecycleOperations =
      PlayerLifecycleCoordinator();
  final Lock _playerInitLock = Lock();
  bool _disposeRequested = false;
  String? _subtitleStorageKey;
  bool _truehdAudioTrackFallbackAttempted = false;
  final EmbeddedTrackSelectionState _embeddedTrackSelection =
      EmbeddedTrackSelectionState();
  final SubtitleTrackSelectionState _subtitleTrackSelection =
      SubtitleTrackSelectionState();

  // 播放器面板状态
  @observable
  bool loading = true;
  @observable
  bool playing = false;
  @observable
  bool isBuffering = true;
  @observable
  bool completed = false;
  @observable
  Duration currentPosition = Duration.zero;
  @observable
  Duration buffer = Duration.zero;
  @observable
  Duration duration = Duration.zero;
  @observable
  double playerSpeed = 1.0;

  Box<Object?> setting = GStorage.setting;
  bool hAenable = true;
  late String hardwareDecoder;
  bool androidEnableOpenSLES = true;
  bool lowMemoryMode = false;
  bool autoPlay = true;
  bool playerDebugMode = false;
  int buttonSkipTime = 80;
  int arrowKeySkipTime = 10;

  // 播放器实时状态
  bool get playerPlaying => mediaPlayer!.state.playing;
  bool get playerBuffering => mediaPlayer!.state.buffering;
  bool get playerCompleted => mediaPlayer!.state.completed;
  double get playerVolume => mediaPlayer!.state.volume;
  Duration get playerPosition => mediaPlayer!.state.position;
  Duration get playerBuffer => mediaPlayer!.state.buffer;
  Duration get playerDuration => mediaPlayer!.state.duration;

  // 播放器调试信息
  @observable
  ObservableList<String> playerLog = ObservableList.of([]);
  @observable
  int playerWidth = 0;
  @observable
  int playerHeight = 0;
  @observable
  String playerVideoParams = '';
  @observable
  String playerAudioParams = '';
  @observable
  String playerPlaylist = '';
  @observable
  String playerAudioTracks = '';
  @observable
  String playerVideoTracks = '';
  @observable
  String playerAudioBitrate = '';

  String sanitizePlayerDiagnostic(String value) => sanitizeMediaDiagnosticText(
        value,
        isLocalPlayback: isLocalPlayback,
      );

  String get playerDebugSource => sanitizePlayerDiagnostic(videoUrl);

  String get playerDebugPlaylist => sanitizePlayerDiagnostic(playerPlaylist);

  /// 播放器调试信息订阅
  StreamSubscription<PlayerLog>? playerLogSubscription;
  StreamSubscription<int?>? playerWidthSubscription;
  StreamSubscription<int?>? playerHeightSubscription;
  StreamSubscription<VideoParams>? playerVideoParamsSubscription;
  StreamSubscription<AudioParams>? playerAudioParamsSubscription;
  StreamSubscription<Playlist>? playerPlaylistSubscription;
  StreamSubscription<Track>? playerTracksSubscription;
  StreamSubscription<Tracks>? playerAvailableTracksSubscription;
  StreamSubscription<double?>? playerAudioBitrateSubscription;
  StreamSubscription<String>? playerErrorSubscription;

  bool isLocalPlayback = false;
  final LocalSubtitleMatcher _localSubtitleMatcher = LocalSubtitleMatcher();
  final LocalSubtitleImporter _localSubtitleImporter = LocalSubtitleImporter();
  @observable
  String currentSubtitlePath = '';
  @observable
  String lastSubtitlePath = '';
  @observable
  ObservableList<String> subtitleCandidates = ObservableList.of([]);
  @observable
  double subtitleFontSize = SubtitleStyleSettings.defaultFontSize;
  @observable
  int subtitleColorValue = SubtitleStyleSettings.defaultColorValue;
  @observable
  int subtitleBorderColorValue = SubtitleStyleSettings.defaultBorderColorValue;
  @observable
  double subtitleBorderSize = SubtitleStyleSettings.defaultBorderSize;
  @observable
  bool subtitleShadowEnabled = SubtitleStyleSettings.defaultShadowEnabled;
  @observable
  double subtitleShadowOffset = SubtitleStyleSettings.defaultShadowOffset;
  @observable
  double subtitlePosition = SubtitleStyleSettings.defaultPosition;
  @observable
  bool subtitleForceStyle = SubtitleStyleSettings.defaultForceStyle;
  @observable
  double subtitleDelaySeconds = 0.0;
  @observable
  ObservableList<EmbeddedTrackInfo> availableAudioTracks =
      ObservableList.of([]);
  @observable
  ObservableList<EmbeddedTrackInfo> availableEmbeddedSubtitleTracks =
      ObservableList.of([]);
  @observable
  String selectedAudioTrackId = '';
  @observable
  String selectedEmbeddedSubtitleTrackId = '';

  SubtitleStyleSettings get subtitleStyleSettings => SubtitleStyleSettings(
        fontSize: subtitleFontSize,
        colorValue: subtitleColorValue,
        borderColorValue: subtitleBorderColorValue,
        borderSize: subtitleBorderSize,
        shadowEnabled: subtitleShadowEnabled,
        shadowOffset: subtitleShadowOffset,
        position: subtitlePosition,
        forceStyle: subtitleForceStyle,
      );

  PlayerLifecycleToken activatePlaybackLifecycle() {
    _disposeRequested = false;
    return _lifecycleOperations.activate();
  }

  Future<void> init(
    PlaybackInitParams params, {
    required PlayerLifecycleToken lifecycleToken,
  }) {
    if (!_lifecycleOperations.isCurrent(lifecycleToken) || _disposeRequested) {
      return Future<void>.value();
    }
    final token = _mediaOperations.beginMedia(params.stableMediaKey);
    return _playerInitLock.synchronized(
      () => _init(params, token, lifecycleToken),
    );
  }

  Future<void> _init(
    PlaybackInitParams params,
    PlayerMediaToken mediaToken,
    PlayerLifecycleToken lifecycleToken,
  ) async {
    if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return;
    final bool isNewMedia = _lastInitParams?.videoUrl != params.videoUrl;
    if (isNewMedia) {
      _truehdAudioTrackFallbackAttempted = false;
      _resetEmbeddedTrackState();
    }
    _lastInitParams = params;
    videoUrl = params.videoUrl;
    isLocalPlayback = params.isLocalPlayback;
    _subtitleStorageKey = params.subtitleStorageKey;
    _loadSubtitleDelayForCurrentVideo();
    bangumiId = params.bangumiId;
    currentEpisode = params.episode;
    currentRoad = params.currentRoad;
    referer = params.referer;
    _applyStoredSubtitleStyle();
    if (isNewMedia) {
      lastSubtitlePath = params.subtitlePath ?? '';
    }
    _setCurrentSubtitlePath(params.subtitlePath ?? '');
    if (!params.isLocalPlayback) {
      subtitleCandidates.clear();
    }

    AppLogger().i(
      'PlayerController: ${params.isLocalPlayback ? "local" : "online"} '
      'playback: ${sanitizeMediaDescription(params.videoUrl, isLocalPlayback: params.isLocalPlayback)}',
    );

    playing = false;
    loading = true;
    isBuffering = true;
    currentPosition = Duration.zero;
    buffer = Duration.zero;
    duration = Duration.zero;
    completed = false;
    playerSpeed = setting.getTyped<double>(
      SettingBoxKey.defaultPlaySpeed,
      defaultValue: 1.0,
    );
    aspectRatioType = setting.getTyped<int>(
      SettingBoxKey.defaultAspectRatioType,
      defaultValue: 1,
    );

    buttonSkipTime = setting.getTyped<int>(
      SettingBoxKey.buttonSkipTime,
      defaultValue: 80,
    );
    arrowKeySkipTime = setting.getTyped<int>(
      SettingBoxKey.arrowKeySkipTime,
      defaultValue: 10,
    );
    try {
      await _disposePlayerResources();
    } catch (_) {}
    if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return;
    int episodeFromTitle = 0;
    try {
      episodeFromTitle = Utils.extractEpisodeNumber(params.episodeTitle);
    } catch (e) {
      AppLogger().e(
          'PlayerController: failed to extract episode number from title',
          error: e);
    }
    if (episodeFromTitle == 0) {
      episodeFromTitle = params.episode;
    }
    if (params.isLocalPlayback) {
      refreshSubtitleCandidates();
    }
    try {
      mediaPlayer ??= await createVideoController(
        params.httpHeaders,
        params.adBlockerEnabled,
        mediaToken: mediaToken,
        lifecycleToken: lifecycleToken,
        initParams: params,
        offset: params.offset,
        subtitlePath: params.subtitlePath,
      );
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) {
        await _disposePlayerResources();
        return;
      }

      if (Utils.isDesktop()) {
        volume = volume != -1 ? volume : 100;
        await setVolume(volume);
      } else {
        // mobile is using system volume, don't setVolume here,
        // or iOS will mute if system volume is too low (#732)
        await FlutterVolumeController.getVolume().then((value) {
          volume = (value ?? 0.0) * 100;
        });
      }
      setPlaybackSpeed(playerSpeed);
      AppLogger().i('PlayerController: video initialized');
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) {
        await _disposePlayerResources();
        return;
      }
      loading = false;

      coverUrl = params.coverUrl;
    } catch (e) {
      if (e is _PlayerInitializationCancelled) return;
      loading = false;
      isBuffering = false;
      AppLogger().e('PlayerController: failed to initialize video', error: e);
      try {
        await _disposePlayerResources().timeout(const Duration(seconds: 5));
      } catch (disposeError) {
        AppLogger().w(
          'PlayerController: failed to dispose after init error',
          error: disposeError,
        );
      }
      rethrow;
    }
  }

  Future<void> setupPlayerDebugInfoSubscription() async {
    await playerLogSubscription?.cancel();
    playerLogSubscription = mediaPlayer!.stream.log.listen((event) {
      final safeLog = sanitizePlayerDiagnostic(event.toString());
      writePlayerLog('MPV: $safeLog');
      if (playerDebugMode) {
        playerLog.add(safeLog);
      }
    });
    await playerWidthSubscription?.cancel();
    playerWidthSubscription = mediaPlayer!.stream.width.listen((event) {
      playerWidth = event ?? 0;
    });
    await playerHeightSubscription?.cancel();
    playerHeightSubscription = mediaPlayer!.stream.height.listen((event) {
      playerHeight = event ?? 0;
    });
    await playerVideoParamsSubscription?.cancel();
    playerVideoParamsSubscription =
        mediaPlayer!.stream.videoParams.listen((event) {
      playerVideoParams = event.toString();
    });
    await playerAudioParamsSubscription?.cancel();
    playerAudioParamsSubscription =
        mediaPlayer!.stream.audioParams.listen((event) {
      playerAudioParams = event.toString();
    });
    await playerPlaylistSubscription?.cancel();
    playerPlaylistSubscription = mediaPlayer!.stream.playlist.listen((event) {
      playerPlaylist = sanitizePlayerDiagnostic(event.toString());
    });
    await playerTracksSubscription?.cancel();
    playerTracksSubscription = mediaPlayer!.stream.track.listen((event) {
      selectedAudioTrackId = event.audio.id;
      if (!event.subtitle.uri && !event.subtitle.data) {
        selectedEmbeddedSubtitleTrackId =
            event.subtitle.id == 'no' || event.subtitle.id == 'auto'
                ? ''
                : event.subtitle.id;
      }
    });
    await playerAvailableTracksSubscription?.cancel();
    playerAvailableTracksSubscription =
        mediaPlayer!.stream.tracks.listen((event) {
      playerAudioTracks = event.audio.toString();
      playerVideoTracks = event.video.toString();
      _updateEmbeddedTracks(event);
      unawaited(_selectDefaultEmbeddedTracks());
    });
    await playerAudioBitrateSubscription?.cancel();
    playerAudioBitrateSubscription =
        mediaPlayer!.stream.audioBitrate.listen((event) {
      playerAudioBitrate = event.toString();
    });
  }

  Future<void> cancelPlayerDebugInfoSubscription() async {
    await playerLogSubscription?.cancel();
    await playerWidthSubscription?.cancel();
    await playerHeightSubscription?.cancel();
    await playerVideoParamsSubscription?.cancel();
    await playerAudioParamsSubscription?.cancel();
    await playerPlaylistSubscription?.cancel();
    await playerTracksSubscription?.cancel();
    await playerAvailableTracksSubscription?.cancel();
    await playerAudioBitrateSubscription?.cancel();
  }

  Future<Player> createVideoController(
      Map<String, String> httpHeaders, bool adBlockerEnabled,
      {required PlayerMediaToken mediaToken,
      required PlayerLifecycleToken lifecycleToken,
      required PlaybackInitParams initParams,
      int offset = 0,
      String? subtitlePath}) async {
    superResolutionType = setting.getTyped<int>(
      SettingBoxKey.defaultSuperResolutionType,
      defaultValue: 1,
    );
    hAenable =
        setting.getTyped<bool>(SettingBoxKey.hAenable, defaultValue: true);
    androidEnableOpenSLES = setting.getTyped<bool>(
      SettingBoxKey.androidEnableOpenSLES,
      defaultValue: true,
    );
    hardwareDecoder = normalizeHardwareDecoder(
      setting.getTyped<String>(
        SettingBoxKey.hardwareDecoder,
        defaultValue: defaultHardwareDecoder,
      ),
    );
    if (hardwareDecoder == 'no') {
      hAenable = false;
    }
    autoPlay =
        setting.getTyped<bool>(SettingBoxKey.autoPlay, defaultValue: true);
    lowMemoryMode = setting.getTyped<bool>(
      SettingBoxKey.lowMemoryMode,
      defaultValue: false,
    );
    playerDebugMode = setting.getTyped<bool>(
      SettingBoxKey.playerDebugMode,
      defaultValue: false,
    );

    mediaPlayer = Player(
      configuration: PlayerConfiguration(
        bufferSize: lowMemoryMode ? 15 * 1024 * 1024 : 1500 * 1024 * 1024,
        osc: false,
        libass: Platform.isWindows,
        logLevel: MPVLogLevel.v,
        adBlocker: adBlockerEnabled,
      ),
    );
    if (!_isMediaOperationActive(mediaToken, lifecycleToken)) {
      await _disposePlayerResources();
      throw const _PlayerInitializationCancelled();
    }

    playerLog.clear();
    await setupPlayerDebugInfoSubscription();
    if (!_isMediaOperationActive(mediaToken, lifecycleToken)) {
      await _disposePlayerResources();
      throw const _PlayerInitializationCancelled();
    }

    var pp = mediaPlayer!.platform as NativePlayer;
    await _prepareSubtitleTrackState(pp);
    // media-kit 默认启用硬盘作为双重缓存，这可以维持大缓存的前提下减轻内存压力
    // media-kit 内部硬盘缓存目录按照 Linux 配置，这导致该功能在其他平台上被损坏
    // 该设置可以在所有平台上正确启用双重缓存
    await pp.setProperty("demuxer-cache-dir", await Utils.getPlayerTempPath());
    await pp.setProperty("af", "scaletempo2=max-speed=8");
    if (Platform.isAndroid) {
      await pp.setProperty("volume-max", "100");
      if (androidEnableOpenSLES) {
        await pp.setProperty("ao", "opensles");
      } else {
        await pp.setProperty("ao", "audiotrack");
      }
    }

    // 设置 HTTP 代理
    final bool proxyEnable = setting.getTyped<bool>(
      SettingBoxKey.proxyEnable,
      defaultValue: false,
    );
    if (shouldApplyPlayerProxy(
      proxyEnabled: proxyEnable,
      networkRoute: initParams.networkRoute,
    )) {
      final String proxyUrl = setting.getTyped<String>(
        SettingBoxKey.proxyUrl,
        defaultValue: '',
      );
      final formattedProxy = ProxyUtils.getFormattedProxyUrl(proxyUrl);
      if (formattedProxy != null) {
        await pp.setProperty("http-proxy", formattedProxy);
        AppLogger().i('Player: HTTP 代理设置成功 $formattedProxy');
      }
    }

    await mediaPlayer!.setAudioTrack(
      AudioTrack.auto(),
    );

    String? videoRenderer;
    if (Platform.isAndroid) {
      final String androidVideoRenderer = setting.getTyped<String>(
        SettingBoxKey.androidVideoRenderer,
        defaultValue: 'auto',
      );

      if (androidVideoRenderer == 'auto') {
        // Android 14 及以上使用基于 Vulkan 的 MPV GPU-NEXT 视频输出，着色器性能更好
        // GPU-NEXT 需要 Vulkan 1.2 支持
        // 避免 Android 14 及以下设备上部分机型 Vulkan 支持不佳导致的黑屏问题
        final int androidSdkVersion = await Utils.getAndroidSdkVersion();
        if (androidSdkVersion >= 34) {
          videoRenderer = 'gpu-next';
        } else {
          videoRenderer = 'gpu';
        }
      } else {
        videoRenderer = androidVideoRenderer;
      }
    }

    if (videoRenderer == 'mediacodec_embed') {
      hAenable = true;
      hardwareDecoder = 'mediacodec';
      superResolutionType = 1;
    }

    videoController ??= VideoController(
      mediaPlayer!,
      configuration: VideoControllerConfiguration(
        vo: videoRenderer,
        enableHardwareAcceleration: hAenable,
        hwdec: hAenable ? hardwareDecoder : 'no',
        androidAttachSurfaceAfterVideoParameters: false,
      ),
    );
    mediaPlayer!.setPlaylistMode(PlaylistMode.none);

    // error handle
    bool showPlayerError = setting.getTyped<bool>(
      SettingBoxKey.showPlayerError,
      defaultValue: true,
    );
    await playerErrorSubscription?.cancel();
    playerErrorSubscription = mediaPlayer!.stream.error.listen((event) async {
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return;
      final errorStr = event.toString();
      if (await _refreshExpiredCloudLink(
        errorStr,
        mediaToken,
        lifecycleToken,
        initParams,
      )) {
        return;
      }
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return;
      // TrueHD 解码失败时只切换已有的兼容音轨，不重建视频解码器。
      if (await _handleTrueHdPlaybackError(
        errorStr,
        mediaToken,
        lifecycleToken,
      )) {
        return;
      }
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return;
      if (showPlayerError) {
        if (errorStr.contains('Failed to open') && playerBuffering) {
          AppDialog.showToast(
              message: '加载失败, 请尝试更换其他视频来源', showActionButton: true);
        } else {
          AppDialog.showToast(
              message: '播放器内部错误，请稍后重试',
              duration: const Duration(seconds: 5),
              showActionButton: true);
        }
      }
      AppLogger().e(
        'PlayerController: player error for '
        '${sanitizeMediaDescription(initParams.videoUrl, isLocalPlayback: initParams.isLocalPlayback)}',
      );
    });

    if (superResolutionType != 1) {
      await setShader(superResolutionType);
    }

    await applySubtitleStyle(save: false);
    final playableUri = MediaUriUtils.toPlayableUri(
      videoUrl,
      isLocalPlayback: isLocalPlayback,
    );
    if (!_isMediaOperationActive(mediaToken, lifecycleToken)) {
      await _disposePlayerResources();
      throw const _PlayerInitializationCancelled();
    }
    await mediaPlayer!
        .open(
          Media(playableUri,
              start: Duration(seconds: offset), httpHeaders: httpHeaders),
          play: autoPlay,
        )
        .timeout(
          _playerOpenTimeout,
          onTimeout: () => throw TimeoutException(
            '播放器打开超时，请检查视频源或本地文件是否可播放',
            _playerOpenTimeout,
          ),
        );
    if (!_isMediaOperationActive(mediaToken, lifecycleToken)) {
      await _disposePlayerResources();
      throw const _PlayerInitializationCancelled();
    }
    if (subtitlePath == null || subtitlePath.isEmpty) {
      await _disableSubtitleTrack(clearCurrentPath: true);
    } else {
      await loadExternalSubtitle(subtitlePath);
    }
    await applySubtitleStyle(save: false);
    await _syncSubtitleDelayToPlayer();

    return mediaPlayer!;
  }

  Future<bool> _handleTrueHdPlaybackError(
    String errorStr,
    PlayerMediaToken mediaToken,
    PlayerLifecycleToken lifecycleToken,
  ) async {
    if (!_isMediaOperationActive(mediaToken, lifecycleToken) ||
        !_isTrueHdRelatedPlaybackError(errorStr) ||
        _lastInitParams == null) {
      return false;
    }

    if (!_truehdAudioTrackFallbackAttempted) {
      _truehdAudioTrackFallbackAttempted = true;
      if (await _switchToCompatibleAudioTrackForTrueHd()) {
        return true;
      }
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return true;
      AppDialog.showToast(
        message: '当前播放器组件无法解码此音轨，请导出诊断日志',
        duration: const Duration(seconds: 5),
        showActionButton: true,
      );
    }
    return true;
  }

  bool _isTrueHdRelatedPlaybackError(String errorStr) {
    final player = mediaPlayer;
    return _trueHdFallbackPolicy.isRelatedError(
      errorStr,
      player?.state.tracks.audio ?? const <AudioTrack>[],
    );
  }

  Future<bool> _switchToCompatibleAudioTrackForTrueHd() async {
    if (!_embeddedTrackSelection.canAutomaticallySelectAudio) {
      AppDialog.showToast(message: '当前音轨播放失败，请手动选择其他音轨或导出诊断日志');
      return false;
    }
    final player = mediaPlayer;
    if (player == null) return false;
    final currentId = player.state.track.audio.id;
    final fallbackTrack = _trueHdFallbackPolicy.chooseFallback(
      player.state.tracks.audio,
      currentTrackId: currentId,
    );

    if (fallbackTrack == null) {
      AppLogger()
          .w('PlayerController: no compatible non-TrueHD audio track found');
      return false;
    }

    try {
      await player.setAudioTrack(fallbackTrack);
      AppLogger().w(
          'PlayerController: switched from TrueHD to audio track ${fallbackTrack.id}');
      AppDialog.showToast(
        message: 'TrueHD 音轨播放失败，已切换到兼容音轨',
        duration: const Duration(seconds: 3),
      );
      return true;
    } catch (e) {
      AppLogger()
          .e('PlayerController: failed to switch TrueHD audio track', error: e);
      return false;
    }
  }

  Future<bool> loadExternalSubtitle(String? subtitlePath) async {
    if (subtitlePath == null || subtitlePath.isEmpty) return false;
    if (!LocalSubtitleMatcher.isSupportedSubtitlePath(subtitlePath)) {
      return false;
    }
    _subtitleTrackSelection.markManualSelection();
    try {
      await _clearSubtitleTrackForSwitch();
      final player = mediaPlayer;
      if (player == null) return false;
      await player.setSubtitleTrack(
        SubtitleTrack.uri(
          MediaUriUtils.toPlayableUri(
            subtitlePath,
            isLocalPlayback: true,
          ),
          title: p.basename(subtitlePath),
          language: 'auto',
        ),
      );
      final pp = player.platform;
      if (pp is NativePlayer) {
        await _setFlutterSubtitleMode(pp);
      }
      _setCurrentSubtitlePath(subtitlePath);
      selectedEmbeddedSubtitleTrackId = '';
      await applySubtitleStyle(save: false);
      AppLogger().i('PlayerController: loaded subtitle $subtitlePath');
      return true;
    } catch (e) {
      AppLogger().w('PlayerController: failed to load subtitle $subtitlePath',
          error: e);
      return false;
    }
  }

  Future<void> _disableSubtitleTrack({bool clearCurrentPath = false}) async {
    if (clearCurrentPath) {
      _setCurrentSubtitlePath('');
    }
    selectedEmbeddedSubtitleTrackId = '';
    final player = mediaPlayer;
    if (player == null) return;
    try {
      await player.setSubtitleTrack(SubtitleTrack.no());
    } catch (e) {
      AppLogger().w(
          'PlayerController: failed to disable media_kit subtitle track',
          error: e);
    }
    final pp = player.platform;
    if (pp is NativePlayer) {
      await _trySetNativeSubtitleProperty(pp, 'sub-visibility', 'no');
      await _trySetNativeSubtitleProperty(pp, 'secondary-sub-visibility', 'no');
      await _trySetNativeSubtitleProperty(pp, 'sid', 'no');
      await _trySetNativeSubtitleProperty(pp, 'secondary-sid', 'no');
    }
  }

  Future<void> _clearSubtitleTrackForSwitch() {
    return _disableSubtitleTrack(clearCurrentPath: true);
  }

  Future<void> _prepareSubtitleTrackState(NativePlayer player) async {
    await _trySetNativeSubtitleProperty(player, 'sub-auto', 'no');
    await _trySetNativeSubtitleProperty(player, 'sid', 'no');
    await _trySetNativeSubtitleProperty(player, 'secondary-sid', 'no');
    await _setFlutterSubtitleMode(player);
  }

  @action
  Future<bool> selectAudioTrack(String trackId, {bool manual = true}) async {
    final player = mediaPlayer;
    if (player == null) return false;
    final track = player.state.tracks.audio
        .where((item) => item.id == trackId)
        .firstOrNull;
    if (track == null) return false;
    final previousId = selectedAudioTrackId;
    try {
      await player.setAudioTrack(track);
      selectedAudioTrackId = track.id;
      if (manual) _embeddedTrackSelection.markAudioSelectedManually();
      AppLogger().i('PlayerController: selected audio track ${track.id}');
      return true;
    } catch (e) {
      selectedAudioTrackId = previousId;
      AppLogger().e(
          'PlayerController: failed to select audio track ${track.id}',
          error: e);
      AppDialog.showToast(message: '音轨切换失败');
      return false;
    }
  }

  @action
  Future<bool> selectEmbeddedSubtitleTrack(String trackId,
      {bool manual = true}) async {
    final player = mediaPlayer;
    if (player == null) return false;
    final track = player.state.tracks.subtitle
        .where((item) => item.id == trackId && !item.uri && !item.data)
        .firstOrNull;
    if (track == null) return false;
    final previousId = selectedEmbeddedSubtitleTrackId;
    if (manual) {
      _subtitleTrackSelection.markManualSelection();
    }
    try {
      await _clearSubtitleTrackForSwitch();
      await player.setSubtitleTrack(track);
      final platform = player.platform;
      if (platform is NativePlayer) {
        await _trySetNativeSubtitleProperty(platform, 'sub-visibility', 'yes');
        await _trySetNativeSubtitleProperty(platform, 'secondary-sid', 'no');
        await _trySetNativeSubtitleProperty(
          platform,
          'secondary-sub-visibility',
          'no',
        );
        await _trySetNativeSubtitleProperty(platform, 'sid', track.id);
      }
      selectedEmbeddedSubtitleTrackId = track.id;
      AppLogger().i('PlayerController: selected embedded subtitle ${track.id}');
      return true;
    } catch (e) {
      selectedEmbeddedSubtitleTrackId = previousId;
      AppLogger().e(
        'PlayerController: failed to select embedded subtitle ${track.id}',
        error: e,
      );
      AppDialog.showToast(message: '字幕切换失败');
      return false;
    }
  }

  void _resetEmbeddedTrackState() {
    _embeddedTrackSelection.reset();
    _subtitleTrackSelection.reset();
    availableAudioTracks.clear();
    availableEmbeddedSubtitleTracks.clear();
    selectedAudioTrackId = '';
    selectedEmbeddedSubtitleTrackId = '';
  }

  @action
  void _updateEmbeddedTracks(Tracks tracks) {
    availableAudioTracks
      ..clear()
      ..addAll(tracks.audio
          .where(
              (track) => track.id != 'auto' && track.id != 'no' && !track.uri)
          .map(EmbeddedTrackInfo.fromAudio));
    availableEmbeddedSubtitleTracks
      ..clear()
      ..addAll(tracks.subtitle
          .where((track) =>
              track.id != 'auto' &&
              track.id != 'no' &&
              !track.uri &&
              !track.data)
          .map(EmbeddedTrackInfo.fromSubtitle));
    AppLogger().i(
      'PlayerController: detected ${availableAudioTracks.length} audio tracks and '
      '${availableEmbeddedSubtitleTracks.length} embedded subtitle tracks',
    );
  }

  Future<void> _selectDefaultEmbeddedTracks() async {
    if (!_embeddedTrackSelection.beginAutomaticSelection(
      hasAudioTracks: availableAudioTracks.isNotEmpty,
    )) {
      return;
    }
    final automaticSubtitleSelection =
        _subtitleTrackSelection.beginAutomaticSelection();
    final current = mediaPlayer?.state.track;
    final audio = selectPreferredAudioTrack(
      availableAudioTracks,
      defaultTrackId: current?.audio.id,
    );
    final subtitle = selectPreferredSubtitleTrack(
      availableEmbeddedSubtitleTracks,
      defaultTrackId: current?.subtitle.id,
    );
    if (audio != null && _embeddedTrackSelection.canAutomaticallySelectAudio) {
      await selectAudioTrack(audio.id, manual: false);
    }
    if (!_subtitleTrackSelection.canApplyAutomaticSelection(
      automaticSubtitleSelection,
    )) {
      return;
    }
    if (subtitle != null && currentSubtitlePath.isEmpty) {
      await selectEmbeddedSubtitleTrack(subtitle.id, manual: false);
    } else if (subtitle == null && currentSubtitlePath.isEmpty) {
      await _disableSubtitleTrack();
    }
    AppLogger().i(
      'PlayerController: automatic track selection audio=${audio?.id ?? "none"}, '
      'subtitle=${subtitle?.id ?? "off"}',
    );
  }

  Future<void> _setFlutterSubtitleMode(NativePlayer player) async {
    final useNativeSubtitleRendering = player.configuration.libass;
    await _trySetNativeSubtitleProperty(
      player,
      'sub-visibility',
      useNativeSubtitleRendering ? 'yes' : 'no',
    );
    await _trySetNativeSubtitleProperty(
      player,
      'secondary-sub-visibility',
      'no',
    );
    await _trySetNativeSubtitleProperty(player, 'secondary-sid', 'no');
  }

  Future<void> _trySetNativeSubtitleProperty(
    NativePlayer player,
    String property,
    String value,
  ) async {
    try {
      await player.setProperty(property, value);
    } catch (e) {
      AppLogger()
          .w('PlayerController: failed to set $property=$value', error: e);
    }
  }

  @action
  void refreshSubtitleCandidates() {
    if (!isLocalPlayback || videoUrl.isEmpty) {
      subtitleCandidates.clear();
      return;
    }
    final candidates = _localSubtitleMatcher.findAllForVideo(videoUrl);
    subtitleCandidates
      ..clear()
      ..addAll(candidates);
  }

  @action
  Future<bool> selectSubtitle(String subtitlePath) async {
    final loaded = await loadExternalSubtitle(subtitlePath);
    if (loaded && isLocalPlayback) {
      refreshSubtitleCandidates();
    }
    return loaded;
  }

  @action
  Future<LocalSubtitleImportResult?> importSubtitle(
    String subtitlePath, {
    LocalSubtitleImportTarget target =
        LocalSubtitleImportTarget.subtitleDirectory,
  }) async {
    if (!isLocalPlayback || videoUrl.isEmpty) return null;
    final result = await _localSubtitleImporter.importForVideo(
      videoPath: videoUrl,
      subtitlePath: subtitlePath,
      target: target,
    );
    refreshSubtitleCandidates();
    await loadExternalSubtitle(result.targetPath);
    return result;
  }

  @action
  Future<void> clearSubtitle() async {
    _subtitleTrackSelection.markManualSelection();
    try {
      await _disableSubtitleTrack(clearCurrentPath: true);
      AppLogger().i('PlayerController: subtitle disabled');
    } catch (e) {
      AppLogger().w('PlayerController: failed to disable subtitle', error: e);
    }
  }

  @action
  Future<bool> restoreLastSubtitle() async {
    final subtitlePath = lastSubtitlePath.trim();
    if (subtitlePath.isEmpty) return false;
    return selectSubtitle(subtitlePath);
  }

  void _setCurrentSubtitlePath(String value) {
    currentSubtitlePath = value;
    if (value.isNotEmpty) {
      lastSubtitlePath = value;
    }
  }

  @action
  Future<void> applySubtitleStyle({
    double? fontSize,
    int? colorValue,
    int? borderColorValue,
    double? borderSize,
    bool? shadowEnabled,
    double? shadowOffset,
    double? position,
    bool? forceStyle,
    bool save = true,
  }) async {
    subtitleFontSize =
        (fontSize ?? subtitleFontSize).clamp(18.0, 72.0).toDouble();
    subtitleColorValue = colorValue ?? subtitleColorValue;
    subtitleBorderColorValue = borderColorValue ?? subtitleBorderColorValue;
    subtitleBorderSize =
        (borderSize ?? subtitleBorderSize).clamp(0.0, 8.0).toDouble();
    subtitleShadowEnabled = shadowEnabled ?? subtitleShadowEnabled;
    subtitleShadowOffset =
        (shadowOffset ?? subtitleShadowOffset).clamp(0.0, 8.0).toDouble();
    subtitlePosition =
        (position ?? subtitlePosition).clamp(60.0, 100.0).toDouble();
    subtitleForceStyle = forceStyle ?? subtitleForceStyle;

    if (save) {
      await _subtitlePreferences.saveStyle(subtitleStyleSettings);
    }
    await _syncSubtitleStyleToPlayer();
  }

  @action
  Future<void> resetSubtitleStyle() {
    return applySubtitleStyle(
      fontSize: SubtitleStyleSettings.defaultFontSize,
      colorValue: SubtitleStyleSettings.defaultColorValue,
      borderColorValue: SubtitleStyleSettings.defaultBorderColorValue,
      borderSize: SubtitleStyleSettings.defaultBorderSize,
      shadowEnabled: SubtitleStyleSettings.defaultShadowEnabled,
      shadowOffset: SubtitleStyleSettings.defaultShadowOffset,
      position: SubtitleStyleSettings.defaultPosition,
      forceStyle: SubtitleStyleSettings.defaultForceStyle,
    );
  }

  @action
  Future<void> setSubtitleDelay(double seconds) async {
    final stepped = (seconds * 2).round() / 2;
    subtitleDelaySeconds = stepped.clamp(-30.0, 30.0).toDouble();
    await _syncSubtitleDelayToPlayer();
    await _saveSubtitleDelayForCurrentVideo();
  }

  @action
  Future<void> resetSubtitleDelay() => setSubtitleDelay(0.0);

  void _loadSubtitleDelayForCurrentVideo() {
    subtitleDelaySeconds = 0.0;
    if (!isLocalPlayback && _subtitleStorageKey == null) return;
    if (_subtitleDelayStorageKey.isEmpty) return;
    try {
      subtitleDelaySeconds =
          _subtitlePreferences.loadDelay(_subtitleDelayStorageKey);
    } catch (e) {
      AppLogger()
          .w('PlayerController: failed to load subtitle delay', error: e);
    }
  }

  Future<void> _saveSubtitleDelayForCurrentVideo() async {
    if (!isLocalPlayback && _subtitleStorageKey == null) return;
    if (_subtitleDelayStorageKey.isEmpty) return;
    try {
      await _subtitlePreferences.saveDelay(
        _subtitleDelayStorageKey,
        subtitleDelaySeconds,
      );
    } catch (e) {
      AppLogger()
          .w('PlayerController: failed to save subtitle delay', error: e);
    }
  }

  String get _subtitleDelayStorageKey =>
      _subtitleStorageKey ?? videoUrl.trim().toLowerCase();

  Future<bool> _refreshExpiredCloudLink(
    String error,
    PlayerMediaToken mediaToken,
    PlayerLifecycleToken lifecycleToken,
    PlaybackInitParams params,
  ) async {
    final refresh = params.refreshCloudPlayback;
    if (!_isMediaOperationActive(mediaToken, lifecycleToken) ||
        refresh == null ||
        !_mediaOperations.tryBeginRefresh(mediaToken, error)) {
      return false;
    }
    final position = currentPosition;
    final wasPlaying = playing;
    final transaction = CloudPlaybackRefreshTransaction(
      previous: params,
      position: position,
      wasPlaying: wasPlaying,
    );
    try {
      final refreshed = transaction.merge(await refresh());
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return true;
      final refreshedToken = _mediaOperations.beginMedia(
        refreshed.stableMediaKey,
        preserveRefreshState: true,
      );
      await _playerInitLock.synchronized(
        () => _init(refreshed, refreshedToken, lifecycleToken),
      );
      if (transaction.shouldPauseAfterRefresh &&
          _isMediaOperationActive(refreshedToken, lifecycleToken)) {
        await pause();
      }
      return true;
    } on Object catch (refreshError, stackTrace) {
      if (!_isMediaOperationActive(mediaToken, lifecycleToken)) return true;
      loading = false;
      isBuffering = false;
      AppLogger().e(
        'PlayerController: cloud playback link refresh failed',
        error: refreshError,
        stackTrace: stackTrace,
      );
      AppDialog.showToast(message: '网盘播放链接已失效，刷新后仍无法播放');
      return true;
    } finally {
      _mediaOperations.finishRefresh(mediaToken);
    }
  }

  Future<void> _syncSubtitleDelayToPlayer() async {
    final pp = mediaPlayer?.platform;
    if (pp is! NativePlayer) return;
    try {
      await pp.setProperty(
          'sub-delay', subtitleDelaySeconds.toStringAsFixed(1));
    } catch (e) {
      AppLogger()
          .w('PlayerController: failed to sync subtitle delay', error: e);
    }
  }

  void _applyStoredSubtitleStyle() {
    final style = _subtitlePreferences.loadStyle();
    subtitleFontSize = style.fontSize;
    subtitleColorValue = style.colorValue;
    subtitleBorderColorValue = style.borderColorValue;
    subtitleBorderSize = style.borderSize;
    subtitleShadowEnabled = style.shadowEnabled;
    subtitleShadowOffset = style.shadowOffset;
    subtitlePosition = style.position;
    subtitleForceStyle = style.forceStyle;
  }

  Future<void> _syncSubtitleStyleToPlayer() async {
    final pp = mediaPlayer?.platform;
    if (pp is! NativePlayer) return;
    try {
      await pp.setProperty(
          'sub-font-size', subtitleFontSize.toStringAsFixed(0));
      await pp.setProperty('sub-color', _mpvColor(Color(subtitleColorValue)));
      await pp.setProperty(
        'sub-border-color',
        _mpvColor(Color(subtitleBorderColorValue)),
      );
      await pp.setProperty(
        'sub-border-size',
        subtitleBorderSize.toStringAsFixed(1),
      );
      await pp.setProperty(
        'sub-shadow-offset',
        subtitleShadowEnabled ? subtitleShadowOffset.toStringAsFixed(1) : '0',
      );
      await pp.setProperty('sub-pos', subtitlePosition.toStringAsFixed(0));
      await pp.setProperty(
        'sub-ass-override',
        subtitleForceStyle ? 'force' : 'no',
      );
      if (currentSubtitlePath.isNotEmpty) {
        await _setFlutterSubtitleMode(pp);
      }
    } catch (e) {
      AppLogger()
          .w('PlayerController: failed to sync subtitle style', error: e);
    }
  }

  String _mpvColor(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';
  }

  Future<void> setShader(int type, {bool synchronized = true}) async {
    var pp = mediaPlayer!.platform as NativePlayer;
    await pp.waitForPlayerInitialization;
    await pp.waitForVideoControllerInitializationIfAttached;
    if (type == 2) {
      await pp.command([
        'change-list',
        'glsl-shaders',
        'set',
        Utils.buildShadersAbsolutePath(
            shadersController.shadersDirectory.path, mpvAnime4KShadersLite),
      ]);
      superResolutionType = 2;
      return;
    }
    if (type == 3) {
      await pp.command([
        'change-list',
        'glsl-shaders',
        'set',
        Utils.buildShadersAbsolutePath(
            shadersController.shadersDirectory.path, mpvAnime4KShaders),
      ]);
      superResolutionType = 3;
      return;
    }
    await pp.command(['change-list', 'glsl-shaders', 'clr', '']);
    superResolutionType = 1;
  }

  Future<void> setPlaybackSpeed(double playerSpeed) async {
    this.playerSpeed = playerSpeed;
    try {
      mediaPlayer!.setRate(playerSpeed);
    } catch (e) {
      AppLogger().e('PlayerController: failed to set playback speed', error: e);
    }
  }

  Future<void> setVolume(double value) async {
    value = value.clamp(0.0, 100.0);
    volume = value;
    try {
      if (Utils.isDesktop()) {
        await mediaPlayer!.setVolume(value);
      } else {
        await FlutterVolumeController.updateShowSystemUI(false);
        await FlutterVolumeController.setVolume(value / 100);
      }
    } catch (_) {}
  }

  Future<void> playOrPause() async {
    if (mediaPlayer!.state.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration duration, {bool enableSync = true}) async {
    currentPosition = duration;
    await mediaPlayer!.seek(duration);
  }

  Future<void> pause({bool enableSync = true}) async {
    await mediaPlayer!.pause();
    playing = false;
  }

  Future<void> play({bool enableSync = true}) async {
    await mediaPlayer!.play();
    playing = true;
  }

  bool _isMediaOperationActive(
    PlayerMediaToken token,
    PlayerLifecycleToken lifecycleToken,
  ) =>
      !_disposeRequested &&
      _mediaOperations.isCurrent(token) &&
      _lifecycleOperations.isCurrent(lifecycleToken);

  Future<void> dispose() {
    _disposeRequested = true;
    _lifecycleOperations.invalidate();
    _mediaOperations.invalidate();
    return _playerInitLock.synchronized(_disposePlayerResources);
  }

  Future<void> _disposePlayerResources() async {
    await playerErrorSubscription?.cancel();
    playerErrorSubscription = null;
    try {
      await cancelPlayerDebugInfoSubscription();
    } catch (_) {}
    await mediaPlayer?.dispose();
    mediaPlayer = null;
    videoController = null;
  }

  Future<void> stop() async {
    try {
      await mediaPlayer?.stop();
      loading = true;
    } catch (_) {}
  }

  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) async {
    return await mediaPlayer!.screenshot(format: format);
  }

  void setButtonForwardTime(int time) {
    buttonSkipTime = time;
    setting.put(SettingBoxKey.buttonSkipTime, time);
  }

  void setArrowKeyForwardTime(int time) {
    arrowKeySkipTime = time;
    setting.put(SettingBoxKey.arrowKeySkipTime, time);
  }

  void lanunchExternalPlayer() async {
    if ((Platform.isAndroid || Platform.isWindows) && referer.isEmpty) {
      if (await ExternalPlayer.launchURLWithMIME(videoUrl, 'video/mp4')) {
        AppDialog.dismiss<void>();
        AppDialog.showToast(
          message: '尝试唤起外部播放器',
        );
      } else {
        AppDialog.showToast(
          message: '唤起外部播放器失败',
        );
      }
    } else if (Platform.isMacOS || Platform.isIOS) {
      if (await ExternalPlayer.launchURLWithReferer(videoUrl, referer)) {
        AppDialog.dismiss<void>();
        AppDialog.showToast(
          message: '尝试唤起外部播放器',
        );
      } else {
        AppDialog.showToast(
          message: '唤起外部播放器失败',
        );
      }
    } else if (Platform.isLinux && referer.isEmpty) {
      AppDialog.dismiss<void>();
      if (await canLaunchUrlString(videoUrl)) {
        launchUrlString(videoUrl);
        AppDialog.showToast(
          message: '尝试唤起外部播放器',
        );
      } else {
        AppDialog.showToast(
          message: '无法使用外部播放器',
        );
      }
    } else {
      if (referer.isEmpty) {
        AppDialog.showToast(
          message: '暂不支持该设备',
        );
      } else {
        AppDialog.showToast(
          message: '暂不支持该规则',
        );
      }
    }
  }
}
