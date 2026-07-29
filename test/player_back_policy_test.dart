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
}
