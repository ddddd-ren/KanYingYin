import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/player_orientation_policy.dart';

void main() {
  test('Android TV 退出播放器后保持横屏', () {
    expect(
      PlayerOrientationPolicy.afterPlayback(
        isAndroidTv: true,
        isTablet: false,
      ),
      PlayerExitOrientation.landscape,
    );
  });

  test('Android 平板退出播放器后保持横屏', () {
    expect(
      PlayerOrientationPolicy.afterPlayback(
        isAndroidTv: false,
        isTablet: true,
      ),
      PlayerExitOrientation.landscape,
    );
  });

  test('手机退出播放器后恢复竖屏', () {
    expect(
      PlayerOrientationPolicy.afterPlayback(
        isAndroidTv: false,
        isTablet: false,
      ),
      PlayerExitOrientation.portrait,
    );
  });
}
