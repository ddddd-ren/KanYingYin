import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/providers/theme_provider.dart';
import 'package:kanyingyin/services/app_shutdown_coordinator.dart';
import 'package:kanyingyin/services/windows_app_shell_service.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

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
    unawaited(
      widget.service.initialize(
        trayListener: widget.trayListener,
        windowListener: widget.windowListener,
      ),
    );
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
    unawaited(
      widget.service.initialize(
        trayListener: widget.trayListener,
        windowListener: widget.windowListener,
      ),
    );
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

class WindowsAppShellHost extends StatefulWidget {
  const WindowsAppShellHost({
    super.key,
    required this.child,
    this.appShellService,
    this.appShellServiceOwnership = AppShellServiceOwnership.borrowed,
    this.shutdownCoordinator,
  });

  final Widget child;
  final WindowsAppShellService? appShellService;
  final AppShellServiceOwnership appShellServiceOwnership;
  final AppShutdownCoordinator? shutdownCoordinator;

  @override
  State<WindowsAppShellHost> createState() => _WindowsAppShellHostState();
}

class _WindowsAppShellHostState extends State<WindowsAppShellHost>
    with TrayListener, WidgetsBindingObserver, WindowListener {
  final TrayManager trayManager = TrayManager.instance;
  late final WindowsAppShellService appShellService;
  late final AppShellServiceOwnership appShellServiceOwnership;
  late final AppShutdownCoordinator shutdownCoordinator;
  bool showingExitDialog = false;

  @override
  void initState() {
    super.initState();
    appShellService = widget.appShellService ?? WindowsAppShellService();
    appShellServiceOwnership = widget.appShellService == null
        ? AppShellServiceOwnership.owned
        : widget.appShellServiceOwnership;
    shutdownCoordinator = widget.shutdownCoordinator ??
        AppShutdownCoordinator(
          disposePlayback: () => Modular.get<PlayerController>().dispose(),
          flushLogs: AppLogOutput.sharedWriter.flush,
          closeStorage: Hive.close,
          terminateProcess: exit,
          onError: (error, stackTrace) => AppLogger().e(
            '应用退出清理失败',
            error: error,
            stackTrace: stackTrace,
            forceLog: true,
          ),
        );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeProvider = Provider.of<ThemeProvider>(context);
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
        unawaited(shutdownCoordinator.shutdown());
    }
  }

  /// 处理窗口关闭事件。
  ///
  /// 需要使用 `windowManager.close()` 来触发，`exit(0)` 会直接退出程序。
  @override
  void onWindowClose() {
    final setting = GStorage.setting;
    final exitBehavior =
        setting.get(SettingBoxKey.exitBehavior, defaultValue: 2);

    switch (exitBehavior) {
      case 0:
        unawaited(shutdownCoordinator.shutdown());
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
          bool saveExitBehavior = false;

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
                  await shutdownCoordinator.shutdown();
                },
                child: const Text('退出看影音'),
              ),
              TextButton(
                onPressed: () async {
                  if (saveExitBehavior) {
                    await setting.put(SettingBoxKey.exitBehavior, 1);
                  }
                  AppDialog.dismiss<void>();
                  windowManager.hide();
                },
                child: const Text('最小化至托盘'),
              ),
              TextButton(
                onPressed: AppDialog.dismiss<void>,
                child: const Text('取消'),
              ),
            ],
          );
        });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
        AppLogger()
            .i('AppLifecycleState.paused: Application moved to background');
      case AppLifecycleState.resumed:
        AppLogger()
            .i('AppLifecycleState.resumed: Application moved to foreground');
      case AppLifecycleState.inactive:
        AppLogger().i('AppLifecycleState.inactive: Application is inactive');
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Future<void> didChangePlatformBrightness() async {
    super.didChangePlatformBrightness();
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    AppLogger().i(
      'Platform brightness changed, themeMode: ${themeProvider.themeMode}',
    );

    if (themeProvider.themeMode == ThemeMode.system) {
      final brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      AppLogger().i('Updating title bar brightness: $brightness');
      await appShellService.syncBrightness(brightness);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShellLifecycle(
      service: appShellService,
      trayListener: this,
      windowListener: this,
      ownership: appShellServiceOwnership,
      child: widget.child,
    );
  }
}
