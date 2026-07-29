import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:kanyingyin/platform/app_platform.dart';

class PlayerAutoPipPolicy {
  const PlayerAutoPipPolicy._();

  static bool shouldEnter({
    required AppPlatformCapabilities capabilities,
    required bool enabled,
    required AppLifecycleState lifecycleState,
    required bool playing,
    required int videoWidth,
    required int videoHeight,
  }) {
    return capabilities.isAndroid &&
        enabled &&
        lifecycleState == AppLifecycleState.inactive &&
        playing &&
        videoWidth > 0 &&
        videoHeight > 0;
  }
}

abstract interface class DesktopPlayerSystemPort {
  Future<void> enterPictureInPicture({
    required int width,
    required int height,
  });

  Future<void> exitPictureInPicture();

  Future<String?> saveScreenshot(Uint8List bytes);
}

abstract interface class AndroidPlayerSystemPort {
  Future<bool> enterPictureInPicture({
    required int width,
    required int height,
  });

  Future<void> setBrightness(double value);

  Future<String?> saveScreenshot(Uint8List bytes);
}

class PlayerSystemService {
  const PlayerSystemService({
    required AppPlatformCapabilities capabilities,
    required DesktopPlayerSystemPort desktopPort,
    required AndroidPlayerSystemPort androidPort,
  })  : _capabilities = capabilities,
        _desktopPort = desktopPort,
        _androidPort = androidPort;

  final AppPlatformCapabilities _capabilities;
  final DesktopPlayerSystemPort _desktopPort;
  final AndroidPlayerSystemPort _androidPort;

  Future<bool> enterPictureInPicture({
    required int width,
    required int height,
  }) async {
    if (_capabilities.systemPictureInPicture) {
      return _androidPort.enterPictureInPicture(
        width: width,
        height: height,
      );
    }
    await _desktopPort.enterPictureInPicture(width: width, height: height);
    return true;
  }

  Future<void> exitPictureInPicture() async {
    if (_capabilities.desktopShell) {
      await _desktopPort.exitPictureInPicture();
    }
  }

  Future<void> setBrightness(double value) async {
    if (!_capabilities.windowBrightness) return;
    await _androidPort.setBrightness(value.clamp(0.01, 1).toDouble());
  }

  Future<String?> saveScreenshot(Uint8List bytes) {
    return _capabilities.isAndroid
        ? _androidPort.saveScreenshot(bytes)
        : _desktopPort.saveScreenshot(bytes);
  }
}
