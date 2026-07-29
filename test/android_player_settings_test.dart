import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 渲染器设置拥有独立页面和路由', () {
    final renderer =
        File('lib/pages/settings/renderer_settings.dart').readAsStringSync();
    final module =
        File('lib/pages/settings/settings_module.dart').readAsStringSync();
    final player =
        File('lib/pages/settings/player_settings.dart').readAsStringSync();

    expect(renderer, contains('androidVideoRenderersList'));
    expect(renderer, contains('SettingBoxKey.androidVideoRenderer'));
    expect(module, contains('/player/renderer'));
    expect(player, contains("'/settings/player/renderer'"));
    expect(player, contains('widget.capabilities ?? detectAppPlatform()'));
    expect(player, contains('if (platform.isAndroid)'));
    expect(player, contains('SettingBoxKey.androidAutoEnterPip'));
  });
}
