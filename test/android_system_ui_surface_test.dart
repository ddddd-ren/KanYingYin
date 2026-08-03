import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/android/android_system_ui_surface.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  testWidgets('Android 普通页面系统栏透明且图标跟随主题', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          themeAnimationDuration: Duration.zero,
          home: AndroidSystemUiSurface(
            capabilities: AppPlatformCapabilities.android,
            child: const SizedBox.expand(),
          ),
        ),
      );

      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byKey(const ValueKey('android-app-system-ui')),
      );
      final expectedIcons =
          brightness == Brightness.light ? Brightness.dark : Brightness.light;
      expect(region.value.statusBarColor, Colors.transparent);
      expect(region.value.systemNavigationBarColor, Colors.transparent);
      expect(region.value.statusBarIconBrightness, expectedIcons);
      expect(region.value.systemNavigationBarIconBrightness, expectedIcons);
      expect(region.value.systemStatusBarContrastEnforced, isFalse);
      expect(region.value.systemNavigationBarContrastEnforced, isFalse);
    }
  });

  testWidgets('Android OLED 页面保持纯黑系统栏底层', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
        home: const AndroidSystemUiSurface(
          capabilities: AppPlatformCapabilities.android,
          child: SizedBox.expand(),
        ),
      ),
    );

    final surface = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('android-app-system-ui-background')),
    );
    expect(surface.color, Colors.black);
  });

  testWidgets('Android 播放页面使用黑色底层和白色系统图标', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AndroidPlaybackSystemUiSurface(
          capabilities: AppPlatformCapabilities.android,
          child: SizedBox.expand(),
        ),
      ),
    );

    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byKey(const ValueKey('android-player-system-ui')),
    );
    final surface = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('android-player-system-ui-background')),
    );
    expect(surface.color, Colors.black);
    expect(region.value.statusBarIconBrightness, Brightness.light);
    expect(region.value.systemNavigationBarIconBrightness, Brightness.light);
  });

  testWidgets('Windows 不增加 Android 系统栏包装', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AndroidSystemUiSurface(
          capabilities: AppPlatformCapabilities.windows,
          child: Text('Windows'),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('android-app-system-ui')), findsNothing);
    expect(find.text('Windows'), findsOneWidget);
  });
}
