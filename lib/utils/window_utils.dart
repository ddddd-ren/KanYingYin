import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/utils/display_utils.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:window_manager/window_manager.dart';

class WindowUtils {
  static Future<void> enterWindowsFullscreen() async {
    if (Platform.isWindows) {
      const platform = MethodChannel('com.kanyingyin.player/intent');
      try {
        await platform.invokeMethod('enterFullscreen');
      } on PlatformException catch (e) {
        AppLogger().e("Failed to enter native window mode: '${e.message}'.");
      }
    }
  }

  static Future<void> exitWindowsFullscreen() async {
    if (Platform.isWindows) {
      const platform = MethodChannel('com.kanyingyin.player/intent');
      try {
        await platform.invokeMethod('exitFullscreen');
      } on PlatformException catch (e) {
        AppLogger().e("Failed to exit native window mode: '${e.message}'.");
      }
    }
  }

  static Future<void> enterFullScreen({bool lockOrientation = true}) async {
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      await windowManager.setFullScreen(true);
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
    if (!lockOrientation) return;
    if (Platform.isAndroid) {
      bool isInMultiWindowMode = await DisplayUtils.isInMultiWindowMode();
      if (isInMultiWindowMode) return;
    }
    await landScape();
  }

  static Future<void> exitFullScreen({bool lockOrientation = true}) async {
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      await windowManager.setFullScreen(false);
    }
    late SystemUiMode mode = SystemUiMode.edgeToEdge;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        if (Platform.isAndroid) {
          const platform = MethodChannel('com.kanyingyin.player/intent');
          try {
            final int sdkVersion =
                await platform.invokeMethod<int>('getAndroidSdkVersion') ?? 0;
            if (sdkVersion < 29) {
              mode = SystemUiMode.manual;
            }
          } on PlatformException catch (e) {
            AppLogger().e("Failed to get Android SDK version: '${e.message}'.");
          }
        }
        await SystemChrome.setEnabledSystemUIMode(
          mode,
          overlays: SystemUiOverlay.values,
        );
        if (DisplayUtils.isCompact() && lockOrientation) {
          if (Platform.isAndroid) {
            bool isInMultiWindowMode = await DisplayUtils.isInMultiWindowMode();
            if (isInMultiWindowMode) return;
          }
          verticalScreen();
        }
      }
    } catch (exception, stacktrace) {
      AppLogger().e('DisPlay: failed to exit full screen',
          error: exception, stackTrace: stacktrace);
    }
  }

  static Future<void> landScape() async {
    dynamic document;
    try {
      if (kIsWeb) {
        await document.documentElement?.requestFullscreen();
      } else if (Platform.isAndroid || Platform.isIOS) {
        await SystemChrome.setPreferredOrientations(
          [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
        );
      }
    } catch (exception, stacktrace) {
      AppLogger().e('Display: failed to enter landscape mode',
          error: exception, stackTrace: stacktrace);
    }
  }

  static Future<void> verticalScreen() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  static Future<void> unlockScreenRotation() async {
    await SystemChrome.setPreferredOrientations([]);
  }

  static Future<void> disposePlayerMenu() async {
    if (!Platform.isMacOS) return;
    const MethodChannel appmenu =
        MethodChannel("com.kanyingyin.player/appmenu");
    await appmenu.invokeMethod("setMenuEnabled", {
      "menu": "PlayerMenu",
      "enable": false,
    });
  }

  static Future<void> initPlayerMenu(
      Map<String, void Function()> actions) async {
    if (!Platform.isMacOS) return;
    const MethodChannel appmenu =
        MethodChannel("com.kanyingyin.player/appmenu");
    await appmenu.invokeMethod("setMenuEnabled", {
      "menu": "PlayerMenu",
      "enable": true,
    });
    appmenu.setMethodCallHandler((call) async {
      final action = actions[call.method];
      action?.call();
    });
  }
}
