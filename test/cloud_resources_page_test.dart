import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/episode_matching/application/cloud_episode_match_service.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_hidden_video.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_media_details_dialog.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_episode_sheet.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_playback_request.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_poster_wall.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_page.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_media_tag_repository.dart';
import 'package:kanyingyin/repositories/cloud_episode_match_rule_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client_capabilities.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/widgets/cloud_poster_image.dart';
import 'package:kanyingyin/widgets/tmdb_network_image.dart';

CloudResourceMediaGroup _seasonMediaGroup() {
  const video = CloudFileEntry(
    id: 'episode',
    remotePath: '/影视/作品/第三季/01.mkv',
    name: '中文剧名 S03E01.mkv',
    size: 200,
    modifiedAt: null,
    isDirectory: false,
  );
  final record = CloudWorkTmdbRecord.matched(
    sourceId: 'source',
    workKey: 'source|work|show',
    workRootId: 'show',
    workRootPath: '/影视/作品',
    remoteName: '作品原名',
    metadata: TmdbMetadata(
      id: 42,
      mediaType: TmdbMediaType.tv,
      title: '中文剧名',
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 7, 20),
      matchConfidence: 1,
      seasons: const <TmdbSeasonMetadata>[
        TmdbSeasonMetadata(
          id: 300,
          seasonNumber: 3,
          name: '第 3 季',
          episodeCount: 6,
          posterUrl: '/season-3.jpg',
        ),
      ],
    ),
    checkedAt: DateTime.utc(2026, 7, 20),
  );
  final season = CloudResourceSeasonGroup(
    seasonNumber: 3,
    videos: const <CloudFileEntry>[video],
    metadata: record.seasons.single,
  );
  return CloudResourceMediaGroup(
    stableKey: 'source|work|show|season:3',
    workKey: 'source|work|show',
    displayName: '中文剧名 第 3 季',
    seriesName: '中文剧名',
    isSeries: true,
    seasonNumber: 3,
    videos: const <CloudFileEntry>[video],
    seasons: <CloudResourceSeasonGroup>[season],
    record: null,
    workRecord: record,
    seasonMetadata: record.seasons.single,
    isWorkScoped: true,
  );
}

CloudResourceMediaGroup _standaloneMediaGroup() {
  const videos = <CloudFileEntry>[
    CloudFileEntry(
      id: 'first',
      remotePath: '/影视/作品/01.mp4',
      name: '01.mp4',
      size: 200,
      modifiedAt: null,
      isDirectory: false,
    ),
    CloudFileEntry(
      id: 'second',
      remotePath: '/影视/作品/02.mp4',
      name: '02.mp4',
      size: 200,
      modifiedAt: null,
      isDirectory: false,
    ),
  ];
  return CloudResourceMediaGroup(
    stableKey: 'source|work|standalone',
    workKey: 'source|work|standalone',
    displayName: '未识别季度作品',
    seriesName: '未识别季度作品',
    isSeries: false,
    videos: videos,
    seasons: const <CloudResourceSeasonGroup>[],
    record: null,
    isWorkScoped: true,
  );
}

CloudResourceMediaGroup _variantMediaGroup() {
  const videos = <CloudFileEntry>[
    CloudFileEntry(
      id: '4k-1',
      remotePath: '/作品/4K 高码率/The.Resurrected.S01E01.mkv',
      name: '回魂计 S01E01 [4K 高码率].mkv',
      size: 200,
      modifiedAt: null,
      isDirectory: false,
    ),
    CloudFileEntry(
      id: 'embedded-1',
      remotePath: '/作品/内封/The.Resurrected.S01E01.mkv',
      name: '回魂计 S01E01 [1080p 内封简繁英].mkv',
      size: 200,
      modifiedAt: null,
      isDirectory: false,
    ),
    CloudFileEntry(
      id: 'burned-in-1',
      remotePath: '/作品/内嵌/The.Resurrected.S01E01.mkv',
      name: '回魂计 S01E01 [1080p 内嵌中字].mkv',
      size: 200,
      modifiedAt: null,
      isDirectory: false,
    ),
  ];
  final season = CloudResourceSeasonGroup(
    seasonNumber: 1,
    videos: videos,
    uniqueEpisodeCount: 9,
  );
  return CloudResourceMediaGroup(
    stableKey: 'source|work|resurrected|season:1',
    workKey: 'source|work|resurrected',
    displayName: '回魂计 第 1 季',
    seriesName: '回魂计',
    isSeries: true,
    seasonNumber: 1,
    videos: videos,
    seasons: <CloudResourceSeasonGroup>[season],
    record: null,
    uniqueEpisodeCount: 9,
    isWorkScoped: true,
  );
}

CloudResourceMediaGroup _indexedVariantMediaGroup() {
  const sourceId = 'source';
  const workKey = 'source|work|duplicate-episodes';
  const root = CloudFileEntry(
    id: 'duplicate-episodes',
    remotePath: '/影视/测试剧',
    name: '测试剧',
    size: 0,
    modifiedAt: null,
    isDirectory: true,
  );
  const work = CloudWorkIdentity(
    sourceId: sourceId,
    workKey: workKey,
    root: root,
    remoteName: '测试剧',
    displayTitle: '测试剧',
    titleCandidates: <String>['测试剧'],
    seasons: <CloudSeasonIdentity>[
      CloudSeasonIdentity(
        workKey: workKey,
        seasonNumber: 3,
        displayName: '测试剧 第 3 季',
        remoteDirectories: <CloudFileEntry>[],
        episodes: <CloudEpisodeIdentity>[],
      ),
    ],
  );
  final items = <CloudMediaIndexItem>[];
  for (var episode = 1; episode <= 6; episode++) {
    final token = episode.toString().padLeft(2, '0');
    for (final (id, folder, tags) in const <(String, String, MediaReleaseTags)>[
      (
        'web',
        '第 3 季 - 2160p WEB-DL H265 DDP 5.1 Atmos',
        MediaReleaseTags(
          resolution: '2160p',
          source: 'WEB-DL',
          codec: 'H265',
          audio: <String>['DDP 5.1', 'Atmos'],
        ),
      ),
      (
        'dv',
        '第三季（2025）4K DV&HDR',
        MediaReleaseTags(
          resolution: '4K',
          dynamicRange: <String>['DV', 'HDR'],
        ),
      ),
    ]) {
      items.add(
        CloudMediaIndexItem(
          sourceId: sourceId,
          remoteId: '$id-$episode',
          remotePath: '/影视/测试剧/$folder/$token.mkv',
          name: '$token.mkv',
          remoteName: '$token.mkv',
          displayName: '测试剧 S03E$token.mkv',
          workKey: workKey,
          workRootId: root.id,
          workRootPath: root.remotePath,
          size: 1024,
          modifiedAt: null,
          seriesName: '测试剧',
          seasonNumber: 3,
          episodeNumber: episode,
          mediaType: CloudMediaType.episode,
          releaseTags: tags,
        ),
      );
    }
  }
  return CloudResourceCollectionGrouper()
      .group(
        items: items,
        works: const <CloudWorkIdentity>[work],
        query: '',
      )
      .groups
      .single;
}

CloudResourceMediaGroup _conflictMediaGroup() {
  const video = CloudFileEntry(
    id: 'conflict-episode',
    remotePath: '/作品/The.Resurrected.S01E01.mkv',
    name: 'The Resurrected S01E01.mkv',
    size: 200,
    modifiedAt: null,
    isDirectory: false,
  );
  final record = CloudWorkTmdbRecord.conflict(
    sourceId: 'source',
    workKey: 'source|work|conflict',
    workRootId: 'conflict',
    workRootPath: '/作品',
    remoteName: 'H-回-云鬼-计 【台剧】',
    checkedAt: DateTime.utc(2026, 7, 20),
  );
  return CloudResourceMediaGroup(
    stableKey: 'source|work|conflict|season:1',
    workKey: 'source|work|conflict',
    displayName: 'The Resurrected 第 1 季',
    seriesName: 'The Resurrected',
    isSeries: true,
    seasonNumber: 1,
    videos: const <CloudFileEntry>[video],
    seasons: <CloudResourceSeasonGroup>[
      CloudResourceSeasonGroup(
        seasonNumber: 1,
        videos: const <CloudFileEntry>[video],
      ),
    ],
    record: null,
    workRecord: record,
    isWorkScoped: true,
  );
}

Future<void> _openCloudMoreActions(WidgetTester tester) async {
  await tester.tap(find.byTooltip('更多网盘操作'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  testWidgets('Android TV 首次加载只恢复快照且 Windows 保持自动扫描', (tester) async {
    final tvController = _RecordingLoadCloudResourcesController();
    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(
          controller: tvController,
          capabilities: AppPlatformCapabilities.android.copyWith(
            television: true,
            androidSdkInt: 28,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tvController.startScanValues, <bool>[false]);
    tvController.dispose();

    final windowsController = _RecordingLoadCloudResourcesController();
    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(
          key: const ValueKey<String>('windows-cloud-resources-page'),
          controller: windowsController,
          capabilities: AppPlatformCapabilities.windows,
        ),
      ),
    );
    await tester.pump();

    expect(windowsController.startScanValues, <bool>[true]);
    windowsController.dispose();
  });

  test('网盘控制器加载完整季度并保存逐视频匹配', () async {
    final credentials = MemoryCloudCredentialStore();
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    await sourceRepository.save(_quarkSource);
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    const video = CloudFileEntry(
      id: 'episode',
      remotePath: '/影视/作品/第三季/Show.S03E01.mkv',
      name: 'Show.S03E01.mkv',
      size: 200,
      modifiedAt: null,
      isDirectory: false,
    );
    await indexRepository.replaceSource(
      _quarkSource.id,
      const <CloudMediaIndexItem>[
        CloudMediaIndexItem(
          sourceId: 'quark-source',
          remoteId: 'episode',
          remotePath: '/影视/作品/第三季/Show.S03E01.mkv',
          name: 'Show.S03E01.mkv',
          size: 200,
          modifiedAt: null,
          seriesName: 'Show',
          seasonNumber: 3,
          episodeNumber: 1,
          mediaType: CloudMediaType.episode,
        ),
      ],
      const <String, String>{},
      const <String, List<CloudFileEntry>>{},
      const <String>['/影视'],
    );
    final ruleRepository = CloudEpisodeMatchRuleRepository(
      storage: MemoryCloudEpisodeMatchRuleStorage(),
    );
    final episodeService = CloudEpisodeMatchService(
      ruleRepository: ruleRepository,
      indexRepository: indexRepository,
    );
    final tmdbClient = _ManualEpisodeTmdbClient();
    final tmdbCoordinator = _ManualTmdbCoordinator();
    final controller = CloudResourcesController(
      repository: sourceRepository,
      credentialStore: credentials,
      mediaIndexRepository: indexRepository,
      tmdbCoordinator: tmdbCoordinator,
      episodeMatchService: episodeService,
      tmdbApiKeyProvider: TmdbApiKeyProvider(userKeyReader: () => 'key'),
      tmdbClientContextRegistry: TmdbClientContextRegistry(
        clientFactory: (_) => tmdbClient,
      ),
      minRecognizedVideoSizeBytesProvider: () => 0,
    );
    await controller.reloadSourcesAndSnapshot(
      preferredSourceId: _quarkSource.id,
    );
    final group = CloudResourceMediaGroup(
      stableKey: 'manual-season-3',
      workKey: 'manual-season-3',
      displayName: 'Show 第 3 季',
      seriesName: 'Show',
      isSeries: true,
      seasonNumber: 3,
      videos: const <CloudFileEntry>[video],
      seasons: const <CloudResourceSeasonGroup>[],
      record: null,
      isWorkScoped: true,
    );

    final matchController =
        await controller.manualEpisodeMatchControllerForGroup(
      group: group,
      selectedSeries: _manualEpisodeMetadata(summaryOnly: true),
    );
    await matchController.initialize();
    matchController.assignEpisode('episode', 2);
    final outcome = await controller.saveManualEpisodeAssignments(
      group: group,
      assignments: matchController.assignments,
      metadata: matchController.metadata,
      selectedSeasonNumber: 3,
    );

    expect(tmdbClient.detailsCalls, 1);
    expect(tmdbClient.seasonCalls, <int>[3]);
    expect(outcome.indexSynced, isTrue);
    expect(tmdbCoordinator.selectedCandidate?.seasons.single.episodes,
        hasLength(2));
    final updated = controller.detailsFor(video);
    expect(updated.episodeNumber, 2);
    expect(updated.tmdbTitle, '异世界悠闲农家');
    expect(updated.displayName, '异世界悠闲农家 S03E02 第一位村民.mkv');
    expect(await ruleRepository.getBySource(_quarkSource.id), hasLength(1));
    controller.dispose();
  });

  test('单季度手动改选 TMDB 季度后作品同步使用新的季度号', () async {
    final credentials = MemoryCloudCredentialStore();
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    await sourceRepository.save(_quarkSource);
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    const video = CloudFileEntry(
      id: 'episode-1',
      remotePath: '/影视/古灵精探B/第 2 季/古灵精探B.S02E01.mp4',
      name: '古灵精探B.S02E01.mp4',
      size: 200,
      modifiedAt: null,
      isDirectory: false,
    );
    await indexRepository.replaceSource(
      _quarkSource.id,
      const <CloudMediaIndexItem>[
        CloudMediaIndexItem(
          sourceId: 'quark-source',
          remoteId: 'episode-1',
          remotePath: '/影视/古灵精探B/第 2 季/古灵精探B.S02E01.mp4',
          name: '古灵精探B.S02E01.mp4',
          workKey: 'quark-source|work|work-root',
          workRootId: 'work-root',
          workRootPath: '/影视/古灵精探B',
          size: 200,
          modifiedAt: null,
          seriesName: '古灵精探B',
          seasonNumber: 2,
          episodeNumber: 1,
          mediaType: CloudMediaType.episode,
        ),
      ],
      const <String, String>{},
      const <String, List<CloudFileEntry>>{
        '/影视': <CloudFileEntry>[
          CloudFileEntry(
            id: 'work-root',
            remotePath: '/影视/古灵精探B',
            name: '古灵精探B',
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
        ],
        '/影视/古灵精探B': <CloudFileEntry>[
          CloudFileEntry(
            id: 'season-2',
            remotePath: '/影视/古灵精探B/第 2 季',
            name: '第 2 季',
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
        ],
        '/影视/古灵精探B/第 2 季': <CloudFileEntry>[video],
      },
      const <String>['/影视'],
    );
    final episodeService = CloudEpisodeMatchService(
      ruleRepository: CloudEpisodeMatchRuleRepository(
        storage: MemoryCloudEpisodeMatchRuleStorage(),
      ),
      indexRepository: indexRepository,
    );
    final workCoordinator = _ManualWorkTmdbCoordinator(indexRepository);
    final controller = CloudResourcesController(
      repository: sourceRepository,
      credentialStore: credentials,
      mediaIndexRepository: indexRepository,
      workTmdbCoordinator: workCoordinator,
      episodeMatchService: episodeService,
      tmdbApiKeyProvider: TmdbApiKeyProvider(userKeyReader: () => 'key'),
      tmdbClientContextRegistry: TmdbClientContextRegistry(
        clientFactory: (_) => _SeasonOneManualEpisodeTmdbClient(),
      ),
      minRecognizedVideoSizeBytesProvider: () => 0,
    );
    await controller.reloadSourcesAndSnapshot(
      preferredSourceId: _quarkSource.id,
    );
    final group = controller.collection.groups.single;
    expect(controller.works, hasLength(1));
    expect(controller.works.single.seasons.single.seasonNumber, 2);
    expect(group.workKeys, contains(controller.works.single.workKey));
    final matchController =
        await controller.manualEpisodeMatchControllerForGroup(
      group: group,
      selectedSeries: _seasonOneManualEpisodeMetadata(summaryOnly: true),
    );
    await matchController.initialize();
    matchController.assignEpisode('episode-1', 1);

    await controller.saveManualEpisodeAssignments(
      group: group,
      assignments: matchController.assignments,
      metadata: matchController.metadata,
      selectedSeasonNumber: 1,
    );

    expect(workCoordinator.selectedWork?.seasons.single.seasonNumber, 1);

    workCoordinator.failSelection = true;
    await expectLater(
      controller.saveManualEpisodeAssignments(
        group: group,
        assignments: matchController.assignments,
        metadata: matchController.metadata,
        selectedSeasonNumber: 1,
      ),
      completes,
    );
    controller.dispose();
  });

  test('网盘播放失败诊断不包含异常中的远程地址', () {
    const source = CloudSource(
      id: 'baidu-source',
      type: CloudSourceType.baidu,
      name: '百度网盘',
      baseUrl: 'https://pan.baidu.com',
      rootPaths: <String>['/'],
    );

    final message = cloudPlaybackFailureDiagnostic(
      source,
      StateError('https://d.pcs.baidu.com/file?access_token=secret'),
    );

    expect(message, contains('provider=baidu'));
    expect(message, contains('sourceId=baidu-source'));
    expect(message, contains('errorType=StateError'));
    expect(message, isNot(contains('d.pcs.baidu.com')));
    expect(message, isNot(contains('secret')));
  });

  test('Android 9 TV 播放失败诊断包含安全档位且保持脱敏', () {
    const source = CloudSource(
      id: 'quark-source',
      type: CloudSourceType.quark,
      name: '夸克网盘',
      baseUrl: 'https://pan.quark.cn',
      rootPaths: <String>['/'],
    );
    final capabilities = AppPlatformCapabilities.android.copyWith(
      television: true,
      androidSdkInt: 28,
    );

    final message = cloudPlaybackFailureDiagnostic(
      source,
      StateError('https://dl.quark.cn/file?token=secret'),
      capabilities: capabilities,
    );

    expect(message, contains('provider=quark'));
    expect(message, contains('sdk=28'));
    expect(message, contains('profile=android_tv_safe'));
    expect(message, contains('errorType=StateError'));
    expect(message, isNot(contains('dl.quark.cn')));
    expect(message, isNot(contains('secret')));
  });

  testWidgets('季度海报墙和选集只显示当前季度虚拟名称', (tester) async {
    final group = _seasonMediaGroup();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                Expanded(
                  child: CloudResourcePosterWall(
                    sourceId: 'source',
                    collection: CloudResourceCollection(
                        groups: <CloudResourceMediaGroup>[group]),
                    scrapingKeys: const <String>{},
                    onOpenGroup: (_) => showCloudResourceEpisodeSheet(
                      context: context,
                      sourceId: 'source',
                      group: group,
                    ),
                    onEditTitle: (_) {},
                    onScrape: (_) {},
                    onRematch: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final resourceAction = find.byTooltip('资源操作');
    expect(tester.getSize(resourceAction), const Size.square(32));
    final actionButton = tester.widget<IconButton>(
      find.ancestor(of: resourceAction, matching: find.byType(IconButton)),
    );
    expect(actionButton.iconSize, 16);
    final actionSurface = tester.widget<Material>(
      find.byKey(const ValueKey<String>('cloud-resource-action-surface')),
    );
    expect(actionSurface.type, MaterialType.transparency);
    expect(find.text('中文剧名 第 3 季'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>(
          'cloud-poster-source|work|show|season:3',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('资源操作'));
    await tester.pumpAndSettle();
    expect(find.text('修改刮削名称'), findsOneWidget);
    expect(find.text('媒体详情'), findsOneWidget);
    await tester.tap(find.text('媒体详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ImmersiveMediaCard));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('cloud-resource-episode-sheet')),
        findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('cloud-resource-episode-sheet'),
        ),
        matching: find.text('中文剧名 第 3 季'),
      ),
      findsOneWidget,
    );
    expect(find.text('中文剧名 S03E01.mkv'), findsOneWidget);
    expect(find.text('01.mkv'), findsNothing);
    expect(
        find.byKey(const ValueKey<String>('cloud-season-3')), findsOneWidget);
  });

  testWidgets('TV 网盘海报和季度缩略图限制解码尺寸', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    final group = _seasonMediaGroup();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCloudResourceEpisodeSheet(
                context: context,
                sourceId: 'source',
                group: group,
                capabilities: AppPlatformCapabilities.android.copyWith(
                  television: true,
                  androidSdkInt: 28,
                ),
              ),
              child: CloudResourcePosterWall(
                capabilities: AppPlatformCapabilities.android.copyWith(
                  television: true,
                  androidSdkInt: 28,
                ),
                sourceId: 'source',
                collection: CloudResourceCollection(
                  groups: <CloudResourceMediaGroup>[group],
                ),
                scrapingKeys: const <String>{},
                onOpenGroup: (_) {},
                onEditTitle: (_) {},
                onScrape: (_) {},
                onRematch: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final poster = tester.widget<TmdbNetworkImage>(
      find.byType(TmdbNetworkImage).first,
    );
    expect(poster.cacheWidth, 720);
    expect(poster.cacheHeight, 1080);
    expect(poster.filterQuality, FilterQuality.medium);

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    final seasonPoster = tester.widget<TmdbNetworkImage>(
      find.byType(TmdbNetworkImage).last,
    );
    expect(seasonPoster.cacheWidth, 368);
    expect(seasonPoster.cacheHeight, 552);
    expect(seasonPoster.filterQuality, FilterQuality.medium);
  });

  testWidgets('网盘海报下载完成前显示媒体占位而不是空白卡片', (tester) async {
    final group = _seasonMediaGroup();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudResourcePosterWall(
            sourceId: 'source',
            collection: CloudResourceCollection(
              groups: <CloudResourceMediaGroup>[group],
            ),
            scrapingKeys: const <String>{},
            onOpenGroup: (_) {},
            onEditTitle: (_) {},
            onScrape: (_) {},
            onRematch: (_) {},
          ),
        ),
      ),
    );

    final poster = tester.widget<TmdbNetworkImage>(
      find.byType(TmdbNetworkImage),
    );
    expect(poster.loadingBuilder, isNotNull);
    expect(
      poster.loadingBuilder!(tester.element(find.byType(TmdbNetworkImage))).key,
      const ValueKey<String>('cloud-media-placeholder'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets('普通资源匹配状态变化时保持同一个海报 State', (tester) async {
    const video = CloudFileEntry(
      id: 'video-fid',
      remotePath: '/影视/动漫.mkv',
      name: '动漫.mkv',
      size: 200,
      modifiedAt: null,
      isDirectory: false,
    );
    CloudResourceMediaGroup group(CloudResourceTmdbRecord record) =>
        CloudResourceMediaGroup(
          stableKey: 'source|card|anime',
          seriesName: '动漫',
          isSeries: false,
          videos: const <CloudFileEntry>[video],
          seasons: const <CloudResourceSeasonGroup>[],
          record: record,
        );
    Widget app(CloudResourceMediaGroup value) => MaterialApp(
          home: Scaffold(
            body: CloudResourcePosterWall(
              sourceId: 'source',
              collection: CloudResourceCollection(
                groups: <CloudResourceMediaGroup>[value],
              ),
              scrapingKeys: const <String>{},
              onOpenGroup: (_) {},
              onEditTitle: (_) {},
              onScrape: (_) {},
              onRematch: (_) {},
            ),
          ),
        );

    final unmatched = CloudResourceTmdbRecord.unmatched(
      sourceId: 'source',
      remoteId: video.id,
      remotePath: video.remotePath,
      displayName: video.name,
      resourceKind: CloudResourceKind.standaloneVideo,
      checkedAt: DateTime.utc(2026, 8, 23),
    );
    await tester.pumpWidget(app(group(unmatched)));
    final originalState = tester.state(find.byType(CloudPosterImage));

    final matched = CloudResourceTmdbRecord.matched(
      sourceId: 'source',
      remoteId: video.id,
      remotePath: video.remotePath,
      displayName: video.name,
      resourceKind: CloudResourceKind.standaloneVideo,
      metadata: TmdbMetadata(
        id: 42,
        mediaType: TmdbMediaType.movie,
        title: '中文片名',
        language: 'zh-CN',
        matchedAt: DateTime.utc(2026, 8, 23),
        matchConfidence: 1,
      ),
      checkedAt: DateTime.utc(2026, 8, 23),
    );
    await tester.pumpWidget(app(group(matched)));

    expect(
      identical(tester.state(find.byType(CloudPosterImage)), originalState),
      isTrue,
    );
  });

  testWidgets('季度识别状态变化时保持同一个海报 State', (tester) async {
    final original = _standaloneMediaGroup();
    final season = CloudResourceMediaGroup(
      stableKey: original.stableKey,
      workKey: original.workKey,
      displayName: '未识别季度作品 第 3 季',
      seriesName: original.seriesName,
      isSeries: true,
      seasonNumber: 3,
      videos: original.videos,
      seasons: original.seasons,
      record: original.record,
      isWorkScoped: true,
    );
    Widget app(CloudResourceMediaGroup value) => MaterialApp(
          home: Scaffold(
            body: CloudResourcePosterWall(
              sourceId: 'source',
              collection: CloudResourceCollection(
                groups: <CloudResourceMediaGroup>[value],
              ),
              scrapingKeys: const <String>{},
              onOpenGroup: (_) {},
              onEditTitle: (_) {},
              onScrape: (_) {},
              onRematch: (_) {},
            ),
          ),
        );

    await tester.pumpWidget(app(original));
    final originalState = tester.state(find.byType(CloudPosterImage));
    await tester.pumpWidget(app(season));

    expect(
      identical(tester.state(find.byType(CloudPosterImage)), originalState),
      isTrue,
    );
  });

  testWidgets('媒体详情显示真实原名路径和发布规格', (tester) async {
    final item = CloudMediaIndexItem(
      sourceId: 'source',
      remoteId: 'episode',
      remotePath: '/影视/作品/第三季（2025）4K DV&HDR/01.mkv',
      name: '01.mkv',
      remoteName: '01.mkv',
      displayName: '中文剧名 S03E01.mkv',
      workKey: 'source|work|show',
      workRootId: 'show',
      workRootPath: '/影视/作品',
      size: 200,
      modifiedAt: null,
      seriesName: '中文剧名',
      seasonNumber: 3,
      episodeNumber: 1,
      mediaType: CloudMediaType.episode,
      releaseTags: const MediaReleaseTags(
        resolution: '4K',
        dynamicRange: <String>['DV', 'HDR'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCloudMediaDetailsDialog(
                context: context,
                item: item,
              ),
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    expect(find.text('媒体详情'), findsOneWidget);
    expect(find.text('01.mkv'), findsOneWidget);
    expect(
      find.text('/影视/作品/第三季（2025）4K DV&HDR/01.mkv'),
      findsOneWidget,
    );
    expect(find.text('S03E01'), findsOneWidget);
    expect(find.text('4K · DV · HDR'), findsOneWidget);
  });

  testWidgets('无季度电影多版本弹层显示版本数量和全部视频', (tester) async {
    final group = _standaloneMediaGroup();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCloudResourceEpisodeSheet(
                context: context,
                sourceId: 'source',
                group: group,
              ),
              child: const Text('打开选集'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开选集'));
    await tester.pumpAndSettle();

    expect(find.text('未识别季度作品'), findsOneWidget);
    expect(find.text('2 个版本'), findsNWidgets(2));
    expect(find.text('版本 1'), findsOneWidget);
    expect(find.text('版本 2'), findsOneWidget);
    expect(find.text('01.mp4'), findsOneWidget);
    expect(find.text('02.mp4'), findsOneWidget);
  });

  testWidgets('多版本选集显示唯一集数和每个版本标签', (tester) async {
    final group = _variantMediaGroup();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCloudResourceEpisodeSheet(
                context: context,
                sourceId: 'source',
                group: group,
              ),
              child: const Text('打开多版本选集'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开多版本选集'));
    await tester.pumpAndSettle();

    expect(find.text('9 集'), findsNWidgets(2));
    expect(find.text('S01E01 · 4K 高码率'), findsOneWidget);
    expect(find.text('S01E01 · 1080p 内封简繁英'), findsOneWidget);
    expect(find.text('S01E01 · 1080p 内嵌中字'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(3));
  });

  testWidgets('不同资源的重复集号使用索引身份且保留全部版本', (tester) async {
    final group = _indexedVariantMediaGroup();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCloudResourceEpisodeSheet(
                context: context,
                sourceId: 'source',
                group: group,
              ),
              child: const Text('打开重复集号选集'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开重复集号选集'));
    await tester.pumpAndSettle();

    expect(group.uniqueEpisodeCount, 6);
    expect(group.videos, hasLength(12));
    expect(find.text('6 集'), findsNWidgets(2));
    expect(find.byType(ListTile), findsNWidgets(12));
    expect(
      find.text('S03E01 · 2160p WEB-DL H265 DDP 5.1 Atmos'),
      findsOneWidget,
    );
    expect(find.text('S03E01 · 4K DV HDR'), findsOneWidget);
    expect(find.textContaining('第 2 集'), findsNothing);
  });

  testWidgets('待确认卡片提供菜单和状态标签双入口', (tester) async {
    final group = _conflictMediaGroup();
    var manualMatchCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudResourcePosterWall(
            sourceId: 'source',
            collection: CloudResourceCollection(
              groups: <CloudResourceMediaGroup>[group],
            ),
            scrapingKeys: const <String>{},
            onOpenGroup: (_) {},
            onEditTitle: (_) {},
            onScrape: (_) {},
            onRematch: (_) {},
            onManualMatch: (_) => manualMatchCalls++,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('资源操作'));
    await tester.pumpAndSettle();
    expect(find.text('手动确认匹配'), findsOneWidget);
    await tester.tap(find.text('手动确认匹配'));
    await tester.pumpAndSettle();
    expect(manualMatchCalls, 1);

    await tester.tap(
      find.byKey(const ValueKey<String>('cloud-manual-match-badge')),
    );
    await tester.pump();
    expect(manualMatchCalls, 2);
  });

  testWidgets('资源操作菜单把隐藏视频回调给当前卡片', (tester) async {
    final group = _standaloneMediaGroup();
    CloudResourceMediaGroup? hiddenGroup;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudResourcePosterWall(
            sourceId: 'source',
            collection: CloudResourceCollection(
              groups: <CloudResourceMediaGroup>[group],
            ),
            scrapingKeys: const <String>{},
            onOpenGroup: (_) {},
            onEditTitle: (_) {},
            onScrape: (_) {},
            onRematch: (_) {},
            onHide: (selected) => hiddenGroup = selected,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('资源操作'));
    await tester.pumpAndSettle();
    expect(find.text('隐藏视频'), findsOneWidget);
    await tester.tap(find.text('隐藏视频'));
    await tester.pumpAndSettle();

    expect(hiddenGroup, same(group));
  });

  testWidgets('网盘资源菜单把匹配剧集回调给当前卡片', (tester) async {
    final group = _standaloneMediaGroup();
    CloudResourceMediaGroup? matchedGroup;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudResourcePosterWall(
            sourceId: 'source',
            collection: CloudResourceCollection(
              groups: <CloudResourceMediaGroup>[group],
            ),
            scrapingKeys: const <String>{},
            onOpenGroup: (_) {},
            onEditTitle: (_) {},
            onScrape: (_) {},
            onRematch: (_) {},
            onMatchEpisodes: (selected) => matchedGroup = selected,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('资源操作'));
    await tester.pumpAndSettle();
    expect(find.text('匹配剧集'), findsOneWidget);
    await tester.tap(find.text('匹配剧集'));
    await tester.pumpAndSettle();

    expect(matchedGroup, same(group));
  });

  testWidgets('海报卡多版本隐藏操作可以只隐藏 B 版本', (tester) async {
    final controller = _HideVideoPageController();
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('资源操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐藏视频'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('hide-video-video-b')),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '隐藏所选'));
    await tester.pumpAndSettle();

    expect(controller.hiddenIds, <String>{'video-b'});
    expect(find.text('已隐藏 1 个视频'), findsOneWidget);
    expect(find.text('示例电影 [A 版本].mkv'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('顶部更多菜单提供管理已隐藏视频入口', (tester) async {
    final controller = _HideVideoPageController();
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    await _openCloudMoreActions(tester);

    expect(find.text('管理已隐藏视频'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('全部视频隐藏时显示可恢复空状态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudResourcePosterWall(
            sourceId: 'source',
            collection: CloudResourceCollection(
              groups: const <CloudResourceMediaGroup>[],
            ),
            scrapingKeys: const <String>{},
            hiddenVideoCount: 2,
            onOpenGroup: (_) {},
            onEditTitle: (_) {},
            onScrape: (_) {},
            onRematch: (_) {},
          ),
        ),
      ),
    );

    expect(
      find.text('视频已隐藏，可从更多网盘操作中恢复'),
      findsOneWidget,
    );
  });

  testWidgets('搜索无匹配结果时不误报视频已隐藏', (tester) async {
    final controller = _HideVideoPageController(
      hasHistoricalHiddenVideo: true,
    );
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '搜索全部网盘资源'),
      'zho',
    );
    await tester.pump();

    expect(find.text('没有找到匹配的视频'), findsOneWidget);
    expect(find.text('视频已隐藏，可从更多网盘操作中恢复'), findsNothing);
    controller.dispose();
  });

  testWidgets('无来源时显示四种网盘添加入口', (tester) async {
    final fixture = await _PageFixture.create();

    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(controller: fixture.controller),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('还没有可用的网盘来源'), findsOneWidget);
    expect(find.text('添加夸克网盘'), findsOneWidget);
    expect(find.text('添加百度网盘'), findsOneWidget);
    expect(find.text('添加迅雷网盘'), findsOneWidget);
    expect(find.text('添加 OpenList'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('已有来源时常驻添加网盘菜单提供四种入口', (tester) async {
    final fixture = await _PageFixture.create(source: _quarkSource);

    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(controller: fixture.controller),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加网盘'));
    await tester.pumpAndSettle();
    expect(find.text('添加夸克网盘'), findsOneWidget);
    expect(find.text('添加百度网盘'), findsOneWidget);
    expect(find.text('添加迅雷网盘'), findsOneWidget);
    expect(find.text('添加 OpenList'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('迅雷和 OpenList 快捷新增后刷新并选中新来源', (tester) async {
    final xunleiFixture = await _PageFixture.create();
    const xunlei = CloudSource(
      id: 'xunlei-added',
      type: CloudSourceType.xunlei,
      name: '迅雷新来源',
      baseUrl: 'https://pan.xunlei.com',
      rootPaths: <String>[],
    );
    await tester.pumpWidget(MaterialApp(
      home: CloudResourcesPage(
        controller: xunleiFixture.controller,
        onAddXunlei: () async {
          await xunleiFixture.repository.save(xunlei);
          return xunlei.id;
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加迅雷网盘'));
    await tester.pumpAndSettle();
    expect(xunleiFixture.controller.selectedSource?.id, xunlei.id);
    xunleiFixture.controller.dispose();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    final openListFixture = await _PageFixture.create();
    const openList = CloudSource(
      id: 'openlist-added',
      type: CloudSourceType.openList,
      name: 'OpenList 新来源',
      baseUrl: 'https://openlist.example.invalid',
      rootPaths: <String>[],
    );
    await tester.pumpWidget(MaterialApp(
      home: CloudResourcesPage(
        controller: openListFixture.controller,
        onAddOpenList: () async {
          await openListFixture.repository.save(openList);
          return openList.id;
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加 OpenList'));
    await tester.pumpAndSettle();
    expect(openListFixture.controller.selectedSource?.id, openList.id);
    openListFixture.controller.dispose();
  });

  testWidgets('显示来源和视频且隐藏文件夹与字幕文件', (tester) async {
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

    expect(find.text('网盘媒体库'), findsOneWidget);
    expect(find.text('夸克媒体库'), findsOneWidget);
    expect(find.text('动漫'), findsNothing);
    expect(find.text('第01集.mkv'), findsOneWidget);
    expect(find.text('第01集.ass'), findsNothing);
    expect(find.textContaining('700.0 MB'), findsOneWidget);
    expect(find.textContaining('2026-07-19'), findsOneWidget);
    expect(find.text('有字幕'), findsOneWidget);
    expect(find.text('无字幕'), findsNothing);
    expect(
      find.widgetWithText(TextField, '搜索全部网盘资源'),
      findsOneWidget,
    );
    expect(find.text('已汇总全部媒体根目录'), findsNothing);
    expect(find.byTooltip('返回上级'), findsNothing);
    expect(find.byTooltip('管理网盘来源'), findsOneWidget);
    expect(find.byTooltip('刷新当前来源'), findsOneWidget);
    expect(find.byTooltip('更多网盘操作'), findsOneWidget);
    final emptyGenreFilter = tester.widget<PopupMenuButton<String>>(
      find.byKey(const ValueKey<String>('cloud-genre-filter')),
    );
    expect(emptyGenreFilter.enabled, isTrue);
    final emptyCustomTagFilter = tester.widget<PopupMenuButton<String>>(
      find.byKey(const ValueKey<String>('cloud-custom-tag-filter')),
    );
    expect(emptyCustomTagFilter.enabled, isTrue);
    expect(emptyGenreFilter.constraints, isNotNull);
    expect(
      emptyCustomTagFilter.constraints?.maxHeight,
      emptyGenreFilter.constraints?.maxHeight,
    );
    await tester.tap(find.byTooltip('筛选 TMDB 类型'));
    await tester.pumpAndSettle();
    expect(find.text('暂无类型标签'), findsOneWidget);
    expect(find.text('刮削当前来源生成标签'), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.text('自动整理当前来源'), findsNothing);
    expect(find.text('刮削当前来源'), findsNothing);
    expect(find.text('移除当前来源'), findsNothing);
    await _openCloudMoreActions(tester);
    expect(find.text('自动整理当前来源'), findsOneWidget);
    expect(find.text('刮削当前来源'), findsOneWidget);
    expect(find.text('移除当前来源'), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    fixture.controller.dispose();
  });

  testWidgets('网盘媒体库不显示目录导航且展示全部海报', (tester) async {
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: <CloudFileEntry>[
        CloudFileEntry(
          id: 'movie-a',
          remotePath: '/影视/电影/影片 A.mkv',
          name: '影片 A.mkv',
          size: 1024 * 1024 * 700,
          modifiedAt: DateTime(2026, 7, 24),
          isDirectory: false,
        ),
        CloudFileEntry(
          id: 'show-b',
          remotePath: '/影视/剧集/剧集 B.mkv',
          name: '剧集 B.mkv',
          size: 1024 * 1024 * 700,
          modifiedAt: DateTime(2026, 7, 24),
          isDirectory: false,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('cloud-directory-address')),
      findsNothing,
    );
    expect(find.text('已汇总全部媒体根目录'), findsNothing);
    expect(find.byTooltip('返回上级'), findsNothing);
    expect(find.text('影片 A.mkv'), findsOneWidget);
    expect(find.text('剧集 B.mkv'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('当前网盘名称右侧的类型菜单支持多选任一匹配和清除', (tester) async {
    final entries = <CloudFileEntry>[
      _pageVideo('science-fiction', '/影视/科幻作品.mkv', '科幻作品.mkv'),
      _pageVideo('documentary', '/影视/纪录片作品.mkv', '纪录片作品.mkv'),
    ];
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: entries,
      snapshotOnly: true,
      indexedItems: <CloudMediaIndexItem>[
        _pageIndexedVideo(entries[0], const <String>['科幻']),
        _pageIndexedVideo(entries[1], const <String>['纪录片']),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    final sourceSelector = find.byKey(
      const ValueKey<String>('cloud-source-selector'),
    );
    final genreFilter = find.byKey(
      const ValueKey<String>('cloud-genre-filter'),
    );
    final customTagFilter = find.byKey(
      const ValueKey<String>('cloud-custom-tag-filter'),
    );
    expect(genreFilter, findsOneWidget);
    expect(customTagFilter, findsOneWidget);
    expect(
      tester.getCenter(genreFilter).dx,
      greaterThan(tester.getCenter(sourceSelector).dx),
    );
    expect(
      tester.getCenter(customTagFilter).dx,
      greaterThan(tester.getCenter(genreFilter).dx),
    );

    await tester.tap(find.byTooltip('筛选 TMDB 类型'));
    await tester.pumpAndSettle();
    await tester.tap(_checkedCloudGenreItem('科幻'));
    await tester.pumpAndSettle();
    expect(find.text('科幻作品'), findsOneWidget);
    expect(find.text('纪录片作品'), findsNothing);

    await tester.tap(find.byTooltip('筛选 TMDB 类型'));
    await tester.pumpAndSettle();
    await tester.tap(_checkedCloudGenreItem('纪录片'));
    await tester.pumpAndSettle();
    expect(find.text('科幻作品'), findsOneWidget);
    expect(find.text('纪录片作品'), findsOneWidget);

    await tester.tap(find.byTooltip('筛选 TMDB 类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(fixture.controller.selectedGenres, isEmpty);
    fixture.controller.dispose();
  });

  testWidgets('网盘标签菜单超出首屏高度时支持内部滚动', (tester) async {
    final entries = List<CloudFileEntry>.generate(
      20,
      (index) => _pageVideo(
        'genre-$index',
        '/影视/类型-$index.mkv',
        '类型-$index.mkv',
      ),
    );
    final indexedItems = List<CloudMediaIndexItem>.generate(
      entries.length,
      (index) => _pageIndexedVideo(entries[index], <String>['类型 $index']),
    );
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: entries,
      snapshotOnly: true,
      indexedItems: indexedItems,
    );
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('筛选 TMDB 类型'));
    await tester.pumpAndSettle();
    final menuScrollable = find.ancestor(
      of: find.text('类型 19'),
      matching: find.byType(Scrollable),
    );
    expect(menuScrollable, findsOneWidget);
    final state = tester.state<ScrollableState>(menuScrollable);
    expect(state.position.maxScrollExtent, greaterThan(0));
    await tester.drag(menuScrollable, const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(state.position.pixels, greaterThan(0));
    fixture.controller.dispose();
  });

  testWidgets('没有类型标签时可从标签菜单直接刮削当前来源', (tester) async {
    final coordinator = _ManualTmdbCoordinator();
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: <CloudFileEntry>[
        _pageVideo('untagged', '/影视/未刮削.mkv', '未刮削.mkv'),
      ],
      tmdbCoordinator: coordinator,
    );
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('筛选 TMDB 类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刮削当前来源生成标签'));
    await tester.pumpAndSettle();

    expect(coordinator.scrapedTarget?.remote.id, 'untagged');
    expect(find.textContaining('当前来源刮削完成'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('资源菜单支持新增自定义标签并可从当前来源筛选', (tester) async {
    final entries = <CloudFileEntry>[
      _pageVideo('custom-tag-video', '/影视/收藏.mkv', '收藏.mkv'),
    ];
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: entries,
      snapshotOnly: true,
      indexedItems: <CloudMediaIndexItem>[
        _pageIndexedVideo(entries.single, const <String>[]),
      ],
      mediaTagRepository: CloudMediaTagRepository(
        storage: MemoryCloudMediaTagStorage(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('资源操作'));
    await tester.pumpAndSettle();
    expect(find.text('管理标签'), findsOneWidget);
    await tester.tap(find.text('管理标签'));
    await tester.pumpAndSettle();
    expect(find.text('管理标签 · 收藏'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('cloud-tag-input')),
      '收藏',
    );
    await tester.tap(find.byKey(const ValueKey<String>('cloud-tag-add')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '收藏'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('cloud-tag-save')));
    await tester.pumpAndSettle();

    expect(fixture.controller.availableCustomTags, <String>['收藏']);
    await tester.tap(find.byTooltip('筛选 TMDB 类型'));
    await tester.pumpAndSettle();
    expect(find.text('自定义标签'), findsNothing);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('筛选自定义标签'));
    await tester.pumpAndSettle();
    expect(find.text('自定义标签'), findsOneWidget);
    await tester.tap(_checkedCloudGenreItem('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('收藏.mkv'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('点击视频使用来源 ID、远程 ID 和同名字幕播放', (tester) async {
    CloudResourcePlaybackRequest? playbackRequest;
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
          onPlayRequest: (value) async => playbackRequest = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .ancestor(
            of: find.text('第01集.mkv'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pump();

    expect(playbackRequest?.targets, hasLength(1));
    final target = playbackRequest?.targets.single;
    expect(target?.sourceId, 'quark-source');
    expect(target?.remoteId, 'video-fid');
    expect(target?.remotePath, '/影视/第01集.mkv');
    expect(target?.subtitleRemoteId, 'subtitle-fid');
    expect(target?.subtitleRemotePath, '/影视/第01集.ass');
    expect(playbackRequest?.selectedStableId, target?.stableId);
    fixture.controller.dispose();
  });

  testWidgets('播放请求进行中连续点击只进入一次', (tester) async {
    final release = Completer<void>();
    var calls = 0;
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[
        CloudFileEntry(
          id: 'video-fid',
          remotePath: '/影视/电影.mkv',
          name: '电影.mkv',
          size: 1024 * 1024 * 700,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(
          controller: fixture.controller,
          onPlayRequest: (_) async {
            calls++;
            await release.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byType(ImmersiveMediaCard).first;
    await tester.tap(card);
    await tester.pump();
    await tester.tap(card);
    await tester.pump();

    expect(calls, 1);
    release.complete();
    await tester.pumpAndSettle();
    fixture.controller.dispose();
  });

  testWidgets('网盘目录按作品显示海报墙并从选集播放真实分集', (tester) async {
    CloudResourcePlaybackRequest? playbackRequest;
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[
        CloudFileEntry(
          id: 'folder',
          remotePath: '/影视/子目录',
          name: '子目录',
          size: 0,
          modifiedAt: null,
          isDirectory: true,
        ),
        CloudFileEntry(
          id: 'episode-2',
          remotePath: '/影视/Show.S01E02.mkv',
          name: 'Show.S01E02.mkv',
          size: 200,
          modifiedAt: null,
          isDirectory: false,
        ),
        CloudFileEntry(
          id: 'episode-s2',
          remotePath: '/影视/Show.S02E01.mkv',
          name: 'Show.S02E01.mkv',
          size: 200,
          modifiedAt: null,
          isDirectory: false,
        ),
        CloudFileEntry(
          id: 'episode-1',
          remotePath: '/影视/Show.S01E01.mkv',
          name: 'Show.S01E01.mkv',
          size: 200,
          modifiedAt: null,
          isDirectory: false,
        ),
        CloudFileEntry(
          id: 'movie',
          remotePath: '/影视/Movie.2026.mkv',
          name: 'Movie.2026.mkv',
          size: 101,
          modifiedAt: null,
          isDirectory: false,
        ),
        CloudFileEntry(
          id: 'subtitle-2',
          remotePath: '/影视/Show.S01E02.ass',
          name: 'Show.S01E02.ass',
          size: 10,
          modifiedAt: null,
          isDirectory: false,
        ),
        CloudFileEntry(
          id: 'sample',
          remotePath: '/影视/样片.mkv',
          name: '样片.mkv',
          size: 100,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
      minRecognizedVideoSizeBytesProvider: () => 100,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(
          controller: fixture.controller,
          onPlayRequest: (value) => playbackRequest = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('cloud-folder-navigation')),
      findsNothing,
    );
    expect(find.text('子目录'), findsNothing);
    expect(find.byType(ImmersiveMediaCard), findsNWidgets(2));
    expect(find.text('Show.S01E02.mkv'), findsNothing);
    expect(find.text('Show.S01E02.ass'), findsNothing);
    expect(find.text('样片.mkv'), findsNothing);
    expect(find.text('3 集'), findsOneWidget);

    await tester.tap(
      find.ancestor(
        of: find.text('3 集'),
        matching: find.byType(ImmersiveMediaCard),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey<String>('cloud-season-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('cloud-season-2')),
      findsOneWidget,
    );
    expect(find.text('第 1 季'), findsOneWidget);
    expect(find.text('第 2 季'), findsOneWidget);
    expect(find.text('S01E01'), findsOneWidget);
    expect(find.text('S01E02'), findsOneWidget);
    expect(find.text('S02E01'), findsOneWidget);

    await tester.tap(find.text('Show.S01E02.mkv'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(playbackRequest?.seriesTitle, 'Show');
    expect(
      playbackRequest?.targets.map((target) => target.remoteId),
      <String>['episode-1', 'episode-2'],
    );
    expect(
      playbackRequest?.targets.map((target) => target.remoteId),
      isNot(contains('episode-s2')),
    );
    final selected = playbackRequest?.targets.last;
    expect(selected?.remotePath, '/影视/Show.S01E02.mkv');
    expect(selected?.subtitleRemoteId, 'subtitle-2');
    expect(playbackRequest?.selectedStableId, selected?.stableId);
    fixture.controller.dispose();
  });

  test('未识别季度播放请求保留作品全部视频', () {
    final group = _standaloneMediaGroup();
    final request = buildCloudResourcePlaybackRequest(
      sourceId: 'source',
      group: group,
      selected: group.videos.last,
      subtitleFor: (_) => null,
    );

    expect(
      request.targets.map((target) => target.remoteId),
      <String>['first', 'second'],
    );
    expect(request.selectedStableId, request.targets.last.stableId);
  });

  test('网盘播放请求保留已经解析的 TMDB 集名', () {
    const video = CloudFileEntry(
      id: 'episode-1',
      remotePath: '/Show/Show.S01E01.mkv',
      name: '异世界悠闲农家 S01E01 万能农具.mkv',
      size: 200,
      modifiedAt: null,
      isDirectory: false,
    );
    final group = CloudResourceMediaGroup(
      stableKey: 'show-season-1',
      seriesName: '异世界悠闲农家',
      isSeries: true,
      videos: const <CloudFileEntry>[video],
      seasons: const <CloudResourceSeasonGroup>[],
      record: null,
    );

    final request = buildCloudResourcePlaybackRequest(
      sourceId: 'source',
      group: group,
      selected: video,
      subtitleFor: (_) => null,
    );

    expect(request.targets.single.title, '异世界悠闲农家 S01E01 万能农具.mkv');
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
    await _openCloudMoreActions(tester);
    await tester.tap(find.text('移除当前来源'));
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

  testWidgets('自动批量整理先确认递归范围和网盘文件安全边界', (tester) async {
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[],
      tmdbCoordinator: _ManualTmdbCoordinator(),
    );

    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();
    await _openCloudMoreActions(tester);
    await tester.tap(find.text('自动整理当前来源'));
    await tester.pumpAndSettle();

    expect(find.text('自动批量整理'), findsOneWidget);
    expect(find.textContaining('递归扫描'), findsOneWidget);
    expect(find.textContaining('不会修改网盘文件'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '开始整理'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    fixture.controller.dispose();
  });

  testWidgets('自动批量整理显示进度禁用重复操作并保持视频可播放', (tester) async {
    const video = CloudFileEntry(
      id: 'video-fid',
      remotePath: '/影视/电影.mkv',
      name: '电影.mkv',
      size: 1024,
      modifiedAt: null,
      isDirectory: false,
    );
    final client = _StagedPageCloudClient(const <CloudFileEntry>[video]);
    final coordinator = _DelayedAutoOrganizeCoordinator();
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      client: client,
      tmdbCoordinator: coordinator,
    );
    var playedId = '';

    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(
          controller: fixture.controller,
          onPlayRequest: (request) =>
              playedId = request.targets.single.remoteId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CloudPosterImage), findsOneWidget);
    final originalPosterState = tester.state(find.byType(CloudPosterImage));
    await _openCloudMoreActions(tester);
    await tester.tap(find.text('自动整理当前来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '开始整理'));
    await tester.pump();

    expect(find.text('正在扫描目录 0，已发现 0 项'), findsOneWidget);
    expect(
      identical(
        tester.state(find.byType(CloudPosterImage)),
        originalPosterState,
      ),
      isTrue,
    );
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey<String>('cloud-source-selector')),
          )
          .onChanged,
      isNull,
    );
    final refreshButton = find
        .ancestor(
          of: find.byTooltip('刷新当前来源'),
          matching: find.byType(IconButton),
        )
        .first;
    expect(tester.widget<IconButton>(refreshButton).onPressed, isNull);
    await _openCloudMoreActions(tester);
    for (final label in <String>[
      '自动整理当前来源',
      '刮削当前来源',
      '移除当前来源',
    ]) {
      final item = find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (widget) => widget is PopupMenuItem,
            ),
          )
          .first;
      expect((tester.widget(item) as PopupMenuItem).enabled, isFalse);
    }
    await tester.tapAt(const Offset(2, 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byType(ImmersiveMediaCard));
    await tester.pump();
    expect(playedId, 'video-fid');

    client.completeAutoScan();
    await tester.pump();
    expect(coordinator.scrapeStarted, isTrue);
    expect(find.text('正在整理 0/1'), findsOneWidget);

    coordinator.completeMatched();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      identical(
        tester.state(find.byType(CloudPosterImage)),
        originalPosterState,
      ),
      isTrue,
    );
    expect(
      find.textContaining(
        '自动整理完成：成功 1 项，待确认 0 项，无结果 0 项，失败 0 项，已跳过 0 项',
      ),
      findsOneWidget,
    );
    fixture.controller.dispose();
  });

  testWidgets('卡片显示海报区域、中文标题、评分和原文件名', (tester) async {
    final record = _matchedVideoRecord();
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[
        CloudFileEntry(
          id: 'video-fid',
          remotePath: '/影视/动漫.mkv',
          name: '动漫.mkv',
          size: 1024 * 1024 * 700,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
      record: record,
    );

    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('cloud-poster-quark-source|tmdb|movie|42'),
      ),
      findsOneWidget,
    );
    expect(find.byType(ImmersiveMediaCard), findsOneWidget);
    expect(
      tester
          .widget<ImmersiveMediaCard>(find.byType(ImmersiveMediaCard))
          .overlayMode,
      ImmersiveMediaCardOverlayMode.hover,
    );
    final cardOpacity = find.descendant(
      of: find.byType(ImmersiveMediaCard),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(cardOpacity).opacity, 0);
    expect(find.byTooltip('资源操作'), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(ImmersiveMediaCard)));
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.widget<AnimatedOpacity>(cardOpacity).opacity, 1);
    expect(find.text('中文片名'), findsOneWidget);
    expect(find.textContaining('8.7 ★'), findsOneWidget);
    expect(find.textContaining('2025'), findsOneWidget);
    expect(find.text('动漫.mkv'), findsOneWidget);
    expect(find.text('已刮削'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('文件夹不显示且独立视频使用媒体卡', (tester) async {
    final collection = CloudResourceCollectionGrouper().group(
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
      minSizeBytes: 0,
      query: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudResourcePosterWall(
            sourceId: 'source',
            collection: collection,
            scrapingKeys: const <String>{},
            subtitleVideoKeys: const <String>{},
            onOpenGroup: (_) {},
            onEditTitle: (_) {},
            onScrape: (_) {},
            onRematch: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ImmersiveMediaCard), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('cloud-folder-navigation')),
      findsNothing,
    );
    expect(find.byIcon(Icons.folder_outlined), findsNothing);
    expect(find.text('普通目录'), findsNothing);
    expect(find.text('电影.mkv'), findsOneWidget);
  });

  testWidgets('网盘资源网格保持海报尺寸并随宽度增加列数', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    Future<void> pumpAt(double width) async {
      tester.view.physicalSize = Size(width, 720);
      final collection = CloudResourceCollectionGrouper().group(
        sourceId: 'source',
        entries: <CloudFileEntry>[
          for (var index = 0; index < 20; index++)
            CloudFileEntry(
              id: 'video-$index',
              remotePath: '/影视/电影$index.mkv',
              name: '电影$index.mkv',
              size: 1024,
              modifiedAt: null,
              isDirectory: false,
            ),
        ],
        records: const <String, CloudResourceTmdbRecord>{},
        minSizeBytes: 0,
        query: '',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CloudResourcePosterWall(
              sourceId: 'source',
              collection: collection,
              scrapingKeys: const <String>{},
              subtitleVideoKeys: const <String>{},
              onOpenGroup: (_) {},
              onEditTitle: (_) {},
              onScrape: (_) {},
              onRematch: (_) {},
            ),
          ),
        ),
      );
    }

    Future<({int columns, double cardWidth})> layoutAt(double width) async {
      await pumpAt(width);
      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;
      expect(delegate.maxCrossAxisExtent, 300);
      expect(delegate.childAspectRatio, 0.68);
      expect(delegate.crossAxisSpacing, 12);
      expect(delegate.mainAxisSpacing, 12);
      final cards = find.byType(ImmersiveMediaCard);
      final firstTop = tester.getTopLeft(cards.first).dy;
      final firstRow = <Rect>[
        for (var index = 0; index < cards.evaluate().length; index++)
          tester.getRect(cards.at(index)),
      ].where((rect) => (rect.top - firstTop).abs() < 0.5).toList();
      expect(firstRow, isNotEmpty);
      expect(tester.takeException(), isNull);
      return (
        columns: firstRow.length,
        cardWidth: firstRow.first.width,
      );
    }

    final narrow = await layoutAt(620);
    final regular = await layoutAt(1320);
    final maximized = await layoutAt(1920);

    expect(narrow.columns, lessThan(regular.columns));
    expect(maximized.columns, greaterThan(regular.columns));
    expect(regular.cardWidth, lessThanOrEqualTo(300));
    expect(maximized.cardWidth, lessThanOrEqualTo(300));
  });

  testWidgets('刮削遮罩只覆盖目标媒体卡且另一张仍可播放', (tester) async {
    var playedId = '';
    const first = CloudFileEntry(
      id: 'first',
      remotePath: '/影视/第一部.mkv',
      name: '第一部.mkv',
      size: 1024,
      modifiedAt: null,
      isDirectory: false,
    );
    const second = CloudFileEntry(
      id: 'second',
      remotePath: '/影视/第二部.mkv',
      name: '第二部.mkv',
      size: 1024,
      modifiedAt: null,
      isDirectory: false,
    );
    final scrapingKey = cloudResourceTmdbKey(
      sourceId: 'source',
      remoteId: first.id,
      remotePath: first.remotePath,
    );
    final collection = CloudResourceCollectionGrouper().group(
      sourceId: 'source',
      entries: const <CloudFileEntry>[first, second],
      records: const <String, CloudResourceTmdbRecord>{},
      minSizeBytes: 0,
      query: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CloudResourcePosterWall(
            sourceId: 'source',
            collection: collection,
            scrapingKeys: <String>{scrapingKey},
            subtitleVideoKeys: const <String>{},
            onOpenGroup: (group) => playedId = group.anchor.id,
            onEditTitle: (_) {},
            onScrape: (_) {},
            onRematch: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final cards = tester
        .widgetList<ImmersiveMediaCard>(find.byType(ImmersiveMediaCard))
        .toList(growable: false);
    expect(cards.map((card) => card.loading), <bool>[true, false]);
    expect(find.text('刮削中'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('cloud-media-placeholder')),
      findsNWidgets(2),
    );
    await tester.tap(find.byType(ImmersiveMediaCard).last);
    await tester.pump();
    expect(playedId, second.id);
  });

  testWidgets('来源级页面不再显示目录系列头部', (tester) async {
    final record = _matchedVideoRecord();
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[
        CloudFileEntry(
          id: 'video-fid',
          remotePath: '/影视/动漫.mkv',
          name: '动漫.mkv',
          size: 1024,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
      record: record,
    );
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('cloud-series-header')),
      findsNothing,
    );
    expect(find.text('中文片名'), findsOneWidget);
    expect(find.text('已汇总全部媒体根目录'), findsNothing);
    fixture.controller.dispose();
  });

  testWidgets('重新匹配显示可编辑搜索词与候选并保存', (tester) async {
    final coordinator = _ManualTmdbCoordinator();
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[
        CloudFileEntry(
          id: 'video-fid',
          remotePath: '/影视/动漫.mkv',
          name: '动漫.mkv',
          size: 1024,
          modifiedAt: null,
          isDirectory: false,
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
      find.byKey(const ValueKey<String>('tmdb-match-dialog')),
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
    expect(
      find.text('已保存“候选片名”，并自动匹配同目录 3 个分集'),
      findsOneWidget,
    );
    fixture.controller.dispose();
  });

  testWidgets('批量刮削不中断并汇总成功待确认无结果和失败', (tester) async {
    final coordinator = _BatchTmdbCoordinator();
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[
        CloudFileEntry(
          id: 'matched',
          remotePath: '/影视/成功.mkv',
          name: '成功.mkv',
          size: 100,
          modifiedAt: null,
          isDirectory: false,
        ),
        CloudFileEntry(
          id: 'pending',
          remotePath: '/影视/待确认.mkv',
          name: '待确认.mkv',
          size: 100,
          modifiedAt: null,
          isDirectory: false,
        ),
        CloudFileEntry(
          id: 'empty',
          remotePath: '/影视/无结果.mkv',
          name: '无结果.mkv',
          size: 100,
          modifiedAt: null,
          isDirectory: false,
        ),
        CloudFileEntry(
          id: 'failed',
          remotePath: '/影视/失败.mkv',
          name: '失败.mkv',
          size: 100,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
      tmdbCoordinator: coordinator,
    );
    await tester.pumpWidget(
      MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
    );
    await tester.pumpAndSettle();

    await _openCloudMoreActions(tester);
    await tester.tap(find.text('刮削当前来源'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('tmdb-match-dialog')),
      findsNothing,
    );
    expect(
      find.textContaining('成功 1 项，待确认 1 项，无结果 1 项，失败 1 项'),
      findsOneWidget,
    );
    fixture.controller.dispose();
  });

  testWidgets('递归发现的单集视频可直接执行来源级刮削', (tester) async {
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

    expect(find.text('Alice in Borderland'), findsOneWidget);
    await _openCloudMoreActions(tester);
    await tester.tap(find.text('刮削当前来源'));
    await tester.pumpAndSettle();

    expect(coordinator.scrapedTarget?.remote.id, 'episode-fid');
    expect(
      coordinator.scrapedTarget?.remote.path,
      '/影视/弥留之国的爱丽丝/第一季/Alice in Borderland S01E01.mkv',
    );
    expect(
      coordinator.scrapedTarget?.displayName,
      'Alice in Borderland S01E01.mkv',
    );
    expect(
      coordinator.scrapedTarget?.resourceKind,
      CloudResourceKind.standaloneVideo,
    );
    fixture.controller.dispose();
  });

  testWidgets('来源没有视频时提示没有需要刮削的资源', (tester) async {
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

    await _openCloudMoreActions(tester);
    await tester.tap(find.text('刮削当前来源'));
    await tester.pump();

    expect(find.text('当前来源没有需要刮削的资源'), findsOneWidget);
    expect(coordinator.scrapedTarget, isNull);
    fixture.controller.dispose();
  });

  testWidgets('资源菜单修改剧名后立即显示且保留原文件名', (tester) async {
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[
        CloudFileEntry(
          id: 'video-fid',
          remotePath: '/影视/动漫.mkv',
          name: '动漫.mkv',
          size: 1024,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
      record: _matchedVideoRecord(),
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
    expect(find.text('动漫.mkv'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('恢复 TMDB 标题只清除自定义剧名', (tester) async {
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[
        CloudFileEntry(
          id: 'video-fid',
          remotePath: '/影视/动漫.mkv',
          name: '动漫.mkv',
          size: 1024,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
      record: _matchedVideoRecord().withCustomTitle('自定义剧名'),
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
    expect(find.text('动漫.mkv'), findsOneWidget);
    fixture.controller.dispose();
  });

  testWidgets('空白剧名不会保存并显示提示', (tester) async {
    final fixture = await _PageFixture.create(
      source: _quarkSource,
      entries: const <CloudFileEntry>[
        CloudFileEntry(
          id: 'video-fid',
          remotePath: '/影视/动漫.mkv',
          name: '动漫.mkv',
          size: 1024,
          modifiedAt: null,
          isDirectory: false,
        ),
      ],
      record: _matchedVideoRecord(),
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

class _HideVideoPageController extends CloudResourcesController {
  factory _HideVideoPageController({bool hasHistoricalHiddenVideo = false}) {
    final credentials = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    return _HideVideoPageController._(
      repository,
      credentials,
      hasHistoricalHiddenVideo,
    );
  }

  _HideVideoPageController._(
    CloudSourceRepository repository,
    MemoryCloudCredentialStore credentials,
    this.hasHistoricalHiddenVideo,
  ) : super(repository: repository, credentialStore: credentials) {
    sources = const <CloudSource>[_quarkSource];
    selectedSource = _quarkSource;
    entries = const <CloudFileEntry>[_versionA, _versionB];
  }

  static const _versionA = CloudFileEntry(
    id: 'video-a',
    remotePath: '/影视/示例电影/A.mkv',
    name: '示例电影 [A 版本].mkv',
    size: 2048,
    modifiedAt: null,
    isDirectory: false,
    variantLabel: 'A 版本',
  );
  static const _versionB = CloudFileEntry(
    id: 'video-b',
    remotePath: '/影视/示例电影/B.mkv',
    name: '示例电影 [B 版本].mkv',
    size: 1024,
    modifiedAt: null,
    isDirectory: false,
    variantLabel: 'B 版本',
  );

  final Set<String> hiddenIds = <String>{};
  final bool hasHistoricalHiddenVideo;

  @override
  List<CloudHiddenVideo> get hiddenVideos => hasHistoricalHiddenVideo
      ? const <CloudHiddenVideo>[
          CloudHiddenVideo(
            sourceId: 'quark-source',
            remoteId: 'historical-hidden',
            remotePath: '/影视/已删除.mkv',
            fileName: '已删除.mkv',
          ),
        ]
      : const <CloudHiddenVideo>[];

  @override
  Future<void> load({bool startScan = true}) async {}

  @override
  CloudResourceCollection get collection {
    final videos = const <CloudFileEntry>[_versionA, _versionB]
        .where(
          (video) =>
              !hiddenIds.contains(video.id) &&
              (query.trim().isEmpty ||
                  video.name.toLowerCase().contains(query.toLowerCase())),
        )
        .toList(growable: false);
    if (videos.isEmpty) {
      return CloudResourceCollection(groups: const <CloudResourceMediaGroup>[]);
    }
    return CloudResourceCollection(
      groups: <CloudResourceMediaGroup>[
        CloudResourceMediaGroup(
          stableKey: 'source|work|example',
          workKey: 'source|work|example',
          displayName: '示例电影',
          seriesName: '示例电影',
          isSeries: false,
          videos: videos,
          seasons: const <CloudResourceSeasonGroup>[],
          record: null,
          isWorkScoped: true,
        ),
      ],
    );
  }

  @override
  Future<void> hideVideos(Iterable<CloudFileEntry> videos) async {
    hiddenIds.addAll(videos.map((video) => video.id));
    notifyListeners();
  }
}

class _PageFixture {
  const _PageFixture(this.controller, this.repository);

  final CloudResourcesController controller;
  final CloudSourceRepository repository;

  static Future<_PageFixture> create({
    CloudSource? source,
    List<CloudFileEntry> entries = const <CloudFileEntry>[],
    List<CloudMediaIndexItem> indexedItems = const <CloudMediaIndexItem>[],
    bool snapshotOnly = false,
    Map<String, List<CloudFileEntry>>? entriesById,
    CloudResourceTmdbRecord? record,
    CloudResourceTmdbCoordinator? tmdbCoordinator,
    CloudDriveClient? client,
    ICloudMediaTagRepository? mediaTagRepository,
    int Function()? minRecognizedVideoSizeBytesProvider,
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
    final resolvedClient =
        client ?? _PageCloudClient(entries, entriesById: entriesById);
    final registry = CloudProviderRegistry(
      clientFactories: <CloudSourceType, CloudProviderClientFactory>{
        CloudSourceType.openList: (_, __, ___) => resolvedClient,
        CloudSourceType.quark: (_, __, ___) => resolvedClient,
        CloudSourceType.xunlei: (_, __, ___) => resolvedClient,
      },
    );
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    if (source != null && indexedItems.isNotEmpty) {
      await indexRepository.replaceSource(
        source.id,
        indexedItems,
        const <String, String>{},
        const <String, List<CloudFileEntry>>{},
        source.remoteRoots.map((root) => root.path).toList(growable: false),
      );
    }
    final minSizeProvider = minRecognizedVideoSizeBytesProvider ?? (() => 0);
    final controller = snapshotOnly
        ? _SnapshotOnlyCloudResourcesController(
            repository: repository,
            credentialStore: credentials,
            mediaIndexRepository: indexRepository,
            mediaTagRepository: mediaTagRepository,
            minRecognizedVideoSizeBytesProvider: minSizeProvider,
          )
        : CloudResourcesController(
            repository: repository,
            credentialStore: credentials,
            providerRegistry: registry,
            mediaIndexRepository: indexRepository,
            mediaTagRepository: mediaTagRepository,
            mediaIndexer: CloudMediaIndexer(
              repository: indexRepository,
              minRecognizedVideoSizeBytesProvider: minSizeProvider,
            ),
            tmdbCoordinator: tmdbCoordinator,
            minRecognizedVideoSizeBytesProvider: minSizeProvider,
          );
    return _PageFixture(controller, repository);
  }
}

class _SnapshotOnlyCloudResourcesController extends CloudResourcesController {
  _SnapshotOnlyCloudResourcesController({
    required super.repository,
    required super.credentialStore,
    required super.mediaIndexRepository,
    super.mediaTagRepository,
    required super.minRecognizedVideoSizeBytesProvider,
  });

  @override
  Future<void> load({bool startScan = true}) => reloadSourcesAndSnapshot();
}

class _RecordingLoadCloudResourcesController extends CloudResourcesController {
  factory _RecordingLoadCloudResourcesController() {
    final credentials = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    return _RecordingLoadCloudResourcesController._(repository, credentials);
  }

  _RecordingLoadCloudResourcesController._(
    CloudSourceRepository repository,
    MemoryCloudCredentialStore credentials,
  ) : super(repository: repository, credentialStore: credentials);

  final List<bool> startScanValues = <bool>[];

  @override
  Future<void> load({bool startScan = true}) async {
    startScanValues.add(startScan);
  }
}

CloudFileEntry _pageVideo(String id, String path, String name) {
  return CloudFileEntry(
    id: id,
    remotePath: path,
    name: name,
    size: 1024 * 1024 * 700,
    modifiedAt: DateTime.utc(2026, 8, 4),
    isDirectory: false,
  );
}

CloudMediaIndexItem _pageIndexedVideo(
  CloudFileEntry entry,
  List<String> genres,
) {
  return CloudMediaIndexItem(
    sourceId: _quarkSource.id,
    remoteId: entry.id,
    remotePath: entry.remotePath,
    name: entry.name,
    size: entry.size,
    modifiedAt: entry.modifiedAt,
    seriesName: entry.name.replaceFirst('.mkv', ''),
    mediaType: CloudMediaType.movie,
    tmdbGenres: genres,
  );
}

Finder _checkedCloudGenreItem(String value) {
  return find.byWidgetPredicate(
    (widget) => widget is CheckedPopupMenuItem<String> && widget.value == value,
  );
}

CloudResourceTmdbRecord _matchedVideoRecord() {
  return CloudResourceTmdbRecord.matched(
    sourceId: 'quark-source',
    remoteId: 'video-fid',
    remotePath: '/影视/动漫.mkv',
    displayName: '动漫.mkv',
    resourceKind: CloudResourceKind.standaloneVideo,
    metadata: TmdbMetadata(
      id: 42,
      mediaType: TmdbMediaType.movie,
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
    List<CloudResourceTmdbTarget> propagationCandidates =
        const <CloudResourceTmdbTarget>[],
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
      seriesPropagation: const CloudSeriesPropagationSummary(
        eligible: true,
        ruleSaved: true,
        propagatedCount: 3,
        indexSyncFailures: 0,
      ),
    );
  }

  @override
  Future<CloudResourceTmdbRecord> select(
    CloudResourceTmdbTarget target,
    TmdbMetadata candidate, {
    TmdbScrapeOptions? options,
    List<CloudResourceTmdbTarget> propagationCandidates =
        const <CloudResourceTmdbTarget>[],
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

class _DelayedAutoOrganizeCoordinator extends _ManualTmdbCoordinator {
  final Completer<CloudResourceTmdbOutcome> _result =
      Completer<CloudResourceTmdbOutcome>();
  bool scrapeStarted = false;

  @override
  Future<CloudResourceTmdbOutcome> scrape(
    CloudResourceTmdbTarget target, {
    TmdbScrapeOptions? options,
  }) {
    scrapedTarget = target;
    scrapeStarted = true;
    return _result.future;
  }

  void completeMatched() {
    final target = scrapedTarget!;
    _result.complete(
      CloudResourceTmdbOutcome(
        candidates: <TmdbMetadata>[_candidate],
        selected: CloudResourceTmdbRecord.matched(
          sourceId: target.sourceId,
          remoteId: target.remote.id,
          remotePath: target.remote.path,
          displayName: target.displayName,
          resourceKind: target.resourceKind,
          metadata: _candidate,
          checkedAt: DateTime.utc(2026, 7, 20),
        ),
      ),
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

TmdbMetadata _manualEpisodeMetadata({required bool summaryOnly}) {
  return TmdbMetadata(
    id: 196285,
    mediaType: TmdbMediaType.tv,
    title: '异世界悠闲农家',
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026, 8, 6),
    matchConfidence: 1,
    seasons: <TmdbSeasonMetadata>[
      TmdbSeasonMetadata(
        id: 3,
        seasonNumber: 3,
        name: '第 3 季',
        episodeCount: 2,
        episodes: summaryOnly
            ? const <TmdbEpisodeMetadata>[]
            : const <TmdbEpisodeMetadata>[
                TmdbEpisodeMetadata(id: 31, episodeNumber: 1, name: '万能农具'),
                TmdbEpisodeMetadata(
                  id: 32,
                  episodeNumber: 2,
                  name: '第一位村民',
                ),
              ],
      ),
    ],
  );
}

TmdbMetadata _seasonOneManualEpisodeMetadata({required bool summaryOnly}) {
  return TmdbMetadata(
    id: 7694,
    mediaType: TmdbMediaType.tv,
    title: '古灵精探B',
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026, 8, 17),
    matchConfidence: 1,
    seasons: <TmdbSeasonMetadata>[
      TmdbSeasonMetadata(
        id: 1,
        seasonNumber: 1,
        name: '第 1 季',
        episodeCount: 1,
        episodes: summaryOnly
            ? const <TmdbEpisodeMetadata>[]
            : const <TmdbEpisodeMetadata>[
                TmdbEpisodeMetadata(
                  id: 11,
                  episodeNumber: 1,
                  name: '灵异奇案',
                ),
              ],
      ),
    ],
  );
}

final class _ManualWorkTmdbCoordinator extends CloudWorkTmdbCoordinator {
  _ManualWorkTmdbCoordinator(CloudMediaIndexRepository indexRepository)
      : super(
          repository: CloudWorkTmdbRepository(
            storage: MemoryCloudWorkTmdbStorage(),
          ),
          legacyRepository: CloudResourceTmdbRepository(
            storage: MemoryCloudResourceTmdbStorage(),
          ),
          indexRepository: indexRepository,
          serviceFactory: (_) => throw UnimplementedError(),
          apiKeyProvider: () => 'key',
        );

  CloudWorkIdentity? selectedWork;
  bool failSelection = false;

  @override
  Future<void> loadAndSchedule(CloudMediaTree tree) async {}

  @override
  Future<CloudWorkTmdbSelectionOutcome> selectCandidate(
    CloudWorkIdentity work,
    TmdbMetadata candidate, {
    TmdbScrapeOptions? options,
  }) async {
    if (failSelection) throw StateError('作品元数据同步失败');
    selectedWork = work;
    return CloudWorkTmdbSelectionOutcome(
      record: CloudWorkTmdbRecord.matched(
        sourceId: work.sourceId,
        workKey: work.workKey,
        workRootId: work.root.id,
        workRootPath: work.root.remotePath,
        remoteName: work.remoteName,
        metadata: candidate,
        checkedAt: DateTime.utc(2026, 8, 17),
      ),
      updatedIndexItems: 1,
      posterCached: true,
      indexSynced: true,
    );
  }
}

final class _SeasonOneManualEpisodeTmdbClient
    implements ITmdbClient, ITmdbClientCapabilities {
  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async =>
      _seasonOneManualEpisodeMetadata(summaryOnly: true);

  @override
  Future<TmdbSeasonMetadata> seasonDetails(
    int id,
    int seasonNumber, {
    String language = 'zh-CN',
  }) async =>
      _seasonOneManualEpisodeMetadata(summaryOnly: false).seasons.single;

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async =>
      <TmdbMetadata>[_seasonOneManualEpisodeMetadata(summaryOnly: true)];

  @override
  Future<TmdbSearchPage> searchPage(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
    required int page,
  }) async =>
      TmdbSearchPage(
        page: page,
        totalPages: 1,
        results: <TmdbMetadata>[
          _seasonOneManualEpisodeMetadata(summaryOnly: true),
        ],
      );

  @override
  Future<List<String>> alternativeTitles(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async =>
      const <String>[];
}

final class _ManualEpisodeTmdbClient
    implements ITmdbClient, ITmdbClientCapabilities {
  int detailsCalls = 0;
  final List<int> seasonCalls = <int>[];

  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    detailsCalls++;
    return _manualEpisodeMetadata(summaryOnly: true);
  }

  @override
  Future<TmdbSeasonMetadata> seasonDetails(
    int id,
    int seasonNumber, {
    String language = 'zh-CN',
  }) async {
    seasonCalls.add(seasonNumber);
    return _manualEpisodeMetadata(summaryOnly: false).seasons.single;
  }

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async =>
      <TmdbMetadata>[_manualEpisodeMetadata(summaryOnly: true)];

  @override
  Future<TmdbSearchPage> searchPage(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
    required int page,
  }) async {
    return TmdbSearchPage(
      page: page,
      totalPages: 1,
      results: <TmdbMetadata>[_manualEpisodeMetadata(summaryOnly: true)],
    );
  }

  @override
  Future<List<String>> alternativeTitles(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async =>
      const <String>[];
}

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

class _StagedPageCloudClient implements CloudDriveClient {
  _StagedPageCloudClient(this.entries);

  final List<CloudFileEntry> entries;
  final Completer<List<CloudFileEntry>> _autoScan =
      Completer<List<CloudFileEntry>>();
  int _listCount = 0;

  void completeAutoScan() => _autoScan.complete(entries);

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
  ) {
    _listCount++;
    if (_listCount == 1) return Future<List<CloudFileEntry>>.value(entries);
    return _autoScan.future;
  }

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}
