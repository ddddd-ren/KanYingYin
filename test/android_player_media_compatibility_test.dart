import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String controller;

  setUpAll(() {
    controller =
        File('lib/pages/player/player_controller.dart').readAsStringSync();
  });

  test('Android libass 使用应用内中文字体渲染字幕', () {
    expect(
      controller,
      contains("libassAndroidFont: 'assets/fonts/MiSans-Regular.ttf'"),
    );
    expect(controller, contains("libassAndroidFontName: 'MiSans'"));
  });

  test('没有外挂字幕时保留内嵌字幕自动选择', () {
    expect(
      controller,
      contains('if (subtitlePath != null && subtitlePath.isNotEmpty)'),
    );
    expect(
      controller,
      isNot(
        contains(
          'if (subtitlePath == null || subtitlePath.isEmpty) {\n'
          '      await _disableSubtitleTrack(clearCurrentPath: true);',
        ),
      ),
    );
  });

  test('字幕自动选择不被已完成的音轨自动选择阻断', () {
    expect(
      controller,
      isNot(
        contains(
          'if (!_embeddedTrackSelection.beginAutomaticSelection(\n'
          '      hasAudioTracks: availableAudioTracks.isNotEmpty,\n'
          '    )) {\n'
          '      return;\n'
          '    }',
        ),
      ),
    );
    expect(controller, contains('final shouldSelectAudio ='));
  });

  test('Android TrueHD 在选择音轨前启用立体声解码输出', () {
    expect(controller, contains('Future<void> _prepareAndroidAudioOutput('));
    expect(controller, contains("'audio-channels'"));
    expect(controller, contains("'stereo'"));
    expect(controller, contains("'ad-lavc-downmix'"));
    expect(controller, contains("'yes'"));
    expect(
      controller,
      contains(
        'await _prepareAudioTrackOutput(player, track);\n'
        '      await player.setAudioTrack(track);',
      ),
    );
  });
}
