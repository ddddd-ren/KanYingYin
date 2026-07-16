import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('运行时代码统一使用看影音平台身份', () {
    final sources = <String>[
      'windows/CMakeLists.txt',
      'windows/runner/platform_channels.cpp',
      'windows/runner/shortcut_utils.cpp',
      'windows/runner/external_player_utils.cpp',
      'lib/utils/windows_shortcut.dart',
      'lib/utils/window_utils.dart',
      'lib/utils/display_utils.dart',
      'lib/utils/external_player.dart',
      'lib/utils/pip_utils.dart',
      'lib/app_widget.dart',
      'lib/services/audio_controller.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(sources, contains('com.kanyingyin.player/intent'));
    expect(sources, contains('com.kanyingyin.player/shortcut'));
    expect(sources, contains('!kanyingyin'));
    expect(sources, isNot(contains(r'\x5C31\x770B')));
    expect(sources, isNot(contains(r'\x5728\x7EBF')));
  });

  test('签名配置不再保存明文密码', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('certificate_' 'password:')));
    expect(pubspec, contains('publisher: CN=' 'KanYingYin'));
  });
}
