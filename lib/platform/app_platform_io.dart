import 'dart:io';

import 'package:kanyingyin/platform/app_platform.dart';

AppPlatformCapabilities detectAppPlatform() {
  if (Platform.isWindows) return AppPlatformCapabilities.windows;
  if (Platform.isAndroid) return AppPlatformCapabilities.android;
  throw UnsupportedError('看影音当前只支持 Windows 和 Android');
}
