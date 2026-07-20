import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/pages/settings/tmdb_settings.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';
import 'package:kanyingyin/utils/storage.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('tmdb-settings');
    Hive.init(hiveDirectory.path);
    GStorage.setting = await Hive.openBox<Object?>('tmdb-settings');
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

  testWidgets('空用户 Key 显示内置来源且用户 Key 可用后切换来源', (tester) async {
    await GStorage.setting.delete('tmdbApiKey');
    var userKey = '';
    final provider = TmdbApiKeyProvider(
      userKeyReader: () => userKey,
      builtinKey: 'builtin-fixture',
    );

    await tester.pumpWidget(
      MaterialApp(home: TmdbSettingsPage(apiKeyProvider: provider)),
    );
    await tester.pumpAndSettle();

    Text sourceLabel() => tester.widget<Text>(
          find.byKey(const ValueKey<String>('tmdb-key-source')),
        );

    expect(sourceLabel().data, '当前使用内置默认 Key');
    expect(sourceLabel().data, isNot(contains('builtin-fixture')));

    userKey = 'user-fixture';
    await tester.pumpWidget(
      MaterialApp(
        home: TmdbSettingsPage(
          key: const ValueKey<String>('user-key-page'),
          apiKeyProvider: provider,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(provider.source, TmdbApiKeySource.user);

    expect(sourceLabel().data, '当前使用用户 Key');
    expect(sourceLabel().data, isNot(contains('user-fixture')));
  });
}
