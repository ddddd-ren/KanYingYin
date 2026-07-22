import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/menu/adaptive_navigation_shell.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';
import 'package:kanyingyin/theme/app_theme.dart';

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    required double width,
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
          selectedIndex: 0,
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
    expect(find.text('本地媒体库'), findsOneWidget);
    expect(find.text('网盘媒体库'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('route-content')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('中等宽度显示紧凑桌面导航', (tester) async {
    await pumpShell(tester, width: 760);

    expect(
      find.byKey(const ValueKey<String>('desktop-sidebar-compact')),
      findsOneWidget,
    );
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('窄窗口切换为底部导航并转发选择', (tester) async {
    var selected = -1;
    await pumpShell(
      tester,
      width: 520,
      onSelected: (index) => selected = index,
    );

    expect(
      find.byKey(const ValueKey<String>('compact-bottom-navigation')),
      findsOneWidget,
    );
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.text('网盘媒体库'));
    await tester.pump();
    expect(selected, 1);
  });

  testWidgets('桌面内容区使用中性表面而不是主色容器', (tester) async {
    await pumpShell(tester, width: 1280);

    final surface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('navigation-content-surface')),
    );
    final decoration = surface.decoration as BoxDecoration;
    final colors = AppTheme.dark(fontFamily: 'MiSans').colorScheme;
    expect(decoration.color, colors.surface);
    expect(decoration.color, isNot(colors.primaryContainer));
    expect(decoration.borderRadius, BorderRadius.circular(12));
  });
}
