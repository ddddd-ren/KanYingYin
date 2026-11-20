import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/library/application/media_ai_classifier.dart';
import 'package:kanyingyin/pages/index_module.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/library/application/library_ports.dart';
import 'package:kanyingyin/features/library/application/media_category_runtime.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/services/local_playback_request_builder.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';

void main() {
  test('正式绑定中打开个人片库和刷新已有资料不会启动 AI 分类', () async {
    final dir = await Directory.systemTemp.createTemp('my_library_bindings_');
    Hive.init(dir.path);
    final box = await Hive.openBox<Object?>('settings');
    GStorage.setting = box;
    addTearDown(() async {
      Modular.destroy();
      await box.close();
      await dir.delete(recursive: true);
    });
    Modular.init(IndexModule(
        tmdbCredentialManager: TmdbCredentialManager(
      store: MemoryTmdbCredentialStore(),
      legacyReader: () => '',
      legacyDelete: () async {},
    )));
    final classifier = _CountingClassifier();
    Modular.replaceInstance<MediaAiClassifier>(classifier);
    final runtime = MediaCategoryRuntime(
      localLibrary: Modular.get<LocalLibraryPort>(),
      cloudLibrary: Modular.get<CloudLibraryPort>(),
      playback: _Playback(),
      settings: TypedSettings(box),
      navigateToPlayer: () async {},
      includeUnavailable: true,
    );
    addTearDown(runtime.dispose);
    await runtime.initialize();
    await runtime.refresh();
    expect(classifier.calls, 0);
  });
  test('个人片库只读缓存，标记跨运行时同步，已看保留待看，播放仍传递原始媒体身份', () async {
    final dir = await Directory.systemTemp.createTemp('my_library_runtime_');
    Hive.init(dir.path);
    final box = await Hive.openBox<Object?>('settings');
    addTearDown(() async {
      await box.close();
      await dir.delete(recursive: true);
    });
    final item = LocalMediaIndexItem(
        path: (await File('${dir.path}/作品.mkv').create()).path,
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
    expect(cloudPort.ensures, 2);
    expect(cloudPort.refreshes, 0);
    await Future.wait([
      first.saveUserState(local.key, favorite: true),
      second.saveUserState(local.key, watchLater: true),
      first.saveUserState(local.key, collections: ['周末']),
    ]);
    final concurrent = (await MediaLibraryUserStateRepository(storage: storage)
        .get(local.key))!;
    expect(concurrent.favorite, isTrue);
    expect(concurrent.watchLater, isTrue);
    expect(concurrent.collections, ['周末']);
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
    await File(item.path).delete();
    await expectLater(
        first.playEpisode(local, local.episodes.single), throwsStateError);
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
  Future<void> ensureLibrary({bool refresh = false}) async {
    cachedReads++;
  }
}

class _CloudPort implements CloudLibraryPort {
  _CloudPort(this.cachedLibrary);
  @override
  final CloudMediaLibrary cachedLibrary;
  int ensures = 0;
  int refreshes = 0;
  @override
  bool get snapshotComplete => true;
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

class _CountingClassifier extends Fake implements MediaAiClassifier {
  int calls = 0;

  @override
  Future<void> process(CloudMediaLibrary Function() library) async {
    calls++;
  }
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
