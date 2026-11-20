import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:synchronized/synchronized.dart';
import 'package:kanyingyin/shaders/shaders_controller.dart';
import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/core/app_version.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/features/app_update/presentation/app_update_flow.dart';
import 'package:kanyingyin/features/version/presentation/version_changelog_dialog.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/utils/version_history.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/services/windows_shortcut_startup_policy.dart';
import 'package:kanyingyin/utils/windows_shortcut.dart';

class StartupPromptSequence {
  final Lock _lock = Lock();
  int _nextStep = 0;

  bool get finished => _nextStep == 3;

  Future<void> resume({
    required bool Function() canPresent,
    required Future<bool> Function() checkShortcut,
    required Future<bool> Function() showVersionChangelog,
    required Future<bool> Function() checkForUpdates,
  }) =>
      _lock.synchronized(() async {
        final steps = [checkShortcut, showVersionChangelog, checkForUpdates];
        while (!finished && canPresent()) {
          if (!await steps[_nextStep]()) return;
          _nextStep++;
        }
      });
}

class StartupLanding extends StatefulWidget {
  const StartupLanding({super.key, required this.child});

  final Widget child;
  static String? _pendingPage;
  static StartupPromptSequence? _sequence;

  static void expectPage(String route) {
    _pendingPage = route;
    _sequence = null;
  }

  @override
  State<StartupLanding> createState() => _StartupLandingState();
}

class _StartupLandingState extends State<StartupLanding> {
  @override
  void initState() {
    super.initState();
    final page = Modular.to.path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || StartupLanding._pendingPage != page) return;
      StartupLanding._pendingPage = null;
      StartupLanding._sequence = StartupPromptSequence();
      final shaders = Modular.get<ShadersController>();
      unawaited(SchedulerBinding.instance.scheduleTask<void>(
        shaders.copyShadersToExternalDirectory,
        Priority.idle,
        debugLabel: 'prepareAnime4K',
      ));
      context.findAncestorStateOfType<_StartupPromptsState>()?._resume();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class StartupPrompts extends StatefulWidget {
  const StartupPrompts({super.key, required this.child});

  final Widget child;

  @override
  State<StartupPrompts> createState() => _StartupPromptsState();
}

class _StartupPromptsState extends State<StartupPrompts> {
  late final TypedSettings setting = Modular.get<TypedSettings>();
  static final _tabPage = RegExp(r'^/tab/[^/?#]+/?$');
  ModalRoute<Object?>? _route;
  bool _scheduled = false;

  bool get _canPresent =>
      mounted &&
      _route?.isCurrent == true &&
      _tabPage.hasMatch(Modular.to.path) &&
      !AppDialog.observer.hasAppDialog;

  @override
  void initState() {
    super.initState();
    Modular.to.addListener(_scheduleResume);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _scheduleResume();
  }

  @override
  void dispose() {
    Modular.to.removeListener(_scheduleResume);
    super.dispose();
  }

  void _scheduleResume() {
    final sequence = StartupLanding._sequence;
    if (_scheduled || sequence == null || sequence.finished) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _resume();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _resume() {
    final sequence = StartupLanding._sequence;
    if (sequence == null || sequence.finished || !_canPresent) return;
    unawaited(sequence.resume(
      canPresent: () => _canPresent,
      checkShortcut: _showShortcutDialog,
      showVersionChangelog: _showVersionChangelog,
      checkForUpdates: () => Modular.get<AppUpdateFlow>().runAutomatic(
        canPresent: () => _canPresent,
      ),
    ));
  }

  Future<bool> _showShortcutDialog() async {
    if (!detectAppPlatform().desktopShell) return true;
    final shortcutState = await WindowsShortcut.inspectShortcutEntries();
    if (!_canPresent) return false;
    final missing = switch (shortcutState) {
      WindowsShortcutEntryState.desktopOnly => '开始菜单',
      WindowsShortcutEntryState.startMenuOnly => '桌面',
      _ => '桌面和开始菜单',
    };
    final dialogAlreadyShown = setting.getTyped<bool>(
      SettingBoxKey.shortcutDialogShown,
      defaultValue: false,
    );
    var prompted = false;
    final result = await const WindowsShortcutStartupCoordinator().run(
      state: shortcutState,
      dialogAlreadyShown: dialogAlreadyShown,
      askToCreate: () {
        prompted = true;
        return AppDialog.show<bool>(
          context: context,
          clickMaskDismiss: false,
          builder: (context) => AlertDialog(
            title: const Text('创建快捷方式'),
            content: Text('是否在$missing创建看影音的快捷方式？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  '暂不创建',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('创建'),
              ),
            ],
          ),
        );
      },
      repairOrCreate:
          shortcutState == WindowsShortcutEntryState.desktopAndStartMenu
              ? WindowsShortcut.createDesktopShortcut
              : WindowsShortcut.createMissingShortcuts,
    );

    if (result.markDialogShown) {
      await setting.put(SettingBoxKey.shortcutDialogShown, true);
    }
    if (!_canPresent) return !prompted || result.markDialogShown;
    switch (result.feedback) {
      case ShortcutStartupFeedback.none:
        break;
      case ShortcutStartupFeedback.detectionFailed:
        AppDialog.showToast(message: '无法检查快捷方式状态，将在下次启动时重试');
        break;
      case ShortcutStartupFeedback.repairFailed:
        AppDialog.showToast(message: '桌面快捷方式修复失败');
        break;
      case ShortcutStartupFeedback.created:
        AppDialog.showToast(message: '快捷方式已创建');
        break;
      case ShortcutStartupFeedback.creationFailed:
        AppDialog.showToast(message: '快捷方式创建失败');
        break;
    }
    return true;
  }

  Future<bool> _showVersionChangelog() async {
    final lastSeenVersion =
        setting.get(SettingBoxKey.lastSeenVersion, defaultValue: '');
    final currentVersion = AppVersion.current;

    if (lastSeenVersion == currentVersion) return true;

    final newVersions = versionHistoryForCurrent(
      currentVersion,
      platform: detectAppPlatform().kind,
    );
    if (newVersions.isEmpty) return true;

    var dismissed = false;
    await AppDialog.show<void>(
      context: context,
      onDismiss: () => dismissed = true,
      builder: (context) => VersionChangelogDialog(versions: newVersions),
    );
    if (dismissed) {
      await setting.put(SettingBoxKey.lastSeenVersion, currentVersion);
    }
    return dismissed;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
