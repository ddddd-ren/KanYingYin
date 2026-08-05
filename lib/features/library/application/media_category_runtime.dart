import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/modules/cloud/cloud_hidden_video.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
import 'package:kanyingyin/repositories/cloud_hidden_video_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/local_playback_request_builder.dart';
import 'package:path/path.dart' as p;

export 'package:kanyingyin/services/cloud/cloud_media_library.dart'
    show
        CloudMediaLibrary,
        MediaLibraryEpisode,
        MediaLibrarySeries,
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

class MediaCategoryRuntime {
  MediaCategoryRuntime({
    required LocalController localController,
    required LocalVideoController videoController,
    required CloudWorkTmdbRepository workTmdbRepository,
    required ICloudHiddenVideoRepository hiddenVideoRepository,
    required TypedSettings settings,
    required Future<void> Function() navigateToPlayer,
  })  : _localController = localController,
        _videoController = videoController,
        _workTmdbRepository = workTmdbRepository,
        _hiddenVideos = MediaCategoryHiddenVideoState(
          repository: hiddenVideoRepository,
        ),
        _settings = settings,
        _navigateToPlayer = navigateToPlayer;

  final LocalController _localController;
  final LocalVideoController _videoController;
  final CloudWorkTmdbRepository _workTmdbRepository;
  final MediaCategoryHiddenVideoState _hiddenVideos;
  final TypedSettings _settings;
  final Future<void> Function() _navigateToPlayer;

  Map<String, CloudWorkTmdbRecord> _workRecords =
      const <String, CloudWorkTmdbRecord>{};

  Future<void> initialize() async {
    _localController.reloadLocalLibraryIndex();
    await _localController.reloadCloudLibraryIndex();
    await _hiddenVideos.load(
      _localController.cloudLibrarySources.map((source) => source.id),
    );
    final records = await _workTmdbRepository.getAll();
    _workRecords = <String, CloudWorkTmdbRecord>{
      for (final record in records) record.workKey: record,
    };
  }

  CloudMediaLibrary get library => const CloudMediaLibraryAggregator().build(
        localItems: _localController.localLibraryItems,
        cloudItems: _hiddenVideos.visibleCloudItems(
          _localController.cloudLibraryItems,
        ),
        cloudSources: _localController.cloudLibrarySources,
        workRecordsByKey: _workRecords,
      );

  Future<void> hideEpisodes(
    MediaLibrarySeries series,
    List<MediaLibraryEpisode> episodes,
  ) async {
    if (series.sourceKind != MediaSourceKind.cloud) {
      throw ArgumentError.value(series.sourceKind, 'series', '只能隐藏网盘视频');
    }
    await _hiddenVideos.hideEpisodes(episodes);
  }

  Future<void> playEpisode(
    MediaLibrarySeries series,
    MediaLibraryEpisode episode,
  ) async {
    final opened = series.sourceKind == MediaSourceKind.local
        ? await _openLocalEpisode(series, episode)
        : await _openCloudEpisode(series, episode);
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
      directoryFiles: [
        for (final item in items)
          <String, String>{
            'path': item.path,
            'name': item.name,
            'title': p.basenameWithoutExtension(item.name),
          },
      ],
      playbackEntries: [
        for (final item in items)
          LocalPlaybackEntry(
            location: item.location,
            parentLocation: item.parentLocation,
            name: item.name,
            title: p.basenameWithoutExtension(item.name),
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
      for (final item in series.episodes)
        if (item.remoteId != null && item.remotePath != null)
          CloudPlaybackTarget(
            sourceId: item.sourceId,
            remoteId: item.remoteId!,
            remotePath: item.remotePath!,
            stableId: item.stableId,
            title: item.name,
            subtitleRemoteId: item.subtitleRemoteRefs.isEmpty
                ? null
                : item.subtitleRemoteRefs.first.id,
            subtitleRemotePath: item.subtitleRemoteRefs.isEmpty
                ? null
                : item.subtitleRemoteRefs.first.path,
            posterUrl: item.tmdbPosterUrl ?? series.tmdbPosterUrl,
            posterCachePath: item.posterCachePath ?? series.posterCachePath,
          ),
    ];
    if (targets.isEmpty) return false;
    await _videoController.openCloudPlayback(
      seriesTitle: series.title,
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
