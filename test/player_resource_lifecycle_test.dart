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
    expect(
      'scrollController.dispose()'.allMatches(videoPage),
      hasLength(1),
    );
    expect(
      videoPage,
      isNot(contains('observerController.controller?.dispose()')),
    );
    expect(decoder, contains('decoder.dispose()'));
  });

  test('快捷键页面不在 build 中创建临时 FocusNode', () {
    final source =
        File('lib/pages/settings/keyboard_settings.dart').readAsStringSync();

    expect(source, isNot(contains('focusNode: FocusNode(')));
    expect(source, contains('canRequestFocus: false'));
  });

  test('播放器在首个异步释放前解除资源所有权且不复用旧实例', () {
    final source =
        File('lib/pages/player/player_controller.dart').readAsStringSync();
    final disposeStart = source.indexOf(
      'Future<void> _disposePlayerResources()',
    );
    final disposeEnd = source.indexOf(
      '\n  Future<void> stop()',
      disposeStart,
    );

    expect(disposeStart, isNonNegative);
    expect(disposeEnd, greaterThan(disposeStart));
    final disposeBody = source.substring(disposeStart, disposeEnd);
    final firstAwait = disposeBody.indexOf('await ');
    expect(firstAwait, isNonNegative);
    for (final ownershipRelease in <String>[
      'playerErrorSubscription = null;',
      'playerLogSubscription = null;',
      'playerAudioBitrateSubscription = null;',
      'mediaPlayer = null;',
      'videoController = null;',
    ]) {
      final releaseIndex = disposeBody.indexOf(ownershipRelease);
      expect(releaseIndex, isNonNegative, reason: ownershipRelease);
      expect(releaseIndex, lessThan(firstAwait), reason: ownershipRelease);
    }

    expect(source, isNot(contains('mediaPlayer ??=')));
    expect(source, contains('mediaPlayer = await createVideoController('));
  });
}
