import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/presentation/media_category_page.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';

void main() {
  testWidgets('合集读取中或失败时不显示未标记作品', (tester) async {
    final pending = Completer<void>();
    var reads = 0;
    final unmarked = series('local', '不应出现的作品');
    await tester.pumpWidget(MaterialApp(
      home: page([unmarked], const {}, refresh: () {
        reads++;
        return reads == 1 ? Future<void>.value() : pending.future;
      }),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '合集'));
    await tester.pump();
    await tester.tap(find.byTooltip('刷新已有资料'));
    await tester.pump();
    expect(find.byType(ImmersiveMediaCard), findsNothing);
    expect(find.text('不应出现的作品'), findsNothing);

    pending.completeError(StateError('缓存读取失败'));
    await tester.pumpAndSettle();
    expect(find.byType(ImmersiveMediaCard), findsNothing);
    expect(find.text('不应出现的作品'), findsNothing);
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('合集刷新挂起或失败仍保留已有合集', (tester) async {
    final pending = Completer<void>();
    final marked = series('cloud', '合集作品');
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
        home: page([
      marked,
      series('local', '不应出现的作品'),
    ], {
      marked.key: const MediaLibraryUserState(collections: ['周末']),
    }, refresh: () => ++reads == 1 ? Future<void>.value() : pending.future)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '合集'));
    await tester.pump();
    await tester.tap(find.byTooltip('刷新已有资料'));
    await tester.pump();
    expect(find.text('周末'), findsOneWidget);
    expect(find.byType(ImmersiveMediaCard), findsNothing);
    pending.completeError(StateError('缓存读取失败'));
    await tester.pumpAndSettle();
    expect(find.text('周末'), findsOneWidget);
    expect(find.byType(ImmersiveMediaCard), findsNothing);
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('页签、合集数量、当前范围搜索与来源筛选复用既有索引', (tester) async {
    final local = series('local', '同名');
    final cloud = series('cloud', '同名');
    final unmarked = series('other', '未标记');
    final states = {
      local.key: const MediaLibraryUserState(
          favorite: true, watchLater: true, collections: ['周末']),
      cloud.key:
          const MediaLibraryUserState(favorite: true, collections: ['周末']),
      'local|orphan':
          const MediaLibraryUserState(watchLater: true, collections: ['断线']),
      'classification-only':
          const MediaLibraryUserState(categoryOverride: ['电影']),
    };
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
        home: page([local, cloud, unmarked], states,
            refresh: () async => reads++)));
    await tester.pumpAndSettle();
    expect(find.byType(ImmersiveMediaCard), findsNWidgets(2));
    expect(find.textContaining('项待关联记录'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Original');
    await tester.pumpAndSettle();
    expect(find.byType(ImmersiveMediaCard), findsNWidgets(2));
    expect(reads, 1);
    await tester
        .tap(find.byKey(const ValueKey('media-category-source-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('网盘').last);
    await tester.pumpAndSettle();
    expect(find.byType(ImmersiveMediaCard), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('media-category-source-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部来源').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '待看'));
    await tester.pumpAndSettle();
    expect(find.byType(ImmersiveMediaCard), findsOneWidget);
    expect(find.text('1 项待关联记录'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '合集'));
    await tester.pumpAndSettle();
    expect(find.byType(ImmersiveMediaCard), findsNothing);
    expect(find.text('2 部作品'), findsOneWidget);
    expect(find.text('1 部作品'), findsOneWidget);
    await tester.tap(find.text('周末'));
    await tester.pumpAndSettle();
    expect(find.byType(ImmersiveMediaCard), findsNWidgets(2));
    expect(find.textContaining('项待关联记录'), findsNothing);
    expect(reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消收藏仅更新收藏，外部标记变更立即刷新，待看保留且播放沿用回调', (tester) async {
    final item = series('local', '作品');
    final changes = ChangeNotifier();
    addTearDown(changes.dispose);
    final states = {
      item.key: const MediaLibraryUserState(
          favorite: true,
          watchLater: true,
          collections: ['周末'],
          categoryOverride: ['电影'])
    };
    String? played;
    await tester.pumpWidget(MaterialApp(
        home: page([item], states,
            changes: changes,
            onSave: (key, {favorite, watchLater, collections}) async {
              expect(favorite, isFalse);
              expect(watchLater, isNull);
              expect(collections, isNull);
              states[key] = states[key]!.copyWith(favorite: favorite);
              changes.notifyListeners();
            },
            onPlay: (_, episode) async => played = episode.stableId)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('媒体操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消收藏'));
    await tester.pumpAndSettle();
    expect(find.byType(ImmersiveMediaCard), findsNothing);
    expect(states[item.key]!.watchLater, isTrue);
    expect(states[item.key]!.collections, ['周末']);
    expect(states[item.key]!.categoryOverride, ['电影']);
    states[item.key] = states[item.key]!.copyWith(favorite: true);
    changes.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(ImmersiveMediaCard), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '待看'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ImmersiveMediaCard));
    await tester.pumpAndSettle();
    expect(played, item.episodes.single.stableId);
    expect(states[item.key]!.watchLater, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('离线缓存允许查看资料并禁用播放，待关联记录沿用关联流程', (tester) async {
    final item = series('cloud', '离线作品', available: false);
    final states = {
      item.key: const MediaLibraryUserState(favorite: true),
      'old': const MediaLibraryUserState(favorite: true)
    };
    var plays = 0;
    (String, String)? linked;
    await tester.pumpWidget(MaterialApp(
        home: page([item], states,
            onPlay: (_, __) async => plays++,
            onRelink: (a, b) async => linked = (a, b))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('媒体操作'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<PopupMenuItem<Object?>>(find.ancestor(
                of: find.text('播放'),
                matching: find.byWidgetPredicate(
                    (widget) => widget is PopupMenuItem<Object?>)))
            .enabled,
        isFalse);
    await tester.tap(find.text('媒体详情'));
    await tester.pumpAndSettle();
    expect(find.text('缓存简介'), findsOneWidget);
    expect(plays, 0);
    Navigator.of(tester.element(find.text('缓存简介'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 项待关联记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('old'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('离线作品 · 网盘 · 1 个视频'));
    await tester.pumpAndSettle();
    expect(linked, ('old', item.key));
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 640.0, 960.0]) {
    testWidgets('我的片库在 $width 宽和两倍文字下可操作', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final item = series('local', '作品');
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!),
          home: page([
            item
          ], {
            item.key:
                const MediaLibraryUserState(favorite: true, watchLater: true)
          })));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '作品');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '待看'));
      await tester.pumpAndSettle();
      expect(find.byType(ImmersiveMediaCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

MediaCategoryPage page(
  List<MediaLibrarySeries> items,
  Map<String, MediaLibraryUserState> states, {
  Future<void> Function()? refresh,
  Listenable? changes,
  MediaLibraryMarksAction? onSave,
  Future<void> Function(MediaLibrarySeries, MediaLibraryEpisode)? onPlay,
  Future<void> Function(String, String)? onRelink,
}) =>
    MediaCategoryPage(
        category: null,
        observeLibrary: false,
        capabilities: AppPlatformCapabilities.windows,
        libraryListenable: changes,
        initialize: refresh ?? () async {},
        refresh: refresh,
        libraryProvider: () => CloudMediaLibrary(series: items, filters: const [
              MediaLibrarySourceFilter('all', '全部来源', null),
              MediaLibrarySourceFilter('local', '本地', MediaSourceKind.local),
              MediaLibrarySourceFilter('cloud', '网盘', MediaSourceKind.cloud),
            ]),
        userStatesProvider: () => states,
        onUserStateChanged: onSave,
        onRelinkUserState: onRelink ?? (_, __) async {},
        onPlayEpisode: onPlay ?? (_, __) async {});

MediaLibrarySeries series(String source, String title,
        {bool available = true}) =>
    MediaLibrarySeries(
      key: '$source|$title',
      seriesKey: title,
      title: title,
      sourceKind: MediaSourceKind.cloud,
      sourceId: source,
      sourceName: '网盘',
      isAvailable: available,
      tmdbOverview: '缓存简介',
      episodes: [
        MediaLibraryEpisode.cloud(
            stableId: title,
            name: '$title.mkv',
            sourceId: source,
            sourceName: '网盘',
            isAvailable: available,
            remoteId: title,
            remotePath: '/$title.mkv',
            tmdbOriginalTitle: 'Original Title')
      ],
    );
