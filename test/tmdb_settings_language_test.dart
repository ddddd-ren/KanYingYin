import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/pages/settings/tmdb_settings.dart';
import 'package:kanyingyin/utils/storage.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('tmdb-settings');
    Hive.init(hiveDirectory.path);
    GStorage.setting = await Hive.openBox<dynamic>('tmdb-settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('识别语言提供简体中文繁体中文英语和日语', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TmdbSettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();

    expect(find.text('简体中文'), findsWidgets);
    expect(find.text('繁体中文'), findsOneWidget);
    expect(find.text('英语'), findsOneWidget);
    expect(find.text('日语'), findsOneWidget);
  });
}
