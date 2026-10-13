// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'package:kanyingyin/features/player/application/player_bookmark.dart';
import 'package:kanyingyin/features/player/application/player_timeline_segments.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:mobx/mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/utils/proxy_utils.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:kanyingyin/utils/constants.dart';
import 'package:kanyingyin/shaders/shaders_controller.dart';
import 'package:kanyingyin/services/local_subtitle_importer.dart';
import 'package:kanyingyin/services/local_subtitle_matcher.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';
import 'package:kanyingyin/features/player/application/cloud_playback_cache_policy.dart';
import 'package:kanyingyin/features/player/application/embedded_track_coordinator.dart';
import 'package:kanyingyin/features/player/application/anime4k_coordinator.dart';
import 'package:kanyingyin/features/player/application/anime4k_policy.dart';
import 'package:kanyingyin/features/player/application/anime4k_shader_executor.dart';
import 'package:kanyingyin/features/player/application/embedded_track_language_preferences.dart';
import 'package:kanyingyin/features/player/application/track_selection_preferences.dart';
import 'package:kanyingyin/features/player/application/player_runtime_preferences.dart';
import 'package:kanyingyin/features/player/application/player_color_profile.dart';
import 'package:kanyingyin/features/player/application/player_decoder_recovery_policy.dart';
import 'package:kanyingyin/features/player/application/player_resource_disposer.dart';
import 'package:kanyingyin/features/player/application/subtitle_preferences.dart';
import 'package:kanyingyin/features/player/application/truehd_fallback_policy.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';
import 'package:kanyingyin/features/player/application/player_chapter.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/utils/external_player.dart';
import 'package:kanyingyin/utils/media_uri_utils.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

part 'player_playback_application_coordinator.dart';
part 'player_controller.g.dart';
part 'player_controller_params.dart';

// ignore: library_private_types_in_public_api
class PlayerController = _PlayerController
    with _PlayerPlaybackApplicationCoordinator, _$PlayerController;

abstract class _PlayerController with Store {
  _PlayerController({
    SubtitlePreferences? subtitlePreferences,
    EmbeddedTrackLanguagePreferences? trackLanguagePreferences,
    TrueHdFallbackPolicy? trueHdFallbackPolicy,
    AppPlatformCapabilities? capabilities,
    ShadersController? shadersController,
    Future<void> Function()? clearLocalPlaybackCache,
    required PlayerRuntimePreferences runtimePreferences,
  })  : _subtitlePreferences = subtitlePreferences ?? SubtitlePreferences(),
        _trackLanguagePreferences =
            trackLanguagePreferences ?? EmbeddedTrackLanguagePreferences(),
        _trueHdFallbackPolicy =
            trueHdFallbackPolicy ?? const TrueHdFallbackPolicy(),
        _capabilities = capabilities ?? detectAppPlatform(),
        _clearLocalPlaybackCache = clearLocalPlaybackCache,
        _runtimePreferences = runtimePreferences,
        shadersController =
            shadersController ?? Modular.get<ShadersController>();

  static const Duration _playerOpenTimeout = Duration(seconds: 25);

  final SubtitlePreferences _subtitlePreferences;
  final EmbeddedTrackLanguagePreferences _trackLanguagePreferences;
  final TrueHdFallbackPolicy _trueHdFallbackPolicy;
  final AppPlatformCapabilities _capabilities;
  final Future<void> Function()? _clearLocalPlaybackCache;
  final PlayerRuntimePreferences _runtimePreferences;
  late final EmbeddedTrackCoordinator _embeddedTrackCoordinator =
      EmbeddedTrackCoordinator(_trackLanguagePreferences);
  final CloudPlaybackLeaseCoordinator _playbackLeaseCoordinator =
      CloudPlaybackLeaseCoordinator();

  final ShadersController shadersController;
  late int mediaId;
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

  @observable
  Anime4kPreference anime4kPreference = Anime4kPreference.off;

  @observable
  Anime4kRuntimeState anime4kRuntimeState = Anime4kRuntimeState.off;

  Timer? _anime4kLayoutDebounce;
  Size _anime4kOutputPixels = Size.zero;

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
  final PlayerResourceDisposer _resourceDisposer =
      const PlayerResourceDisposer();
  final Lock _playerInitLock = Lock();
  bool _disposeRequested = false;
  Future<void>? _disposeFuture;
  String? _subtitleStorageKey;
  bool _truehdAudioTrackFallbackAttempted = false;
  bool _softwareVideoDecoderFallbackAttempted = false;
  final PlayerDecoderRecoveryPolicy _decoderRecoveryPolicy =
      PlayerDecoderRecoveryPolicy();
  final EmbeddedTrackSelectionState _embeddedTrackSelection =
      EmbeddedTrackSelectionState();
  final SubtitleTrackSelectionState _subtitleTrackSelection =
      SubtitleTrackSelectionState();
  int _audioTrackRequestRevision = 0;
  int _subtitleTrackRequestRevision = 0;
  final TrackLanguageConfirmationState _trackLanguageConfirmationState =
      TrackLanguageConfirmationState();

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

  bool hAenable = true;
  late String hardwareDecoder;
  String? videoRenderer;
  bool anime4kSupported = true;
  bool lowMemoryMode = false;
  bool autoPlay = true;
  bool playerDebugMode = false;
  PlayerColorProfile colorProfile = PlayerColorProfile.automatic;
  PlayerColorProfile effectiveColorProfile = PlayerColorProfile.automatic;
  String? colorProfileFallbackReason;
  String? _lastColorDiagnostic;
  int buttonSkipTime = 80;
  int arrowKeySkipTime = 10;

  // 播放器实时状态
  bool get hasActivePlayer => !_disposeRequested && mediaPlayer != null;
  String _timelineMediaRevision = '';
  // shortcut: 以大小、修改时间和时长检测替换；需要识别相同元数据的内容替换时再引入内容哈希。
  String get timelineMediaFingerprint => _timelineMediaRevision;
  final ObservableList<PlayerTimelineSegment> timelineSegments =
      ObservableList();
  late final PlayerTimelineSegmentRepository timelineSegmentRepository =
      PlayerTimelineSegmentRepository(TypedSettingsPlayerBookmarkStorage(
          _runtimePreferences.settings,
          storageKey: SettingBoxKey.playerTimelineSegments));
  void refreshTimelineSegments() {
    final key = currentStableMediaKey;
    timelineSegments
      ..clear()
      ..addAll(key == null
          ? const []
          : timelineSegmentRepository.visibleSegments(key,
              fingerprint: timelineMediaFingerprint, duration: duration));
  }

  String? get currentStableMediaKey {
    final stable = _lastInitParams?.stableMediaKey?.trim();
    if (stable != null && stable.isNotEmpty) return stable;
    final fallback = videoUrl.trim();
    return fallback.isEmpty ? null : fallback;
  }

  late final TrackSelectionPreferences _trackPreferences =
      TrackSelectionPreferences(TypedSettingsPlayerBookmarkStorage(
          _runtimePreferences.settings,
          storageKey: SettingBoxKey.trackSelectionPreferences));
  String get _trackPreferenceKey => _lastInitParams?.trackPreferenceKey ?? '';
  Future<void> _rememberTrack(String workKey, EmbeddedTrackInfo? track) async {
    if (track == null || workKey.isEmpty) return;
    try {
      await _trackPreferences.save(workKey, track);
    } on Object {
      AppDialog.showToast(message: '已切换轨道，但跨集偏好保存失败');
    }
  }

  Future<List<PlayerChapter>> loadEmbeddedChapters() async {
    final platform = mediaPlayer?.platform;
    if (_disposeRequested || platform is! NativePlayer) {
      return const <PlayerChapter>[];
    }
    try {
      final count = int.tryParse(
            await platform.getProperty('chapter-list/count'),
          ) ??
          0;
      if (count <= 0) return const <PlayerChapter>[];
      final chapters = <PlayerChapter>[];
      for (var index = 0; index < count && index < 200; index++) {
        final time = await platform.getProperty('chapter-list/$index/time');
        try {
          final title = await platform.getProperty('chapter-list/$index/title');
          chapters.add(PlayerChapter.fromMpvValues(
            index: index,
            title: title,
            time: time,
          ));
        } on FormatException {
          // 单个章节损坏时保留其他章节。
        }
      }
      return List<PlayerChapter>.unmodifiable(chapters);
    } on Object catch (error, stackTrace) {
      AppLogger().w(
        'PlayerController: failed to read embedded chapters',
        error: error,
        stackTrace: stackTrace,
      );
      return const <PlayerChapter>[];
    }
  }

  bool get anime4kShadersAvailable =>
      anime4kSupported && shadersController.shadersDirectory != null;

  PlayerRuntimeSnapshot? readRuntimeSnapshot() {
    final player = mediaPlayer;
    if (_disposeRequested || player == null) return null;
    final state = player.state;
    return PlayerRuntimeSnapshot(
      playing: state.playing,
      buffering: state.buffering,
      completed: state.completed,
      volume: state.volume,
      position: state.position,
      buffer: state.buffer,
      duration: state.duration,
    );
  }

  bool get playerPlaying => readRuntimeSnapshot()?.playing ?? false;
  bool get playerBuffering => readRuntimeSnapshot()?.buffering ?? false;
  bool get playerCompleted => readRuntimeSnapshot()?.completed ?? false;
  double get playerVolume => readRuntimeSnapshot()?.volume ?? volume;
  Duration get playerPosition =>
      readRuntimeSnapshot()?.position ?? currentPosition;
  Duration get playerBuffer => readRuntimeSnapshot()?.buffer ?? buffer;
  Duration get playerDuration => readRuntimeSnapshot()?.duration ?? duration;

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
  bool androidAutoEnterPip = false;
  final LocalSubtitleMatcher _localSubtitleMatcher = LocalSubtitleMatcher();
  final LocalSubtitleImporter _localSubtitleImporter = LocalSubtitleImporter();
  bool get canImportSubtitleToVideoDirectory =>
      isLocalPlayback &&
      _localSubtitleImporter.supportsVideoDirectory(videoPath: videoUrl);
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
  ObservableList<PendingTrackLanguage> pendingTrackLanguages =
      ObservableList.of([]);
  @observable
  int trackLanguageConfirmationRevision = 0;
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

  // MobX 生成 mixin 需要在基类看到由应用协调器实现的公开入口。
  Future<bool> selectAudioTrack(String trackId, {bool manual = true});
  Future<bool> selectEmbeddedSubtitleTrack(String trackId,
      {bool manual = true});
  void _updateEmbeddedTracks(Tracks tracks);
  Future<String?> confirmTrackLanguages(
    int revision,
    Map<String, TrackLanguageChoice> choices,
  );
  Future<String?> confirmTrackLanguage(
    int revision,
    String fingerprint,
    TrackLanguageChoice choice,
  );
  Future<void> refreshSubtitleCandidates();
  Future<bool> selectSubtitle(String subtitlePath);
  Future<LocalSubtitleImportResult?> importSubtitle(
    String subtitlePath, {
    LocalSubtitleImportTarget target =
        LocalSubtitleImportTarget.subtitleDirectory,
  });
  Future<void> clearSubtitle();
  Future<bool> restoreLastSubtitle();
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
  });
  Future<void> resetSubtitleStyle();
  Future<void> setSubtitleDelay(double seconds);
  Future<void> resetSubtitleDelay();
  Future<void> setAnime4kPreference(Anime4kPreference value);
  void setAspectRatioType(int value);
}
