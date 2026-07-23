import 'package:flutter/services.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:window_manager/window_manager.dart';

class WindowUtils {
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

  static Future<void> enterFullScreen({bool lockOrientation = true}) =>
      windowManager.setFullScreen(true);

  static Future<void> exitFullScreen({bool lockOrientation = true}) =>
      windowManager.setFullScreen(false);
}
