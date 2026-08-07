import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 播放设置提供独立色彩方案入口', () {
    final player =
        File('lib/pages/settings/player_settings.dart').readAsStringSync();
    final module =
        File('lib/pages/settings/settings_module.dart').readAsStringSync();
    final color = File(
      'lib/pages/settings/player_color_settings.dart',
    ).readAsStringSync();

    expect(player, contains('if (platform.isWindows)'));
    expect(player, contains("'/settings/player/color'"));
    expect(module, contains('"/player/color"'));
    expect(color, contains('PlayerColorProfile.values'));
    expect(color, contains('HDR 直通需要 Windows 已开启 HDR'));
  });

  test('TV 不应用 Windows 色彩方案', () {
    final controller =
        File('lib/pages/player/player_controller.dart').readAsStringSync();

    expect(controller, contains('_capabilities.isWindows'));
    expect(
      controller,
      contains(': PlayerColorProfile.automatic'),
    );
  });
}
