import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/menu/adaptive_navigation_shell.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';

void main() {
  testWidgets('Android 窄屏使用安全区和底部导航', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveNavigationShell(
          selectedIndex: 0,
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
    expect(
      find.byKey(const ValueKey<String>('mobile-safe-content')),
      findsOneWidget,
    );
  });
}
