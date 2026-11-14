import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/cloud_hidden_video_repository.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/utils/storage.dart';

void main() {
  late Directory root;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('my_library_cache_');
    Hive.init(root.path);
    GStorage.setting = await Hive.openBox<Object?>('settings');
  });
  tearDownAll(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test('离线本地缓存不受阈值影响，恢复后保留作品身份和已保存标记', () async {
    final source = Directory('${root.path}/media');
    final item = LocalMediaIndexItem(
        path: '${source.path}/作品.S01E01.mkv',
        name: '作品.S01E01.mkv',
        parentPath: source.path,
        sourcePath: source.path,
        size: 100,
        seriesName: '作品',
        modified: DateTime(2026),
        indexedAt: DateTime(2026),
        seasonNumber: 1,
        episodeNumber: 1);
    final index = LocalMediaIndexRepository();
    await index.saveForSource(source.path, [item]);
    final controller = LocalController(
        mediaIndexRepository: index, localMinSizeBytesProvider: () => 1000);
    controller.reloadLocalLibraryIndex();
    expect(controller.localMediaLibrary.series, isEmpty);
    final cached = controller.cachedLocalMediaLibrary.series.single;
    expect(cached.isAvailable, isFalse);
    expect(cached.episodes.single.stableId, item.id);
    var marksBox = await Hive.openBox<Object?>('marks');
    final marksStorage = _BoxUserStates(() => marksBox);
    MediaLibraryUserStateRepository marks() =>
        MediaLibraryUserStateRepository(storage: marksStorage);
    await marks().save(
        cached.key,
        MediaLibraryUserState(
            favorite: true,
            watchLater: true,
            collections: const ['周末'],
            mediaIds: [item.id]));
    await marksBox.close();
    marksBox = await Hive.openBox<Object?>('marks');
    expect((await marks().get(cached.key))?.collections, ['周末']);
    await source.create();
    await File(item.path).writeAsString('video');
    controller.reloadLocalLibraryIndex();
    final restored = controller.cachedLocalMediaLibrary.series.single;
    expect(restored.key, cached.key);
    expect(restored.isAvailable, isTrue);
    expect((await marks().get(restored.key))?.watchLater, isTrue);
  });

  test('禁用和大小过滤的云索引仍可读，跨来源同名不合并，刷新只读缓存', () async {
    final credentials = MemoryCloudCredentialStore();
    final sources = CloudSourceRepository(
        storage: MemoryCloudSourceStorage(), credentialStore: credentials);
    final index =
        CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
    var clients = 0;
    for (final id in ['a', 'b']) {
      await sources.save(CloudSource(
          id: id,
          type: CloudSourceType.openList,
          name: '网盘$id',
          baseUrl: 'https://example.com',
          rootPaths: const ['/电影'],
          enabled: id == 'a'));
      await index.replaceSource(id, [
        CloudMediaIndexItem(
          sourceId: id,
          remoteId: 'same',
          remotePath: '/电影/同名.mkv',
          name: '同名.mkv',
          workKey: '$id|work|movie',
          workRootId: 'movie',
          workRootPath: '/电影',
          size: 100,
          modifiedAt: DateTime(2026),
          seriesName: '同名',
          tmdbId: 42,
          tmdbTitle: '中文名',
          tmdbOriginalTitle: 'Original Title',
          mediaType: CloudMediaType.movie,
        )
      ], {}, {}, [
        '/电影'
      ]);
    }
    final controller = CloudResourcesController(
      repository: sources,
      credentialStore: credentials,
      mediaIndexRepository: index,
      hiddenVideoRepository:
          CloudHiddenVideoRepository(storage: MemoryCloudHiddenVideoStorage()),
      minRecognizedVideoSizeBytesProvider: () => 1000,
      providerRegistry: CloudProviderRegistry(clientFactories: {
        CloudSourceType.openList: (_, __, ___) {
          clients++;
          throw StateError('读取片库不能创建网络客户端');
        }
      }),
    );
    addTearDown(controller.dispose);
    await controller.ensureMediaLibrarySnapshot();
    expect(controller.mediaLibrarySnapshot.series, isEmpty);
    final cached = controller.cachedMediaLibrarySnapshot.series;
    expect(cached, hasLength(2));
    expect(cached.map((s) => s.key).toSet(), hasLength(2));
    expect(cached.map((s) => s.episodes.single.stableId).toSet(), hasLength(2));
    expect(cached.singleWhere((s) => s.sourceId == 'b').isAvailable, isFalse);
    final oldKey = cached.singleWhere((s) => s.sourceId == 'b').key;
    final disabled = (await sources.getAll()).singleWhere((s) => s.id == 'b');
    await sources.save(disabled.copyWith(enabled: true));
    await controller.reloadMediaLibrarySnapshot();
    expect(
        controller.cachedMediaLibrarySnapshot.series
            .singleWhere((s) => s.key == oldKey)
            .isAvailable,
        isTrue);
    expect(clients, 0);
    expect(controller.scanning, isFalse);
    for (final source in await sources.getAll()) {
      await sources.save(source.copyWith(enabled: false));
    }
    await controller.load(startScan: false);
    expect(controller.cachedMediaLibrarySnapshot.series, hasLength(2));
    expect(
        controller.cachedMediaLibrarySnapshot.series
            .every((item) => !item.isAvailable),
        isTrue);
    expect(controller.mediaLibrarySnapshot.series, isEmpty);
    expect(controller.selectedSource, isNull);
    expect(clients, 0);
    final hidden = controller.cachedMediaLibrarySnapshot.series.first;
    await controller.hideMediaLibraryEpisodes(hidden.episodes);
    expect(
        controller.cachedMediaLibrarySnapshot.series
            .any((s) => s.key == hidden.key),
        isFalse);
  });
}

class _BoxUserStates implements MediaLibraryUserStateStorage {
  _BoxUserStates(this.box);
  final Box<Object?> Function() box;
  @override
  Object get synchronizationIdentity => this;
  @override
  Future<Map<String, Object?>> read() async => Map<String, Object?>.from(
      box().get('marks', defaultValue: <String, Object?>{})! as Map);
  @override
  Future<void> write(Map<String, Object?> value) => box().put('marks', value);
}
