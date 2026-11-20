import 'dart:io';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/library/application/media_library_classification.dart';
import 'package:kanyingyin/features/library/application/media_watch_state.dart';
import 'package:kanyingyin/features/player/application/player_bookmark.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';
import 'package:kanyingyin/features/library/application/library_ports.dart';
import 'package:kanyingyin/modules/cloud/cloud_hidden_video.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/repositories/cloud_hidden_video_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/local_playback_request_builder.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

export 'package:kanyingyin/services/cloud/cloud_media_library.dart'
    show
        CloudMediaLibrary,
        MediaLibraryEpisode,
        MediaLibrarySeries,
        MediaLibraryVersionGroup,
        MediaSourceKind;

typedef MediaCategoryLibraryProvider = CloudMediaLibrary Function();
typedef MediaCategoryEpisodeAction = Future<void> Function(
  MediaLibrarySeries series,
  MediaLibraryEpisode episode,
);
typedef MediaCategoryHideEpisodesAction = Future<void> Function(
  MediaLibrarySeries series,
  List<MediaLibraryEpisode> episodes,
);

class MediaCategoryRuntime extends ChangeNotifier {
  MediaCategoryRuntime({
    required LocalLibraryPort localLibrary,
    required CloudLibraryPort cloudLibrary,
    required PlaybackPort playback,
    required TypedSettings settings,
    required Future<void> Function() navigateToPlayer,
    MediaLibraryUserStateRepository? userStateRepository,
    this.includeUnavailable = false,
  })  : _localLibrary = localLibrary,
        _cloudLibrary = cloudLibrary,
        _playback = playback,
        _settings = settings,
        _navigateToPlayer = navigateToPlayer,
        _userStateRepository =
            userStateRepository ?? MediaLibraryUserStateRepository() {
    MediaLibraryUserStateRepository.changes.addListener(_reloadUserStates);
  }

  final bool includeUnavailable;
  final LocalLibraryPort _localLibrary;
  final CloudLibraryPort _cloudLibrary;
  final PlaybackPort _playback;
  final TypedSettings _settings;
  final Future<void> Function() _navigateToPlayer;
  final MediaLibraryUserStateRepository _userStateRepository;
  final Lock _userStateLock = Lock();
  Map<String, MediaLibraryUserState> _userStates =
      const <String, MediaLibraryUserState>{};

  Map<String, MediaLibraryUserState> get userStates => _userStates;
  bool _disposed = false;

  MediaClassificationMode get classificationMode =>
      MediaClassificationMode.values.firstWhere(
        (mode) =>
            mode.name ==
            _settings.readRaw(SettingBoxKey.mediaClassificationMode),
        orElse: () => MediaClassificationMode.conservative,
      );

  Future<void> _reloadUserStates() async {
    try {
      final states = await _userStateRepository.getAll();
      if (_disposed) return;
      _userStates = states;
      notifyListeners();
    } on Object {
      // 设置暂不可读时保留当前人工选择，避免回退到自动分类。
    }
  }

  @override
  void dispose() {
    _disposed = true;
    MediaLibraryUserStateRepository.changes.removeListener(_reloadUserStates);
    super.dispose();
  }

  late final MediaWatchStateRepository _watchRepository =
      MediaWatchStateRepository(TypedSettingsPlayerBookmarkStorage(_settings,
          storageKey: SettingBoxKey.mediaWatchStates));
  Map<String, MediaWatchState> get watchStates => _watchRepository.loadAll();
  Future<void> setWatched(List<MediaLibraryEpisode> episodes, bool watched) =>
      _watchRepository.setWatched(
          episodes.map(mediaWatchKeyForEpisode), watched);

  bool _initialized = false;
  int _loadGeneration = 0;
  CloudMediaLibrary? _identityLocal, _identityCloud;
  Map<String, Set<String>> _identities = const {};
  CloudMediaLibrary? _lastLocal, _lastCloud, _merged;

  Future<void> initialize() => _load(refresh: false);
  Future<void> refresh() => _load(refresh: true);

  Future<void> _load({required bool refresh}) async {
    final generation = ++_loadGeneration;
    _initialized = false;
    await Future.wait([
      _localLibrary.ensureLibrary(refresh: refresh),
      refresh ? _cloudLibrary.refreshLibrary() : _cloudLibrary.ensureLibrary(),
      _userStateRepository.getAll().then((states) {
        if (!_disposed && generation == _loadGeneration) _userStates = states;
      }),
    ]);
    if (_disposed || generation != _loadGeneration) return;
    _initialized = true;
    await reconcileUserStates();
  }

  Future<void> saveUserState(
    String seriesKey, {
    bool? favorite,
    bool? watchLater,
    List<String>? collections,
  }) =>
      _userStateLock.synchronized(() async {
        final ids = _mediaIdentities()[seriesKey];
        if (ids == null) throw StateError('作品已不在媒体库中，请刷新后重试');
        await _userStateRepository.updateMarks(
          seriesKey,
          favorite: favorite,
          watchLater: watchLater,
          collections: collections,
          mediaIds: ids,
        );
        _userStates = await _userStateRepository.getAll();
      });

  Future<void> saveClassification(
    String seriesKey,
    MediaLibraryUserState state,
  ) =>
      _userStateLock.synchronized(() async {
        final ids = _mediaIdentities()[seriesKey];
        if (ids == null) throw StateError('作品已不在媒体库中，请刷新后重试');
        await _userStateRepository.saveClassification(
          seriesKey,
          categories: state.categoryOverride,
          genres: state.genreOverride,
          mediaIds: ids,
        );
        _userStates = await _userStateRepository.getAll();
      });

  Map<String, Set<String>> _mediaIdentities() {
    final local = _localLibrary.cachedLibrary;
    final cloud = _cloudLibrary.cachedLibrary;
    if (!identical(local, _identityLocal) ||
        !identical(cloud, _identityCloud)) {
      _identityLocal = local;
      _identityCloud = cloud;
      _identities = {
        for (final works in [local.series, cloud.series])
          for (final series in works)
            series.key:
                series.episodes.map((episode) => episode.stableId).toSet(),
      };
    }
    return _identities;
  }

  Future<void> reconcileUserStates() => _userStateLock.synchronized(() async {
        if (!_initialized ||
            !_cloudLibrary.snapshotComplete ||
            _userStates.isEmpty) {
          return;
        }
        final identities = _mediaIdentities();
        final local = _identityLocal;
        final cloud = _identityCloud;
        _userStates = await _userStateRepository.reconcile(identities,
            isCurrent: () =>
                !_disposed &&
                _initialized &&
                _cloudLibrary.snapshotComplete &&
                identical(local, _localLibrary.cachedLibrary) &&
                identical(cloud, _cloudLibrary.cachedLibrary));
      });

  Future<void> relinkUserState(String oldKey, String targetKey) =>
      _userStateLock.synchronized(() async {
        final ids = _mediaIdentities()[targetKey];
        if (ids == null) throw StateError('作品已不在媒体库中，请刷新后重试');
        await _userStateRepository.relink(oldKey, targetKey, ids);
        _userStates = await _userStateRepository.getAll();
      });

  CloudMediaLibrary get library {
    final local = includeUnavailable
        ? _localLibrary.cachedLibrary
        : _localLibrary.library;
    final cloud = includeUnavailable
        ? _cloudLibrary.cachedLibrary
        : _cloudLibrary.library;
    if (identical(_lastLocal, local) && identical(_lastCloud, cloud)) {
      return _merged!;
    }
    _lastLocal = local;
    _lastCloud = cloud;
    return _merged = CloudMediaLibrary(
      series: <MediaLibrarySeries>[...local.series, ...cloud.series],
      filters: <MediaLibrarySourceFilter>[
        const MediaLibrarySourceFilter('all', '全部来源', null),
        const MediaLibrarySourceFilter('local', '本地', MediaSourceKind.local),
        ...cloud.filters.where((item) => item.id != 'all'),
      ],
    );
  }

  Future<void> hideEpisodes(
    MediaLibrarySeries series,
    List<MediaLibraryEpisode> episodes,
  ) async {
    if (series.sourceKind != MediaSourceKind.cloud) {
      throw ArgumentError.value(series.sourceKind, 'series', '只能隐藏网盘视频');
    }
    await _cloudLibrary.hideEpisodes(episodes);
  }

  Future<void> playEpisode(
    MediaLibrarySeries series,
    MediaLibraryEpisode episode,
  ) async {
    final matches = library.series
        .where((candidate) =>
            candidate.sourceKind == series.sourceKind &&
            candidate.sourceId == series.sourceId &&
            candidate.episodes.any((item) => item.stableId == episode.stableId))
        .take(2)
        .toList(growable: false);
    if (matches.length != 1) throw StateError('作品已不在媒体库中，请刷新后重试');
    final currentSeries = matches.single;
    if (!currentSeries.isAvailable) throw StateError('来源暂不可用，请恢复来源后刷新');
    final currentEpisode = currentSeries
        .playbackEpisodesFor(episode)
        .singleWhere((item) => item.stableId == episode.stableId);
    if (!currentEpisode.isAvailable) throw StateError('视频暂不可用，请检查媒体来源');
    final opened = currentSeries.sourceKind == MediaSourceKind.local
        ? await _openLocalEpisode(currentSeries, currentEpisode)
        : await _openCloudEpisode(currentSeries, currentEpisode);
    if (opened) await _navigateToPlayer();
  }

  Future<bool> _openLocalEpisode(
    MediaLibrarySeries series,
    MediaLibraryEpisode episode,
  ) async {
    final items = series.episodes
        .map((item) => item.localItem)
        .whereType<LocalMediaIndexItem>()
        .toList(growable: false);
    final selected = episode.localItem;
    if (selected == null || items.isEmpty) return false;
    if (selected.location.isFile && !await File(selected.path).exists()) {
      await _localLibrary.ensureLibrary(refresh: true);
      throw StateError('文件已不存在，请检查媒体来源');
    }
    await _playback.openFile(
      filePath: selected.path,
      seriesTitle: series.title,
      legacySeriesTitles: series.legacySeriesTitles,
      directoryFiles: [
        for (final entry in series.episodes)
          if (entry.localItem case final item?)
            <String, String>{
              'path': item.path,
              'name': item.name,
              'title': p.basenameWithoutExtension(entry.name),
            },
      ],
      playbackEntries: [
        for (final entry in series.episodes)
          if (entry.localItem case final item?)
            LocalPlaybackEntry(
              location: item.location,
              parentLocation: item.parentLocation,
              name: item.name,
              title: p.basenameWithoutExtension(entry.name),
              subtitlePath: item.subtitlePath,
            ),
      ],
      playlistAlreadyIsolated: true,
      autoLoadSubtitle: _settings.getTyped<bool>(
        SettingBoxKey.localAutoLoadSubtitle,
        defaultValue: true,
      ),
    );
    return true;
  }

  Future<bool> _openCloudEpisode(
    MediaLibrarySeries series,
    MediaLibraryEpisode episode,
  ) async {
    final targets = <CloudPlaybackTarget>[
      for (final item in series.playbackEpisodesFor(episode))
        if (item.remoteId != null && item.remotePath != null)
          CloudPlaybackTarget(
            sourceId: item.sourceId,
            remoteId: item.remoteId!,
            remotePath: item.remotePath!,
            stableId: item.stableId,
            title: item.name,
            episodeNumber: item.episodeNumber,
            subtitleRemoteId: item.subtitleRemoteRefs.isEmpty
                ? null
                : item.subtitleRemoteRefs.first.id,
            subtitleRemotePath: item.subtitleRemoteRefs.isEmpty
                ? null
                : item.subtitleRemoteRefs.first.path,
            posterUrl: item.tmdbPosterUrl ?? series.tmdbPosterUrl,
            posterCachePath: item.posterCachePath ?? series.posterCachePath,
            size: item.size,
            modifiedAt: item.modifiedAt,
          ),
    ];
    if (targets.isEmpty) return false;
    await _playback.openCloud(
      seriesTitle: series.title,
      workKey: series.seriesKey,
      legacySeriesTitles: series.legacySeriesTitles,
      targets: targets,
      selectedStableId: episode.stableId,
      resolver: CloudPlaybackResolver().resolve,
    );
    return true;
  }
}

class MediaCategoryHiddenVideoState {
  MediaCategoryHiddenVideoState(
      {required ICloudHiddenVideoRepository repository})
      : _repository = repository;

  final ICloudHiddenVideoRepository _repository;
  final Map<String, List<CloudHiddenVideo>> _recordsBySource =
      <String, List<CloudHiddenVideo>>{};

  Future<void> load(Iterable<String> sourceIds) async {
    final uniqueSourceIds = sourceIds
        .map((sourceId) => sourceId.trim())
        .where((sourceId) => sourceId.isNotEmpty)
        .toSet();
    final loaded = <String, List<CloudHiddenVideo>>{};
    for (final sourceId in uniqueSourceIds) {
      loaded[sourceId] = await _repository.getBySource(sourceId);
    }
    _recordsBySource
      ..clear()
      ..addAll(loaded);
  }

  Iterable<CloudMediaIndexItem> visibleCloudItems(
    Iterable<CloudMediaIndexItem> items,
  ) sync* {
    for (final item in items) {
      final records = _recordsBySource[item.sourceId];
      final hidden = records?.any(
            (record) => record.matches(
              sourceId: item.sourceId,
              remoteId: item.remoteId,
              remotePath: item.remotePath,
            ),
          ) ==
          true;
      if (!hidden) yield item;
    }
  }

  Future<void> hideEpisodes(Iterable<MediaLibraryEpisode> episodes) async {
    final episodesBySource = <String, List<MediaLibraryEpisode>>{};
    for (final episode in episodes) {
      final remoteId = episode.remoteId;
      final remotePath = episode.remotePath;
      if (episode.sourceKind != MediaSourceKind.cloud ||
          remoteId == null ||
          remotePath == null) {
        throw ArgumentError.value(episode, 'episodes', '隐藏项必须是有效的网盘视频');
      }
      episodesBySource.putIfAbsent(episode.sourceId, () => []).add(episode);
    }

    for (final entry in episodesBySource.entries) {
      final sourceId = entry.key;
      final recordsByIdentity = <String, CloudHiddenVideo>{
        for (final record in await _repository.getBySource(sourceId))
          record.identityKey: record,
      };
      for (final episode in entry.value) {
        final record = CloudHiddenVideo(
          sourceId: sourceId,
          remoteId: episode.remoteId!,
          remotePath: normalizeCloudHiddenVideoPath(episode.remotePath!),
          fileName: episode.name,
        );
        recordsByIdentity[record.identityKey] = record;
      }
      final records = recordsByIdentity.values.toList(growable: false);
      await _repository.replaceSource(sourceId, records);
      _recordsBySource[sourceId] = records;
    }
  }
}
