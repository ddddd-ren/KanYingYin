import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/player_back_policy.dart';

void main() {
  test('返回键按浮层、全屏、播放器顺序消费', () {
    expect(
      PlayerBackPolicy.decide(overlayVisible: true, fullscreen: true),
      PlayerBackAction.closeOverlay,
    );
    expect(
      PlayerBackPolicy.decide(overlayVisible: false, fullscreen: true),
      PlayerBackAction.exitFullscreen,
    );
    expect(
      PlayerBackPolicy.decide(overlayVisible: false, fullscreen: false),
      PlayerBackAction.leavePlayer,
    );
  });

  test('Android 全屏播放按一次返回键直接离开播放器', () {
    final source = File('lib/pages/video/video_page.dart').readAsStringSync();

    expect(
      source,
      contains(
        'fullscreen: localVideoController.isFullscreen && Utils.isDesktop()',
      ),
    );
    expect(
      source,
      contains(
        'if (!Utils.isDesktop() && localVideoController.isFullscreen)',
      ),
    );
    expect(source, contains('if (!context.mounted) return;'));
  });
}
