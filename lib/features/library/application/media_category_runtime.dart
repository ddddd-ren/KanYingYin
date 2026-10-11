import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/library/application/media_library_classification.dart';
import 'package:kanyingyin/features/library/application/media_watch_state.dart';
import 'package:kanyingyin/features/player/application/player_bookmark.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';
import 'package:kanyingyin/modules/cloud/cloud_hidden_video.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
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
typedef MediaCategoryCloudLibraryRefresh = Future<void> Function();
typedef MediaCategoryCloudLibraryProvider = CloudMediaLibrary Function();
typedef MediaCategoryCloudHideAction = Future<void> Function(
  Iterable<MediaLibraryEpisode> episodes,
);

class MediaCategoryRuntime extends ChangeNotifier {
  MediaCategoryRuntime({
    required LocalController localController,
    required LocalVideoController videoController,
    required MediaCategoryCloudLibraryRefresh refreshCloudLibrary,
    MediaCategoryCloudLibraryRefresh? ensureCloudLibrary,
    required MediaCategoryCloudLibraryProvider cloudLibraryProvider,
    required MediaCategoryCloudHideAction hideCloudEpisodes,
    required TypedSettings settings,
    required Future<void> Function() navigateToPlayer,
    MediaLibraryUserStateRepository? userStateRepository,
  })  : _localController = localController,
        _videoController = videoController,
        _refreshCloudLibrary = refreshCloudLibrary,
        _ensureCloudLibrary = ensureCloudLibrary ?? refreshCloudLibrary,
        _cloudLibraryProvider = cloudLibraryProvider,
        _hideCloudEpisodes = hideCloudEpisodes,
        _settings = settings,
        _navigateToPlayer = navigateToPlayer,
        _userStateRepository =
            userStateRepository ?? MediaLibraryUserStateRepository() {
    MediaLibraryUserStateRepository.changes.addListener(_reloadUserStates);
  }

  final LocalController _localController;
  final LocalVideoController _videoController;
  final MediaCategoryCloudLibraryRefresh _refreshCloudLibrary;
  final MediaCategoryCloudLibraryRefresh _ensureCloudLibrary;
  final MediaCategoryCloudLibraryProvider _cloudLibraryProvider;
  final MediaCategoryCloudHideAction _hideCloudEpisodes;
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
        (mode) => mode.name == _settings.readRaw(SettingBoxKey.mediaClassificationMode),
        orElse: () => MediaClassificationMode.conservative,
      );

  Future<void> setClassificationMode(MediaClassificationMode mode) async {
    await _settings.write(SettingBoxKey.mediaClassificationMode, mode.name);
    MediaLibraryUserStateRepository.changes.value++;
  }

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

  Future<void> initialize() async {
    _userStates = await _userStateRepository.getAll();
    _localController.reloadAvailableLocalLibraryIndex();
    await _ensureCloudLibrary();
    await reconcileUserStates();
  }

  Future<void> refresh() async {
    _userStates = await _userStateRepository.getAll();
    _localController.reloadAvailableLocalLibraryIndex();
    await _refreshCloudLibrary();
    await reconcileUserStates();
  }

  Future<void> saveUserState(
    String seriesKey,
    MediaLibraryUserState state,
  ) =>
      _userStateLock.synchronized(() async {
        final ids = _mediaIdentities()[seriesKey];
        await _userStateRepository.save(
          seriesKey,
          state.copyWith(mediaIds: ids),
          preserveClassification: true,
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

  Map<String, Set<String>> _mediaIdentities() => {
        for (final series in library.series)
          series.key:
              series.episodes.map((episode) => episode.stableId).toSet(),
      };

  Future<void> reconcileUserStates() => _userStateLock.synchronized(() async {
        _userStates = await _userStateRepository.reconcile(_mediaIdentities());
      });

  Future<void> relinkUserState(String oldKey, String targetKey) =>
      _userStateLock.synchronized(() async {
        final ids = _mediaIdentities()[targetKey];
        if (ids == null) throw StateError('作品已不在媒体库中，请刷新后重试');
        await _userStateRepository.relink(oldKey, targetKey, ids);
        _userStates = await _userStateRepository.getAll();
      });

  CloudMediaLibrary get library {
    final local = _localController.localMediaLibrary;
    final cloud = _cloudLibraryProvider();
    return CloudMediaLibrary(
      series: <MediaLibrarySeries>[...local.series, ...cloud.series],
      filters: <MediaLibrarySourceFilter>[
        const MediaLibrarySourceFilter('all', '全部', null),
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
    await _hideCloudEpisodes(episodes);
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
    final currentSeries = matches.length == 1 ? matches.single : series;
    final currentEpisode = currentSeries
        .playbackEpisodesFor(episode)
        .singleWhere((item) => item.stableId == episode.stableId);
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
    await _videoController.openFilePlayback(
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
    await _videoController.openCloudPlayback(
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
