import 'dart:async';

import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/history/domain/playback_history_entry.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/roads/road_module.dart';
import 'package:kanyingyin/modules/video/local_playback_session.dart';
import 'package:kanyingyin/modules/video/playback_media_item.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/features/player/application/track_selection_preferences.dart';
import 'package:kanyingyin/pages/video/video_page_controller_interface.dart';
import 'package:kanyingyin/services/local_playback_request_builder.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:kanyingyin/services/local_series_grouper.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:mobx/mobx.dart';
import 'package:path/path.dart' as p;

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
  String _cloudTrackPreferenceKey = '';
  int? _cloudMediaId;
  final Map<String, String> _cloudEpisodeTitles = {};
  List<String> _cloudLegacySeriesTitles = const [];
  String _localRawSeriesTitle = '';
  List<String> _localLegacySeriesTitles = const [];
  PlaybackInitParams? _preparedCloudParams;
  final CloudPlaybackOperationCoordinator _playbackOperations =
      CloudPlaybackOperationCoordinator();
  CloudPlaybackSessionToken? _playbackSessionToken;

  @override
  late PlaybackMediaItem mediaItem;

  @override
  final ObservableList<Road> roadList = ObservableList<Road>();

  final Observable<int> _currentEpisode = Observable(1);
  final Observable<int> _currentRoad = Observable(0);
  final Observable<bool> _loading = Observable(true);
  final Observable<String?> _errorMessage = Observable(null);
  final Observable<bool> _isFullscreen = Observable(false);
  Future<void>? _fullscreenTransition;
  bool _fullscreenTarget = false;
  final Observable<bool> _isPip = Observable(false);
  final Observable<bool> _showTabBody = Observable(true);
  final Observable<CloudRangeRelayStatus?> _relayStatus = Observable(null);
  final Observable<int?> _relayTotalBytes = Observable(null);
  StreamSubscription<CloudRangeRelayStatus>? _relayStatusSubscription;
  var _relayStatusGeneration = 0;

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

  CloudPlaybackTarget? get currentCloudPlaybackTarget {
    final targets = _cloudTargets;
    return targets != null &&
            currentEpisode >= 1 &&
            currentEpisode <= targets.length
        ? targets[currentEpisode - 1]
        : null;
  }

  bool refreshCloudSourceTitles(Iterable<MediaLibrarySeries> sourceSeries) {
    final current = currentCloudPlaybackTarget;
    final targets = _cloudTargets;
    if (current == null || targets == null) return false;
    bool matches(CloudPlaybackTarget target, MediaLibraryEpisode episode) =>
        episode.sourceId == target.sourceId &&
        (target.remoteId.trim().isNotEmpty
            ? episode.remoteId == target.remoteId
            : episode.remotePath == target.remotePath);
    final matched = sourceSeries
        .where((series) =>
            series.sourceKind == MediaSourceKind.cloud &&
            series.sourceId == current.sourceId &&
            series.episodes.any((episode) => matches(current, episode)))
        .take(2)
        .toList(growable: false);
    if (matched.length != 1 || matched.single.title.trim().isEmpty) return false;
    final series = matched.single;
    var changed = _cloudSeriesTitle != series.title;
    for (final target in targets) {
      final episodes = series.episodes
          .where((episode) => matches(target, episode))
          .take(2)
          .toList(growable: false);
      if (episodes.length != 1 || episodes.single.name.trim().isEmpty) continue;
      final name = episodes.single.name;
      if ((_cloudEpisodeTitles[target.stableId] ?? target.title) != name) {
        _cloudEpisodeTitles[target.stableId] = name;
        changed = true;
      }
    }
    _cloudLegacySeriesTitles =
        List<String>.unmodifiable(series.legacySeriesTitles);
    _cloudSeriesTitle = series.title;
    final prepared = _preparedCloudParams;
    if (prepared != null) {
      final target = targets[prepared.episode - 1];
      _preparedCloudParams = prepared.withDisplayTitles(
        mediaTitle: series.title,
        episodeTitle: _cloudEpisodeTitles[target.stableId] ?? target.title,
        legacyTrackPreferenceKeys: _cloudLegacyTrackPreferenceKeys(current.sourceId),
      );
    }
    if (!changed) return false;
    title = series.title;
    mediaItem = PlaybackMediaItem(
      id: mediaItem.id,
      title: series.title,
      displayTitle: series.title,
      summary: mediaItem.summary,
      artworkUrl: mediaItem.artworkUrl,
    );
    if (roadList.isNotEmpty) {
      final road = roadList.first;
      roadList[0] = Road(
        name: road.name,
        data: road.data,
        identifier: targets
            .map((target) => _cloudEpisodeTitles[target.stableId] ?? target.title)
            .toList(growable: false),
      );
    }
    return true;
  }

  @override
  CloudRangeRelayStatus? get relayStatus => _relayStatus.value;

  @override
  int? get relayTotalBytes => _relayTotalBytes.value;

  LocalPlaybackSession get session {
    final value = _session;
    if (value == null) {
      throw StateError('本地播放会话尚未初始化');
    }
    return value;
  }

  /// 构造当前剧集对应的观看历史记录。
  PlaybackHistoryEntry? buildPlaybackHistoryEntry({
    required Duration position,
    required Duration duration,
  }) {
    final localSession = _session;
    final cloudTargets = _cloudTargets;
    if (localSession != null) {
      final episode = localSession.currentEpisode;
      return PlaybackHistoryEntry(
        stableKey: _localHistoryKey(episode.id),
        source: PlaybackHistorySource.local,
        sourceId: 'local',
        seriesTitle: localSession.seriesTitle,
        episodeTitle: episode.title,
        mediaPath: episode.path,
        episodeIndex: episode.episodeNumber ?? localSession.currentIndex + 1,
        positionSeconds: _seconds(position),
        durationSeconds: _seconds(duration),
        updatedAt: DateTime.now(),
        posterCachePath: localSession.coverPath,
      );
    }
    if (cloudTargets != null &&
        currentEpisode >= 1 &&
        currentEpisode <= cloudTargets.length) {
      final target = cloudTargets[currentEpisode - 1];
      CloudPlaybackTarget? posterFallback;
      for (final candidate in cloudTargets) {
        if (candidate.posterUrl?.trim().isNotEmpty == true ||
            candidate.posterCachePath?.trim().isNotEmpty == true) {
          posterFallback = candidate;
          break;
        }
      }
      return PlaybackHistoryEntry(
        stableKey: _cloudHistoryKey(target),
        source: PlaybackHistorySource.cloud,
        sourceId: target.sourceId,
        seriesTitle: _cloudSeriesTitle ?? title,
        episodeTitle: _cloudEpisodeTitles[target.stableId] ?? target.title,
        mediaPath: target.remotePath,
        remoteId: target.remoteId,
        episodeIndex: target.episodeNumber ?? currentEpisode,
        positionSeconds: _seconds(position),
        durationSeconds: _seconds(duration),
        updatedAt: DateTime.now(),
        posterUrl: target.posterUrl?.trim().isNotEmpty == true
            ? target.posterUrl
            : posterFallback?.posterUrl,
        posterCachePath: target.posterCachePath?.trim().isNotEmpty == true
            ? target.posterCachePath
            : posterFallback?.posterCachePath,
      );
    }
    return null;
  }

  String? get currentPlaybackHistoryKey {
    final localSession = _session;
    if (localSession != null) {
      return _localHistoryKey(localSession.currentEpisode.id);
    }
    final cloudTargets = _cloudTargets;
    if (cloudTargets != null &&
        currentEpisode >= 1 &&
        currentEpisode <= cloudTargets.length) {
      return _cloudHistoryKey(cloudTargets[currentEpisode - 1]);
    }
    return null;
  }

  void openSession(LocalPlaybackSession session,
      {List<String>? legacySeriesTitles, String? originalFileName}) {
    _playbackSessionToken = _playbackOperations.beginSession();
    _cloudTargets = null;
    _cloudSeriesTitle = null;
    _cloudTrackPreferenceKey = '';
    _cloudMediaId = null;
    _cloudEpisodeTitles.clear();
    _cloudLegacySeriesTitles = const [];
    _replacePreparedCloudParams(null);
    _trackRelayLease(null, null);
    _session = session;
    final rawEpisode = session.episodes.first;
    final rawPath = originalFileName == null
        ? rawEpisode.path
        : p.join(p.dirname(rawEpisode.path), originalFileName);
    _localRawSeriesTitle = const LocalSeriesGrouper()
        .group([
          LocalFileItem(
            path: rawPath,
            name: p.basename(rawPath),
            size: 0,
            modified: DateTime.fromMillisecondsSinceEpoch(0),
            isDirectory: false,
            isVideo: true,
            episodeInfo: LocalEpisodeParser().parse(rawPath),
          ),
        ])
        .single
        .title;
    _localLegacySeriesTitles = List<String>.unmodifiable(
        legacySeriesTitles ?? [session.seriesTitle]);
    title = session.seriesTitle;
    currentRoad = 0;
    currentEpisode = session.currentIndex + 1;
    loading = false;
    errorMessage = null;
    mediaItem = _buildMediaItem(session);
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
    String? workKey,
    List<String>? legacySeriesTitles,
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
    _replacePreparedCloudParams(null);
    _playbackSessionToken = null;
    final requestToken = _playbackOperations.beginRequest(sessionToken);
    final playbackResolver = resolver ?? _resolveCloudPlayback;
    if (playbackResolver == null) throw StateError('网盘播放解析器尚未配置');
    try {
      final resolved = await playbackResolver(targets[selectedIndex]);
      if (!_playbackOperations.isCurrent(requestToken)) {
        await resolved.lease?.close();
        return;
      }
      _session = null;
      _resolveCloudPlayback = playbackResolver;
      _cloudTargets = List<CloudPlaybackTarget>.unmodifiable(targets);
      _cloudSeriesTitle = seriesTitle;
      final stableWorkKey = workKey?.trim();
      _cloudTrackPreferenceKey = stableWorkKey?.isNotEmpty == true
          ? 'cloud-work|$sourceId|$stableWorkKey'
          : 'cloud|$sourceId|$seriesTitle';
      _cloudMediaId = _stableId('$sourceId|$seriesTitle');
      _cloudEpisodeTitles.clear();
      _cloudLegacySeriesTitles =
          List<String>.unmodifiable(legacySeriesTitles ?? [seriesTitle]);
      _playbackSessionToken = sessionToken;
      _replacePreparedCloudParams(_cloudParams(
        resolved,
        selectedIndex + 1,
        0,
      ));
      title = seriesTitle;
      currentRoad = 0;
      currentEpisode = selectedIndex + 1;
      loading = false;
      errorMessage = null;
      mediaItem = _buildCloudMediaItem(seriesTitle, sourceId);
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

  Future<void> openFilePlayback({
    required String filePath,
    required String seriesTitle,
    List<String>? legacySeriesTitles,
    List<Map<String, String>>? directoryFiles,
    List<LocalPlaybackEntry>? playbackEntries,
    bool playlistAlreadyIsolated = false,
    bool autoLoadSubtitle = true,
  }) async {
    final session = await LocalPlaybackRequestBuilder().buildSession(
      filePath: filePath,
      fileName: seriesTitle,
      directoryFiles: directoryFiles,
      playbackEntries: playbackEntries,
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
      legacySeriesTitles: legacySeriesTitles,
      originalFileName: playbackEntries
          ?.where((entry) => entry.location.stableId == session.episodes.first.id)
          .firstOrNull
          ?.name,
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
      mediaId: _stableId(currentSession.seriesId),
      sourceLabel: '本地媒体库',
      episode: currentSession.currentIndex + 1,
      httpHeaders: const {},
      episodeTitle: episode.title,
      referer: '',
      currentRoad: 0,
      coverUrl: currentSession.coverPath,
      mediaTitle: currentSession.seriesTitle,
      subtitlePath: episode.subtitlePath,
      stableMediaKey: _localHistoryKey(episode.id),
      trackPreferenceKey:
          'local-work-id|${currentSession.seriesId}|${Uri.encodeComponent(_localRawSeriesTitle.trim().toLowerCase())}',
      legacyTrackPreferenceKeys: {
        for (final oldTitle in _localLegacySeriesTitles)
          localWorkTrackPreferenceKey(currentSession.seriesId, oldTitle),
      }.toList(growable: false),
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
          await prepared.lease?.close();
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
      if (!_playbackOperations.isCurrent(requestToken)) {
        await resolved.lease?.close();
        return;
      }
      final params = _cloudParams(resolved, episode, offset);
      try {
        await _initializePlayback(params);
      } on Object {
        await params.lease?.close();
        rethrow;
      }
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
    _trackRelayLease(resolved.lease, resolved.totalBytes);
    final target = resolved.target;
    return PlaybackInitParams(
      videoUrl: resolved.videoUrl,
      offset: offset,
      isLocalPlayback: false,
      mediaId: _cloudMediaId ?? _stableId(target.sourceId),
      sourceLabel: '网盘媒体库',
      episode: episode,
      httpHeaders: resolved.httpHeaders,
      episodeTitle: _cloudEpisodeTitles[target.stableId] ?? target.title,
      referer: '',
      currentRoad: 0,
      mediaTitle: _cloudSeriesTitle,
      subtitlePath: resolved.subtitlePath,
      subtitleDisplayName: target.subtitleDisplayName,
      subtitleStorageKey: target.subtitleOffsetKey,
      stableMediaKey: '${target.sourceId}|${target.stableId}',
      trackPreferenceKey: _cloudTrackPreferenceKey,
      legacyTrackPreferenceKeys:
          _cloudLegacyTrackPreferenceKeys(target.sourceId),
      mediaRevision:
          'remote:${target.size ?? resolved.totalBytes ?? ''}:${target.modifiedAt?.microsecondsSinceEpoch ?? ''}',
      networkRoute: resolved.networkRoute,
      cloudProviderName: resolved.cloudProviderName,
      transport: resolved.transport,
      lease: resolved.lease,
      totalBytes: resolved.totalBytes,
      refreshCloudPlayback: () async {
        final refreshed = await _resolveCloudPlayback!(target);
        return _cloudParams(refreshed, episode, offset);
      },
    );
  }

  List<String> _cloudLegacyTrackPreferenceKeys(String sourceId) => {
        for (final oldTitle in _cloudLegacySeriesTitles)
          if (oldTitle.trim().isNotEmpty) 'cloud|$sourceId|$oldTitle',
      }.toList(growable: false);

  @override
  void cancelQueryRoads() {}

  void invalidatePlaybackOperations() {
    _playbackOperations.beginSession();
    _playbackSessionToken = null;
    _replacePreparedCloudParams(null);
    _trackRelayLease(null, null);
    _playerLifecycleToken = null;
  }

  void _trackRelayLease(CloudPlaybackLease? lease, int? totalBytes) {
    final generation = ++_relayStatusGeneration;
    unawaited(_relayStatusSubscription?.cancel());
    _relayStatusSubscription = null;
    runInAction(() {
      _relayStatus.value = lease?.currentStatus;
      _relayTotalBytes.value = totalBytes;
    });
    if (lease == null) return;
    _relayStatusSubscription = lease.statuses.listen((status) {
      if (generation != _relayStatusGeneration) return;
      runInAction(() => _relayStatus.value = status);
    });
  }

  void _replacePreparedCloudParams(PlaybackInitParams? params) {
    final previous = _preparedCloudParams;
    _preparedCloudParams = params;
    if (previous != null && !identical(previous.lease, params?.lease)) {
      unawaited(previous.lease?.close());
    }
  }

  @override
  Future<void> enterFullScreen() => _setFullscreen(true);

  @override
  Future<void> exitFullScreen() => _setFullscreen(false);

  Future<void>? get fullscreenTransition => _fullscreenTransition;

  Future<void> _setFullscreen(bool value) {
    _fullscreenTarget = value;
    if (_fullscreenTransition == null && isFullscreen == value) {
      return Future<void>.value();
    }
    return _fullscreenTransition ??= _applyFullscreenTarget();
  }

  Future<void> _applyFullscreenTarget() async {
    // 所有入口共享原生完成信号，切换期间仅保留最后一次目标。
    try {
      while (isFullscreen != _fullscreenTarget) {
        final target = _fullscreenTarget;
        if (target) {
          await Utils.enterFullScreen();
        } else {
          await Utils.exitFullScreen();
        }
        isFullscreen = target;
      }
    } finally {
      _fullscreenTransition = null;
    }
  }

  PlaybackMediaItem _buildMediaItem(LocalPlaybackSession session) {
    return PlaybackMediaItem(
      id: _stableId(session.seriesId),
      title: session.seriesTitle,
      displayTitle: session.seriesTitle,
      summary: '',
      artworkUrl: session.coverPath,
    );
  }

  PlaybackMediaItem _buildCloudMediaItem(String seriesTitle, String sourceId) {
    return PlaybackMediaItem(
      id: _stableId('$sourceId|$seriesTitle'),
      title: seriesTitle,
      displayTitle: seriesTitle,
      summary: '',
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

  static int _seconds(Duration value) {
    final seconds = value.inSeconds;
    if (seconds < 0) return 0;
    if (seconds > 2147483647) return 2147483647;
    return seconds;
  }

  static String _localHistoryKey(String episodeId) => 'local|$episodeId';

  static String _cloudHistoryKey(CloudPlaybackTarget target) =>
      '${target.sourceId}|${target.stableId}';
}
