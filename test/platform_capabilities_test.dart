import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  test('Windows 和 Android 能力边界互不混淆', () {
    expect(AppPlatformCapabilities.windows.desktopShell, isTrue);
    expect(AppPlatformCapabilities.windows.systemPictureInPicture, isFalse);
    expect(AppPlatformCapabilities.android.desktopShell, isFalse);
    expect(AppPlatformCapabilities.android.systemPictureInPicture, isTrue);
    expect(AppPlatformCapabilities.android.storageAccessFramework, isTrue);
  });

  test('Android 不暴露 Windows 解码器', () {
    expect(AppPlatformCapabilities.android.hardwareDecoders, ['auto', 'no']);
    expect(
      AppPlatformCapabilities.windows.hardwareDecoders,
      contains('d3d11va-copy'),
    );
  });
}
