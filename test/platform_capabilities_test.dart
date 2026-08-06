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

  test('Android TV 能力副本保留基础平台边界', () {
    final capabilities = AppPlatformCapabilities.android.copyWith(
      television: true,
      touchscreen: false,
      androidSdkInt: 24,
      webViewAvailable: false,
    );

    expect(capabilities.isAndroidTv, isTrue);
    expect(capabilities.isAndroid, isTrue);
    expect(capabilities.desktopShell, isFalse);
    expect(capabilities.touchscreen, isFalse);
    expect(capabilities.androidSdkInt, 24);
    expect(capabilities.webViewAvailable, isFalse);
  });
}
