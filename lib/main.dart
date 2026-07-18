import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:kanyingyin/app_module.dart';
import 'package:kanyingyin/app_widget.dart';
import 'package:kanyingyin/core/app_version.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/providers/theme_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kanyingyin/utils/proxy_manager.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kanyingyin/pages/error/storage_error_page.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kanyingyin/utils/app_identity.dart';
import 'package:kanyingyin/utils/logger.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    _installGlobalErrorLogging();
    final sessionId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    AppLogger().i(
      '应用启动: version=${AppVersion.current} '
      'os=${Platform.operatingSystemVersion} session=$sessionId',
      forceLog: true,
    );
    await _startApplication();
  }, (error, stackTrace) {
    AppLogger().f(
      'Zone 未捕获异常',
      error: error,
      stackTrace: stackTrace,
      forceLog: true,
    );
  });
}

void _installGlobalErrorLogging() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger().e(
      'Flutter 未捕获异常',
      error: details.exception,
      stackTrace: details.stack,
      forceLog: true,
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogger().f(
      '平台未捕获异常',
      error: error,
      stackTrace: stackTrace,
      forceLog: true,
    );
    return true;
  };
}

Future<void> _startApplication() async {
  MediaKit.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ));
  }

  if (Platform.isAndroid) {}

  try {
    final hivePath =
        '${(await getApplicationSupportDirectory()).path}/${AppIdentity.storageNamespace}/hive';
    await Hive.initFlutter(hivePath);
    await GStorage.init();
  } catch (e) {
    // Log the error for debugging (if logger is available)
    debugPrint('Storage initialization failed: $e');

    if (Platform.isWindows) {
      await windowManager.ensureInitialized();
      windowManager.waitUntilReadyToShow(null, () async {
        // Native window show has been blocked in `flutter_windows.cppL36` to avoid flickering.
        // Without this. the window will never show on Windows.
        await windowManager.show();
        await windowManager.focus();
      });
    }
    runApp(MaterialApp(
        title: '初始化失败',
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [
          Locale.fromSubtags(
              languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN")
        ],
        locale: const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN"),
        builder: (context, child) {
          return const StorageErrorPage();
        }));
    return;
  }
  bool showWindowButton = GStorage.setting.getTyped<bool>(
    SettingBoxKey.showWindowButton,
    defaultValue: false,
  );
  if (Utils.isDesktop()) {
    await windowManager.ensureInitialized();
    bool isLowResolution = await Utils.isLowResolution();
    WindowOptions windowOptions = WindowOptions(
      size: isLowResolution ? const Size(840, 600) : const Size(1280, 860),
      center: true,
      skipTaskbar: false,
      // macOS always hide title bar regardless of showWindowButton setting
      titleBarStyle: (Platform.isMacOS || !showWindowButton)
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      windowButtonVisibility: showWindowButton,
      title: AppIdentity.displayName,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      // Native window show has been blocked in `flutter_windows.cppL36` to avoid flickering.
      // Without this. the window will never show on Windows.
      await windowManager.show();
      await windowManager.focus();
    });
  }
  await ProxyManager.initializeProxy();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: ModularApp(
        module: AppModule(),
        child: const AppWidget(),
      ),
    ),
  );
}
