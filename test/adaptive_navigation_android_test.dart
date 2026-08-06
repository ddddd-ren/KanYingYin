import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/bean/widget/glass_surface.dart';
import 'package:kanyingyin/pages/menu/adaptive_navigation_shell.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';
import 'package:kanyingyin/platform/app_platform.dart';

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
}
