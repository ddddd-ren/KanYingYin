import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

void main() {
  group('CloudResourcesController', () {
    test('只显示已启用来源且单根目录直接加载', () async {
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'quark-enabled',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
          CloudSource(
            id: 'openlist-disabled',
            type: CloudSourceType.openList,
            name: '已停用',
            baseUrl: 'https://drive.example.invalid',
            rootPaths: <String>['/'],
            enabled: false,
          ),
        ],
        clients: <String, _FakeCloudClient>{
          'quark-enabled': _FakeCloudClient(
            entriesById: <String, List<CloudFileEntry>>{
              'root-fid': const <CloudFileEntry>[
                CloudFileEntry(
                  id: 'child-fid',
                  remotePath: '/影视/动漫',
                  name: '动漫',
                  size: 0,
                  modifiedAt: null,
                  isDirectory: true,
                ),
              ],
            },
          ),
        },
      );

      await fixture.controller.load();

      expect(
        fixture.controller.sources.map((source) => source.id),
        <String>['quark-enabled'],
      );
      expect(
        fixture.clients['quark-enabled']!.listed.single,
        const CloudRemoteRef(id: 'root-fid', path: '/影视'),
      );
      expect(fixture.controller.currentDirectory?.id, 'root-fid');
      expect(fixture.controller.entries.single.name, '动漫');
      fixture.controller.dispose();
    });

    test('多根目录先显示虚拟根页', () async {
      final client = _FakeCloudClient();
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'openlist-multiple',
            type: CloudSourceType.openList,
            name: '家庭网盘',
            baseUrl: 'https://drive.example.invalid',
            rootPaths: <String>['/动漫', '/电影'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: '/动漫', path: '/动漫'),
              CloudRemoteRef(id: '/电影', path: '/电影'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{'openlist-multiple': client},
      );

      await fixture.controller.load();

      expect(fixture.controller.isVirtualRoot, isTrue);
      expect(
        fixture.controller.entries.map((entry) => entry.id),
        <String>['/动漫', '/电影'],
      );
      expect(client.listed, isEmpty);
      fixture.controller.dispose();
    });

    test('进入目录、返回上级和搜索保留强类型引用', () async {
      final client = _FakeCloudClient(
        entriesById: <String, List<CloudFileEntry>>{
          'root-fid': <CloudFileEntry>[
            const CloudFileEntry(
              id: 'child-fid',
              remotePath: '/影视/动漫',
              name: '动漫',
              size: 0,
              modifiedAt: null,
              isDirectory: true,
            ),
            CloudFileEntry(
              id: 'movie-fid',
              remotePath: '/影视/剧场版.mkv',
              name: '剧场版.mkv',
              size: 1024,
              modifiedAt: DateTime(2026, 7, 19),
              isDirectory: false,
            ),
            const CloudFileEntry(
              id: 'subtitle-fid',
              remotePath: '/影视/剧场版.ass',
              name: '剧场版.ass',
              size: 100,
              modifiedAt: null,
              isDirectory: false,
            ),
          ],
          'child-fid': const <CloudFileEntry>[
            CloudFileEntry(
              id: 'episode-fid',
              remotePath: '/影视/动漫/第01集.mkv',
              name: '第01集.mkv',
              size: 2048,
              modifiedAt: null,
              isDirectory: false,
            ),
          ],
        },
      );
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'quark-navigation',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{'quark-navigation': client},
      );
      await fixture.controller.load();

      expect(
        fixture.controller.visibleEntries.map((entry) => entry.name),
        <String>['动漫', '剧场版.mkv'],
      );
      fixture.controller.setQuery('剧场版');
      expect(fixture.controller.visibleEntries.single.name, '剧场版.mkv');
      fixture.controller.setQuery('');
      await fixture.controller.openDirectory(
        const CloudRemoteRef(id: 'child-fid', path: '/影视/动漫'),
      );
      expect(fixture.controller.currentDirectory?.id, 'child-fid');
      expect(fixture.controller.canGoBack, isTrue);
      await fixture.controller.goBack();
      expect(fixture.controller.currentDirectory?.id, 'root-fid');
      fixture.controller.dispose();
    });

    test('慢响应不会覆盖新来源', () async {
      final slowClient = _DelayedCloudClient();
      final fastClient = _FakeCloudClient(
        entriesById: <String, List<CloudFileEntry>>{
          'fast-root': const <CloudFileEntry>[
            CloudFileEntry(
              id: 'new-directory',
              remotePath: '/新目录',
              name: '新目录',
              size: 0,
              modifiedAt: null,
              isDirectory: true,
            ),
          ],
        },
      );
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'fast',
            type: CloudSourceType.openList,
            name: '快来源',
            baseUrl: 'https://fast.example.invalid',
            rootPaths: <String>['/'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'fast-root', path: '/'),
            ],
          ),
          CloudSource(
            id: 'slow',
            type: CloudSourceType.quark,
            name: '慢来源',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/慢'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'slow-root', path: '/慢'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{
          'fast': fastClient,
          'slow': slowClient,
        },
      );
      await fixture.controller.load();

      final oldRequest = fixture.controller.selectSource('slow');
      await fixture.controller.selectSource('fast');
      slowClient.complete(const <CloudFileEntry>[
        CloudFileEntry(
          id: 'old-directory',
          remotePath: '/旧目录',
          name: '旧目录',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ]);
      await oldRequest;

      expect(fixture.controller.selectedSource?.id, 'fast');
      expect(fixture.controller.entries.single.name, '新目录');
      fixture.controller.dispose();
    });

    test('根目录调度文件夹和独立视频，子目录只标记为非配置根', () async {
      final coordinator = _RecordingTmdbCoordinator();
      final client = _FakeCloudClient(
        entriesById: <String, List<CloudFileEntry>>{
          'root-fid': const <CloudFileEntry>[
            CloudFileEntry(
              id: 'folder-fid',
              remotePath: '/影视/剧集',
              name: '剧集',
              size: 0,
              modifiedAt: null,
              isDirectory: true,
            ),
            CloudFileEntry(
              id: 'movie-fid',
              remotePath: '/影视/电影.mkv',
              name: '电影.mkv',
              size: 100,
              modifiedAt: null,
              isDirectory: false,
            ),
          ],
          'folder-fid': const <CloudFileEntry>[
            CloudFileEntry(
              id: 'season-fid',
              remotePath: '/影视/剧集/第一季',
              name: '第一季',
              size: 0,
              modifiedAt: null,
              isDirectory: true,
            ),
          ],
        },
      );
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-a',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{'source-a': client},
        tmdbCoordinator: coordinator,
      );

      await fixture.controller.load();
      expect(coordinator.contexts.single.isConfiguredRoot, isTrue);
      expect(coordinator.contexts.single.entries, hasLength(2));
      await fixture.controller.openDirectory(
        const CloudRemoteRef(id: 'folder-fid', path: '/影视/剧集'),
      );
      expect(coordinator.contexts.last.isConfiguredRoot, isFalse);
      fixture.controller.dispose();
    });

    test('TMDB 失败不改写目录错误且视频仍可播放', () async {
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-a',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{
          'source-a': _FakeCloudClient(
            entriesById: <String, List<CloudFileEntry>>{
              'root-fid': const <CloudFileEntry>[
                CloudFileEntry(
                  id: 'video-fid',
                  remotePath: '/影视/电影.mkv',
                  name: '电影.mkv',
                  size: 100,
                  modifiedAt: null,
                  isDirectory: false,
                ),
              ],
            },
          ),
        },
        tmdbCoordinator: _FailingTmdbCoordinator(),
      );

      await fixture.controller.load();
      await Future<void>.delayed(Duration.zero);

      expect(fixture.controller.errorMessage, isNull);
      expect(fixture.controller.visibleEntries.single.name, '电影.mkv');
      fixture.controller.dispose();
    });

    test('修改显示剧名不改变远程引用且客户端只读取目录', () async {
      final coordinator = _RecordingTmdbCoordinator();
      final client = _FakeCloudClient(
        entriesById: <String, List<CloudFileEntry>>{
          'root-fid': const <CloudFileEntry>[
            CloudFileEntry(
              id: 'folder-fid',
              remotePath: '/影视/原目录',
              name: '原目录',
              size: 0,
              modifiedAt: null,
              isDirectory: true,
            ),
          ],
        },
      );
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-a',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{'source-a': client},
        tmdbCoordinator: coordinator,
      );
      await fixture.controller.load();
      final folder = fixture.controller.entries.single;

      await fixture.controller.saveCustomTitle(folder, '新剧名');

      expect(fixture.controller.tmdbTargetFor(folder).remote.id, 'folder-fid');
      expect(
        fixture.controller.tmdbTargetFor(folder).remote.path,
        '/影视/原目录',
      );
      expect(
        client.listed,
        <CloudRemoteRef>[
          const CloudRemoteRef(id: 'root-fid', path: '/影视'),
        ],
      );
      fixture.controller.dispose();
    });

    test('生成结构化草稿并透传显式搜索和候选选择', () async {
      final coordinator = _RecordingTmdbCoordinator();
      final client = _FakeCloudClient(
        entriesById: <String, List<CloudFileEntry>>{
          'root-fid': const <CloudFileEntry>[
            CloudFileEntry(
              id: 'episode-fid',
              remotePath: '/影视/Alice in Borderland S01E01.mkv',
              name: 'Alice in Borderland S01E01.mkv',
              size: 100,
              modifiedAt: null,
              isDirectory: false,
            ),
          ],
        },
      );
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-a',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{'source-a': client},
        tmdbCoordinator: coordinator,
      );
      await fixture.controller.load();
      final episode = fixture.controller.entries.single;
      await fixture.controller.saveCustomTitle(episode, '弥留之国的爱丽丝');

      final draft = fixture.controller.tmdbDraftFor(episode);
      expect(draft.searchTitle, '弥留之国的爱丽丝');
      expect(draft.seasonNumber, 1);
      expect(draft.episodeNumber, 1);

      const request = CloudResourceTmdbSearchRequest(
        queryTitle: 'Alice in Borderland',
        queryYear: 2020,
        mediaTypeMode: TmdbMediaTypeMode.tv,
        options: TmdbScrapeOptions.defaults(),
      );
      await fixture.controller.searchTmdb(episode, request);
      expect(coordinator.searchRequest, same(request));

      final candidate = TmdbRankedCandidate(
        metadata: TmdbMetadata(
          id: 42,
          mediaType: TmdbMediaType.tv,
          title: '弥留之国的爱丽丝',
          language: 'zh-CN',
          matchedAt: _matchedAt,
          matchConfidence: 1,
        ),
        score: 1,
        titleMatched: true,
        yearMatched: true,
        typeMatched: true,
      );
      await fixture.controller.applyTmdbCandidate(
        episode,
        candidate,
        options: const TmdbScrapeOptions.defaults(),
      );
      expect(coordinator.appliedCandidate, same(candidate));
      fixture.controller.dispose();
    });
  });
}

final _matchedAt = DateTime.utc(2026, 7, 19);

class _Fixture {
  const _Fixture({required this.controller, required this.clients});

  final CloudResourcesController controller;
  final Map<String, _FakeCloudClient> clients;

  static Future<_Fixture> create({
    required List<CloudSource> sources,
    required Map<String, _FakeCloudClient> clients,
    CloudResourceTmdbCoordinator? tmdbCoordinator,
  }) async {
    final credentials = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    for (final source in sources) {
      await repository.save(source);
    }
    final registry = CloudProviderRegistry(
      clientFactories: <CloudSourceType, CloudProviderClientFactory>{
        CloudSourceType.openList: (source, _, __) => clients[source.id]!,
        CloudSourceType.quark: (source, _, __) => clients[source.id]!,
      },
    );
    return _Fixture(
      controller: CloudResourcesController(
        repository: repository,
        credentialStore: credentials,
        providerRegistry: registry,
        tmdbCoordinator: tmdbCoordinator,
      ),
      clients: clients,
    );
  }
}

class _RecordingTmdbCoordinator extends CloudResourceTmdbCoordinator {
  _RecordingTmdbCoordinator()
      : super(
          repository: CloudResourceTmdbRepository(
            storage: MemoryCloudResourceTmdbStorage(),
          ),
          serviceFactory: (_) => throw UnimplementedError(),
          apiKeyProvider: () => '',
        );

  final List<CloudResourceDirectoryContext> contexts =
      <CloudResourceDirectoryContext>[];
  CloudResourceTmdbSearchRequest? searchRequest;
  TmdbRankedCandidate? appliedCandidate;

  @override
  Future<void> loadAndSchedule(CloudResourceDirectoryContext context) async {
    contexts.add(context);
  }

  @override
  Future<CloudResourceTmdbSearchOutcome> searchPrepared(
    CloudResourceTmdbTarget target,
    CloudResourceTmdbSearchRequest request,
  ) async {
    searchRequest = request;
    return const CloudResourceTmdbSearchOutcome(
      ranked: TmdbRankedResult(
        candidates: <TmdbRankedCandidate>[],
        shouldAutoMatch: false,
      ),
    );
  }

  @override
  Future<CloudResourceTmdbSelectionOutcome> selectPrepared(
    CloudResourceTmdbTarget target,
    TmdbRankedCandidate candidate, {
    required TmdbScrapeOptions options,
  }) async {
    appliedCandidate = candidate;
    return CloudResourceTmdbSelectionOutcome(
      record: CloudResourceTmdbRecord.matched(
        sourceId: target.sourceId,
        remoteId: target.remote.id,
        remotePath: target.remote.path,
        displayName: target.displayName,
        resourceKind: target.resourceKind,
        metadata: candidate.metadata,
        checkedAt: _matchedAt,
      ),
      posterCached: true,
      indexSynced: true,
    );
  }
}

class _FailingTmdbCoordinator extends _RecordingTmdbCoordinator {
  @override
  Future<void> loadAndSchedule(CloudResourceDirectoryContext context) async {
    throw StateError('模拟 TMDB 失败');
  }
}

class _FakeCloudClient implements CloudDriveClient {
  _FakeCloudClient({
    this.entriesById = const <String, List<CloudFileEntry>>{},
  });

  final Map<String, List<CloudFileEntry>> entriesById;
  final List<CloudRemoteRef> listed = <CloudRemoteRef>[];

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
    listed.add(directory);
    return entriesById[directory.id] ?? const <CloudFileEntry>[];
  }

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}

class _DelayedCloudClient extends _FakeCloudClient {
  final Completer<List<CloudFileEntry>> _completer =
      Completer<List<CloudFileEntry>>();

  void complete(List<CloudFileEntry> entries) => _completer.complete(entries);

  @override
  Future<List<CloudFileEntry>> listDirectory(CloudRemoteRef directory) {
    listed.add(directory);
    return _completer.future;
  }
}
