import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/library_media_view_data_builder.dart';
import 'package:kanyingyin/features/library/application/media_library_classification.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_card_view_data.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_episode_sheet.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_poster_wall.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/local_series_grouper.dart';

void main() {
  test('普通目录不构造媒体播放标识也不显示自动分类', () {
    final data = CloudResourceCardViewData.fromEntry(
      entry: const CloudFileEntry(
        id: '',
        remotePath: '/目录',
        name: '目录',
        size: 0,
        modifiedAt: null,
        isDirectory: true,
      ),
      record: null,
      scraping: false,
      hasSubtitle: false,
    );

    expect(data.kind, CloudResourceCardKind.directory);
    expect(data.unifiedDetails, isEmpty);
  });

  test('网盘卡片两套详情文案使用同一动漫分类结果', () {
    final data = CloudResourceCardViewData.fromGroup(
      group: _group(),
      scraping: false,
    );

    expect(data.details, contains('动漫'));
    expect(data.details, isNot(contains('电视剧')));
    expect(data.unifiedDetails, contains('动漫'));
    expect(data.unifiedBadges.map((value) => value.label), contains('动漫'));
  });

  test('独立视频卡片优先真实作品并尊重人工清空和门槛', () {
    final group = _group();
    final series = _series(group);
    CloudResourceCardViewData build({
      MediaLibraryUserState? state,
      MediaClassificationMode mode = MediaClassificationMode.conservative,
    }) =>
        CloudResourceCardViewData.fromEntry(
          entry: group.videos.single,
          record: null,
          scraping: false,
          hasSubtitle: false,
          librarySeries: series,
          userState: state,
          classificationMode: mode,
        );

    expect(build().unifiedDetails, contains('动漫'));
    expect(build().details, contains('动漫'));
    expect(build(mode: MediaClassificationMode.manual).unifiedDetails,
        contains('待确认'));
    final empty = build(
        state: const MediaLibraryUserState(
            categoryOverride: [], genreOverride: []));
    expect(empty.unifiedDetails, contains('未分类'));
    expect(empty.details, contains('未分类'));
  });

  test('本地卡片通过真实索引读取动漫分类并允许人工覆盖', () {
    final group = _group();
    final localGroup = LocalVideoGroup(episodes: [
      LocalFileItem(
        path: r'D:\动画\S01E01.mkv',
        name: 'S01E01.mkv',
        size: 1024,
        modified: DateTime.utc(2026, 10, 11),
        isDirectory: false,
        isVideo: true,
      ),
    ], titleOverride: '测试动画');
    const builder = LibraryMediaViewDataBuilder();
    final automatic = builder.build(localGroup,
        isScraping: false, librarySeries: _series(group));
    final manual = builder.build(
      localGroup,
      isScraping: false,
      librarySeries: _series(group),
      userState: const MediaLibraryUserState(
          categoryOverride: ['电影'], genreOverride: []),
      classificationMode: MediaClassificationMode.manual,
    );

    expect(automatic.unifiedDetails, contains('动漫'));
    expect(automatic.unifiedDetails, isNot(contains('电视剧')));
    expect(manual.unifiedDetails, contains('电影'));
  });

  testWidgets('网盘海报墙将作品状态与门槛传入卡片', (tester) async {
    final group = _group();
    var requested = 0;
    Future<void> show(
        {MediaLibraryUserState? state,
        MediaClassificationMode mode =
            MediaClassificationMode.conservative}) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: CloudResourcePosterWall(
        sourceId: 'cloud',
        collection: CloudResourceCollection(groups: [group]),
        scrapingKeys: const {},
        userStates: {if (state != null) group.stableKey: state},
        classificationMode: mode,
        classificationSeriesForGroup: (value) {
          expect(value, same(group));
          requested++;
          return _series(value);
        },
        onOpenGroup: (_) {},
        onEditTitle: (_) {},
        onScrape: (_) {},
        onRematch: (_) {},
      ))));
      await tester.pumpAndSettle();
    }

    await show(
        state: const MediaLibraryUserState(
            categoryOverride: ['电影'], genreOverride: []));
    expect(
        tester
            .widget<ImmersiveMediaCard>(find.byType(ImmersiveMediaCard))
            .details,
        contains('电影'));
    expect(requested, greaterThan(0));
    await show(mode: MediaClassificationMode.manual);
    expect(
        tester
            .widget<ImmersiveMediaCard>(find.byType(ImmersiveMediaCard))
            .details,
        contains('待确认'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('打开中的网盘选集页跟随人工选择与门槛更新', (tester) async {
    final changes = ChangeNotifier();
    final group = _group();
    var states = <String, MediaLibraryUserState>{
      group.stableKey: const MediaLibraryUserState(categoryOverride: ['电影']),
    };
    var mode = MediaClassificationMode.conservative;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => FilledButton(
        onPressed: () => showCloudResourceEpisodeSheet(
          context: context,
          sourceId: 'cloud',
          group: group,
          groupListenable: changes,
          userStatesProvider: () => states,
          classificationModeProvider: () => mode,
          classificationSeriesForGroup: _series,
        ),
        child: const Text('打开选集'),
      ),
    ))));
    await tester.tap(find.text('打开选集'));
    await tester.pumpAndSettle();
    expect(find.text('电影'), findsNWidgets(2));
    states = {};
    mode = MediaClassificationMode.manual;
    changes.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('电影'), findsNothing);
    expect(find.text('待确认'), findsNWidgets(2));
    expect(find.text('S01E01.mkv'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    changes.dispose();
  });

  testWidgets('网盘选集页沿用人工分类且不改变剧集入口', (tester) async {
    final group = _group();
    var requested = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => FilledButton(
        onPressed: () => showCloudResourceEpisodeSheet(
          context: context,
          sourceId: 'cloud',
          group: group,
          userStates: {
            group.stableKey: const MediaLibraryUserState(
                categoryOverride: ['电影'], genreOverride: [])
          },
          classificationMode: MediaClassificationMode.manual,
          classificationSeriesForGroup: (value) {
            requested++;
            return _series(value);
          },
        ),
        child: const Text('打开选集'),
      ),
    ))));

    await tester.tap(find.text('打开选集'));
    await tester.pumpAndSettle();
    expect(find.text('电影'), findsNWidgets(2));
    expect(find.text('动漫'), findsNothing);
    expect(find.text('S01E01.mkv'), findsOneWidget);
    expect(requested, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}

MediaLibrarySeries _series(CloudResourceMediaGroup group) => MediaLibrarySeries(
      key: group.stableKey,
      seriesKey: group.workKey,
      title: group.displayName,
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'cloud',
      sourceName: '网盘',
      isAvailable: true,
      episodes: const [],
      mediaType: group.workRecord!.metadata!.mediaType,
      genres: group.workRecord!.metadata!.genres,
      tmdbMetadata: group.workRecord!.metadata,
    );

CloudResourceMediaGroup _group() {
  final metadata = TmdbMetadata(
    id: 42,
    mediaType: TmdbMediaType.tv,
    title: '测试动画',
    genres: const ['动画'],
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026, 10, 11),
    matchConfidence: 1,
  );
  return CloudResourceMediaGroup(
    stableKey: 'cloud|animation',
    workKey: 'cloud|animation',
    displayName: '测试动画',
    seriesName: '测试动画',
    isSeries: true,
    isWorkScoped: true,
    videos: const [
      CloudFileEntry(
        id: 'episode',
        remotePath: '/动画/S01E01.mkv',
        name: 'S01E01.mkv',
        size: 1024,
        modifiedAt: null,
        isDirectory: false,
        seasonNumber: 1,
        episodeNumber: 1,
      ),
    ],
    seasons: const [],
    record: null,
    workRecord: CloudWorkTmdbRecord.matched(
      sourceId: 'cloud',
      workKey: 'cloud|animation',
      workRootId: 'animation',
      workRootPath: '/动画',
      remoteName: '测试动画',
      metadata: metadata,
      checkedAt: DateTime.utc(2026, 10, 11),
    ),
  );
}
