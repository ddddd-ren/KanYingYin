import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/platform/android/android_system_service.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:window_manager/window_manager.dart';

class WindowUtils {
  static const AndroidSystemService _androidSystem = AndroidSystemService();

  static Future<void> enterWindowsFullscreen() async {
    const platform = MethodChannel('com.kanyingyin.player/intent');
    try {
      await platform.invokeMethod('enterFullscreen');
    } on PlatformException catch (e) {
      AppLogger().e("进入 Windows 原生全屏失败：'${e.message}'。");
    }
  }

  static Future<void> exitWindowsFullscreen() async {
    const platform = MethodChannel('com.kanyingyin.player/intent');
    try {
      await platform.invokeMethod('exitFullscreen');
    } on PlatformException catch (e) {
      AppLogger().e("退出 Windows 原生全屏失败：'${e.message}'。");
    }
  }

  static Future<void> enterFullScreen({bool lockOrientation = true}) async {
    if (detectAppPlatform().desktopShell) {
      await windowManager.setFullScreen(true);
      return;
    }
    if (lockOrientation) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    await _androidSystem.setImmersive(true);
  }

  static Future<void> exitFullScreen({bool lockOrientation = true}) async {
    if (detectAppPlatform().desktopShell) {
      await windowManager.setFullScreen(false);
      return;
    }
    await _androidSystem.setImmersive(false);
    if (lockOrientation) {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final isTablet =
          view.physicalSize.shortestSide / view.devicePixelRatio >= 600;
      await SystemChrome.setPreferredOrientations(
        preferredOrientationsAfterPlayback(
          isAndroidTv: detectAppPlatform().isAndroidTv,
          isTablet: isTablet,
        ),
      );
    }
  }

  static List<DeviceOrientation> preferredOrientationsAfterPlayback({
    required bool isAndroidTv,
    required bool isTablet,
  }) =>
      isAndroidTv || isTablet
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [DeviceOrientation.portraitUp];
}
