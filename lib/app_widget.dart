import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:kanyingyin/utils/constants.dart';
import 'package:kanyingyin/utils/app_identity.dart';
import 'package:kanyingyin/services/windows_app_shell_service.dart';

class AppWidget extends StatefulWidget {
  const AppWidget({super.key, this.appShellService});

  final WindowsAppShellService? appShellService;

  @override
  State<AppWidget> createState() => _AppWidgetState();
}

class _AppWidgetState extends State<AppWidget>
    with TrayListener, WidgetsBindingObserver, WindowListener {
  Box setting = GStorage.setting;

  final TrayManager trayManager = TrayManager.instance;
  late final WindowsAppShellService appShellService;
  bool showingExitDialog = false;
  bool _displayModeInitialized = false;

  @override
  void initState() {
    super.initState();
    appShellService = widget.appShellService ?? WindowsAppShellService();
    WidgetsBinding.instance.addObserver(this);
    Modular.setObservers([AppDialog.observer]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(appShellService.initialize(
        trayListener: this,
        windowListener: this,
      ));
      unawaited(_initializeDisplayMode());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeProvider = Provider.of<ThemeProvider>(context);
    _applyStoredThemePreferences(themeProvider);
    final brightness =
        themeProvider.isEffectiveDark() ? Brightness.dark : Brightness.light;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(appShellService.syncBrightness(brightness));
    });
  }

  @override
  void dispose() {
    appShellService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        windowManager.show();
      case 'exit':
        exit(0);
    }
  }

  /// 处理窗口关闭事件，
  /// 需要使用 `windowManager.close()` 来触发，`exit(0)` 会直接退出程序
  @override
  void onWindowClose() {
    final setting = GStorage.setting;
    final exitBehavior =
        setting.get(SettingBoxKey.exitBehavior, defaultValue: 2);

    switch (exitBehavior) {
      case 0:
        exit(0);
      case 1:
        AppDialog.dismiss();
        windowManager.hide();
        break;
      default:
        if (showingExitDialog) return;
        showingExitDialog = true;
        AppDialog.show(onDismiss: () {
          showingExitDialog = false;
        }, builder: (context) {
          bool saveExitBehavior = false; // 下次不再询问？

          return AlertDialog(
            title: const Text('退出确认'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('您想要退出看影音吗？'),
                const SizedBox(height: 24),
                StatefulBuilder(builder: (context, setState) {
                  onChanged(value) {
                    saveExitBehavior = value ?? false;
                    setState(() {});
                  }

                  return Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Checkbox(value: saveExitBehavior, onChanged: onChanged),
                      const Text('下次不再询问'),
                    ],
                  );
                }),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () async {
                    if (saveExitBehavior) {
                      await setting.put(SettingBoxKey.exitBehavior, 0);
                    }
                    exit(0);
                  },
                  child: const Text('退出看影音')),
              TextButton(
                  onPressed: () async {
                    if (saveExitBehavior) {
                      await setting.put(SettingBoxKey.exitBehavior, 1);
                    }
                    AppDialog.dismiss();
                    windowManager.hide();
                  },
                  child: const Text('最小化至托盘')),
              const TextButton(onPressed: AppDialog.dismiss, child: Text('取消')),
            ],
          );
        });
    }
  }

  /// 处理前后台变更
  /// windows/linux 在程序后台或失去焦点时只会触发 inactive 不会触发 paused
  /// android/ios/macos 在程序后台时会先触发 inactive 再触发 paused, 回到前台时会先触发 inactive 再触发 resumed
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      AppLogger()
          .i("AppLifecycleState.paused: Application moved to background");
    } else if (state == AppLifecycleState.resumed) {
      AppLogger()
          .i("AppLifecycleState.resumed: Application moved to foreground");
    } else if (state == AppLifecycleState.inactive) {
      AppLogger().i("AppLifecycleState.inactive: Application is inactive");
    }
  }

  @override
  Future<void> didChangePlatformBrightness() async {
    super.didChangePlatformBrightness();
    final ThemeProvider themeProvider =
        Provider.of<ThemeProvider>(context, listen: false);
    AppLogger().i(
        "Platform brightness changed, themeMode: ${themeProvider.themeMode}");

    // Only update title bar theme when following system
    // If user has forced a specific theme, keep title bar consistent with app content
    if (themeProvider.themeMode == ThemeMode.system && Platform.isWindows) {
      final brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      AppLogger().i("Updating title bar brightness: $brightness");
      await appShellService.syncBrightness(brightness);
    }
  }

  void _applyStoredThemePreferences(ThemeProvider themeProvider) {
    final Object? storedThemeMode =
        setting.get(SettingBoxKey.themeMode, defaultValue: 'system');
    final themeMode = switch (storedThemeMode) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    themeProvider.setThemeMode(themeMode, notify: false);

    final bool useSystemFont =
        setting.get(SettingBoxKey.useSystemFont, defaultValue: false);
    themeProvider.setFontFamily(useSystemFont, notify: false);
  }

  Future<void> _initializeDisplayMode() async {
    if (_displayModeInitialized || !Platform.isAndroid) return;
    _displayModeInitialized = true;
    try {
      final modes = await FlutterDisplayMode.supported;
      final Object? storedDisplayMode = setting.get(SettingBoxKey.displayMode);
      final selectedMode = storedDisplayMode == null
          ? DisplayMode.auto
          : modes.firstWhere(
              (mode) => mode.toString() == storedDisplayMode,
              orElse: () => DisplayMode.auto,
            );
      final preferredMode = modes.firstWhere(
        (mode) => mode == selectedMode,
        orElse: () => DisplayMode.auto,
      );
      await FlutterDisplayMode.setPreferredMode(preferredMode);
    } catch (error, stackTrace) {
      AppLogger().e(
        'DisPlay: set preferred mode failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeProvider themeProvider = Provider.of<ThemeProvider>(context);
    final Object? storedThemeColor =
        setting.get(SettingBoxKey.themeColor, defaultValue: 'default');
    final Color color = parseStoredThemeColor(storedThemeColor);
    bool oledEnhance =
        setting.get(SettingBoxKey.oledEnhance, defaultValue: false);
    var defaultDarkTheme = ThemeData(
        useMaterial3: true,
        fontFamily: themeProvider.currentFontFamily,
        brightness: Brightness.dark,
        colorSchemeSeed: color,
        progressIndicatorTheme: progressIndicatorTheme2024,
        sliderTheme: sliderTheme2024,
        pageTransitionsTheme: pageTransitionsTheme2024);
    var oledDarkTheme = Utils.oledDarkTheme(defaultDarkTheme);
    themeProvider.setTheme(
      ThemeData(
          useMaterial3: true,
          fontFamily: themeProvider.currentFontFamily,
          brightness: Brightness.light,
          colorSchemeSeed: color,
          progressIndicatorTheme: progressIndicatorTheme2024,
          sliderTheme: sliderTheme2024,
          pageTransitionsTheme: pageTransitionsTheme2024),
      oledEnhance ? oledDarkTheme : defaultDarkTheme,
      notify: false,
    );
    var app = DynamicColorBuilder(
      builder: (theme, darkTheme) {
        if (themeProvider.useDynamicColor) {
          themeProvider.setTheme(
            ThemeData(
                useMaterial3: true,
                fontFamily: themeProvider.currentFontFamily,
                colorScheme: theme,
                brightness: Brightness.light,
                progressIndicatorTheme: progressIndicatorTheme2024,
                sliderTheme: sliderTheme2024,
                pageTransitionsTheme: pageTransitionsTheme2024),
            oledEnhance
                ? Utils.oledDarkTheme(ThemeData(
                    useMaterial3: true,
                    fontFamily: themeProvider.currentFontFamily,
                    colorScheme: darkTheme,
                    brightness: Brightness.dark,
                    progressIndicatorTheme: progressIndicatorTheme2024,
                    sliderTheme: sliderTheme2024,
                    pageTransitionsTheme: pageTransitionsTheme2024))
                : ThemeData(
                    useMaterial3: true,
                    fontFamily: themeProvider.currentFontFamily,
                    colorScheme: darkTheme,
                    brightness: Brightness.dark,
                    progressIndicatorTheme: progressIndicatorTheme2024,
                    sliderTheme: sliderTheme2024,
                    pageTransitionsTheme: pageTransitionsTheme2024),
            notify: false,
          );
        }
        return MaterialApp.router(
          title: AppIdentity.displayName,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [
            Locale.fromSubtags(
                languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN")
          ],
          locale: const Locale.fromSubtags(
              languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN"),
          theme: themeProvider.light,
          darkTheme: themeProvider.dark,
          themeMode: themeProvider.themeMode,
          routerConfig: Modular.routerConfig,
        );
      },
    );
    return app;
  }
}
