import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_library_category.dart';
import 'package:kanyingyin/features/library/presentation/media_category_page.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_playback_request.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_episode_sheet.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_media_library_adapter.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';

CloudMediaIndexItem episode(String id, int number,
        {String directory = 'A',
        bool hdr = false,
        MediaReleaseTags? tags,
        int season = 1,
        String root = 'show',
        String sourceId = 'quark',
        String suffix = ''}) =>
    CloudMediaIndexItem(
      sourceId: sourceId,
      remoteId: id,
      remotePath: '/剧/$directory/S01E$number$suffix.mkv',
      name: 'S01E$number.mkv',
      workKey: '$sourceId|work|$root',
      workRootId: root,
      workRootPath: '/剧',
      size: 1024,
      modifiedAt: null,
      seriesName: '示例剧',
      seasonNumber: season,
      episodeNumber: number,
      mediaType: CloudMediaType.episode,
      subtitleRefs: [CloudRemoteRef(id: 'sub-$id', path: '/字幕/$id.srt')],
      releaseTags: tags ??
          MediaReleaseTags(
            resolution: '2160p',
            source: 'Web-DL',
            dynamicRange: hdr ? const ['HDR'] : const [],
          ),
    );

CloudResourceMediaGroup group(List<CloudMediaIndexItem> items) =>
    CloudResourceCollectionGrouper()
        .group(items: items, query: '')
        .groups
        .single;

void main() {
  test('不同目录版本分开且缺集共享所有候选，保留真实身份和稳定顺序', () {
    final items = [
      episode('a1', 1),
      episode('a2', 2),
      episode('a2-extra', 2),
      episode('b1', 1, directory: 'B'),
      episode('b3', 3, directory: 'B'),
    ];
    final result = group(items);
    expect(result.videos, hasLength(5));
    expect(result.uniqueEpisodeCount, 3);
    expect(result.versions, hasLength(2));
    final second = result.versions.last;
    final shared = second.videos.where((video) => video.isShared).toList();
    expect(shared.map((video) => video.id), ['a2', 'a2-extra']);
    expect(shared.first.remotePath, items[1].remotePath);
    expect(shared.first.sharedFromVersionLabel, result.versions.first.label);
    expect(second.videos.map((video) => video.episodeNumber), [1, 2, 2, 3]);
    final reversed = group(items.reversed.toList());
    expect(reversed.versions.map((version) => version.key),
        result.versions.map((version) => version.key));
    expect(reversed.versions.map((version) => version.label),
        result.versions.map((version) => version.label));
    final request = buildCloudResourcePlaybackRequest(
      sourceId: 'quark',
      group: result,
      selected: shared.first,
      subtitleFor: (_) => null,
    );
    expect(request.targets.map((target) => target.remoteId),
        second.videos.map((video) => video.id));
    expect(request.targets.map((target) => target.remoteId),
        isNot(contains('a1')));
  });

  test('同目录 HDR 与普通版本分开且未识别集号不共享', () {
    final result = group([
      episode('hdr1', 1, hdr: true),
      episode('plain1', 1),
      episode('hdr2', 2, hdr: true),
      episode('unknown', 0),
    ]);
    expect(result.versions, hasLength(2));
    final plain = result.versions
        .singleWhere((version) => !version.label.contains('HDR'));
    expect(
        plain.videos.singleWhere((video) => video.episodeNumber == 2).isShared,
        isTrue);
    expect(
        result.versions
            .expand((version) => version.videos)
            .where((video) => video.id == 'unknown' && video.isShared),
        isEmpty);
  });

  test('无重集的普通单版本不因规格缺失而拆分', () {
    final result = group([episode('a1', 1), episode('a2', 2, hdr: true)]);
    expect(result.versions, isEmpty);
    expect(result.videos, hasLength(2));
  });

  test('规格别名等价，且逐集嵌套目录按版本归并', () {
    final result = group([
      episode('a1', 1,
          directory: 'A/S01/第1集',
          tags: const MediaReleaseTags(resolution: '4K', codec: 'H265')),
      episode('a2', 2,
          directory: 'A/S01/第2集',
          tags: const MediaReleaseTags(resolution: '2160p', codec: 'HEVC')),
      episode('b1', 1, directory: 'B/S01/第1集'),
    ]);
    expect(result.versions, hasLength(2));
    expect(
        result.versions.first.videos
            .where((video) => !video.isShared)
            .map((video) => video.id),
        ['a1', 'a2']);
    expect(
        group([
          episode('a1', 1,
              tags: const MediaReleaseTags(resolution: '4K', codec: 'H265')),
          episode('a1-copy', 1,
              tags: const MediaReleaseTags(resolution: '2160p', codec: 'HEVC')),
        ]).versions,
        isEmpty);
  });

  test('选择共享集后切换下一集，播放器仍只解析当前版本', () async {
    final result = group([
      episode('a1', 1),
      episode('a2', 2),
      episode('b1', 1, directory: 'B'),
      episode('b3', 3, directory: 'B')
    ]);
    final selected =
        result.versions.last.videos.singleWhere((video) => video.isShared);
    final request = buildCloudResourcePlaybackRequest(
        sourceId: 'quark',
        group: result,
        selected: selected,
        subtitleFor: (_) => null);
    final resolved = <String>[];
    final controller = LocalVideoController(
        initializePlayer: (_) async {},
        resolveCloudPlayback: (target) async {
          resolved.add(target.remoteId);
          return CloudResolvedPlayback(
              target: target,
              videoUrl: 'https://example.com/video',
              httpHeaders: const {});
        });
    await controller.openCloudPlayback(
        seriesTitle: request.seriesTitle,
        targets: request.targets,
        selectedStableId: request.selectedStableId);
    await controller.changeEpisode(3);
    expect(resolved, ['a2', 'b3']);
    expect(controller.roadList.single.data,
        result.versions.last.videos.map((video) => video.remotePath));
    controller.invalidatePlaybackOperations();
  });

  test('只在当前季度共享，媒体库转换保留字幕与版本播放隔离', () {
    final items = [
      episode('a1', 1),
      episode('a2', 2),
      episode('b1', 1, directory: 'B'),
      episode('s2e3', 3, season: 2)
    ];
    final collection =
        CloudResourceCollectionGrouper().group(items: items, query: '');
    final series = const CloudResourceMediaLibraryAdapter()
        .convert(
          source: const CloudSource(
              id: 'quark',
              type: CloudSourceType.quark,
              name: '夸克网盘',
              baseUrl: 'https://pan.quark.cn',
              rootPaths: ['/剧']),
          collection: collection,
          indexedItems: items,
        )
        .singleWhere((series) => series.episodes.first.seasonNumber == 1);
    expect(series.episodes, hasLength(3));
    final shared = series.versions.last.episodes
        .singleWhere((video) => video.sharedFromVersionLabel != null);
    expect(shared.remoteId, 'a2');
    expect(shared.subtitleRemoteRefs.single.id, 'sub-a2');
    expect(series.playbackEpisodesFor(shared).map((video) => video.remoteId),
        ['b1', 'a2']);
    expect(
        series.versions
            .expand((version) => version.episodes)
            .map((video) => video.remoteId),
        isNot(contains('s2e3')));
  });

  test('相同 TMDB 的不同来源根分别成版，但不同网盘不混合共享', () {
    final items = [
      episode('a1', 1, root: 'root-a'),
      episode('a2', 2, root: 'root-a'),
      episode('b1', 1, root: 'root-b'),
      episode('other3', 3, sourceId: 'other')
    ];
    final records = <String, CloudWorkTmdbRecord>{
      for (final item in items)
        item.workKey!: CloudWorkTmdbRecord.matched(
          sourceId: item.sourceId,
          workKey: item.workKey!,
          workRootId: item.workRootId!,
          workRootPath: item.workRootPath!,
          remoteName: '示例剧',
          checkedAt: DateTime.utc(2026, 10, 11),
          metadata: TmdbMetadata(
              id: 42,
              mediaType: TmdbMediaType.tv,
              title: '示例剧',
              language: 'zh-CN',
              matchedAt: DateTime.utc(2026, 10, 11),
              matchConfidence: 1),
        ),
    };
    final results = CloudResourceCollectionGrouper()
        .group(items: items, recordsByWorkKey: records, query: '')
        .groups;
    expect(results, hasLength(2));
    final quark =
        results.singleWhere((group) => group.stableKey.startsWith('quark|'));
    expect(quark.versions, hasLength(2));
    expect(quark.versions.last.videos.map((video) => video.id), ['b1', 'a2']);
    expect(
        quark.versions
            .expand((version) => version.videos)
            .map((video) => video.id),
        isNot(contains('other3')));
  });

  test('旧索引无结构化规格时使用文件原名拆 HDR 版本', () {
    final result = group([
      episode('hdr1', 1,
          suffix: '.2160p.WEB-DL.HDR', tags: const MediaReleaseTags()),
      episode('plain1', 1,
          suffix: '.2160p.WEB-DL', tags: const MediaReleaseTags()),
      episode('hdr2', 2,
          suffix: '.2160p.WEB-DL.HDR', tags: const MediaReleaseTags())
    ]);
    expect(result.versions, hasLength(2));
    final plain = result.versions
        .singleWhere((version) => !version.label.contains('HDR'));
    expect(plain.videos.last.id, 'hdr2');
    expect(plain.videos.last.isShared, isTrue);
  });

  test('同集规格各自缺字段时不崩溃且保留全部候选', () {
    final result = group([
      episode('resolution-a', 1,
          tags: const MediaReleaseTags(resolution: '2160p')),
      episode('resolution-b', 1,
          tags: const MediaReleaseTags(resolution: '1080p')),
      episode('codec-a', 1, tags: const MediaReleaseTags(codec: 'H265')),
      episode('codec-b', 1, tags: const MediaReleaseTags(codec: 'AVC')),
    ]);
    expect(result.videos, hasLength(4));
    expect(result.versions, isEmpty);
  });

  test('旧资源入口混合多版本季度和单版本季度时仍可选择全部季度', () {
    final entries = [
      for (final (id, directory, season) in [
        ('a1', 'A', 1),
        ('b1', 'B', 1),
        ('s2e1', 'A', 2)
      ])
        CloudFileEntry(
            id: id,
            remotePath: '/剧/$directory/示例剧.S0${season}E01.mkv',
            name: '示例剧.S0${season}E01.mkv',
            size: 1024,
            modifiedAt: null,
            isDirectory: false),
    ];
    final records = [
      for (final entry in entries)
        CloudResourceTmdbRecord.matched(
            sourceId: 'quark',
            remoteId: entry.id,
            remotePath: entry.remotePath,
            displayName: entry.name,
            resourceKind: CloudResourceKind.standaloneVideo,
            checkedAt: DateTime.utc(2026, 10, 11),
            metadata: TmdbMetadata(
                id: 42,
                mediaType: TmdbMediaType.tv,
                title: '示例剧',
                language: 'zh-CN',
                matchedAt: DateTime.utc(2026, 10, 11),
                matchConfidence: 1)),
    ];
    final collection = CloudResourceCollectionGrouper().group(
        sourceId: 'quark',
        entries: entries,
        records: {for (final record in records) record.stableKey: record},
        query: '');
    final series = const CloudResourceMediaLibraryAdapter().convert(
      source: const CloudSource(
          id: 'quark',
          type: CloudSourceType.quark,
          name: '夸克网盘',
          baseUrl: 'https://pan.quark.cn',
          rootPaths: ['/剧']),
      collection: collection,
      indexedItems: const [],
    ).single;
    expect(series.versions, hasLength(3));
    final singleSeason =
        series.versions.singleWhere((version) => version.label == '第 2 季');
    final selected = singleSeason.episodes.single;
    expect(selected.remoteId, 's2e1');
    expect(series.playbackEpisodesFor(selected).single.remoteId, 's2e1');
  });

  for (final width in [320.0, 390.0, 600.0, 1280.0]) {
    testWidgets('选集在 $width 像素切换版本并返回共享文件的版本身份', (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final result = group([
        episode('a1', 1),
        episode('a2', 2),
        episode('b1', 1, directory: 'B')
      ]);
      CloudFileEntry? selected;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
        builder: (context) => FilledButton(
            onPressed: () async {
              selected = await showCloudResourceEpisodeSheet(
                  context: context, sourceId: 'quark', group: result);
            },
            child: const Text('选集')),
      ))));
      await tester.tap(find.text('选集'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(ChoiceChip, result.versions.last.label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final sharedTile = find.ancestor(
          of: find.text('共享自${result.versions.first.label}'),
          matching: find.byType(ListTile));
      await tester.ensureVisible(sharedTile);
      await tester.tap(sharedTile);
      await tester.pumpAndSettle();
      expect(selected?.id, 'a2');
      expect(selected?.playbackVersionKey, result.versions.last.key);
    });
  }

  testWidgets('分类页选集切换版本后播放共享候选', (tester) async {
    final items = [
      episode('a1', 1),
      episode('a2', 2),
      episode('b1', 1, directory: 'B')
    ];
    final series = const CloudResourceMediaLibraryAdapter()
        .convert(
          source: const CloudSource(
              id: 'quark',
              type: CloudSourceType.quark,
              name: '夸克网盘',
              baseUrl: 'https://pan.quark.cn',
              rootPaths: ['/剧']),
          collection: CloudResourceCollection(groups: [group(items)]),
          indexedItems: items,
        )
        .single;
    MediaLibraryEpisode? played;
    await tester.pumpWidget(MaterialApp(
        home: MediaCategoryPage(
      category: MediaLibraryCategory.tvSeries,
      initialize: () async {},
      libraryProvider: () =>
          CloudMediaLibrary(series: [series], filters: const []),
      onPlayEpisode: (_, episode) async => played = episode,
      observeLibrary: false,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('media-category-card-${series.key}')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(ChoiceChip, series.versions.last.label));
    await tester.pumpAndSettle();
    final sharedTile = find.ancestor(
        of: find.text('共享自${series.versions.first.label}'),
        matching: find.byType(ListTile));
    await tester.tap(sharedTile);
    await tester.pumpAndSettle();
    expect(played?.remoteId, 'a2');
    expect(played?.playbackVersionKey, series.versions.last.key);
    expect(tester.takeException(), isNull);
  });
}
