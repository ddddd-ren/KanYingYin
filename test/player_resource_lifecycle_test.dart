import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('播放器面板和页面释放其持有的 Flutter 控制器', () {
    final panel =
        File('lib/pages/player/player_item_panel.dart').readAsStringSync();
    final smallestPanel =
        File('lib/pages/player/smallest_player_item_panel.dart')
            .readAsStringSync();
    final videoPage =
        File('lib/pages/video/video_page.dart').readAsStringSync();
    final decoder =
        File('lib/pages/settings/decoder_settings.dart').readAsStringSync();

    expect(panel, contains('textController.dispose()'));
    expect(panel, contains('textFieldFocus.dispose()'));
    expect(smallestPanel, contains('textController.dispose()'));
    expect(videoPage, contains('keyboardFocus.dispose()'));
    expect(videoPage, contains('scrollController.dispose()'));
    expect(decoder, contains('decoder.dispose()'));
  });

  test('快捷键页面不在 build 中创建临时 FocusNode', () {
    final source =
        File('lib/pages/settings/keyboard_settings.dart').readAsStringSync();

    expect(source, isNot(contains('focusNode: FocusNode(')));
    expect(source, contains('canRequestFocus: false'));
  });
}
