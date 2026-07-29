import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/app_bootstrap.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  test('Android 启动跳过桌面窗口初始化', () async {
    final port = _FakeDesktopWindowPort();
    await AppBootstrap(
      capabilities: AppPlatformCapabilities.android,
      desktopWindow: port,
    ).prepareWindow(showWindowButtons: false, lowResolution: false);

    expect(port.initializeCalls, 0);
  });

  test('Android 存储失败跳过桌面窗口初始化', () async {
    final port = _FakeDesktopWindowPort();
    await AppBootstrap(
      capabilities: AppPlatformCapabilities.android,
      desktopWindow: port,
    ).prepareStorageFailureWindow();

    expect(port.storageFailureCalls, 0);
  });

  test('共享启动入口不直接依赖桌面窗口插件', () {
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(mainSource, isNot(contains('package:window_manager')));
    expect(mainSource, isNot(contains('windowManager.')));
  });
}

class _FakeDesktopWindowPort implements DesktopWindowPort {
  int initializeCalls = 0;
  int storageFailureCalls = 0;

  @override
  Future<void> initialize({
    required bool showWindowButtons,
    required bool lowResolution,
  }) async {
    initializeCalls++;
  }

  @override
  Future<void> showStorageFailureWindow() async {
    storageFailureCalls++;
  }
}
