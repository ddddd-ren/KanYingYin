import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/pages/my/my_page.dart';

void main() {
  Future<void> pumpHub(
    WidgetTester tester, {
    required double width,
    ValueChanged<String>? onOpenPath,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsHubContent(
            onOpenPath: onOpenPath ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('设置分组列表在三种宽度下完整构建且无溢出', (tester) async {
    for (final width in <double>[1280, 900, 640]) {
      await pumpHub(tester, width: width);
      expect(find.byType(KSettingsSection), findsNWidgets(4));
      expect(find.byType(KSettingsNavigationTile), findsNWidgets(8));
      for (final section in <String>[
        '本地媒体库',
        '播放器设置',
        '应用与外观',
        '其他',
      ]) {
        expect(find.text(section), findsOneWidget);
      }
      expect(tester.takeException(), isNull, reason: '窗口宽度 $width');
    }
  });

  testWidgets('设置分组列表将入口路径原样转发', (tester) async {
    String? openedPath;
    await pumpHub(
      tester,
      width: 1280,
      onOpenPath: (path) => openedPath = path,
    );

    await tester.tap(find.text('播放设置'));
    await tester.pumpAndSettle();

    expect(openedPath, '/settings/player');
  });
}
