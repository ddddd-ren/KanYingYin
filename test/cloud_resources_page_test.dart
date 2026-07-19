import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_page.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

void main() {
  testWidgets('无来源时显示两种添加入口', (tester) async {
    final fixture = await _PageFixture.create();

    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(controller: fixture.controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有可用的网盘来源'), findsOneWidget);
    expect(find.text('添加 OpenList'), findsOneWidget);
    expect(find.text('添加夸克网盘'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('显示来源、文件夹和视频且不显示字幕', (tester) async {
    final fixture = await _PageFixture.create(
      source: const CloudSource(
        id: 'quark-source',
        type: CloudSourceType.quark,
        name: '夸克媒体库',
        baseUrl: 'https://pan.quark.cn',
        rootPaths: <String>['/影视'],
        rootRefs: <CloudRemoteRef>[
          CloudRemoteRef(id: 'root-fid', path: '/影视'),
        ],
      ),
      entries: <CloudFileEntry>[
        const CloudFileEntry(
          id: 'folder-fid',
          remotePath: '/影视/动漫',
          name: '动漫',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
        CloudFileEntry(
          id: 'video-fid',
          remotePath: '/影视/第01集.mkv',
          name: '第01集.mkv',
          size: 1024 * 1024 * 700,
          modifiedAt: DateTime(2026, 7, 19),
          isDirectory: false,
        ),
        const CloudFileEntry(
          id: 'subtitle-fid',
          remotePath: '/影视/第01集.ass',
          name: '第01集.ass',
          size: 1024,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(controller: fixture.controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('网盘资源'), findsOneWidget);
    expect(find.text('夸克媒体库'), findsOneWidget);
    expect(find.text('动漫'), findsOneWidget);
    expect(find.text('第01集.mkv'), findsOneWidget);
    expect(find.text('第01集.ass'), findsNothing);
    expect(find.text('700.0 MB'), findsOneWidget);
    expect(find.text('2026-07-19'), findsOneWidget);
    expect(find.widgetWithText(TextField, '搜索当前目录'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('点击视频使用来源 ID、远程 ID 和同名字幕播放', (tester) async {
    CloudPlaybackTarget? target;
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[
        CloudFileEntry(
          id: 'video-fid',
          remotePath: '/影视/第01集.mkv',
          name: '第01集.mkv',
          size: 1024 * 1024 * 700,
          modifiedAt: null,
          isDirectory: false,
        ),
        CloudFileEntry(
          id: 'subtitle-fid',
          remotePath: '/影视/第01集.ass',
          name: '第01集.ass',
          size: 1024,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(
          controller: fixture.controller,
          onPlayTarget: (value) async => target = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('第01集.mkv'));
    await tester.pump();

    expect(target?.sourceId, 'quark-source');
    expect(target?.remoteId, 'video-fid');
    expect(target?.remotePath, '/影视/第01集.mkv');
    expect(target?.subtitleRemoteId, 'subtitle-fid');
    expect(target?.subtitleRemotePath, '/影视/第01集.ass');
    fixture.controller.dispose();
  });

  testWidgets('移除来源先提示不删除远程文件', (tester) async {
    String? deletedSourceId;
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(
          controller: fixture.controller,
          onDeleteSource: (sourceId) async => deletedSourceId = sourceId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除当前来源'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('不会删除网盘中的任何文件'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, '移除'));
    await tester.pumpAndSettle();
    expect(deletedSourceId, 'quark-source');
    fixture.controller.dispose();
  });

  testWidgets('卡片显示海报区域、中文标题、评分和原文件名', (tester) async {
    final record = _matchedFolderRecord();
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[
        CloudFileEntry(
          id: 'folder-fid',
          remotePath: '/影视/动漫',
          name: '动漫',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ],
      record: record,
    );

    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey<String>('tmdb-poster-${record.stableKey}')),
      findsOneWidget,
    );
    expect(find.text('中文片名'), findsOneWidget);
    expect(find.text('8.7 ★'), findsOneWidget);
    expect(find.text('动漫'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('进入已匹配文件夹显示系列头部', (tester) async {
    final record = _matchedFolderRecord();
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[
        CloudFileEntry(
          id: 'folder-fid',
          remotePath: '/影视/动漫',
          name: '动漫',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ],
      record: record,
    );
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('中文片名'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('cloud-series-header')),
      findsOneWidget,
    );
    expect(find.text('系列简介'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('重新匹配显示选项与候选并保存所选结果', (tester) async {
    final coordinator = _ManualTmdbCoordinator();
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[
        CloudFileEntry(
          id: 'folder-fid',
          remotePath: '/影视/动漫',
          name: '动漫',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
      ],
      tmdbCoordinator: coordinator,
    );
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('资源操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新匹配'));
    await tester.pumpAndSettle();
    expect(find.text('本次刮削选项'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '开始刮削'));
    await tester.pumpAndSettle();
    expect(find.text('候选片名'), findsOneWidget);
    await tester.tap(find.text('候选片名'));
    await tester.pumpAndSettle();

    expect(coordinator.selectedCandidate?.id, 42);
    fixture.controller.dispose();
  });
}

const _quarkSource = CloudSource(
  id: 'quark-source',
  type: CloudSourceType.quark,
  name: '夸克媒体库',
  baseUrl: 'https://pan.quark.cn',
  rootPaths: <String>['/影视'],
  rootRefs: <CloudRemoteRef>[
    CloudRemoteRef(id: 'root-fid', path: '/影视'),
  ],
);

class _PageFixture {
  const _PageFixture(this.controller);

  final CloudResourcesController controller;

  static Future<_PageFixture> create({
    CloudSource? source,
    List<CloudFileEntry> entries = const <CloudFileEntry>[],
    CloudResourceTmdbRecord? record,
    CloudResourceTmdbCoordinator? tmdbCoordinator,
  }) async {
    final credentials = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    if (source != null) await repository.save(source);
    if (record != null) {
      final resourceRepository = CloudResourceTmdbRepository(
        storage: MemoryCloudResourceTmdbStorage(),
      );
      await resourceRepository.upsert(record);
      tmdbCoordinator = CloudResourceTmdbCoordinator(
        repository: resourceRepository,
        serviceFactory: (_) => throw UnimplementedError(),
        apiKeyProvider: () => '',
      );
    }
    final client = _PageCloudClient(entries);
    final registry = CloudProviderRegistry(
      clientFactories: <CloudSourceType, CloudProviderClientFactory>{
        CloudSourceType.openList: (_, __, ___) => client,
        CloudSourceType.quark: (_, __, ___) => client,
      },
    );
    return _PageFixture(
      CloudResourcesController(
        repository: repository,
        credentialStore: credentials,
        providerRegistry: registry,
        tmdbCoordinator: tmdbCoordinator,
      ),
    );
  }
}

CloudResourceTmdbRecord _matchedFolderRecord() {
  return CloudResourceTmdbRecord.matched(
    sourceId: 'quark-source',
    remoteId: 'folder-fid',
    remotePath: '/影视/动漫',
    displayName: '动漫',
    resourceKind: CloudResourceKind.directory,
    metadata: TmdbMetadata(
      id: 42,
      mediaType: TmdbMediaType.tv,
      title: '中文片名',
      overview: '系列简介',
      rating: 8.7,
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 7, 19),
      matchConfidence: 1,
    ),
    checkedAt: DateTime.utc(2026, 7, 19),
  );
}

class _ManualTmdbCoordinator extends CloudResourceTmdbCoordinator {
  _ManualTmdbCoordinator()
      : super(
          repository: CloudResourceTmdbRepository(
            storage: MemoryCloudResourceTmdbStorage(),
          ),
          serviceFactory: (_) => throw UnimplementedError(),
          apiKeyProvider: () => 'key',
        );

  TmdbMetadata? selectedCandidate;

  @override
  Future<void> loadAndSchedule(CloudResourceDirectoryContext context) async {}

  @override
  Future<CloudResourceTmdbOutcome> rematch(
    CloudResourceTmdbTarget target, {
    TmdbScrapeOptions? options,
  }) async {
    return CloudResourceTmdbOutcome(
      candidates: <TmdbMetadata>[_candidate],
    );
  }

  @override
  Future<CloudResourceTmdbRecord> select(
    CloudResourceTmdbTarget target,
    TmdbMetadata candidate, {
    TmdbScrapeOptions? options,
  }) async {
    selectedCandidate = candidate;
    return CloudResourceTmdbRecord.matched(
      sourceId: target.sourceId,
      remoteId: target.remote.id,
      remotePath: target.remote.path,
      displayName: target.displayName,
      resourceKind: target.resourceKind,
      metadata: candidate,
      checkedAt: DateTime.utc(2026, 7, 19),
    );
  }
}

final _candidate = TmdbMetadata(
  id: 42,
  mediaType: TmdbMediaType.tv,
  title: '候选片名',
  releaseDate: '2025-01-01',
  language: 'zh-CN',
  matchedAt: DateTime.utc(2026, 7, 19),
  matchConfidence: 1,
);

class _PageCloudClient implements CloudDriveClient {
  const _PageCloudClient(this.entries);

  final List<CloudFileEntry> entries;

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
  ) async =>
      entries;

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}
