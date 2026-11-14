import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/settings/backup_migration_page.dart';

void main() {
  testWidgets('备份聚合页说明范围并复用两个旧路由', (tester) async {
    String? opened;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [390.0, 640.0, 900.0]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              textScaler: TextScaler.linear(width == 640 ? 2 : 1)),
          child: BackupMigrationPage(onOpenPath: (path) => opened = path),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('备份与迁移'), findsOneWidget);
      expect(find.textContaining('视频和字幕需要自行保留'), findsOneWidget);
      expect(find.textContaining('AI 接口密钥'), findsOneWidget);
      await tester.tap(find.text('配置与观看记录'));
      expect(opened, '/settings/cloud-sources/configuration-transfer');
      await tester.tap(find.text('刮削资料与封面'));
      expect(opened, '/settings/tmdb/transfer');
      expect(tester.takeException(), isNull);
    }
  });
}
