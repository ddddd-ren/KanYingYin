import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/pages/settings/player_settings.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  late Directory root;
  late Box<Object?> box;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('kanyingyin-track-settings-');
    Hive.init(root.path);
    box = await Hive.openBox<Object?>('settings');
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });
  testWidgets('全局语言偏好经设置入口持久保存', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: PlayerSettingsPage(
            settings: TypedSettings(box),
            capabilities: AppPlatformCapabilities.windows)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首选音轨语言'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('日语'));
      await box.flush();
    });
    await tester.pumpAndSettle();
    expect(box.get(SettingBoxKey.preferredAudioLanguage), 'ja');
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
