import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/bean/widget/glass_surface.dart';
import 'package:kanyingyin/pages/menu/adaptive_navigation_shell.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';
import 'package:kanyingyin/theme/app_theme.dart';

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    required double width,
    int selectedIndex = 0,
    ValueChanged<int>? onSelected,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(fontFamily: 'MiSans'),
        home: AdaptiveNavigationShell(
          selectedIndex: selectedIndex,
          destinations: appNavigationDestinations,
          onDestinationSelected: onSelected ?? (_) {},
          content: const ColoredBox(
            key: ValueKey<String>('route-content'),
            color: Colors.transparent,
          ),
        ),
      ),
    );
  }

  testWidgets('宽窗口显示带品牌名称和文字标签的桌面侧栏', (tester) async {
    await pumpShell(tester, width: 1280);

    expect(
      find.byKey(const ValueKey<String>('desktop-sidebar-expanded')),
      findsOneWidget,
    );
    expect(find.text('看影音'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('动漫'), findsOneWidget);
    expect(find.text('电视剧'), findsOneWidget);
    expect(find.text('媒体库'), findsOneWidget);
    expect(find.text('网盘媒体库'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.byTooltip('切换浅色模式'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('route-content')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('中等宽度显示紧凑桌面导航', (tester) async {
    await pumpShell(tester, width: 760);

    expect(
      find.byKey(const ValueKey<String>('desktop-sidebar-compact')),
      findsOneWidget,
    );
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.destinations, hasLength(appNavigationDestinations.length - 1));
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.byTooltip('切换浅色模式'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('desktop-sidebar-compact-tools')),
      findsOneWidget,
    );
    expect(
      tester
          .getBottomRight(
            find.byKey(
              const ValueKey<String>('desktop-sidebar-compact-tools'),
            ),
          )
          .dy,
      greaterThan(680),
    );
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('紧凑侧边栏在设置页不选中主导航并转发设置入口', (tester) async {
    var selected = -1;
    await pumpShell(
      tester,
      width: 760,
      selectedIndex: appNavigationDestinations.length - 1,
      onSelected: (index) => selected = index,
    );

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.selectedIndex, isNull);
    await tester.tap(find.byTooltip('设置'));
    await tester.pump();
    expect(selected, appNavigationDestinations.length - 1);
  });

  testWidgets('窄窗口切换为底部导航并转发选择', (tester) async {
    var selected = -1;
    await pumpShell(
      tester,
      width: 520,
      selectedIndex: 3,
      onSelected: (index) => selected = index,
    );

    expect(
      find.byKey(const ValueKey<String>('compact-bottom-navigation')),
      findsOneWidget,
    );
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('电影'), findsNothing);
    expect(find.text('动漫'), findsNothing);
    expect(find.text('电视剧'), findsNothing);
    await tester.tap(find.text('网盘媒体库'));
    await tester.pump();
    expect(selected, 4);
  });

  testWidgets('桌面内容区使用中性表面而不是主色容器', (tester) async {
    await pumpShell(tester, width: 1280);

    final surface = tester.widget<GlassSurface>(
      find.byKey(const ValueKey<String>('navigation-content-surface')),
    );
    final colors = AppTheme.dark(fontFamily: 'MiSans').colorScheme;
    expect(surface.color, colors.surface.withValues(alpha: 0.66));
    expect(surface.color, isNot(colors.primaryContainer));
    expect(surface.borderRadius, BorderRadius.circular(12));
    expect(surface.blurSigma, 14);
  });
}
