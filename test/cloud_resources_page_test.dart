import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
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
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

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

void main() {
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

    expect(find.text('中文剧名 第 3 季'), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('season-poster-3')), findsOneWidget);
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

  testWidgets('无季度多视频作品的选集弹层仍显示全部视频', (tester) async {
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
    expect(find.text('2 集'), findsNWidgets(2));
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

  testWidgets('无来源时显示两种添加入口', (tester) async {
    final fixture = await _PageFixture.create();

    await tester.pumpWidget(
      MaterialApp(
        home: CloudResourcesPage(controller: fixture.controller),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('还没有可用的网盘来源'), findsOneWidget);
    expect(find.text('添加 OpenList'), findsOneWidget);
    expect(find.text('添加夸克网盘'), findsOneWidget);
    fixture.controller.dispose();
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

    expect(find.text('网盘资源'), findsOneWidget);
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
    expect(find.text('已汇总全部媒体根目录'), findsOneWidget);
    expect(find.byTooltip('返回上级'), findsNothing);
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
    await tester.tap(find.byTooltip('自动整理当前来源'));
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
    await tester.tap(find.byTooltip('自动整理当前来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '开始整理'));
    await tester.pump();

    expect(find.text('正在扫描目录 0，已发现 0 项'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey<String>('cloud-source-selector')),
          )
          .onChanged,
      isNull,
    );
    for (final tooltip in <String>[
      '自动整理当前来源',
      '刮削当前来源',
      '移除当前来源',
      '刷新当前来源',
    ]) {
      final button = find
          .ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(IconButton),
          )
          .first;
      expect(tester.widget<IconButton>(button).onPressed, isNull);
    }

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
      find.byKey(ValueKey<String>('tmdb-poster-${record.stableKey}')),
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
      expect(delegate.maxCrossAxisExtent, 220);
      expect(delegate.childAspectRatio, 0.5);
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
    expect(regular.cardWidth, lessThanOrEqualTo(220));
    expect(maximized.cardWidth, lessThanOrEqualTo(220));
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
    expect(find.text('已汇总全部媒体根目录'), findsOneWidget);
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

    await tester.tap(find.byTooltip('刮削当前来源'));
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
    await tester.tap(find.byTooltip('刮削当前来源'));
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

    await tester.tap(find.byTooltip('刮削当前来源'));
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

class _PageFixture {
  const _PageFixture(this.controller);

  final CloudResourcesController controller;

  static Future<_PageFixture> create({
    CloudSource? source,
    List<CloudFileEntry> entries = const <CloudFileEntry>[],
    Map<String, List<CloudFileEntry>>? entriesById,
    CloudResourceTmdbRecord? record,
    CloudResourceTmdbCoordinator? tmdbCoordinator,
    CloudDriveClient? client,
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
      },
    );
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    final minSizeProvider = minRecognizedVideoSizeBytesProvider ?? (() => 0);
    return _PageFixture(
      CloudResourcesController(
        repository: repository,
        credentialStore: credentials,
        providerRegistry: registry,
        mediaIndexRepository: indexRepository,
        mediaIndexer: CloudMediaIndexer(
          repository: indexRepository,
          minRecognizedVideoSizeBytesProvider: minSizeProvider,
        ),
        tmdbCoordinator: tmdbCoordinator,
        minRecognizedVideoSizeBytesProvider: minSizeProvider,
      ),
    );
  }
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
