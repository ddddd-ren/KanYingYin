import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
      'lib/pages/settings/renderer_settings.dart',
      'lib/pages/settings/super_resolution_settings.dart',
      'lib/pages/settings/displaymode_settings.dart',
      'lib/pages/settings/decoder_settings.dart',
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
}
