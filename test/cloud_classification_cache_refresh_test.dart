import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_media_tree_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_coordinator.dart';

void main() {
  test('重刮先刷新分类缓存再清除失效题材筛选', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;
    expect(controller.availableGenres, ['科幻']);
    controller.toggleGenre('科幻');
    expect(controller.collection.groups, hasLength(1));

    await fixture.publishGenre('纪录片');

    expect(controller.selectedGenres, isEmpty);
    expect(controller.availableGenres, ['纪录片']);
    expect(controller.collection.groups, hasLength(1));
  });

  test('同源快照刷新保留仍可用的已选题材', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;
    controller.toggleGenre('科幻');
    expect(controller.collection.groups, hasLength(1));

    await controller.reloadSourcesAndSnapshot(preferredSourceId: _source.id);

    expect(controller.availableGenres, ['科幻']);
    expect(controller.selectedGenres, {'科幻'});
    expect(controller.collection.groups, hasLength(1));
  });

  test('同源快照移除旧题材作品后解除筛选并保留未分类视频', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final controller = fixture.controller;
    controller.toggleGenre('科幻');
    expect(controller.collection.groups, hasLength(1));
    await fixture.replaceIndex(const CloudFileEntry(
      id: 'unclassified-video',
      remotePath: '/影视/未分类.mkv',
      name: '未分类.mkv',
      size: 1024,
      modifiedAt: null,
      isDirectory: false,
    ));

    await controller.reloadSourcesAndSnapshot(preferredSourceId: _source.id);

    expect(controller.availableGenres, isEmpty);
    expect(controller.selectedGenres, isEmpty);
    expect(controller.visibleIndexedItems, hasLength(1));
    expect(controller.collection.groups, hasLength(1));
  });
}

const _source = CloudSource(
  id: 'classification-refresh',
  type: CloudSourceType.openList,
  name: '分类刷新测试',
  baseUrl: 'https://classification.example.com',
  rootPaths: ['/影视'],
);

const _video = CloudFileEntry(
  id: 'video',
  remotePath: '/影视/测试.mkv',
  name: '测试.mkv',
  size: 1024,
  modifiedAt: null,
  isDirectory: false,
);

class _Fixture {
  _Fixture(
      this.controller, this.index, this.records, this.coordinator, this.tree);

  final CloudResourcesController controller;
  final CloudMediaIndexRepository index;
  final CloudWorkTmdbRepository records;
  final CloudWorkTmdbCoordinator coordinator;
  CloudMediaTree tree;

  static Future<_Fixture> create() async {
    final credentials = MemoryCloudCredentialStore();
    final sources = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    await sources.save(_source);
    final index = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    final records = CloudWorkTmdbRepository(
      storage: MemoryCloudWorkTmdbStorage(),
    );
    final coordinator = CloudWorkTmdbCoordinator(
      repository: records,
      legacyRepository: CloudResourceTmdbRepository(
        storage: MemoryCloudResourceTmdbStorage(),
      ),
      indexRepository: index,
      serviceFactory: (_) => throw StateError('无 API Key 时不应调用网络服务'),
      apiKeyProvider: () => '',
    );
    final controller = CloudResourcesController(
      repository: sources,
      credentialStore: credentials,
      mediaIndexRepository: index,
      workTmdbCoordinator: coordinator,
      minRecognizedVideoSizeBytesProvider: () => 0,
    );
    final fixture = _Fixture(
      controller,
      index,
      records,
      coordinator,
      _treeFor(_video),
    );
    await fixture.replaceIndex(_video);
    await fixture.publishGenre('科幻');
    await controller.reloadSourcesAndSnapshot(preferredSourceId: _source.id);
    await fixture.reloadTmdbRecords();
    return fixture;
  }

  Future<void> replaceIndex(CloudFileEntry video) {
    tree = _treeFor(video);
    final work = tree.works.single;
    return index.replaceSource(
      _source.id,
      [
        CloudMediaIndexItem(
          sourceId: _source.id,
          remoteId: video.id,
          remotePath: video.remotePath,
          name: video.name,
          size: video.size,
          modifiedAt: video.modifiedAt,
          workKey: work.workKey,
          workRootId: work.root.id,
          workRootPath: work.root.remotePath,
          seriesName: work.displayTitle,
          mediaType: CloudMediaType.movie,
        ),
      ],
      const {},
      {
        '/影视': [video]
      },
      const ['/影视'],
    );
  }

  Future<void> publishGenre(String genre) async {
    final now = DateTime.utc(2026, 10, 11);
    final work = tree.works.single;
    await records.upsert(CloudWorkTmdbRecord.matched(
      sourceId: _source.id,
      workKey: work.workKey,
      workRootId: work.root.id,
      workRootPath: work.root.remotePath,
      remoteName: work.remoteName,
      metadata: TmdbMetadata(
        id: 42,
        mediaType: TmdbMediaType.movie,
        title: '测试电影',
        language: 'zh-CN',
        matchedAt: now,
        matchConfidence: 1,
        genres: [genre],
      ),
      checkedAt: now,
    ));
    await reloadTmdbRecords();
  }

  Future<void> reloadTmdbRecords() => coordinator.loadAndSchedule(tree);

  void dispose() {
    controller.dispose();
    coordinator.dispose();
  }
}

CloudMediaTree _treeFor(CloudFileEntry video) =>
    const CloudMediaTreeResolver().resolve(
      sourceId: _source.id,
      configuredRoots: const ['/影视'],
      directoryEntries: {
        '/影视': [video]
      },
      minSizeBytes: 0,
    );
