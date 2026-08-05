import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/pages/settings/tmdb_settings.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:kanyingyin/utils/storage.dart';

const _zeroConfigCopy =
    '公共安装包不内置 TMDB Key。没有 Key 或断网时，本地扫描和播放仍可用；不会修改或删除原始视频、字幕。';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('tmdb-zero-config');
    Hive.init(hiveDirectory.path);
    GStorage.setting = await Hive.openBox<Object?>('tmdb-zero-config');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('README 和设置页源文件包含零配置边界', () {
    final readme = File('README.md').readAsStringSync(encoding: utf8);
    final settings = File(
      'lib/pages/settings/tmdb_settings.dart',
    ).readAsStringSync(encoding: utf8);

    expect(readme, contains('公共安装包不内置 TMDB Key'));
    expect(readme, contains('没有 Key 或断网时，本地扫描和播放仍可用'));
    expect(readme, contains('不会修改或删除原始视频、字幕'));
    expect(settings, contains(_zeroConfigCopy));
  });

  testWidgets('设置页显示零配置说明', (tester) async {
    final manager = TmdbCredentialManager(
      store: MemoryTmdbCredentialStore(),
      legacyReader: () => '',
      legacyDelete: () async {},
      warningLogger: (_) {},
    );
    await manager.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: TmdbSettingsPage(
          credentialManager: manager,
          settings: TypedSettings(GStorage.setting),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('tmdb-zero-config-notice')),
      findsOneWidget,
    );
    expect(find.text(_zeroConfigCopy), findsOneWidget);
  });
}
