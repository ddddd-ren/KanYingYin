import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/core/app_version.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/features/app_update/presentation/app_update_flow.dart';
import 'package:kanyingyin/features/version/presentation/version_changelog_dialog.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/utils/version_history.dart';
import 'package:provider/provider.dart';
import 'package:kanyingyin/providers/theme_provider.dart';
import 'package:kanyingyin/shaders/shaders_controller.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/services/windows_shortcut_startup_policy.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/windows_shortcut.dart';
import 'package:kanyingyin/features/tv_preload/application/tv_preload_import_service.dart';
import 'package:kanyingyin/features/tv_preload/application/tv_preload_import_ports.dart';

typedef InitShaderErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

Future<void> runInitStartupSequence({
  required Future<void> Function() prepareShaders,
  Future<void> Function()? runPreloadedImport,
  required Future<void> Function() checkShortcut,
  required void Function() navigateToDefaultPage,
  InitShaderErrorHandler? onShaderError,
}) async {
  try {
    await prepareShaders();
  } on Object catch (error, stackTrace) {
    onShaderError?.call(error, stackTrace);
  }
  if (runPreloadedImport != null) await runPreloadedImport();
  await checkShortcut();
  navigateToDefaultPage();
}

Future<void> runPostNavigationStartupSequence({
  required Future<void> Function() delayUntilPageReady,
  required Future<void> Function() showVersionChangelog,
  required Future<void> Function() checkForUpdates,
}) async {
  await delayUntilPageReady();
  await showVersionChangelog();
  await checkForUpdates();
}

class InitPage extends StatefulWidget {
  const InitPage({super.key});

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  final ShadersController shadersController = Modular.get<ShadersController>();
  final TypedSettings setting = Modular.get<TypedSettings>();
  late final ThemeProvider themeProvider;

  @override
  void initState() {
    super.initState();
    themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await runInitStartupSequence(
      prepareShaders: _loadShaders,
      runPreloadedImport: _runPreloadedImport,
      checkShortcut: _showShortcutDialog,
      navigateToDefaultPage: _startDefaultPage,
      onShaderError: (error, stackTrace) => AppLogger().e(
        'InitPage: 着色器准备异常，继续启动应用',
        error: error,
        stackTrace: stackTrace,
      ),
    );

    await runPostNavigationStartupSequence(
      // 等待默认页面完成首次布局，避免全局弹窗挂载到初始化页。
      delayUntilPageReady: () =>
          Future<void>.delayed(const Duration(milliseconds: 500)),
      showVersionChangelog: _showVersionChangelog,
      checkForUpdates: () => Modular.get<AppUpdateFlow>().runAutomatic(),
    );
  }

  Future<void> _runPreloadedImport() async {
    final result = await Modular.get<TvPreloadImportService>().run();
    if (result.status != TvPreloadImportStatus.skipped) {
      AppLogger().i('TV 个人预置导入状态: ${result.status.name}');
    }
  }

  void _startDefaultPage() {
    final storedDefaultStartupPage = setting.getTyped<String>(
      SettingBoxKey.defaultStartupPage,
      defaultValue: defaultStartupPage,
    );
    final startupPage = _normalizeDefaultStartupPage(storedDefaultStartupPage);
    Modular.to.navigate(startupPage);
  }

  String _normalizeDefaultStartupPage(Object? value) {
    final page = value is String ? value : defaultStartupPage;
    if (isValidStartupPage(page)) {
      return page;
    }
    setting.put(SettingBoxKey.defaultStartupPage, defaultStartupPage);
    return defaultStartupPage;
  }

  Future<void> _loadShaders() async {
    await shadersController.copyShadersToExternalDirectory();
  }

  Future<void> _showShortcutDialog() async {
    if (!detectAppPlatform().desktopShell) return;
    final shortcutState = await WindowsShortcut.inspectShortcutEntries();
    final dialogAlreadyShown = setting.getTyped<bool>(
      SettingBoxKey.shortcutDialogShown,
      defaultValue: false,
    );
    final result = await const WindowsShortcutStartupCoordinator().run(
      state: shortcutState,
      dialogAlreadyShown: dialogAlreadyShown,
      askToCreate: () => AppDialog.show<bool>(
        clickMaskDismiss: false,
        builder: (context) => AlertDialog(
          title: const Text('创建桌面快捷方式'),
          content: const Text('是否在桌面创建看影音的快捷方式？'),
          actions: [
            TextButton(
              onPressed: () => AppDialog.dismiss(popWith: false),
              child: Text(
                '暂不创建',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => AppDialog.dismiss(popWith: true),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
      repairOrCreate: WindowsShortcut.createDesktopShortcut,
    );

    if (result.markDialogShown) {
      await setting.put(SettingBoxKey.shortcutDialogShown, true);
    }
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
        AppDialog.showToast(message: '桌面快捷方式已创建');
        break;
      case ShortcutStartupFeedback.creationFailed:
        AppDialog.showToast(message: '桌面快捷方式创建失败');
        break;
    }
  }

  Future<void> _showVersionChangelog() async {
    final lastSeenVersion =
        setting.get(SettingBoxKey.lastSeenVersion, defaultValue: '');
    final currentVersion = AppVersion.current;

    if (lastSeenVersion == currentVersion) return;

    final newVersions = versionHistoryForCurrent(
      currentVersion,
      platform: detectAppPlatform().kind,
    );
    if (newVersions.isEmpty) return;

    // 更新 lastSeenVersion
    setting.put(SettingBoxKey.lastSeenVersion, currentVersion);

    await AppDialog.show<void>(
      builder: (context) => VersionChangelogDialog(versions: newVersions),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const LoadingWidget();
  }
}

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Container());
  }
}
