import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/window_utils.dart';

void main() {
  test('退出播放器后 TV 和平板保持横屏，手机恢复竖屏', () {
    expect(
      WindowUtils.preferredOrientationsAfterPlayback(
        isAndroidTv: true,
        isTablet: false,
      ),
      const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    );
    expect(
      WindowUtils.preferredOrientationsAfterPlayback(
        isAndroidTv: false,
        isTablet: true,
      ),
      const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    );
    expect(
      WindowUtils.preferredOrientationsAfterPlayback(
        isAndroidTv: false,
        isTablet: false,
      ),
      const [DeviceOrientation.portraitUp],
    );
  });
}
