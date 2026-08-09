import 'dart:io';

import 'package:kanyingyin/platform/android/android_device_capabilities.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/utils/logger.dart';

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
    androidPerformanceProfile: device.performanceProfile,
    androidManufacturer: device.manufacturer,
    androidModel: device.model,
    androidHardware: device.hardware,
    androidSocModel: device.socModel,
    androidCurrentRefreshRate: device.currentRefreshRate,
    androidSupportedRefreshRates: device.supportedRefreshRates,
    androidPreferredDisplayModeId: device.preferredDisplayModeId,
  );
  _installedCapabilities = enriched;
  AppLogger().i(
    'AndroidPerformance: manufacturer=${device.manufacturer} '
    'model=${device.model} hardware=${device.hardware} '
    'soc=${device.socModel} refresh=${device.currentRefreshRate} '
    'supported=${device.supportedRefreshRates.join(',')} '
    'preferredMode=${device.preferredDisplayModeId} '
    'profile=${device.performanceProfile.name}',
    forceLog: true,
  );
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
