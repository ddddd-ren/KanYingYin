import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/library/application/library_ports.dart';
import 'package:kanyingyin/features/library/application/media_category_runtime.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/services/local_playback_request_builder.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';

void main() {
  test('个人片库只读缓存，标记跨运行时同步，已看保留待看，播放仍传递原始媒体身份', () async {
    final dir = await Directory.systemTemp.createTemp('my_library_runtime_');
    Hive.init(dir.path);
    final box = await Hive.openBox<Object?>('settings');
    addTearDown(() async {
      await box.close();
      await dir.delete(recursive: true);
    });
    final item = LocalMediaIndexItem(
        path: r'D:\媒体\作品.mkv',
        name: '作品.mkv',
        parentPath: r'D:\媒体',
        sourcePath: r'D:\媒体',
        size: 100,
        modified: DateTime(2026),
        seriesName: '作品',
        indexedAt: DateTime(2026));
    final local = MediaLibrarySeries(
        key: 'local|作品',
        seriesKey: '作品',
        title: '作品',
        sourceKind: MediaSourceKind.local,
        sourceId: 'local',
        sourceName: '本地',
        isAvailable: true,
        episodes: [
          MediaLibraryEpisode.local(
              stableId: item.id, name: item.name, localItem: item)
        ]);
    final cloud = MediaLibrarySeries(
        key: 'disk|作品',
        seriesKey: 'work',
        title: '作品',
        sourceKind: MediaSourceKind.cloud,
        sourceId: 'disk',
        sourceName: '网盘',
        isAvailable: true,
        episodes: [
          MediaLibraryEpisode.cloud(
              stableId: 'stable',
              name: '作品.mkv',
              sourceId: 'disk',
              sourceName: '网盘',
              isAvailable: true,
              remoteId: 'remote',
              remotePath: '/作品.mkv')
        ]);
    final localPort =
        _LocalPort(CloudMediaLibrary(series: [local], filters: const []));
    final cloudPort =
        _CloudPort(CloudMediaLibrary(series: [cloud], filters: const []));
    addTearDown(cloudPort.notifier.dispose);
    final storage = MemoryMediaLibraryUserStateStorage();
    final playback = _Playback();
    var navigations = 0;
    MediaCategoryRuntime runtime() => MediaCategoryRuntime(
        localLibrary: localPort,
        cloudLibrary: cloudPort,
        playback: playback,
        settings: TypedSettings(box),
        navigateToPlayer: () async => navigations++,
        includeUnavailable: true,
        userStateRepository: MediaLibraryUserStateRepository(storage: storage));
    final first = runtime();
    final second = runtime();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await first.initialize();
    await second.initialize();
    expect(first.library.series, hasLength(2));
    expect(localPort.cachedReads, 2);
    expect(cloudPort.ensures, 0);
    expect(cloudPort.refreshes, 2);
    await first.saveUserState(
        local.key,
        const MediaLibraryUserState(
            favorite: true, watchLater: true, collections: ['周末']));
    await Future<void>.delayed(Duration.zero);
    expect(second.userStates[local.key]?.favorite, isTrue);
    expect(second.userStates[local.key]?.mediaIds, [item.id]);
    await first.setWatched(local.episodes, true);
    expect(first.watchStates.values.single.watched, isTrue);
    expect(
        (await MediaLibraryUserStateRepository(storage: storage).get(local.key))
            ?.watchLater,
        isTrue);
    await first.playEpisode(local, local.episodes.single);
    expect(playback.path, item.path);
    expect(playback.entries!.single.location, item.location);
    expect(navigations, 1);
    await first.playEpisode(cloud, cloud.episodes.single);
    expect(playback.targets!.single.sourceId, 'disk');
    expect(playback.targets!.single.remoteId, 'remote');
    expect(playback.selected, cloud.episodes.single.stableId);
    expect(navigations, 2);
  });
}

class _LocalPort implements LocalLibraryPort {
  _LocalPort(this.cachedLibrary);
  @override
  final CloudMediaLibrary cachedLibrary;
  int cachedReads = 0;
  @override
  CloudMediaLibrary get library =>
      const CloudMediaLibrary(series: [], filters: []);
  @override
  void reloadAvailableLibrary({bool includeUnavailable = false}) {
    expect(includeUnavailable, isTrue);
    cachedReads++;
  }
}

class _CloudPort implements CloudLibraryPort {
  _CloudPort(this.cachedLibrary);
  @override
  final CloudMediaLibrary cachedLibrary;
  int ensures = 0;
  int refreshes = 0;
  final notifier = ChangeNotifier();
  @override
  Listenable get changes => notifier;
  @override
  CloudMediaLibrary get library =>
      const CloudMediaLibrary(series: [], filters: []);
  @override
  Future<void> ensureLibrary() async {
    ensures++;
  }

  @override
  Future<void> refreshLibrary() async {
    refreshes++;
  }

  @override
  Future<void> hideEpisodes(Iterable<MediaLibraryEpisode> episodes) async {}
}

class _Playback implements PlaybackPort {
  String? path;
  List<LocalPlaybackEntry>? entries;
  List<CloudPlaybackTarget>? targets;
  String? selected;
  @override
  Future<void> openFile(
      {required String filePath,
      required String seriesTitle,
      List<String>? legacySeriesTitles,
      List<Map<String, String>>? directoryFiles,
      List<LocalPlaybackEntry>? playbackEntries,
      bool playlistAlreadyIsolated = false,
      bool autoLoadSubtitle = true}) async {
    path = filePath;
    entries = playbackEntries;
  }

  @override
  Future<void> openCloud(
      {required String seriesTitle,
      String? workKey,
      List<String>? legacySeriesTitles,
      required List<CloudPlaybackTarget> targets,
      required String selectedStableId,
      MediaCategoryCloudPlaybackResolver? resolver}) async {
    this.targets = targets;
    selected = selectedStableId;
  }
}
