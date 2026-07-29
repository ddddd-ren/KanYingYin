import 'package:flutter/material.dart';
import 'package:kanyingyin/platform/app_bootstrap.dart';
import 'package:kanyingyin/utils/app_identity.dart';
import 'package:window_manager/window_manager.dart';

class WindowsDesktopWindowPort implements DesktopWindowPort {
  const WindowsDesktopWindowPort();

  @override
  Future<void> initialize({
    required bool showWindowButtons,
    required bool lowResolution,
  }) async {
    await windowManager.ensureInitialized();
    final windowOptions = WindowOptions(
      size: lowResolution ? const Size(840, 600) : const Size(1280, 860),
      center: true,
      skipTaskbar: false,
      titleBarStyle:
          !showWindowButtons ? TitleBarStyle.hidden : TitleBarStyle.normal,
      windowButtonVisibility: showWindowButtons,
      title: AppIdentity.displayName,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // Windows 原生窗口默认禁止自动显示，等待 Flutter 首帧准备后再显示可避免闪烁。
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  Future<void> showStorageFailureWindow() async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(null, () async {
      // Windows 原生窗口默认禁止自动显示，等待 Flutter 首帧准备后再显示可避免闪烁。
      await windowManager.show();
      await windowManager.focus();
    });
  }
}
