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

  test('Android TV 控制层显示时系统返回键先关闭控制层', () {
    final action = Function.apply(
      PlayerBackPolicy.decide,
      const <Object?>[],
      <Symbol, Object?>{
        #overlayVisible: false,
        #fullscreen: true,
        #controlsVisible: true,
        #isAndroidTv: true,
      },
    );

    expect(action, PlayerBackAction.closeOverlay);
  });

  test('Android TV 选集列表显示时返回键先关闭列表', () {
    final action = Function.apply(
      PlayerBackPolicy.decide,
      const <Object?>[],
      <Symbol, Object?>{
        #overlayVisible: false,
        #episodePanelVisible: true,
        #fullscreen: false,
        #controlsVisible: false,
        #isAndroidTv: true,
      },
    );

    expect(action, PlayerBackAction.closeEpisodePanel);
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
      contains('controlsVisible: playerController.showVideoController'),
    );
    expect(source, contains('isAndroidTv: capabilities.isAndroidTv'));
    expect(
      source,
      contains('_playerItemKey.currentState?.hideVideoController()'),
    );
    expect(source, contains('!capabilities.isAndroidTv'));
    expect(source, contains('localVideoController.isFullscreen'));
    expect(source, contains('if (!context.mounted) return;'));
  });
}
