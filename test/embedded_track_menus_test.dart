import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('未解析轨道从字幕和音轨菜单提供确认入口', () {
    final source = File('lib/pages/player/widgets/embedded_track_menus.dart')
        .readAsStringSync();

    expect(source, contains('onConfirmTrackLanguage'));
    expect(source, contains('!track.isLanguageResolved'));
    expect(source, contains("title: '确认语言'"));
  });
}
