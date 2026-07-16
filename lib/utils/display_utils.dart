import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/utils/logger.dart';

class DisplayUtils {
  static Future<bool> isLowResolution() async {
    if (Platform.isMacOS) return false;
    Map<String, double> screenInfo = await getScreenInfo();
    if (screenInfo['height']! / screenInfo['ratio']! < 900) return true;
    return false;
  }

  static Future<Map<String, double>> getScreenInfo() async {
    final MediaQueryData mediaQuery = MediaQueryData.fromView(
        WidgetsBinding.instance.platformDispatcher.views.first);
    final Size screenSize =
        WidgetsBinding.instance.platformDispatcher.displays.first.size;
    final double screenRatio = mediaQuery.devicePixelRatio;
    Map<String, double>? screenInfo = {};
    screenInfo = {
      'width': screenSize.width,
      'height': screenSize.height,
      'ratio': screenRatio
    };
    return screenInfo;
  }

  static bool isDesktop() {
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  static bool isWideScreen() {
    final MediaQueryData mediaQuery = MediaQueryData.fromView(
        WidgetsBinding.instance.platformDispatcher.views.first);
    final bool isWideScreen = mediaQuery.size.shortestSide >= 600 &&
        mediaQuery.size.shortestSide / mediaQuery.size.longestSide >= 9 / 16;
    return isWideScreen;
  }

  static bool isTablet() {
    return isWideScreen() && !isDesktop();
  }

  static bool isCompact() {
    return !isDesktop() && !isWideScreen();
  }

  static Future<bool> isInMultiWindowMode() async {
    if (Platform.isAndroid) {
      const platform = MethodChannel('com.kanyingyin.player/intent');
      try {
        final bool result =
            await platform.invokeMethod('checkIfInMultiWindowMode');
        return result;
      } on PlatformException catch (e) {
        AppLogger().e("Failed to check multi window mode: '${e.message}'.");
        return false;
      }
    }
    return false;
  }

  static Future<bool> isRunningOnX11() async {
    if (Platform.isLinux) {
      const platform = MethodChannel('com.kanyingyin.player/intent');
      try {
        final bool result = await platform.invokeMethod('isRunningOnX11');
        return result;
      } on PlatformException catch (e) {
        AppLogger().e("Failed to check X11 environment: '${e.message}'.");
        return false;
      }
    }
    return false;
  }

  static Future<int> getAndroidSdkVersion() async {
    if (Platform.isAndroid) {
      const platform = MethodChannel('com.kanyingyin.player/intent');
      try {
        final int sdkVersion =
            await platform.invokeMethod('getAndroidSdkVersion');
        return sdkVersion;
      } on PlatformException catch (e) {
        AppLogger().e("Failed to get Android SDK version: '${e.message}'.");
        return 0;
      }
    }
    return 0;
  }
}
