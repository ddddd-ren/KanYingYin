import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('桌面与小窗口控制栏均提供共享字幕和语言菜单', () {
    for (final path in [
      'lib/pages/player/player_item_panel.dart',
      'lib/pages/player/smallest_player_item_panel.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('EmbeddedTrackMenus'), reason: path);
    }
    final menu = File('lib/pages/player/widgets/embedded_track_menus.dart')
        .readAsStringSync();
    expect(menu, contains("'字幕'"));
    expect(menu, contains("'语言'"));
    expect(menu, contains('showSubtitleSettings'));
  });
}
