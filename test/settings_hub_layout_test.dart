import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/pages/my/my_page.dart';

void main() {
  Future<void> pumpHub(
    WidgetTester tester, {
    required double width,
    double textScale = 1,
    ValueChanged<String>? onOpenPath,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: SettingsHubContent(onOpenPath: onOpenPath ?? (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('设置分组列表在三种宽度下完整构建且无溢出', (tester) async {
    for (final width in <double>[1280, 900, 640]) {
      await pumpHub(tester, width: width);
      await tester.scrollUntilVisible(find.text('媒体库'), -200);
      expect(find.byType(KSettingsSection), findsWidgets);
      expect(find.byType(KSettingsNavigationTile), findsWidgets);
      for (final section in <String>[
        '媒体库',
        '设置',
        '应用与外观',
        '其他',
      ]) {
        await tester.scrollUntilVisible(find.text(section), 200);
        expect(find.text(section), findsOneWidget);
      }
      expect(tester.takeException(), isNull, reason: '窗口宽度 $width');
    }
  });

  testWidgets('备份与迁移入口打开聚合页', (tester) async {
    String? openedPath;
    await pumpHub(tester,
        width: 640, textScale: 2, onOpenPath: (path) => openedPath = path);
    await tester.tap(find.text('备份与迁移'));
    expect(openedPath, '/settings/backup-migration');
    await tester.scrollUntilVisible(find.text('关于'), 250);
    await tester.tap(find.text('关于'));
    expect(openedPath, '/settings/about/');
    expect(tester.takeException(), isNull);
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

  testWidgets('存储入口打开存储设置页', (tester) async {
    String? openedPath;
    await pumpHub(
      tester,
      width: 1280,
      onOpenPath: (path) => openedPath = path,
    );

    await tester.tap(find.text('存储'));
    await tester.pumpAndSettle();

    expect(openedPath, '/settings/storage');
  });

  testWidgets('AI 识别与分类入口直达模型配置页', (tester) async {
    String? openedPath;
    await pumpHub(
      tester,
      width: 1280,
      onOpenPath: (path) => openedPath = path,
    );

    await tester.tap(find.text('AI 识别与分类'));
    await tester.pumpAndSettle();

    expect(openedPath, '/settings/tmdb/vision');
  });
}
