import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_grid.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_page.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
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
    expect(find.textContaining('700.0 MB'), findsOneWidget);
    expect(find.textContaining('2026-07-19'), findsOneWidget);
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
    expect(find.byType(ImmersiveMediaCard), findsOneWidget);
    expect(
      tester
          .widget<ImmersiveMediaCard>(find.byType(ImmersiveMediaCard))
          .overlayMode,
      ImmersiveMediaCardOverlayMode.always,
    );
    expect(find.text('中文片名'), findsOneWidget);
    expect(find.textContaining('8.7 ★'), findsOneWidget);
    expect(find.textContaining('2025'), findsOneWidget);
    expect(find.text('动漫'), findsOneWidget);
    expect(find.text('已刮削'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('未匹配目录保持文件夹卡而独立视频使用媒体卡', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudResourcesGrid(
            sourceId: 'source',
            entries: const <CloudFileEntry>[
              CloudFileEntry(
                id: 'folder',
                remotePath: '/影视/普通目录',
                name: '普通目录',
                size: 0,
                modifiedAt: null,
                isDirectory: true,
              ),
              CloudFileEntry(
                id: 'video',
                remotePath: '/影视/电影.mkv',
                name: '电影.mkv',
                size: 1024,
                modifiedAt: null,
                isDirectory: false,
              ),
            ],
            records: const <String, CloudResourceTmdbRecord>{},
            scrapingKeys: const <String>{},
            subtitleVideoKeys: const <String>{},
            onOpenDirectory: (_) {},
            onPlay: (_) {},
            onEditTitle: (_) {},
            onScrape: (_) {},
            onRematch: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ImmersiveMediaCard), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.text('普通目录'), findsOneWidget);
    expect(find.text('电影.mkv'), findsOneWidget);
  });

  testWidgets('网盘资源网格按宽度使用二三四列和统一海报比例', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    Future<void> pumpAt(double width) async {
      tester.view.physicalSize = Size(width, 720);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudResourcesGrid(
              sourceId: 'source',
              entries: const <CloudFileEntry>[
                CloudFileEntry(
                  id: 'video',
                  remotePath: '/影视/电影.mkv',
                  name: '电影.mkv',
                  size: 1024,
                  modifiedAt: null,
                  isDirectory: false,
                ),
              ],
              records: const <String, CloudResourceTmdbRecord>{},
              scrapingKeys: const <String>{},
              subtitleVideoKeys: const <String>{},
              onOpenDirectory: (_) {},
              onPlay: (_) {},
              onEditTitle: (_) {},
              onScrape: (_) {},
              onRematch: (_) {},
            ),
          ),
        ),
      );
    }

    Future<void> expectColumns(double width, int count) async {
      await pumpAt(width);
      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, count);
      expect(delegate.childAspectRatio, 0.68);
      expect(delegate.crossAxisSpacing, 12);
      expect(delegate.mainAxisSpacing, 12);
    }

    await expectColumns(620, 2);
    await expectColumns(800, 3);
    await expectColumns(1100, 4);
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

  testWidgets('重新匹配显示可编辑搜索词与候选并保存', (tester) async {
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
    expect(
      find.byKey(const ValueKey<String>('cloud-tmdb-match-dialog')),
      findsOneWidget,
    );
    expect(find.text('动漫'), findsWidgets);
    expect(find.text('本次刮削选项'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '搜索 TMDB'));
    await tester.pumpAndSettle();
    expect(find.text('候选片名'), findsOneWidget);
    await tester.tap(find.text('候选片名'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '应用匹配'));
    await tester.pumpAndSettle();

    expect(coordinator.selectedCandidate?.id, 42);
    fixture.controller.dispose();
  });

  testWidgets('批量刮削不中断并汇总成功待确认无结果和失败', (tester) async {
    final coordinator = _BatchTmdbCoordinator();
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[
        CloudFileEntry(
          id: 'matched',
          remotePath: '/影视/成功',
          name: '成功',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
        CloudFileEntry(
          id: 'pending',
          remotePath: '/影视/待确认',
          name: '待确认',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
        CloudFileEntry(
          id: 'empty',
          remotePath: '/影视/无结果',
          name: '无结果',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
        CloudFileEntry(
          id: 'failed',
          remotePath: '/影视/失败',
          name: '失败',
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

    await tester.tap(find.byTooltip('刮削当前目录'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('cloud-tmdb-match-dialog')),
      findsNothing,
    );
    expect(
      find.textContaining('成功 1 项，待确认 1 项，无结果 1 项，失败 1 项'),
      findsOneWidget,
    );
    fixture.controller.dispose();
  });

  testWidgets('只含单集视频的季目录可刮削当前目录并提取系列名', (tester) async {
    final coordinator = _ManualTmdbCoordinator();
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entriesById: const <String, List<CloudFileEntry>>{
        'root-fid': <CloudFileEntry>[
          CloudFileEntry(
            id: 'series-fid',
            remotePath: '/影视/弥留之国的爱丽丝',
            name: '弥留之国的爱丽丝',
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
        ],
        'series-fid': <CloudFileEntry>[
          CloudFileEntry(
            id: 'season-fid',
            remotePath: '/影视/弥留之国的爱丽丝/第一季',
            name: '第一季',
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
        ],
        'season-fid': <CloudFileEntry>[
          CloudFileEntry(
            id: 'episode-fid',
            remotePath: '/影视/弥留之国的爱丽丝/第一季/Alice in Borderland S01E01.mkv',
            name: 'Alice in Borderland S01E01.mkv',
            size: 1024,
            modifiedAt: null,
            isDirectory: false,
          ),
        ],
      },
      tmdbCoordinator: coordinator,
    );
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('弥留之国的爱丽丝'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一季'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刮削当前目录'));
    await tester.pumpAndSettle();

    expect(coordinator.scrapedTarget?.remote.id, 'season-fid');
    expect(coordinator.scrapedTarget?.remote.path, '/影视/弥留之国的爱丽丝/第一季');
    expect(coordinator.scrapedTarget?.displayName, 'Alice in Borderland');
    expect(
        coordinator.scrapedTarget?.resourceKind, CloudResourceKind.directory);
    fixture.controller.dispose();
  });

  testWidgets('空的网盘子目录仍提示没有需要刮削的资源', (tester) async {
    final coordinator = _ManualTmdbCoordinator();
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entriesById: const <String, List<CloudFileEntry>>{
        'root-fid': <CloudFileEntry>[
          CloudFileEntry(
            id: 'empty-fid',
            remotePath: '/影视/空目录',
            name: '空目录',
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
        ],
        'empty-fid': <CloudFileEntry>[],
      },
      tmdbCoordinator: coordinator,
    );
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('空目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刮削当前目录'));
    await tester.pump();

    expect(find.text('当前目录没有需要刮削的资源'), findsOneWidget);
    expect(coordinator.scrapedTarget, isNull);
    fixture.controller.dispose();
  });

  testWidgets('资源菜单修改剧名后立即显示且保留原文件名', (tester) async {
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
      record: _matchedFolderRecord(),
    );
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('资源操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改剧名'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('cloud-title-input')),
      '新剧名',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('新剧名'), findsOneWidget);
    expect(find.text('动漫'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('恢复 TMDB 标题只清除自定义剧名', (tester) async {
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
      record: _matchedFolderRecord().withCustomTitle('自定义剧名'),
    );
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('资源操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改剧名'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复 TMDB 标题'));
    await tester.pumpAndSettle();

    expect(find.text('中文片名'), findsOneWidget);
    expect(find.text('动漫'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('空白剧名不会保存并显示提示', (tester) async {
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
      record: _matchedFolderRecord(),
    );
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('资源操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改剧名'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('cloud-title-input')),
      '   ',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();

    expect(find.text('剧名不能为空'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
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
    Map<String, List<CloudFileEntry>>? entriesById,
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
    final client = _PageCloudClient(entries, entriesById: entriesById);
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
      releaseDate: '2025-01-01',
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
  CloudResourceTmdbTarget? scrapedTarget;

  @override
  Future<void> loadAndSchedule(CloudResourceDirectoryContext context) async {}

  @override
  Future<CloudResourceTmdbOutcome> scrape(
    CloudResourceTmdbTarget target, {
    TmdbScrapeOptions? options,
  }) async {
    scrapedTarget = target;
    return const CloudResourceTmdbOutcome(
      candidates: <TmdbMetadata>[],
    );
  }

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
  Future<CloudResourceTmdbSearchOutcome> searchPrepared(
    CloudResourceTmdbTarget target,
    CloudResourceTmdbSearchRequest request,
  ) async {
    return CloudResourceTmdbSearchOutcome(
      ranked: TmdbRankedResult(
        candidates: <TmdbRankedCandidate>[
          TmdbRankedCandidate(
            metadata: _candidate,
            score: 1,
            titleMatched: true,
            yearMatched: true,
            typeMatched: true,
          ),
        ],
        shouldAutoMatch: true,
      ),
    );
  }

  @override
  Future<CloudResourceTmdbSelectionOutcome> selectPrepared(
    CloudResourceTmdbTarget target,
    TmdbRankedCandidate candidate, {
    required TmdbScrapeOptions options,
  }) async {
    final record = await select(
      target,
      candidate.metadata,
      options: options,
    );
    return CloudResourceTmdbSelectionOutcome(
      record: record,
      posterCached: true,
      indexSynced: true,
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

class _BatchTmdbCoordinator extends _ManualTmdbCoordinator {
  @override
  Future<CloudResourceTmdbOutcome> scrape(
    CloudResourceTmdbTarget target, {
    TmdbScrapeOptions? options,
  }) async {
    switch (target.remote.id) {
      case 'matched':
        return CloudResourceTmdbOutcome(
          candidates: <TmdbMetadata>[_candidate],
          selected: CloudResourceTmdbRecord.matched(
            sourceId: target.sourceId,
            remoteId: target.remote.id,
            remotePath: target.remote.path,
            displayName: target.displayName,
            resourceKind: target.resourceKind,
            metadata: _candidate,
            checkedAt: DateTime.utc(2026, 7, 19),
          ),
        );
      case 'pending':
        return CloudResourceTmdbOutcome(
          candidates: <TmdbMetadata>[_candidate],
        );
      case 'empty':
        return const CloudResourceTmdbOutcome(
          candidates: <TmdbMetadata>[],
        );
      case 'failed':
        throw StateError('模拟失败');
    }
    throw StateError('未识别的测试资源');
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
  const _PageCloudClient(this.entries, {this.entriesById});

  final List<CloudFileEntry> entries;
  final Map<String, List<CloudFileEntry>>? entriesById;

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
      entriesById?[directory.id] ?? entries;

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}
