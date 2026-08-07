import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/bean/widget/glass_surface.dart';
import 'package:kanyingyin/features/library/presentation/directory_address_dropdown.dart';
import 'package:kanyingyin/features/library/presentation/library_media_grid.dart';
import 'package:kanyingyin/features/library/presentation/library_path_bar.dart';
import 'package:kanyingyin/features/tv/presentation/tv_focus_surface.dart';
import 'package:kanyingyin/pages/menu/adaptive_navigation_shell.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';

void main() {
  testWidgets('Android 窄屏使用安全区和底部导航', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveNavigationShell(
          selectedIndex: 3,
          destinations: appNavigationDestinations,
          onDestinationSelected: (_) {},
          content: const Text('内容'),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('desktop-sidebar-expanded')),
      findsNothing,
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('电影'), findsNothing);
    expect(find.text('动漫'), findsNothing);
    expect(find.text('电视剧'), findsNothing);
    expect(find.text('分类'), findsOneWidget);
    expect(find.text('媒体库'), findsOneWidget);
    expect(find.text('网盘媒体库'), findsOneWidget);
    await tester.tap(find.text('分类'));
    await tester.pumpAndSettle();
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('动漫'), findsOneWidget);
    expect(find.text('电视剧'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('mobile-safe-content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('compact-bottom-navigation-surface')),
      findsOneWidget,
    );
    final bottomSafeArea = tester.widget<SafeArea>(
      find.byKey(
        const ValueKey<String>('compact-bottom-navigation-safe-area'),
      ),
    );
    expect(bottomSafeArea.top, isFalse);
    expect(bottomSafeArea.bottom, isTrue);
    final bottomSurface = tester.widget<GlassSurface>(
      find.byKey(const ValueKey<String>('compact-bottom-navigation-surface')),
    );
    expect(
      bottomSurface.color,
      Theme.of(tester.element(find.byType(NavigationBar)))
          .colorScheme
          .surfaceContainerLow
          .withValues(alpha: 0.78),
    );
    expect(bottomSurface.blurSigma, 18);
  });

  testWidgets('Android TV 宽屏保持带文字的侧栏并建立焦点组', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(760, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveNavigationShell(
          capabilities: AppPlatformCapabilities.android.copyWith(
            television: true,
          ),
          selectedIndex: 0,
          destinations: appNavigationDestinations,
          onDestinationSelected: (_) {},
          content: const Text('TV 内容'),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('desktop-sidebar-expanded')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('tv-navigation-focus-group')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('tv-content-focus-group')),
        findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
  });

  testWidgets('Android TV 内容区按左键后焦点进入侧栏', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final searchController = TextEditingController();
    addTearDown(searchController.dispose);
    installAppPlatformCapabilities(
      AppPlatformCapabilities.android.copyWith(television: true),
    );
    addTearDown(
      () => installAppPlatformCapabilities(AppPlatformCapabilities.windows),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveNavigationShell(
          capabilities: AppPlatformCapabilities.android.copyWith(
            television: true,
          ),
          selectedIndex: 0,
          destinations: appNavigationDestinations,
          onDestinationSelected: (_) {},
          content: FocusTraversalGroup(
            key: const ValueKey<String>('nested-content-focus-group'),
            child: LibraryPathBar(
              data: LibraryPathBarViewData(
                breadcrumbs: const <LibraryBreadcrumbViewData>[],
                recentPaths: const <LibraryRecentPathViewData>[],
                sortBy: 'name',
                sortAscending: true,
                status: const LibraryDirectoryStatusViewData(
                  kind: LibraryDirectoryStatusKind.idle,
                  label: '0 部剧/0 个视频',
                ),
              ),
              sourceMenu: const SizedBox(width: 32, height: 32),
              searchController: searchController,
              onPickDirectory: () {},
              onRefresh: () {},
              onSort: (_) {},
              onSearchChanged: (_) {},
              onClearSearch: () {},
              onBreadcrumbSelected: (_) {},
              onPathSubmitted: (_) async => null,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(TextField, '搜索当前目录'));
    await tester.pump();
    final searchEditable = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextField, '搜索当前目录'),
        matching: find.byType(EditableText),
      ),
    );
    expect(searchEditable.focusNode.hasFocus, isTrue);

    final navigationGroup =
        find.byKey(const ValueKey<String>('tv-navigation-focus-group'));
    expect(
      find.descendant(
        of: navigationGroup,
        matching: find.byKey(const ValueKey<String>('tv-focused-surface')),
      ),
      findsNothing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(
      find.descendant(
        of: navigationGroup,
        matching: find.byKey(const ValueKey<String>('tv-focused-surface')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Android TV 路径输入框按左键后焦点进入侧栏', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    installAppPlatformCapabilities(
      AppPlatformCapabilities.android.copyWith(television: true),
    );
    addTearDown(
      () => installAppPlatformCapabilities(AppPlatformCapabilities.windows),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveNavigationShell(
          capabilities: AppPlatformCapabilities.android.copyWith(
            television: true,
          ),
          selectedIndex: 0,
          destinations: appNavigationDestinations,
          onDestinationSelected: (_) {},
          content: Center(
            child: SizedBox(
              width: 520,
              child: DirectoryAddressDropdown(
                currentPath: r'D:\TV',
                enabled: true,
                loadChildren: (_) async => const <DirectoryNavigationItem>[],
                onChildSelected: (_) {},
                onSubmitted: (_) async => null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final addressField = find.byKey(
      const ValueKey<String>('directory-address'),
    );
    await tester.tap(addressField);
    await tester.pump();
    final editable = tester.widget<EditableText>(
      find.descendant(of: addressField, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    final navigationGroup =
        find.byKey(const ValueKey<String>('tv-navigation-focus-group'));
    expect(
      find.descendant(
        of: navigationGroup,
        matching: find.byKey(const ValueKey<String>('tv-focused-surface')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Android TV 本地媒体卡按左键后焦点进入侧栏', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tvCapabilities =
        AppPlatformCapabilities.android.copyWith(television: true);
    installAppPlatformCapabilities(tvCapabilities);
    addTearDown(
      () => installAppPlatformCapabilities(AppPlatformCapabilities.windows),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveNavigationShell(
          capabilities: tvCapabilities,
          selectedIndex: 0,
          destinations: appNavigationDestinations,
          onDestinationSelected: (_) {},
          content: LibraryMediaGrid(
            capabilities: tvCapabilities,
            data: LibraryMediaGridViewData(
              items: const <LibraryMediaItemViewData>[
                LibraryMediaItemViewData(
                  id: 'show-1',
                  title: '测试影片',
                  subtitle: '第 1 季',
                  infoText: 'MKV  1.0 GB',
                  modifiedText: '2026-08-07',
                  hasMultipleEpisodes: true,
                  hasSubtitle: true,
                  scrapeLabel: '已刮削',
                ),
              ],
            ),
            onPlay: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final contentGroup =
        find.byKey(const ValueKey<String>('tv-content-focus-group'));
    final unfocusedCard = find.descendant(
      of: contentGroup,
      matching: find.byKey(const ValueKey<String>('tv-unfocused-surface')),
    );
    expect(unfocusedCard, findsOneWidget);
    final cardFocus = Focus.of(tester.element(unfocusedCard));
    cardFocus.requestFocus();
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: contentGroup,
        matching: find.byKey(const ValueKey<String>('tv-focused-surface')),
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    final navigationGroup =
        find.byKey(const ValueKey<String>('tv-navigation-focus-group'));
    expect(
      find.descendant(
        of: navigationGroup,
        matching: find.byKey(const ValueKey<String>('tv-focused-surface')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Android TV 页面内层焦点范围按左键后焦点进入侧栏', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tvCapabilities =
        AppPlatformCapabilities.android.copyWith(television: true);
    installAppPlatformCapabilities(tvCapabilities);
    addTearDown(
      () => installAppPlatformCapabilities(AppPlatformCapabilities.windows),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveNavigationShell(
          capabilities: tvCapabilities,
          selectedIndex: 0,
          destinations: appNavigationDestinations,
          onDestinationSelected: (_) {},
          content: FocusScope(
            child: FocusTraversalGroup(
              child: TvFocusSurface(
                autofocus: true,
                onPressed: () {},
                child: const SizedBox(width: 320, height: 180),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('tv-content-focus-group')),
        matching: find.byKey(const ValueKey<String>('tv-focused-surface')),
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('tv-navigation-focus-group')),
        matching: find.byKey(const ValueKey<String>('tv-focused-surface')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Android TV 子页面闭环焦点在最左侧仍能进入侧栏', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tvCapabilities =
        AppPlatformCapabilities.android.copyWith(television: true);
    installAppPlatformCapabilities(tvCapabilities);
    addTearDown(
      () => installAppPlatformCapabilities(AppPlatformCapabilities.windows),
    );
    final loopScope = FocusScopeNode(
      directionalTraversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    );
    addTearDown(loopScope.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveNavigationShell(
          capabilities: tvCapabilities,
          selectedIndex: 0,
          destinations: appNavigationDestinations,
          onDestinationSelected: (_) {},
          content: FocusScope.withExternalFocusNode(
            focusScopeNode: loopScope,
            child: Row(
              children: [
                TvFocusSurface(
                  autofocus: true,
                  onPressed: () {},
                  child: const SizedBox(width: 180, height: 120),
                ),
                TvFocusSurface(
                  onPressed: () {},
                  child: const SizedBox(width: 180, height: 120),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('tv-navigation-focus-group')),
        matching: find.byKey(const ValueKey<String>('tv-focused-surface')),
      ),
      findsOneWidget,
    );
  });
}
