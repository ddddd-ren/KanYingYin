import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/pages/settings/player_settings.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  late Directory hiveDirectory;
  late Box<Object?> settingBox;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('player-settings');
    Hive.init(hiveDirectory.path);
    settingBox = await Hive.openBox<Object?>('player-settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('设置区域不再依赖 card_settings_ui', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('card_settings_ui:')));

    final removedPackageImport = 'package:${'card_settings_ui'}/';
    for (final root in <String>['lib', 'test']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        expect(
          entity.readAsStringSync(),
          isNot(contains(removedPackageImport)),
          reason: entity.path,
        );
      }
    }
  });

  test('全部设置页使用看影音设置表现层', () {
    const pages = <String>[
      'lib/pages/settings/interface_settings.dart',
      'lib/pages/settings/super_resolution_settings.dart',
      'lib/pages/settings/decoder_settings.dart',
      'lib/pages/settings/renderer_settings.dart',
      'lib/pages/settings/keyboard_settings.dart',
      'lib/pages/settings/player_settings.dart',
      'lib/pages/settings/theme_settings_page.dart',
      'lib/pages/settings/media_recognition_settings.dart',
      'lib/pages/settings/tmdb_settings.dart',
      'lib/pages/settings/cloud_sources_settings.dart',
      'lib/pages/cloud/openlist_source_editor.dart',
      'lib/pages/cloud/quark/quark_source_editor.dart',
      'lib/pages/cloud/quark/quark_share_import_page.dart',
      'lib/pages/cloud/baidu/baidu_source_editor.dart',
      'lib/pages/about/about_page.dart',
    ];

    for (final path in pages) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('features/settings/presentation/settings_presentation.dart'),
        reason: path,
      );
      expect(
        source,
        contains('KSettingsScaffold('),
        reason: path,
      );
    }
  });

  test('Windows 与 Android 播放设置通过平台能力隔离', () {
    const paths = <String>[
      'lib/app_widget.dart',
      'lib/pages/init_page.dart',
      'lib/providers/theme_provider.dart',
      'lib/pages/settings/theme_settings_page.dart',
      'lib/pages/settings/player_settings.dart',
      'lib/pages/settings/settings_module.dart',
      'lib/utils/storage.dart',
    ];
    const forbidden = <String>[
      'DynamicColorBuilder',
      'useDynamicColor',
      'setDynamic(',
      '/theme/display',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      for (final token in forbidden) {
        expect(source, isNot(contains(token)), reason: '$path: $token');
      }
    }
    expect(
      File('lib/pages/settings/displaymode_settings.dart').existsSync(),
      isFalse,
    );
    final playerSettings =
        File('lib/pages/settings/player_settings.dart').readAsStringSync();
    expect(playerSettings, contains('widget.capabilities'));
    expect(playerSettings, contains("'/settings/player/renderer'"));
    expect(
      File('lib/pages/settings/renderer_settings.dart').existsSync(),
      isTrue,
    );
  });

  testWidgets('播放设置按注入能力显示 Windows 或 Android 选项', (tester) async {
    tester.view.physicalSize = const Size(1280, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget page(AppPlatformCapabilities capabilities) => PlayerSettingsPage(
          key: ValueKey<AppPlatformKind>(capabilities.kind),
          settings: TypedSettings(settingBox),
          capabilities: capabilities,
        );

    await tester.pumpWidget(
      MaterialApp(home: page(AppPlatformCapabilities.windows)),
    );
    await tester.pumpAndSettle();

    expect(find.text('视频渲染器'), findsNothing);
    expect(find.text('滑动手势'), findsNothing);
    expect(find.text('自动画中画'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: page(AppPlatformCapabilities.android),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('视频渲染器'), findsOneWidget);
    expect(find.text('滑动手势'), findsOneWidget);
    expect(find.text('自动画中画'), findsOneWidget);
  });
}
