import 'package:flutter/material.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:window_manager/window_manager.dart';

class PipUtils {
  // 比例约分
  static Size getPIPAspectSize({required int width, required int height}) {
    if (width <= 0 || height <= 0) {
      return const Size(16, 9);
    }
    final int divisor = width.gcd(height);
    return Size(width / divisor, height / divisor);
  }

  // 进入桌面设备小窗模式，并用播放源比例固定窗口宽高比
  static Future<void> enterDesktopPIPWindow(
      {int width = 16, int height = 9}) async {
    final Size aspectSize = getPIPAspectSize(width: width, height: height);
    final double aspectRatio = aspectSize.width / aspectSize.height;
    const double pipWidth = 480;
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setAspectRatio(aspectRatio);
    await windowManager.setSize(Size(pipWidth, pipWidth / aspectRatio));
  }

  // 退出桌面设备小窗模式
  static Future<void> exitDesktopPIPWindow() async {
    bool isLowResolution = await Utils.isLowResolution();
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setAspectRatio(0);
    await windowManager.setSize(
        isLowResolution ? const Size(800, 600) : const Size(1280, 860));
    await windowManager.center();
  }
}
