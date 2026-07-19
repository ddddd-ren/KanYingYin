import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/modules/bangumi/bangumi_item.dart';
import 'package:kanyingyin/modules/roads/road_module.dart';
import 'package:kanyingyin/modules/video/local_playback_session.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/pages/video/video_page_controller_interface.dart';
import 'package:kanyingyin/services/local_playback_request_builder.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:mobx/mobx.dart';

typedef LocalPlayerInitializer = Future<void> Function(
  PlaybackInitParams params,
);
typedef CloudPlaybackInitializer = Future<CloudResolvedPlayback> Function(
  CloudPlaybackTarget target,
);

class LocalVideoController implements IVideoPageController {
  LocalVideoController({
    LocalPlayerInitializer? initializePlayer,
    CloudPlaybackInitializer? resolveCloudPlayback,
  })  : _customPlayerInitializer = initializePlayer,
        _resolveCloudPlayback = resolveCloudPlayback;

  final LocalPlayerInitializer? _customPlayerInitializer;
  PlayerLifecycleToken? _playerLifecycleToken;
  CloudPlaybackInitializer? _resolveCloudPlayback;
  LocalPlaybackSession? _session;
  List<CloudPlaybackTarget>? _cloudTargets;
  String? _cloudSeriesTitle;
  PlaybackInitParams? _preparedCloudParams;
  final CloudPlaybackOperationCoordinator _playbackOperations =
      CloudPlaybackOperationCoordinator();
  CloudPlaybackSessionToken? _playbackSessionToken;

  @override
  late BangumiItem bangumiItem;

  @override
  final ObservableList<Road> roadList = ObservableList<Road>();

  final Observable<int> _currentEpisode = Observable(1);
  final Observable<int> _currentRoad = Observable(0);
  final Observable<bool> _loading = Observable(true);
  final Observable<String?> _errorMessage = Observable(null);
  final Observable<bool> _isFullscreen = Observable(false);
  final Observable<bool> _isPip = Observable(false);
  final Observable<bool> _showTabBody = Observable(true);

  @override
  int get currentEpisode => _currentEpisode.value;

  @override
  set currentEpisode(int value) =>
      runInAction(() => _currentEpisode.value = value);

  @override
  int get currentRoad => _currentRoad.value;

  @override
  set currentRoad(int value) => runInAction(() => _currentRoad.value = value);

  @override
  bool get loading => _loading.value;

  @override
  set loading(bool value) => runInAction(() => _loading.value = value);

  @override
  String? get errorMessage => _errorMessage.value;

  @override
  set errorMessage(String? value) =>
      runInAction(() => _errorMessage.value = value);

  @override
  bool get isFullscreen => _isFullscreen.value;

  @override
  set isFullscreen(bool value) =>
      runInAction(() => _isFullscreen.value = value);

  @override
  bool get isPip => _isPip.value;

  @override
  set isPip(bool value) => runInAction(() => _isPip.value = value);

  @override
  bool get showTabBody => _showTabBody.value;

  @override
  set showTabBody(bool value) => runInAction(() => _showTabBody.value = value);

  @override
  String title = '';

  @override
  int get actualEpisodeNumber => _cloudTargets != null
      ? currentEpisode
      : session.currentEpisode.episodeNumber ?? currentEpisode;

  bool get hasSession => _session != null || _cloudTargets != null;

  @override
  bool get isCloudPlayback => _cloudTargets != null;

  LocalPlaybackSession get session {
    final value = _session;
    if (value == null) {
      throw StateError('本地播放会话尚未初始化');
    }
    return value;
  }

  void openSession(LocalPlaybackSession session) {
    _playbackSessionToken = _playbackOperations.beginSession();
    _cloudTargets = null;
    _cloudSeriesTitle = null;
    _preparedCloudParams = null;
    _session = session;
    title = session.seriesTitle;
    currentRoad = 0;
    currentEpisode = session.currentIndex + 1;
    loading = false;
    errorMessage = null;
    bangumiItem = _buildBangumiItem(session);
    roadList
      ..clear()
      ..add(
        Road(
          name: '本地播放列表',
          data: session.episodes.map((episode) => episode.path).toList(),
          identifier: session.episodes.map((episode) => episode.title).toList(),
        ),
      );
  }

  void activatePlayerLifecycle() {
    if (_customPlayerInitializer != null) return;
    _playerLifecycleToken =
        Modular.get<PlayerController>().activatePlaybackLifecycle();
  }

  Future<void> _initializePlayback(PlaybackInitParams params) {
    final custom = _customPlayerInitializer;
    if (custom != null) return custom(params);
    final lifecycleToken = _playerLifecycleToken;
    if (lifecycleToken == null) return Future<void>.value();
    return Modular.get<PlayerController>().init(
      params,
      lifecycleToken: lifecycleToken,
    );
  }

  Future<void> openCloudPlayback({
    required String seriesTitle,
    required List<CloudPlaybackTarget> targets,
    required String selectedStableId,
    CloudPlaybackInitializer? resolver,
  }) async {
    if (targets.isEmpty) throw ArgumentError('云播放列表不能为空');
    final sourceId = targets.first.sourceId;
    if (targets.any((target) => target.sourceId != sourceId)) {
      throw ArgumentError('云播放列表不能混合不同来源');
    }
    final selectedIndex =
        targets.indexWhere((target) => target.stableId == selectedStableId);
    if (selectedIndex < 0) throw ArgumentError('选中的云媒体不在播放列表中');
    final sessionToken = _playbackOperations.beginSession();
    _playbackSessionToken = null;
    final requestToken = _playbackOperations.beginRequest(sessionToken);
    final playbackResolver = resolver ?? _resolveCloudPlayback;
    if (playbackResolver == null) throw StateError('网盘播放解析器尚未配置');
    try {
      final resolved = await playbackResolver(targets[selectedIndex]);
      if (!_playbackOperations.isCurrent(requestToken)) return;
      _session = null;
      _resolveCloudPlayback = playbackResolver;
      _cloudTargets = List<CloudPlaybackTarget>.unmodifiable(targets);
      _cloudSeriesTitle = seriesTitle;
      _playbackSessionToken = sessionToken;
      _preparedCloudParams = _cloudParams(
        resolved,
        selectedIndex + 1,
        0,
      );
      title = seriesTitle;
      currentRoad = 0;
      currentEpisode = selectedIndex + 1;
      loading = false;
      errorMessage = null;
      bangumiItem = _buildCloudBangumiItem(seriesTitle, sourceId);
      roadList
        ..clear()
        ..add(Road(
          name: '网盘播放列表',
          data: targets
              .map((target) => target.remotePath)
              .toList(growable: false),
          identifier:
              targets.map((target) => target.title).toList(growable: false),
        ));
    } catch (error) {
      if (!_playbackOperations.isCurrent(requestToken)) return;
      rethrow;
    }
  }

  void openFilePlayback({
    required String filePath,
    required String seriesTitle,
    List<Map<String, String>>? directoryFiles,
    bool playlistAlreadyIsolated = false,
    bool autoLoadSubtitle = true,
  }) {
    final session = LocalPlaybackRequestBuilder().buildSession(
      filePath: filePath,
      fileName: seriesTitle,
      directoryFiles: directoryFiles,
      playlistAlreadyIsolated: playlistAlreadyIsolated,
      autoLoadSubtitle: autoLoadSubtitle,
    );
    openSession(
      LocalPlaybackSession(
        seriesId: session.seriesId,
        seriesTitle: session.seriesTitle,
        episodes: session.episodes,
        currentEpisodeId: session.currentEpisodeId,
        coverPath: session.coverPath,
      ),
    );
  }

  void selectEpisode(String episodeId) {
    _session = session.selectEpisode(episodeId);
    currentEpisode = session.currentIndex + 1;
  }

  PlaybackInitParams createPlaybackParams() {
    return _localPlaybackParams(session);
  }

  PlaybackInitParams _localPlaybackParams(LocalPlaybackSession currentSession) {
    final episode = currentSession.currentEpisode;
    return PlaybackInitParams(
      videoUrl: episode.path,
      offset: 0,
      isLocalPlayback: true,
      bangumiId: _stableId(currentSession.seriesId),
      pluginName: '本地媒体库',
      episode: currentSession.currentIndex + 1,
      httpHeaders: const {},
      adBlockerEnabled: false,
      episodeTitle: episode.title,
      referer: '',
      currentRoad: 0,
      coverUrl: currentSession.coverPath,
      bangumiName: currentSession.seriesTitle,
      subtitlePath: episode.subtitlePath,
    );
  }

  @override
  Future<void> changeEpisode(
    int episode, {
    int currentRoad = 0,
    int offset = 0,
  }) async {
    final sessionToken = _playbackSessionToken;
    if (sessionToken == null) return;
    final requestToken = _playbackOperations.beginRequest(sessionToken);
    if (!_playbackOperations.isCurrent(requestToken)) return;
    final cloudTargets = _cloudTargets;
    final localSession = _session;
    final episodeCount =
        cloudTargets?.length ?? localSession?.episodes.length ?? 0;
    if (currentRoad != 0 || episode < 1 || episode > episodeCount) {
      return;
    }
    if (cloudTargets != null) {
      final prepared = _preparedCloudParams;
      if (prepared != null && episode == currentEpisode) {
        _preparedCloudParams = null;
        loading = true;
        try {
          await _initializePlayback(prepared.withOffset(offset));
          if (!_playbackOperations.isCurrent(requestToken)) return;
        } catch (error) {
          if (!_playbackOperations.isCurrent(requestToken)) return;
          errorMessage = '播放器加载失败：$error';
          rethrow;
        } finally {
          if (_playbackOperations.isCurrent(requestToken)) loading = false;
        }
        return;
      }
      await _changeCloudEpisode(
        cloudTargets,
        requestToken,
        episode,
        offset,
      );
      return;
    }
    if (localSession == null) return;
    final nextSession =
        localSession.selectEpisode(localSession.episodes[episode - 1].id);
    loading = true;
    errorMessage = null;
    try {
      await _initializePlayback(
        _localPlaybackParams(nextSession).withOffset(offset),
      );
      if (!_playbackOperations.isCurrent(requestToken)) return;
      _session = nextSession;
      currentEpisode = episode;
    } catch (error) {
      if (!_playbackOperations.isCurrent(requestToken)) return;
      errorMessage = '播放器加载失败：$error';
    } finally {
      if (_playbackOperations.isCurrent(requestToken)) loading = false;
    }
  }

  Future<void> _changeCloudEpisode(
    List<CloudPlaybackTarget> targets,
    CloudPlaybackRequestToken requestToken,
    int episode,
    int offset,
  ) async {
    final resolver = _resolveCloudPlayback;
    if (resolver == null) throw StateError('网盘播放解析器尚未配置');
    if (!_playbackOperations.isCurrent(requestToken)) return;
    loading = true;
    final target = targets[episode - 1];
    try {
      final resolved = await resolver(target);
      if (!_playbackOperations.isCurrent(requestToken)) return;
      await _initializePlayback(_cloudParams(resolved, episode, offset));
      if (!_playbackOperations.isCurrent(requestToken)) return;
      currentEpisode = episode;
      errorMessage = null;
    } catch (error) {
      if (!_playbackOperations.isCurrent(requestToken)) return;
      errorMessage = '网盘视频解析或加载失败：$error';
      rethrow;
    } finally {
      if (_playbackOperations.isCurrent(requestToken)) loading = false;
    }
  }

  PlaybackInitParams _cloudParams(
    CloudResolvedPlayback resolved,
    int episode,
    int offset,
  ) {
    final target = resolved.target;
    return PlaybackInitParams(
      videoUrl: resolved.videoUrl,
      offset: offset,
      isLocalPlayback: false,
      bangumiId: _stableId('${target.sourceId}|${_cloudSeriesTitle ?? ''}'),
      pluginName: '网盘媒体库',
      episode: episode,
      httpHeaders: resolved.httpHeaders,
      adBlockerEnabled: false,
      episodeTitle: target.title,
      referer: '',
      currentRoad: 0,
      bangumiName: _cloudSeriesTitle,
      subtitlePath: resolved.subtitlePath,
      subtitleStorageKey: target.subtitleOffsetKey,
      stableMediaKey: '${target.sourceId}|${target.stableId}',
      networkRoute: resolved.networkRoute,
      cloudProviderName: resolved.cloudProviderName,
      refreshCloudPlayback: () async {
        final refreshed = await _resolveCloudPlayback!(target);
        return _cloudParams(refreshed, episode, offset);
      },
    );
  }

  @override
  void cancelQueryRoads() {}

  void invalidatePlaybackOperations() {
    _playbackOperations.beginSession();
    _playbackSessionToken = null;
    _preparedCloudParams = null;
    _playerLifecycleToken = null;
  }

  @override
  void enterFullScreen() {
    Utils.enterFullScreen();
    isFullscreen = true;
  }

  @override
  void exitFullScreen() {
    Utils.exitFullScreen();
    isFullscreen = false;
  }

  BangumiItem _buildBangumiItem(LocalPlaybackSession session) {
    return BangumiItem(
      id: _stableId(session.seriesId),
      type: 0,
      name: session.seriesTitle,
      nameCn: session.seriesTitle,
      summary: '',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: {
        if (session.coverPath != null) 'large': session.coverPath!,
      },
      tags: [],
      alias: [],
      ratingScore: 0,
      votes: 0,
      votesCount: [],
      info: '',
    );
  }

  BangumiItem _buildCloudBangumiItem(String seriesTitle, String sourceId) {
    return BangumiItem(
      id: _stableId('$sourceId|$seriesTitle'),
      type: 0,
      name: seriesTitle,
      nameCn: seriesTitle,
      summary: '',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: const {},
      tags: const [],
      alias: const [],
      ratingScore: 0,
      votes: 0,
      votesCount: const [],
      info: '',
    );
  }

  int _stableId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
