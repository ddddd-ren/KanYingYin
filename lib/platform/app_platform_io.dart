import 'dart:io';

import 'package:kanyingyin/platform/android/android_device_capabilities.dart';
import 'package:kanyingyin/platform/app_platform.dart';

AppPlatformCapabilities? _installedCapabilities;

AppPlatformCapabilities detectAppPlatform() {
  final installed = _installedCapabilities;
  if (installed != null) return installed;
  return _detectBasePlatform();
}

Future<AppPlatformCapabilities> loadAppPlatformCapabilities() async {
  final base = _detectBasePlatform();
  if (!base.isAndroid) {
    _installedCapabilities = base;
    return base;
  }
  final device = await AndroidDeviceCapabilities.load();
  final enriched = base.copyWith(
    television: device.isAndroidTv,
    touchscreen: device.touchscreen,
    androidSdkInt: device.sdkInt,
    webViewAvailable: device.webView,
  );
  _installedCapabilities = enriched;
  return enriched;
}

void installAppPlatformCapabilities(AppPlatformCapabilities capabilities) {
  _installedCapabilities = capabilities;
}

AppPlatformCapabilities _detectBasePlatform() {
  if (Platform.isWindows) return AppPlatformCapabilities.windows;
  if (Platform.isAndroid) return AppPlatformCapabilities.android;
  throw UnsupportedError('看影音当前只支持 Windows 和 Android');
}
