import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/cloud/application/cloud_directory_scope_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_coordinator.dart';

void main() {
  test('几百个资源只构建一次目录树并复用海报集合', () async {
    var treeBuildCount = 0;
    final grouper = _CountingCollectionGrouper();
    final fixture = await _createCacheFixture(
      itemCount: 500,
      collectionGrouper: grouper,
      directoryScopeTreeBuilder: ({
        required rootPaths,
        required mediaPaths,
      }) {
        treeBuildCount++;
        return CloudDirectoryScopeTree.build(
          rootPaths: rootPaths,
          mediaPaths: mediaPaths,
        );
      },
    );

    final first = fixture.controller.collection;
    final second = fixture.controller.collection;

    expect(first.groups, hasLength(500));
    expect(identical(first, second), isTrue);
    expect(treeBuildCount, 1);
    expect(grouper.calls, 1);
    fixture.controller.dispose();
  });

  test('搜索词变化只重算海报集合并复用目录树', () async {
    var treeBuildCount = 0;
    final grouper = _CountingCollectionGrouper();
    final fixture = await _createCacheFixture(
      itemCount: 500,
      collectionGrouper: grouper,
      directoryScopeTreeBuilder: ({
        required rootPaths,
        required mediaPaths,
      }) {
        treeBuildCount++;
        return CloudDirectoryScopeTree.build(
          rootPaths: rootPaths,
          mediaPaths: mediaPaths,
        );
      },
    );
    final initial = fixture.controller.collection;

    fixture.controller.setQuery('电影 499');
    final filtered = fixture.controller.collection;

    expect(identical(initial, filtered), isFalse);
    expect(filtered.groups, hasLength(1));
    expect(treeBuildCount, 1);
    expect(grouper.calls, 2);
    fixture.controller.dispose();
  });

  test('TMDB 加载状态通知复用集合且资料修订后重算', () async {
    final coordinator = _CacheTmdbCoordinator();
    final grouper = _CountingCollectionGrouper();
    final fixture = await _createCacheFixture(
      itemCount: 500,
      collectionGrouper: grouper,
      tmdbCoordinator: coordinator,
      directoryScopeTreeBuilder: ({
        required rootPaths,
        required mediaPaths,
      }) =>
          CloudDirectoryScopeTree.build(
        rootPaths: rootPaths,
        mediaPaths: mediaPaths,
      ),
    );
    final first = fixture.controller.collection;

    coordinator.emitStatusChange();
    final statusOnly = fixture.controller.collection;

    expect(identical(first, statusOnly), isTrue);
    expect(grouper.calls, 1);

    coordinator.emitRecordChange();
    final recordsChanged = fixture.controller.collection;

    expect(identical(first, recordsChanged), isFalse);
    expect(grouper.calls, 2);
    fixture.controller.dispose();
  });
}

Future<_CacheFixture> _createCacheFixture({
  required int itemCount,
  required CloudResourceCollectionGrouper collectionGrouper,
  required CloudDirectoryScopeTreeBuilder directoryScopeTreeBuilder,
  CloudResourceTmdbCoordinator? tmdbCoordinator,
}) async {
  final credentials = MemoryCloudCredentialStore();
  final sourceRepository = CloudSourceRepository(
    storage: MemoryCloudSourceStorage(),
    credentialStore: credentials,
  );
  const source = CloudSource(
    id: 'cache-source',
    type: CloudSourceType.openList,
    name: '缓存测试来源',
    baseUrl: 'https://drive.example.com',
    rootPaths: <String>['/影视'],
  );
  await sourceRepository.save(source);
  final indexRepository = CloudMediaIndexRepository(
    storage: MemoryCloudMediaIndexStorage(),
  );
  await indexRepository.replaceSource(
    source.id,
    List<CloudMediaIndexItem>.generate(
      itemCount,
      (index) => CloudMediaIndexItem(
        sourceId: source.id,
        remoteId: 'movie-$index',
        remotePath: '/影视/电影 $index/电影 $index.mkv',
        name: '电影 $index.mkv',
        size: 200,
        modifiedAt: null,
        seriesName: '电影 $index',
        mediaType: CloudMediaType.movie,
      ),
      growable: false,
    ),
    const <String, String>{},
    const <String, List<CloudFileEntry>>{},
    const <String>['/影视'],
  );
  final controller = CloudResourcesController(
    repository: sourceRepository,
    credentialStore: credentials,
    mediaIndexRepository: indexRepository,
    minRecognizedVideoSizeBytesProvider: () => 0,
    collectionGrouper: collectionGrouper,
    directoryScopeTreeBuilder: directoryScopeTreeBuilder,
    tmdbCoordinator: tmdbCoordinator,
  );
  await controller.reloadSourcesAndSnapshot();
  return _CacheFixture(controller);
}

class _CacheFixture {
  const _CacheFixture(this.controller);

  final CloudResourcesController controller;
}

class _CountingCollectionGrouper extends CloudResourceCollectionGrouper {
  int calls = 0;

  @override
  CloudResourceCollection group({
    String? sourceId,
    List<CloudFileEntry> entries = const <CloudFileEntry>[],
    Map<String, CloudResourceTmdbRecord> records =
        const <String, CloudResourceTmdbRecord>{},
    int minSizeBytes = 0,
    List<CloudMediaIndexItem> items = const <CloudMediaIndexItem>[],
    List<CloudWorkIdentity> works = const <CloudWorkIdentity>[],
    Map<String, CloudWorkTmdbRecord> recordsByWorkKey =
        const <String, CloudWorkTmdbRecord>{},
    required String query,
  }) {
    calls++;
    return super.group(
      sourceId: sourceId,
      entries: entries,
      records: records,
      minSizeBytes: minSizeBytes,
      items: items,
      works: works,
      recordsByWorkKey: recordsByWorkKey,
      query: query,
    );
  }
}

class _CacheTmdbCoordinator extends CloudResourceTmdbCoordinator {
  _CacheTmdbCoordinator()
      : super(
          repository: CloudResourceTmdbRepository(
            storage: MemoryCloudResourceTmdbStorage(),
          ),
          serviceFactory: (_) => throw UnimplementedError(),
          apiKeyProvider: () => '',
        );

  int _testRevision = 0;

  @override
  int get recordsRevision => _testRevision;

  void emitStatusChange() => notifyListeners();

  void emitRecordChange() {
    _testRevision++;
    notifyListeners();
  }

  @override
  Future<void> loadAndSchedule(CloudResourceDirectoryContext context) async {}
}
