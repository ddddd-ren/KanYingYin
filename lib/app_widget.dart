import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:kanyingyin/utils/app_identity.dart';
import 'package:kanyingyin/services/windows_app_shell_service.dart';
import 'package:kanyingyin/theme/app_theme.dart';

const Color _fallbackThemeColor = AppTheme.brandBlue;

/// 将持久化主题色转换为应用主题颜色，不访问平台或存储。
Color parseStoredThemeColor(Object? storedValue) {
  if (storedValue == null || storedValue == 'default') {
    return _fallbackThemeColor;
  }

  int? colorValue;
  if (storedValue is int) {
    colorValue = storedValue;
  } else if (storedValue is String) {
    final normalized = storedValue.trim().replaceFirst(
          RegExp(r'^0x', caseSensitive: false),
          '',
        );
    colorValue = int.tryParse(normalized, radix: 16);
  }

  if (colorValue == null || colorValue < 0 || colorValue > 0xFFFFFFFF) {
    return _fallbackThemeColor;
  }
  return Color(colorValue);
}

enum AppShellServiceOwnership { borrowed, owned }

class AppShellLifecycle extends StatefulWidget {
  const AppShellLifecycle({
    super.key,
    required this.service,
    required this.trayListener,
    required this.windowListener,
    required this.ownership,
    required this.child,
  });

  final WindowsAppShellService service;
  final TrayListener trayListener;
  final WindowListener windowListener;
  final AppShellServiceOwnership ownership;
  final Widget child;

  @override
  State<AppShellLifecycle> createState() => _AppShellLifecycleState();
}

class _AppShellLifecycleState extends State<AppShellLifecycle> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.service.initialize(
      trayListener: widget.trayListener,
      windowListener: widget.windowListener,
    ));
  }

  @override
  void didUpdateWidget(covariant AppShellLifecycle oldWidget) {
    super.didUpdateWidget(oldWidget);
    final serviceChanged = !identical(oldWidget.service, widget.service);
    final listenersChanged =
        !identical(oldWidget.trayListener, widget.trayListener) ||
            !identical(oldWidget.windowListener, widget.windowListener);
    if (!serviceChanged && !listenersChanged) return;

    if (serviceChanged) {
      _release(oldWidget);
    } else {
      oldWidget.service.detach();
    }
    unawaited(widget.service.initialize(
      trayListener: widget.trayListener,
      windowListener: widget.windowListener,
    ));
  }

  @override
  void dispose() {
    _release(widget);
    super.dispose();
  }

  void _release(AppShellLifecycle configuration) {
    if (configuration.ownership == AppShellServiceOwnership.owned) {
      configuration.service.dispose();
    } else {
      configuration.service.detach();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AppWidget extends StatefulWidget {
  const AppWidget({
    super.key,
    this.appShellService,
    this.appShellServiceOwnership = AppShellServiceOwnership.borrowed,
  });

  final WindowsAppShellService? appShellService;
  final AppShellServiceOwnership appShellServiceOwnership;

  @override
  State<AppWidget> createState() => _AppWidgetState();
}

class _AppWidgetState extends State<AppWidget>
    with TrayListener, WidgetsBindingObserver, WindowListener {
  Box<Object?> setting = GStorage.setting;

  final TrayManager trayManager = TrayManager.instance;
  late final WindowsAppShellService appShellService;
  late final AppShellServiceOwnership appShellServiceOwnership;
  bool showingExitDialog = false;

  @override
  void initState() {
    super.initState();
    appShellService = widget.appShellService ?? WindowsAppShellService();
    appShellServiceOwnership = widget.appShellService == null
        ? AppShellServiceOwnership.owned
        : widget.appShellServiceOwnership;
    WidgetsBinding.instance.addObserver(this);
    Modular.setObservers([AppDialog.observer]);
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
        AppDialog.dismiss<void>();
        windowManager.hide();
        break;
      default:
        if (showingExitDialog) return;
        showingExitDialog = true;
        AppDialog.show<void>(onDismiss: () {
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
                  void onChanged(bool? value) {
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
                    AppDialog.dismiss<void>();
                    windowManager.hide();
                  },
                  child: const Text('最小化至托盘')),
              TextButton(
                onPressed: AppDialog.dismiss<void>,
                child: const Text('取消'),
              ),
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

    final bool useSystemFont = setting.getTyped<bool>(
      SettingBoxKey.useSystemFont,
      defaultValue: false,
    );
    themeProvider.setFontFamily(useSystemFont, notify: false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeProvider themeProvider = Provider.of<ThemeProvider>(context);
    final Object? storedThemeColor =
        setting.get(SettingBoxKey.themeColor, defaultValue: 'default');
    final Color color = parseStoredThemeColor(storedThemeColor);
    bool oledEnhance = setting.getTyped<bool>(
      SettingBoxKey.oledEnhance,
      defaultValue: false,
    );
    final defaultDarkTheme = AppTheme.dark(
      fontFamily: themeProvider.currentFontFamily,
      seedColor: color,
    );
    final defaultLightTheme = AppTheme.light(
      fontFamily: themeProvider.currentFontFamily,
      seedColor: color,
    );
    final effectiveDarkTheme = oledEnhance
        ? AppTheme.withOledBackground(defaultDarkTheme)
        : defaultDarkTheme;
    final app = AppShellLifecycle(
      service: appShellService,
      trayListener: this,
      windowListener: this,
      ownership: appShellServiceOwnership,
      child: MaterialApp.router(
        title: AppIdentity.displayName,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [
          Locale.fromSubtags(
              languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN")
        ],
        locale: const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN"),
        theme: defaultLightTheme,
        darkTheme: effectiveDarkTheme,
        themeMode: themeProvider.themeMode,
        routerConfig: Modular.routerConfig,
      ),
    );
    return app;
  }
}
