import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/pages/settings/tmdb_settings.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:kanyingyin/services/tmdb/tmdb_vision_model_credentials.dart';
import 'package:kanyingyin/utils/storage.dart';

void main() {
  test('TMDB 关键操作使用统一设置项焦点表面', () {
    final source =
        File('lib/pages/settings/tmdb_settings.dart').readAsStringSync();
    expect(source,
        contains("key: const ValueKey<String>('tmdb-test-connection')"));
    expect(source, contains("key: const ValueKey<String>('tmdb-clear-cache')"));

    expect(source, contains('TvSettingsFocusSurface('));
  });

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
    final manager = await _memoryManager();
    await tester.pumpWidget(
      MaterialApp(
        home: TmdbSettingsPage(
          credentialManager: manager,
          settings: TypedSettings(GStorage.setting),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();

    expect(find.text('简体中文'), findsWidgets);
    expect(find.text('繁体中文'), findsOneWidget);
    expect(find.text('英语'), findsOneWidget);
    expect(find.text('日语'), findsOneWidget);
  });

  testWidgets('迁移入口集中到备份与迁移页', (tester) async {
    final manager = await _memoryManager();
    await tester.pumpWidget(
      MaterialApp(
        home: TmdbSettingsPage(
          credentialManager: manager,
          settings: TypedSettings(GStorage.setting),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(ListView),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();

    expect(find.text('迁移刮削资料'), findsNothing);
    expect(find.text('配置迁移'), findsNothing);
  });

  testWidgets('AI 配置直达页显示模型设置且不显示 TMDB 密钥区', (tester) async {
    final manager = await _memoryManager();
    await tester.pumpWidget(
      MaterialApp(
        home: TmdbSettingsPage(
          credentialManager: manager,
          settings: TypedSettings(GStorage.setting),
          visionCredentials: MemoryTmdbVisionModelCredentials(),
          visionOnly: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 识别与分类'), findsNWidgets(2));
    expect(find.text('兼容接口地址'), findsOneWidget);
    expect(find.text('多模态模型名称'), findsOneWidget);
    expect(find.text('TMDB API Key'), findsNothing);
    expect(find.byKey(const ValueKey<String>('tmdb-vision-test-connection')),
        findsOneWidget);
  });

  testWidgets('AI 配置页保存不会改动 TMDB Key 和刮削设置', (tester) async {
    var saved = false;
    final manager = await _memoryManager();
    final settings = _MemorySettings();
    await manager.save('existing-tmdb-key');
    await settings.put('tmdbAutoScrape', false);
    await settings.put('tmdbScrapeOptions', <String, Object?>{
      'language': 'ja-JP',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TmdbSettingsPage(
          credentialManager: manager,
          settings: settings,
          visionCredentials: MemoryTmdbVisionModelCredentials(),
          visionOnly: true,
          onVisionSettingsSaved: () async => saved = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final saveButton = find.text('保存');
    await tester.scrollUntilVisible(saveButton, 300,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(saved, isTrue);
    expect(find.text('AI 设置已保存'), findsOneWidget);
    expect(manager.read(), 'existing-tmdb-key');
    expect(
      settings.getTyped<bool>('tmdbAutoScrape', defaultValue: true),
      isFalse,
    );
    expect(settings.get('tmdbScrapeOptions'), <String, Object?>{
      'language': 'ja-JP',
    });
  });

  testWidgets('空用户 Key 显示内置来源且用户 Key 可用后切换来源', (tester) async {
    await tester.runAsync(() => GStorage.setting.delete('tmdbApiKey'));
    var userKey = '';
    final provider = TmdbApiKeyProvider(
      userKeyReader: () => userKey,
      builtinKey: 'builtin-fixture',
    );
    final manager = await _memoryManager();

    await tester.pumpWidget(
      MaterialApp(
        home: TmdbSettingsPage(
          credentialManager: manager,
          settings: TypedSettings(GStorage.setting),
          apiKeyProvider: provider,
        ),
      ),
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
          credentialManager: manager,
          settings: TypedSettings(GStorage.setting),
          apiKeyProvider: provider,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(provider.source, TmdbApiKeySource.user);

    expect(sourceLabel().data, '当前使用用户 Key');
    expect(sourceLabel().data, isNot(contains('user-fixture')));
  });

  test('设置页使用安全凭据管理器', () async {
    await GStorage.setting.put('tmdbApiKey', 'legacy-key');
    final store = MemoryTmdbCredentialStore();
    final manager = TmdbCredentialManager(
      store: store,
      legacyReader: () =>
          GStorage.setting.get('tmdbApiKey', defaultValue: '').toString(),
      legacyDelete: () => GStorage.setting.delete('tmdbApiKey'),
      warningLogger: (_) {},
    );
    await manager.initialize();
    final provider = TmdbApiKeyProvider(userKeyReader: manager.read);

    final page = TmdbSettingsPage(
      credentialManager: manager,
      settings: TypedSettings(GStorage.setting),
      apiKeyProvider: provider,
    );

    expect(page.credentialManager, same(manager));
    expect(page.apiKeyProvider, same(provider));
    expect(await store.read(), 'legacy-key');
    expect(manager.read(), 'legacy-key');
    expect(GStorage.setting.get('tmdbApiKey'), isNull);
  });
}

Future<TmdbCredentialManager> _memoryManager() async {
  final manager = TmdbCredentialManager(
    store: MemoryTmdbCredentialStore(),
    legacyReader: () => '',
    legacyDelete: () async {},
    warningLogger: (_) {},
  );
  await manager.initialize();
  return manager;
}

class _MemorySettings extends Fake implements TypedSettings {
  final values = <String, Object?>{};
  @override
  Object? get(String key, {Object? defaultValue}) =>
      values[key] ?? defaultValue;
  @override
  T getTyped<T>(String key, {required T defaultValue}) =>
      values[key] is T ? values[key] as T : defaultValue;
  @override
  Future<void> put<T>(String key, T value) async => values[key] = value;
}
