import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

void main() {
  test('先显示缓存再递归汇总全部根目录且只输出合格视频', () async {
    final credentials = MemoryCloudCredentialStore();
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    const source = CloudSource(
      id: 'source-a',
      type: CloudSourceType.baidu,
      name: '百度媒体库',
      baseUrl: 'https://pan.baidu.com',
      rootPaths: <String>['/电影', '/剧集'],
      rootRefs: <CloudRemoteRef>[
        CloudRemoteRef(id: 'movies-root', path: '/电影'),
        CloudRemoteRef(id: 'shows-root', path: '/剧集'),
      ],
    );
    await sourceRepository.save(source);
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await indexRepository.replaceSource(
      source.id,
      const <CloudMediaIndexItem>[
        CloudMediaIndexItem(
          sourceId: 'source-a',
          remoteId: 'cached',
          remotePath: '/电影/旧电影.mkv',
          name: '旧电影.mkv',
          size: 300,
          modifiedAt: null,
          seriesName: '旧电影',
        ),
      ],
      const <String, String>{},
      const <String, List<CloudFileEntry>>{},
      const <String>['/电影', '/剧集'],
    );
    final client = _RecursiveClient(
      entriesById: <String, List<CloudFileEntry>>{
        'movies-root': const <CloudFileEntry>[
          CloudFileEntry(
            id: 'movie',
            remotePath: '/电影/新电影.mkv',
            name: '新电影.mkv',
            size: 300,
            modifiedAt: null,
            isDirectory: false,
          ),
        ],
        'shows-root': const <CloudFileEntry>[
          CloudFileEntry(
            id: 'show-folder',
            remotePath: '/剧集/Show',
            name: 'Show',
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
        ],
        'show-folder': const <CloudFileEntry>[
          CloudFileEntry(
            id: 'episode-1',
            remotePath: '/剧集/Show/Show.S01E01.mkv',
            name: 'Show.S01E01.mkv',
            size: 300,
            modifiedAt: null,
            isDirectory: false,
          ),
          CloudFileEntry(
            id: 'small-video',
            remotePath: '/剧集/Show/sample.mkv',
            name: 'sample.mkv',
            size: 100,
            modifiedAt: null,
            isDirectory: false,
          ),
          CloudFileEntry(
            id: 'subtitle-1',
            remotePath: '/剧集/Show/Show.S01E01.ass',
            name: 'Show.S01E01.ass',
            size: 10,
            modifiedAt: null,
            isDirectory: false,
          ),
        ],
      },
    );
    final registry = CloudProviderRegistry(
      clientFactories: <CloudSourceType, CloudProviderClientFactory>{
        CloudSourceType.baidu: (_, __, ___) => client,
      },
    );
    final indexer = CloudMediaIndexer(
      repository: indexRepository,
      minRecognizedVideoSizeBytesProvider: () => 100,
    );
    final controller = CloudResourcesController(
      repository: sourceRepository,
      credentialStore: credentials,
      providerRegistry: registry,
      mediaIndexRepository: indexRepository,
      mediaIndexer: indexer,
      minRecognizedVideoSizeBytesProvider: () => 100,
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.entries.map((entry) => entry.id), <String>['cached']);
    expect(controller.scanning, isTrue);

    await controller.scanCompletion;

    expect(controller.entries.map((entry) => entry.id).toSet(),
        <String>{'movie', 'episode-1'});
    expect(client.listedIds.toSet(),
        <String>{'movies-root', 'shows-root', 'show-folder'});
    final episode = controller.entries.singleWhere(
      (entry) => entry.id == 'episode-1',
    );
    expect(
      controller.subtitleFor(episode),
      const CloudRemoteRef(
        id: 'subtitle-1',
        path: '/剧集/Show/Show.S01E01.ass',
      ),
    );
    expect(controller.hasSubtitle(episode), isTrue);
  });
}

class _RecursiveClient implements CloudDriveClient {
  _RecursiveClient({required this.entriesById});

  final Map<String, List<CloudFileEntry>> entriesById;
  final List<String> listedIds = <String>[];

  @override
  Future<void> authenticate(CloudSource source, CloudCredential credential) =>
      throw UnimplementedError();

  @override
  Future<void> close() async {}

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) =>
      throw UnimplementedError();

  @override
  Future<List<CloudFileEntry>> listDirectory(
    CloudRemoteRef directory,
  ) async {
    listedIds.add(directory.id);
    return entriesById[directory.id] ?? const <CloudFileEntry>[];
  }

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}
