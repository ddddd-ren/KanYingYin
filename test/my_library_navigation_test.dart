import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/menu/adaptive_navigation_shell.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';
import 'package:kanyingyin/features/library/presentation/library_path_bar.dart';
import 'package:kanyingyin/features/library/presentation/library_source_menu.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  for (final (width, hidden, sidebar) in [
    (639.0, false, false),
    (640.0, false, true),
    (959.0, false, true),
    (960.0, false, true),
    (520.0, false, false),
    (1280.0, true, false),
  ]) {
    testWidgets('真实容器宽度 $width、隐藏导航 $hidden 时只保留一个片库入口', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final search = TextEditingController();
      addTearDown(search.dispose);
      var selected = 3;
      await tester.pumpWidget(MaterialApp(
          home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                  width: width,
                  child: StatefulBuilder(
                      builder: (context, setState) => AdaptiveNavigationShell(
                            selectedIndex: selected,
                            destinations: appNavigationDestinations,
                            navigationHidden: hidden,
                            capabilities: AppPlatformCapabilities.windows,
                            onDestinationSelected: (value) =>
                                setState(() => selected = value),
                            content: Builder(builder: (context) {
                              final scope =
                                  LibraryNavigationScope.maybeOf(context)!;
                              expect(scope.sidebarVisible, sidebar);
                              return toolbar(
                                  search,
                                  scope.sidebarVisible
                                      ? null
                                      : scope.openMyLibrary);
                            }),
                          ))))));
      await tester.pumpAndSettle();
      final buttons = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '我的片库');
      expect(buttons, sidebar ? findsNothing : findsOneWidget);
      if (!sidebar) {
        await tester.tap(buttons);
        await tester.pumpAndSettle();
        expect(appNavigationDestinations[selected].path, '/my-library');
      }
      if (!sidebar && !hidden) {
        await tester.tap(find.text('分类'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(ListTile, '我的片库'), findsNothing);
        expect(find.widgetWithText(ListTile, '电影'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('窄窗入口选中我的片库后拉宽，侧栏保留相同选择', (tester) async {
    tester.view.physicalSize = const Size(639, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = 3;
    await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
            builder: (context, setState) => AdaptiveNavigationShell(
                  selectedIndex: selected,
                  destinations: appNavigationDestinations,
                  onDestinationSelected: (value) =>
                      setState(() => selected = value),
                  capabilities: AppPlatformCapabilities.windows,
                  content: Builder(
                      builder: (context) => TextButton(
                          onPressed: LibraryNavigationScope.maybeOf(context)!
                              .openMyLibrary,
                          child: const Text('打开片库'))),
                ))));
    await tester.tap(find.text('打开片库'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(640, 900);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        selected);
    expect(appNavigationDestinations[selected].path, '/my-library');
    expect(tester.takeException(), isNull);
  });
}

Widget toolbar(TextEditingController search, VoidCallback? open) =>
    LibraryPathBar(
      data: LibraryPathBarViewData(
          breadcrumbs: const [],
          recentPaths: const [],
          sortBy: 'name',
          sortAscending: true,
          status: const LibraryDirectoryStatusViewData(
              kind: LibraryDirectoryStatusKind.idle, label: '')),
      sourceMenu: LibrarySourceMenu(
          data: LibrarySourceMenuViewData(sources: const []),
          onOpen: (_) {},
          onRemove: (_) {},
          onRemoveUnavailable: () {}),
      searchController: search,
      onPickDirectory: () {},
      onRefresh: () {},
      onSort: (_) {},
      onSearchChanged: (_) {},
      onClearSearch: () {},
      onBreadcrumbSelected: (_) {},
      onPathSubmitted: (_) async => null,
      onOpenMyLibrary: open,
    );
