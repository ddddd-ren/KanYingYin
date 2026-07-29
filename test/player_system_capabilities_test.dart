import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/player_system_service.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  test('Android PIP、亮度和截图只调用 Android 系统端口', () async {
    final desktop = _DesktopPort();
    final android = _AndroidPort();
    final service = PlayerSystemService(
      capabilities: AppPlatformCapabilities.android,
      desktopPort: desktop,
      androidPort: android,
    );

    expect(
      await service.enterPictureInPicture(width: 1920, height: 1080),
      isTrue,
    );
    await service.setBrightness(-1);
    await service.setBrightness(2);
    expect(
      await service.saveScreenshot(Uint8List.fromList(<int>[1, 2, 3])),
      'content://media/image/1',
    );

    expect(desktop.enterCount, 0);
    expect(desktop.savedCount, 0);
    expect(android.enterSizes, <(int, int)>[(1920, 1080)]);
    expect(android.brightnessValues, <double>[0.01, 1]);
    expect(android.savedCount, 1);
  });

  test('Windows PIP 和截图只调用桌面端口', () async {
    final desktop = _DesktopPort();
    final android = _AndroidPort();
    final service = PlayerSystemService(
      capabilities: AppPlatformCapabilities.windows,
      desktopPort: desktop,
      androidPort: android,
    );

    expect(
      await service.enterPictureInPicture(width: 4, height: 3),
      isTrue,
    );
    await service.exitPictureInPicture();
    expect(
      await service.saveScreenshot(Uint8List.fromList(<int>[4, 5, 6])),
      'D:/capture.png',
    );

    expect(desktop.enterCount, 1);
    expect(desktop.exitCount, 1);
    expect(desktop.savedCount, 1);
    expect(android.enterSizes, isEmpty);
    expect(android.savedCount, 0);
  });

  test('Android 自动 PIP 只在播放视频并进入非活动态时触发', () {
    expect(
      PlayerAutoPipPolicy.shouldEnter(
        capabilities: AppPlatformCapabilities.android,
        enabled: true,
        lifecycleState: AppLifecycleState.inactive,
        playing: true,
        videoWidth: 1920,
        videoHeight: 1080,
      ),
      isTrue,
    );
    expect(
      PlayerAutoPipPolicy.shouldEnter(
        capabilities: AppPlatformCapabilities.android,
        enabled: true,
        lifecycleState: AppLifecycleState.paused,
        playing: true,
        videoWidth: 1920,
        videoHeight: 1080,
      ),
      isFalse,
    );
    expect(
      PlayerAutoPipPolicy.shouldEnter(
        capabilities: AppPlatformCapabilities.android,
        enabled: true,
        lifecycleState: AppLifecycleState.inactive,
        playing: false,
        videoWidth: 1920,
        videoHeight: 1080,
      ),
      isFalse,
    );
    expect(
      PlayerAutoPipPolicy.shouldEnter(
        capabilities: AppPlatformCapabilities.android,
        enabled: true,
        lifecycleState: AppLifecycleState.inactive,
        playing: true,
        videoWidth: 0,
        videoHeight: 0,
      ),
      isFalse,
    );
  });
}

class _DesktopPort implements DesktopPlayerSystemPort {
  int enterCount = 0;
  int exitCount = 0;
  int savedCount = 0;

  @override
  Future<void> enterPictureInPicture({
    required int width,
    required int height,
  }) async {
    enterCount++;
  }

  @override
  Future<void> exitPictureInPicture() async {
    exitCount++;
  }

  @override
  Future<String?> saveScreenshot(Uint8List bytes) async {
    savedCount++;
    return 'D:/capture.png';
  }
}

class _AndroidPort implements AndroidPlayerSystemPort {
  final List<(int, int)> enterSizes = <(int, int)>[];
  final List<double> brightnessValues = <double>[];
  int savedCount = 0;

  @override
  Future<bool> enterPictureInPicture({
    required int width,
    required int height,
  }) async {
    enterSizes.add((width, height));
    return true;
  }

  @override
  Future<String?> saveScreenshot(Uint8List bytes) async {
    savedCount++;
    return 'content://media/image/1';
  }

  @override
  Future<void> setBrightness(double value) async {
    brightnessValues.add(value);
  }
}
