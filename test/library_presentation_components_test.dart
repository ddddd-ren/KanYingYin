import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerEnterEvent, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/features/library/presentation/library_media_grid.dart';
import 'package:kanyingyin/features/library/presentation/library_path_bar.dart';
import 'package:kanyingyin/features/library/presentation/library_source_menu.dart';

void main() {
  test('TMDB 匹配状态显示实际 current/total 而不是插值字面量', () {
    final status = LibraryDirectoryStatusViewData.matchingMetadata(
      label: '正在匹配',
      current: 3,
      total: 12,
    );

    expect(status.progressLabel, '3/12');
    expect(status.progressLabel, isNot(contains(r'${')));
  });

  test('展示 view data 会复制并冻结所有列表', () {
    const breadcrumb = LibraryBreadcrumbViewData(label: 'D:', path: r'D:\');
    const source = LibrarySourceViewData(
      id: 'local',
      name: '本地',
      path: r'D:\',
      subtitle: '本地来源',
    );
    const media = LibraryMediaItemViewData(
      id: 'media',
      title: '标题',
      subtitle: '副标题',
      infoText: '信息',
      modifiedText: '2026-07-19',
      hasMultipleEpisodes: false,
      hasSubtitle: false,
      scrapeLabel: '未刮削',
    );
    final breadcrumbs = <LibraryBreadcrumbViewData>[breadcrumb];
    final sources = <LibrarySourceViewData>[source];
    final items = <LibraryMediaItemViewData>[media];
    final sourceData = LibrarySourceMenuViewData(sources: sources);
    final pathData = LibraryPathBarViewData(
      breadcrumbs: breadcrumbs,
      recentPaths: const [],
      sortBy: 'name',
      sortAscending: true,
      status: const LibraryDirectoryStatusViewData(
        kind: LibraryDirectoryStatusKind.idle,
        label: '',
      ),
    );
    final gridData = LibraryMediaGridViewData(items: items);

    breadcrumbs.clear();
    sources.clear();
    items.clear();
    expect(pathData.breadcrumbs, hasLength(1));
    expect(sourceData.sources, hasLength(1));
    expect(gridData.items, hasLength(1));
    expect(() => pathData.breadcrumbs.add(breadcrumb), throwsUnsupportedError);
    expect(
        () => pathData.recentPaths.add(
              const LibraryRecentPathViewData(label: '视频', path: r'D:\视频'),
            ),
        throwsUnsupportedError);
    expect(() => sourceData.sources.add(source), throwsUnsupportedError);
    expect(() => gridData.items.add(media), throwsUnsupportedError);
  });

  group('LibraryPathBar', () {
    testWidgets('显示路径工具、排序和搜索，并转发动作', (tester) async {
      var picked = false;
      var refreshed = false;
      var sortedBy = '';
      var searched = '';
      var breadcrumbPath = '';
      final searchController = TextEditingController();
      addTearDown(searchController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryPathBar(
              data: LibraryPathBarViewData(
                breadcrumbs: [
                  LibraryBreadcrumbViewData(label: 'D:', path: r'D:\'),
                  LibraryBreadcrumbViewData(
                    label: '动画',
                    path: r'D:\动画',
                    isCurrent: true,
                  ),
                ],
                recentPaths: [],
                sortBy: 'name',
                sortAscending: true,
                status: LibraryDirectoryStatusViewData(
                  kind: LibraryDirectoryStatusKind.idle,
                  label: '2 部剧/12 个视频',
                ),
                canReadMediaInfo: true,
                canGenerateThumbnails: true,
              ),
              sourceMenu: const SizedBox.shrink(),
              searchController: searchController,
              onPickDirectory: () async => picked = true,
              onRefresh: () async => refreshed = true,
              onSort: (field) async => sortedBy = field,
              onSearchChanged: (value) => searched = value,
              onClearSearch: () {},
              onBreadcrumbSelected: (path) async => breadcrumbPath = path,
            ),
          ),
        ),
      );

      expect(find.byTooltip('选择目录'), findsOneWidget);
      expect(find.byTooltip('刷新'), findsOneWidget);
      expect(find.text('动画'), findsOneWidget);
      expect(find.text('名称'), findsOneWidget);
      expect(find.text('2 部剧/12 个视频'), findsOneWidget);
      expect(find.widgetWithText(TextField, '搜索当前目录'), findsOneWidget);

      await tester.tap(find.byTooltip('选择目录'));
      await tester.tap(find.byTooltip('刷新'));
      await tester.tap(find.text('大小'));
      await tester.enterText(find.byType(TextField), '关键字');
      await tester.tap(find.text('D:'));
      await tester.pump();

      expect(picked, isTrue);
      expect(refreshed, isTrue);
      expect(sortedBy, 'size');
      expect(searched, '关键字');
      expect(breadcrumbPath, r'D:\');
    });
  });

  group('LibrarySourceMenu', () {
    testWidgets('展示可用和失效来源，并转发打开与清理动作', (tester) async {
      String? opened;
      String? removed;
      var cleaned = false;
      const available = LibrarySourceViewData(
        id: r'D:\动画',
        name: '动画',
        path: r'D:\动画',
        subtitle: '3 个文件夹  12 个视频  未扫描',
        isCurrent: true,
      );
      const unavailable = LibrarySourceViewData(
        id: r'Z:\离线',
        name: '离线盘',
        path: r'Z:\离线',
        subtitle: '目录不可访问，可移除这条记录',
        isAvailable: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibrarySourceMenu(
              data: LibrarySourceMenuViewData(
                sources: [available, unavailable],
                unavailableCount: 1,
              ),
              onOpen: (source) async => opened = source.id,
              onRemove: (source) async => removed = source.id,
              onRemoveUnavailable: () async => cleaned = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('媒体源'));
      await tester.pumpAndSettle();
      expect(find.text('动画'), findsOneWidget);
      expect(find.text('离线盘'), findsOneWidget);
      expect(find.text('目录不可访问，可移除这条记录'), findsOneWidget);
      expect(find.text('清理 1 个失效媒体源'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.tap(find.text('动画'));
      await tester.pumpAndSettle();
      expect(opened, available.id);

      await tester.tap(find.byTooltip('媒体源'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除“离线盘”'));
      await tester.pumpAndSettle();
      expect(removed, unavailable.id);

      await tester.tap(find.byTooltip('媒体源'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清理 1 个失效媒体源'));
      await tester.pumpAndSettle();
      expect(cleaned, isTrue);
    });
  });

  group('ImmersiveMediaCard', () {
    testWidgets('always 模式始终显示信息和状态标签', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              height: 380,
              child: ImmersiveMediaCard(
                overlayMode: ImmersiveMediaCardOverlayMode.always,
                cover: const ColoredBox(color: Colors.blue),
                title: '中文片名',
                subtitle: '真实文件名.mkv',
                details: '8.7 ★  ·  电影  ·  2025  ·  2.0 GB',
                badges: const <ImmersiveMediaCardBadge>[
                  ImmersiveMediaCardBadge(
                    icon: Icons.closed_caption_outlined,
                    label: '有字幕',
                  ),
                  ImmersiveMediaCardBadge(
                    icon: Icons.image_search_outlined,
                    label: '已刮削',
                  ),
                ],
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );

      final opacity =
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacity.opacity, 1);
      expect(opacity.duration, const Duration(milliseconds: 160));
      expect(opacity.curve, Curves.easeOut);
      expect(find.text('中文片名'), findsOneWidget);
      expect(find.text('真实文件名.mkv'), findsOneWidget);
      expect(find.textContaining('2025'), findsOneWidget);
      expect(find.text('有字幕'), findsOneWidget);
      expect(find.text('已刮削'), findsOneWidget);
      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('键盘焦点使用 Enter 和 Space 触发主操作', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              height: 380,
              child: ImmersiveMediaCard(
                overlayMode: ImmersiveMediaCardOverlayMode.always,
                cover: const ColoredBox(color: Colors.blue),
                title: '键盘卡片',
                onTap: () => taps += 1,
              ),
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(taps, 2);
    });
  });

  group('LibraryMediaGrid', () {
    const item = LibraryMediaItemViewData(
      id: 'show-1',
      title: '测试动画',
      subtitle: '第 1 季',
      infoText: 'MKV  1.0 GB',
      modifiedText: '2026-07-19',
      hasMultipleEpisodes: true,
      hasSubtitle: true,
      scrapeLabel: '已刮削',
      heroTag: 'library-show-1',
    );

    testWidgets('本地海报墙保持海报尺寸并随宽度增加列数', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final layoutItems = <LibraryMediaItemViewData>[
        for (var index = 0; index < 20; index++)
          LibraryMediaItemViewData(
            id: 'show-$index',
            title: '测试动画 $index',
            subtitle: '第 1 季',
            infoText: 'MKV  1.0 GB',
            modifiedText: '2026-07-20',
            hasMultipleEpisodes: true,
            hasSubtitle: false,
            scrapeLabel: '未刮削',
          ),
      ];

      Future<void> pumpAt(double width) async {
        tester.view.physicalSize = Size(width, 720);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LibraryMediaGrid(
                data: LibraryMediaGridViewData(items: layoutItems),
              ),
            ),
          ),
        );
      }

      Future<({int columns, double cardWidth})> layoutAt(double width) async {
        await pumpAt(width);
        final grid = tester.widget<GridView>(find.byType(GridView));
        expect(
          grid.gridDelegate,
          isA<SliverGridDelegateWithMaxCrossAxisExtent>(),
        );
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
      expect(narrow.cardWidth, lessThanOrEqualTo(300));
      expect(regular.cardWidth, lessThanOrEqualTo(300));
      expect(maximized.cardWidth, lessThanOrEqualTo(300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('桌面卡片保持悬浮信息且点击卡片', (tester) async {
      String? played;

      Future<void> pumpAt(Size size) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LibraryMediaGrid(
                data: LibraryMediaGridViewData(items: const [item]),
                onPlay: (value) async => played = value.id,
                onShowActions: (_) async {},
              ),
            ),
          ),
        );
      }

      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await pumpAt(const Size(1000, 700));
      expect(find.byType(ImmersiveMediaCard), findsOneWidget);
      expect(
        tester
            .widget<ImmersiveMediaCard>(find.byType(ImmersiveMediaCard))
            .overlayMode,
        ImmersiveMediaCardOverlayMode.hover,
      );
      expect(find.text('测试动画'), findsOneWidget);
      expect(find.text('有字幕'), findsOneWidget);
      expect(find.text('已刮削'), findsOneWidget);
      expect(tester.widget<Hero>(find.byType(Hero)).tag, item.heroTag);
      expect(
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
          0);
      expect(find.byIcon(Icons.video_collection_outlined), findsOneWidget);

      await tester.tap(find.byType(InkWell));
      await tester.pump();
      expect(played, item.id);
    });

    testWidgets('长按卡片触发更多动作', (tester) async {
      String? actionItem;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LibraryMediaGrid(
            data: LibraryMediaGridViewData(items: const [item]),
            onShowActions: (value) async => actionItem = value.id,
          ),
        ),
      ));

      await tester.longPress(find.byType(InkWell));
      await tester.pump();
      expect(actionItem, item.id);
    });

    testWidgets('鼠标右键触发更多动作', (tester) async {
      String? actionItem;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LibraryMediaGrid(
            data: LibraryMediaGridViewData(items: const [item]),
            onShowActions: (value) async => actionItem = value.id,
          ),
        ),
      ));

      await tester.tap(find.byType(InkWell), buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(actionItem, item.id);
    });

    testWidgets('悬浮 160ms 后显示信息 overlay 并保持原动画曲线', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LibraryMediaGrid(
            data: LibraryMediaGridViewData(items: const [item]),
          ),
        ),
      ));
      final opacityFinder = find.byType(AnimatedOpacity);
      var opacity = tester.widget<AnimatedOpacity>(opacityFinder);
      expect(opacity.opacity, 0);
      expect(opacity.duration, const Duration(milliseconds: 160));
      expect(opacity.curve, Curves.easeOut);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(tester.getCenter(find.byType(InkWell)));
      await tester.pump();
      opacity = tester.widget<AnimatedOpacity>(opacityFinder);
      expect(opacity.opacity, 1);
      await tester.pump(const Duration(milliseconds: 160));
      expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 1);
    });

    testWidgets('媒体项重排后悬浮状态按 id 跟随而不按位置串位', (tester) async {
      const first = LibraryMediaItemViewData(
        id: 'first',
        title: '第一项',
        subtitle: '',
        infoText: '',
        modifiedText: '',
        hasMultipleEpisodes: false,
        hasSubtitle: false,
        scrapeLabel: '已刮削',
      );
      const second = LibraryMediaItemViewData(
        id: 'second',
        title: '第二项',
        subtitle: '',
        infoText: '',
        modifiedText: '',
        hasMultipleEpisodes: false,
        hasSubtitle: false,
        scrapeLabel: '已刮削',
      );

      Widget build(List<LibraryMediaItemViewData> items) => MaterialApp(
            home: Scaffold(
              body: LibraryMediaGrid(
                data: LibraryMediaGridViewData(items: items),
              ),
            ),
          );

      await tester.pumpWidget(build(const [first, second]));
      final cardRegion = tester
          .widgetList<MouseRegion>(find.byType(MouseRegion))
          .firstWhere((region) => region.onEnter != null);
      cardRegion.onEnter!(const PointerEnterEvent());
      await tester.pump();
      double opacityFor(String title) => tester
          .widget<AnimatedOpacity>(find
              .ancestor(
                of: find.text(title),
                matching: find.byType(AnimatedOpacity),
              )
              .first)
          .opacity;
      expect(opacityFor('第一项'), 1);
      expect(opacityFor('第二项'), 0);

      await tester.pumpWidget(build(const [second, first]));
      await tester.pump();
      expect(opacityFor('第二项'), 0);
      expect(opacityFor('第一项'), 1);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey<String>('second'))).dx,
        lessThan(
            tester.getTopLeft(find.byKey(const ValueKey<String>('first'))).dx),
      );
    });

    testWidgets('加载和海报刮削状态显示进度', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LibraryMediaGrid(
            data: LibraryMediaGridViewData(isLoading: true),
          ),
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LibraryMediaGrid(
            data: LibraryMediaGridViewData(items: const [
              LibraryMediaItemViewData(
                id: 'fetching',
                title: '刮削中',
                subtitle: '',
                infoText: '',
                modifiedText: '',
                hasMultipleEpisodes: false,
                hasSubtitle: false,
                scrapeLabel: '正在刮削',
                isScraping: true,
              ),
            ]),
          ),
        ),
      ));
      expect(find.text('正在刮削'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('网络封面失败后回退本地封面，本地失败后显示占位', (tester) async {
      final localCover = File(r'C:\test\cover.png');
      final networkProvider = MemoryImage(base64Decode('AA=='));

      final item = LibraryMediaItemViewData(
        id: 'local-fallback',
        title: '本地回退',
        subtitle: '',
        infoText: '',
        modifiedText: '',
        hasMultipleEpisodes: false,
        hasSubtitle: false,
        scrapeLabel: '已刮削',
        networkCoverUrl: 'https://unused.invalid/cover.png',
        localCoverPath: localCover.path,
        networkCoverProvider: networkProvider,
        localCoverProvider: FileImage(localCover),
      );
      late BuildContext imageContext;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          imageContext = context;
          return const SizedBox.shrink();
        }),
      ));
      final networkImage = LibraryMediaCoverFallback.buildNetwork(
        item,
        localBuilder: (context) => LibraryMediaCoverFallback.buildLocal(
          item,
          placeholderBuilder: (_) => const Icon(Icons.play_circle_fill),
        ),
      ) as Image;
      expect(networkImage.image, same(networkProvider));
      final localFallback = networkImage.errorBuilder!(
        imageContext,
        StateError('模拟网络封面失败'),
        StackTrace.empty,
      ) as Image;
      expect(localFallback.image, isA<FileImage>());

      final placeholder = localFallback.errorBuilder!(
        imageContext,
        StateError('模拟本地封面失败'),
        StackTrace.empty,
      );
      await tester.pumpWidget(MaterialApp(home: placeholder));
      expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    });

    test('封面优先级可选择本地已下载海报或季度网络海报', () {
      final localProvider = MemoryImage(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ));
      final networkProvider = MemoryImage(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ));
      LibraryMediaItemViewData item({required bool preferLocalCover}) =>
          LibraryMediaItemViewData(
            id: 'season-2',
            title: '第 2 季',
            subtitle: '',
            infoText: '',
            modifiedText: '',
            hasMultipleEpisodes: true,
            hasSubtitle: false,
            scrapeLabel: '已刮削',
            preferLocalCover: preferLocalCover,
            localCoverProvider: localProvider,
            networkCoverProvider: networkProvider,
          );

      final localFirst = LibraryMediaCoverFallback.build(
        item(preferLocalCover: true),
        placeholderBuilder: (_) => const Icon(Icons.movie_outlined),
      ) as Image;
      final networkFirst = LibraryMediaCoverFallback.build(
        item(preferLocalCover: false),
        placeholderBuilder: (_) => const Icon(Icons.movie_outlined),
      ) as Image;

      expect(localFirst.image, same(localProvider));
      expect(networkFirst.image, same(networkProvider));
    });

    testWidgets('失败 ImageProvider 在真实卡片中依次回退到本地和占位', (tester) async {
      const failed = _FailingImageProvider();
      final local = MemoryImage(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LibraryMediaGrid(
            data: LibraryMediaGridViewData(items: [
              LibraryMediaItemViewData(
                id: 'local',
                title: '本地回退',
                subtitle: '',
                infoText: '',
                modifiedText: '',
                hasMultipleEpisodes: false,
                hasSubtitle: false,
                scrapeLabel: '已刮削',
                networkCoverProvider: failed,
                localCoverProvider: local,
              ),
              const LibraryMediaItemViewData(
                id: 'placeholder',
                title: '占位回退',
                subtitle: '',
                infoText: '',
                modifiedText: '',
                hasMultipleEpisodes: true,
                hasSubtitle: false,
                scrapeLabel: '未刮削',
                networkCoverProvider: failed,
                localCoverProvider: failed,
              ),
            ]),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(
        tester.widgetList<Image>(find.byType(Image)).any(
              (image) => identical(image.image, local),
            ),
        isTrue,
      );
      expect(find.byIcon(Icons.video_collection_outlined), findsOneWidget);
    });

    testWidgets('空目录保留选择文件夹入口', (tester) async {
      var picked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryMediaGrid(
              data: LibraryMediaGridViewData(currentPath: ''),
              onPickDirectory: () async => picked = true,
            ),
          ),
        ),
      );

      expect(find.text('请先设置本地文件目录'), findsOneWidget);
      await tester.tap(find.text('选择文件夹'));
      await tester.pump();
      expect(picked, isTrue);
    });
  });

  test('展示组件不依赖控制器、Modular、服务或仓储', () {
    const files = [
      'lib/features/library/presentation/library_path_bar.dart',
      'lib/features/library/presentation/library_media_grid.dart',
      'lib/features/library/presentation/library_source_menu.dart',
    ];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('local_controller.dart')), reason: path);
      expect(source, isNot(contains('flutter_modular')), reason: path);
      expect(source, isNot(contains('/services/')), reason: path);
      expect(source, isNot(contains('/repositories/')), reason: path);
    }
  });

  test('LocalPage 实际组合三个媒体库展示组件', () {
    final source = File('lib/pages/local/local_page.dart').readAsStringSync();
    expect(source, contains('LibraryPathBar('));
    expect(source, contains('LibrarySourceMenu('));
    expect(source, contains('LibrarySourceMenuViewData('));
    expect(
      source,
      matches(RegExp(
        r'enabled:\s*!localController\.isLoading\s*&&\s*'
        r'!localController\.isIndexingLibrary',
      )),
    );
    expect(
      RegExp(
        r'if \(localController\.isLoading \|\|\s*'
        r'localController\.isIndexingLibrary\) return;',
      ).allMatches(source),
      hasLength(2),
    );
    expect(source, contains('LibraryMediaGrid('));
    expect(source, contains('heroTag:'));
  });
}

class _FailingImageProvider extends ImageProvider<_FailingImageProvider> {
  const _FailingImageProvider();

  @override
  Future<_FailingImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FailingImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _FailingImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.error(StateError('测试图片加载失败')),
    );
  }
}
