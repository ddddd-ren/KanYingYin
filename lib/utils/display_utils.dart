import 'package:flutter/material.dart';

class DisplayUtils {
  static Future<bool> isLowResolution() async {
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

  static bool isDesktop() => true;

  static bool isWideScreen() {
    final MediaQueryData mediaQuery = MediaQueryData.fromView(
        WidgetsBinding.instance.platformDispatcher.views.first);
    final bool isWideScreen = mediaQuery.size.shortestSide >= 600 &&
        mediaQuery.size.shortestSide / mediaQuery.size.longestSide >= 9 / 16;
    return isWideScreen;
  }

  static bool isTablet() => false;

  static bool isCompact() => false;
}
