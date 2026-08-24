import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:kanyingyin/app_module.dart';
import 'package:kanyingyin/app_widget.dart';
import 'package:kanyingyin/core/app_version.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/platform/app_bootstrap.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/platform/windows/windows_desktop_window_port.dart';
import 'package:kanyingyin/providers/theme_provider.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kanyingyin/utils/proxy_manager.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:media_kit/media_kit.dart';
import 'package:kanyingyin/pages/error/storage_error_page.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:kanyingyin/services/storage/storage_path_resolver.dart';
import 'package:kanyingyin/services/storage/app_data_migration_service.dart';

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
  final capabilities = await loadAppPlatformCapabilities();
  final bootstrap = AppBootstrap(
    capabilities: capabilities,
    desktopWindow: const WindowsDesktopWindowPort(),
  );
  late final TmdbCredentialManager tmdbCredentialManager;
  try {
    final storageResolver = await StoragePathResolver.load();
    StoragePathResolver.install(storageResolver);
    final needsInitialMigration = !storageResolver.isConfigured &&
        storageResolver.dataRoot.path != storageResolver.legacyDataRoot.path &&
        await storageResolver.legacyDataRoot.exists();
    if (storageResolver.hasPendingMigration || needsInitialMigration) {
      try {
        await const AppDataMigrationService().migrateResolver(storageResolver);
      } on Object catch (error, stackTrace) {
        AppLogger().w(
          '启动存储迁移失败，继续使用上一个成功目录',
          error: error,
          stackTrace: stackTrace,
        );
        final fallbackResolver = StoragePathResolver(
          dataRoot: storageResolver.legacyDataRoot,
          cacheRoot: storageResolver.legacyCacheRoot,
          configFile: storageResolver.configFile,
          legacyDataRoot: storageResolver.legacyDataRoot,
          legacyCacheRoot: storageResolver.legacyCacheRoot,
          isConfigured: true,
        );
        await fallbackResolver.save();
        StoragePathResolver.install(fallbackResolver);
      }
    }
    final hivePath = StoragePathResolver.current!.hiveRoot.path;
    await Hive.initFlutter(hivePath);
    await GStorage.init(hivePath: hivePath);
    tmdbCredentialManager = TmdbCredentialManager(
      store: SecureTmdbCredentialStore(),
      legacyReader: () =>
          GStorage.setting.get('tmdbApiKey', defaultValue: '').toString(),
      legacyDelete: () => GStorage.setting.delete('tmdbApiKey'),
    );
    await tmdbCredentialManager.initialize();
  } catch (e) {
    // Log the error for debugging (if logger is available)
    debugPrint('Storage initialization failed: $e');

    await bootstrap.prepareStorageFailureWindow();
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
  final isLowResolution =
      capabilities.desktopShell && await Utils.isLowResolution();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: ModularApp(
        module: AppModule(tmdbCredentialManager: tmdbCredentialManager),
        child: AppWidget(capabilities: capabilities),
      ),
    ),
  );
  await bootstrap.prepareWindow(
    showWindowButtons: showWindowButton,
    lowResolution: isLowResolution,
  );
  unawaited(
    ProxyManager.initializeProxy().catchError((Object error, StackTrace stack) {
      AppLogger().w(
        '启动代理探测失败，不影响应用使用',
        error: error,
        stackTrace: stack,
      );
    }),
  );
}
