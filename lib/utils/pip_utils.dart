import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kanyingyin/features/player/application/player_system_service.dart';
import 'package:kanyingyin/platform/android/android_system_service.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:window_manager/window_manager.dart';

class PipUtils {
  static final _capabilities = detectAppPlatform();
  static final PlayerSystemService _systemService = PlayerSystemService(
    capabilities: _capabilities,
    desktopPort: const _DesktopPlayerSystemPort(),
    androidPort: const _AndroidPlayerSystemPort(),
  );

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

  static Future<bool> enterPIPWindow({
    int width = 16,
    int height = 9,
  }) {
    return _systemService.enterPictureInPicture(width: width, height: height);
  }

  static Future<void> exitPIPWindow() => _systemService.exitPictureInPicture();

  static Future<void> setBrightness(double value) =>
      _systemService.setBrightness(value);

  static Future<String?> saveScreenshot(Uint8List bytes) =>
      _systemService.saveScreenshot(bytes);

  static bool shouldAutoEnterPip({
    required AppLifecycleState lifecycleState,
    required bool enabled,
    required bool playing,
    required int videoWidth,
    required int videoHeight,
  }) {
    return PlayerAutoPipPolicy.shouldEnter(
      capabilities: _capabilities,
      enabled: enabled,
      lifecycleState: lifecycleState,
      playing: playing,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
    );
  }
}

class _DesktopPlayerSystemPort implements DesktopPlayerSystemPort {
  const _DesktopPlayerSystemPort();

  @override
  Future<void> enterPictureInPicture({
    required int width,
    required int height,
  }) {
    return PipUtils.enterDesktopPIPWindow(width: width, height: height);
  }

  @override
  Future<void> exitPictureInPicture() => PipUtils.exitDesktopPIPWindow();

  @override
  Future<String?> saveScreenshot(Uint8List bytes) async {
    final target = await FilePicker.saveFile(
      dialogTitle: '保存截图',
      fileName: '看影音-${DateTime.now().millisecondsSinceEpoch}.png',
      type: FileType.custom,
      allowedExtensions: const <String>['png'],
    );
    if (target == null) return null;
    await File(target).writeAsBytes(bytes, flush: true);
    return target;
  }
}

class _AndroidPlayerSystemPort implements AndroidPlayerSystemPort {
  const _AndroidPlayerSystemPort();

  static const AndroidSystemService _system = AndroidSystemService();

  @override
  Future<bool> enterPictureInPicture({
    required int width,
    required int height,
  }) =>
      _system.enterPictureInPicture(width: width, height: height);

  @override
  Future<String?> saveScreenshot(Uint8List bytes) =>
      _system.saveScreenshot(bytes);

  @override
  Future<void> setBrightness(double value) => _system.setBrightness(value);
}
