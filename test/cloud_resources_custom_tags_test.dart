import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_media_tag_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_media_tree_resolver.dart';

void main() {
  test('自定义标签只筛选当前网盘来源并支持作品级资源', () async {
    final credentials = MemoryCloudCredentialStore();
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    const sourceA = CloudSource(
      id: 'source-a',
      type: CloudSourceType.openList,
      name: '来源 A',
      baseUrl: 'https://a.example.com',
      rootPaths: <String>['/影视'],
    );
    const sourceB = CloudSource(
      id: 'source-b',
      type: CloudSourceType.openList,
      name: '来源 B',
      baseUrl: 'https://b.example.com',
      rootPaths: <String>['/影视'],
    );
    await sourceRepository.save(sourceA);
    await sourceRepository.save(sourceB);

    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await indexRepository.replaceSource(
      sourceA.id,
      <CloudMediaIndexItem>[
        _item(sourceA.id, 'a-video', '/影视/A.mkv', '作品 A'),
      ],
      const <String, String>{},
      const <String, List<CloudFileEntry>>{},
      const <String>['/影视'],
    );
    await indexRepository.replaceSource(
      sourceB.id,
      <CloudMediaIndexItem>[
        _item(sourceB.id, 'b-video', '/影视/B.mkv', '作品 B'),
      ],
      const <String, String>{},
      const <String, List<CloudFileEntry>>{},
      const <String>['/影视'],
    );
    final tagRepository = CloudMediaTagRepository(
      storage: MemoryCloudMediaTagStorage(),
    );
    final controller = CloudResourcesController(
      repository: sourceRepository,
      credentialStore: credentials,
      mediaIndexRepository: indexRepository,
      mediaTagRepository: tagRepository,
      minRecognizedVideoSizeBytesProvider: () => 0,
    );

    await controller.reloadSourcesAndSnapshot(preferredSourceId: sourceA.id);
    final groupA = controller.collection.groups.single;
    await controller.saveCustomTags(groupA, const <String>['收藏']);
    expect(controller.availableCustomTags, <String>['收藏']);
    controller.toggleGenre('收藏');
    expect(
      controller.collection.groups.single.videos.single.id,
      'a-video',
    );

    await controller.reloadSourcesAndSnapshot(preferredSourceId: sourceB.id);
    expect(controller.availableCustomTags, isEmpty);
    expect(controller.selectedGenres, isEmpty);
    expect(controller.collection.groups, hasLength(1));
    controller.dispose();
  });

  test('作品级网盘标签按 workKey 作用于所有季度卡', () async {
    final credentials = MemoryCloudCredentialStore();
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    const source = CloudSource(
      id: 'work-source',
      type: CloudSourceType.openList,
      name: '作品来源',
      baseUrl: 'https://work.example.com',
      rootPaths: <String>['/影视'],
    );
    await sourceRepository.save(source);
    const root = CloudFileEntry(
      id: 'work-root',
      remotePath: '/影视/示例剧',
      name: '示例剧',
      size: 0,
      modifiedAt: null,
      isDirectory: true,
    );
    const video = CloudFileEntry(
      id: 'work-video',
      remotePath: '/影视/示例剧/S01E01.mkv',
      name: 'S01E01.mkv',
      size: 1024,
      modifiedAt: null,
      isDirectory: false,
    );
    final directoryEntries = <String, List<CloudFileEntry>>{
      '/影视': <CloudFileEntry>[root],
      '/影视/示例剧': <CloudFileEntry>[video],
    };
    final workKey = const CloudMediaTreeResolver()
        .resolve(
          sourceId: source.id,
          configuredRoots: const <String>['/影视'],
          directoryEntries: directoryEntries,
          minSizeBytes: 0,
        )
        .works
        .single
        .workKey;
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await indexRepository.replaceSource(
      source.id,
      <CloudMediaIndexItem>[
        CloudMediaIndexItem(
          sourceId: source.id,
          remoteId: video.id,
          remotePath: video.remotePath,
          name: video.name,
          size: video.size,
          modifiedAt: video.modifiedAt,
          seriesName: '示例剧',
          workKey: workKey,
          workRootId: root.id,
          workRootPath: root.remotePath,
          seasonNumber: 1,
          episodeNumber: 1,
          mediaType: CloudMediaType.episode,
        ),
      ],
      const <String, String>{},
      directoryEntries,
      const <String>['/影视'],
    );
    final tagRepository = CloudMediaTagRepository(
      storage: MemoryCloudMediaTagStorage(),
    );
    final controller = CloudResourcesController(
      repository: sourceRepository,
      credentialStore: credentials,
      mediaIndexRepository: indexRepository,
      mediaTagRepository: tagRepository,
      workTmdbCoordinator: _NoopWorkTmdbCoordinator(indexRepository),
      minRecognizedVideoSizeBytesProvider: () => 0,
    );

    await controller.reloadSourcesAndSnapshot(preferredSourceId: source.id);
    expect(controller.works, isNotEmpty);
    expect(controller.works.single.workKey, workKey);
    expect(controller.visibleIndexedItems, hasLength(1));
    final group = controller.collection.groups.single;
    expect(group.isWorkScoped, isTrue);
    await controller.saveCustomTags(group, const <String>['收藏']);
    expect(controller.customTagsForGroup(group), <String>['收藏']);
    controller.toggleGenre('收藏');
    expect(controller.collection.groups.single.workKey, workKey);
    controller.dispose();
  });

  test('已刮削的 TMDB 合并资源保存标签后仍可筛选', () async {
    final credentials = MemoryCloudCredentialStore();
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    const source = CloudSource(
      id: 'tmdb-source',
      type: CloudSourceType.openList,
      name: 'TMDB 来源',
      baseUrl: 'https://tmdb.example.com',
      rootPaths: <String>['/影视'],
    );
    await sourceRepository.save(source);
    const entry = CloudFileEntry(
      id: 'tmdb-video',
      remotePath: '/影视/电影.mkv',
      name: '电影.mkv',
      size: 1024,
      modifiedAt: null,
      isDirectory: false,
    );
    final item = CloudMediaIndexItem(
      sourceId: source.id,
      remoteId: entry.id,
      remotePath: entry.remotePath,
      name: entry.name,
      size: entry.size,
      modifiedAt: entry.modifiedAt,
      seriesName: '电影',
      mediaType: CloudMediaType.movie,
    );
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await indexRepository.replaceSource(
      source.id,
      <CloudMediaIndexItem>[item],
      const <String, String>{},
      const <String, List<CloudFileEntry>>{},
      const <String>['/影视'],
    );
    final tmdbRepository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    await tmdbRepository.upsert(
      CloudResourceTmdbRecord.matched(
        sourceId: source.id,
        remoteId: entry.id,
        remotePath: entry.remotePath,
        displayName: entry.name,
        resourceKind: CloudResourceKind.standaloneVideo,
        metadata: TmdbMetadata(
          id: 42,
          mediaType: TmdbMediaType.movie,
          title: '中文电影',
          language: 'zh-CN',
          matchedAt: DateTime.utc(2026, 8, 4),
          matchConfidence: 1,
        ),
        checkedAt: DateTime.utc(2026, 8, 4),
      ),
    );
    final tmdbCoordinator = CloudResourceTmdbCoordinator(
      repository: tmdbRepository,
      serviceFactory: (_) => throw UnimplementedError(),
      apiKeyProvider: () => '',
    );
    final controller = CloudResourcesController(
      repository: sourceRepository,
      credentialStore: credentials,
      mediaIndexRepository: indexRepository,
      mediaTagRepository: CloudMediaTagRepository(
        storage: MemoryCloudMediaTagStorage(),
      ),
      tmdbCoordinator: tmdbCoordinator,
      minRecognizedVideoSizeBytesProvider: () => 0,
    );

    await controller.reloadSourcesAndSnapshot(preferredSourceId: source.id);
    await tmdbCoordinator.loadAndSchedule(
      CloudResourceDirectoryContext(
        source: source,
        directory: const CloudRemoteRef(id: 'library', path: '/'),
        entries: const <CloudFileEntry>[entry],
        isConfiguredRoot: true,
      ),
    );
    final group = controller.collection.groups.single;
    expect(group.stableKey, 'tmdb-source|tmdb|movie|42');

    await controller.saveCustomTags(group, const <String>['收藏']);
    expect(controller.availableCustomTags, <String>['收藏']);
    controller.toggleGenre('收藏');
    expect(controller.collection.groups, hasLength(1));
    controller.dispose();
  });
}

class _NoopWorkTmdbCoordinator extends CloudWorkTmdbCoordinator {
  _NoopWorkTmdbCoordinator(CloudMediaIndexRepository indexRepository)
      : super(
          repository: CloudWorkTmdbRepository(
            storage: MemoryCloudWorkTmdbStorage(),
          ),
          legacyRepository: CloudResourceTmdbRepository(
            storage: MemoryCloudResourceTmdbStorage(),
          ),
          indexRepository: indexRepository,
          serviceFactory: (_) => throw UnimplementedError(),
          apiKeyProvider: () => '',
        );

  @override
  Future<void> loadAndSchedule(CloudMediaTree tree) async {}
}

CloudMediaIndexItem _item(
  String sourceId,
  String remoteId,
  String remotePath,
  String title,
) {
  return CloudMediaIndexItem(
    sourceId: sourceId,
    remoteId: remoteId,
    remotePath: remotePath,
    name: '$title.mkv',
    size: 1024,
    modifiedAt: null,
    seriesName: title,
    mediaType: CloudMediaType.movie,
  );
}
