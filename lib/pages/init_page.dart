import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/core/app_version.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:kanyingyin/utils/version_history.dart';
import 'package:provider/provider.dart';
import 'package:kanyingyin/providers/theme_provider.dart';
import 'package:kanyingyin/shaders/shaders_controller.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';
import 'package:kanyingyin/services/windows_shortcut_startup_policy.dart';
import 'package:kanyingyin/utils/windows_shortcut.dart';

class InitPage extends StatefulWidget {
  const InitPage({super.key});

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  final ShadersController shadersController = Modular.get<ShadersController>();
  Box<Object?> setting = GStorage.setting;
  late final ThemeProvider themeProvider;

  @override
  void initState() {
    super.initState();
    themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadShaders();
    await _checkRunningOnX11();
    await _showShortcutDialog();

    _startDefaultPage();
    // delay to ensure that the default page is fully loaded
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _showVersionChangelog();
  }

  void _startDefaultPage() {
    final storedDefaultStartupPage = setting.getTyped<String>(
      SettingBoxKey.defaultStartupPage,
      defaultValue: defaultStartupPage,
    );
    final startupPage = _normalizeDefaultStartupPage(storedDefaultStartupPage);
    // Workaround for dynamic_color. dynamic_color need PlatformChannel to get color, it takes time.
    // setDynamic here to avoid white screen flash when themeMode is dark.
    themeProvider.setDynamic(setting.getTyped<bool>(
      SettingBoxKey.useDynamicColor,
      defaultValue: false,
    ));
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

  Future<void> _checkRunningOnX11() async {
    if (!Platform.isLinux) {
      return;
    }
    bool isRunningOnX11 = await Utils.isRunningOnX11();
    if (isRunningOnX11) {
      await AppDialog.show<void>(
        clickMaskDismiss: false,
        builder: (context) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('X11环境检测'),
              content: const Text(
                  '检测到您当前运行在X11环境下，看影音在X11环境下可能出现性能问题或界面异常，建议切换到Wayland以获得更好的体验。您是否希望在X11下继续使用看影音？'),
              actions: [
                TextButton(
                  onPressed: () {
                    exit(0);
                  },
                  child: Text(
                    '退出',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    AppDialog.dismiss<void>();
                  },
                  child: const Text('继续'),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Future<void> _showShortcutDialog() async {
    if (!Platform.isWindows) return;
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

  void _showVersionChangelog() {
    final lastSeenVersion =
        setting.get(SettingBoxKey.lastSeenVersion, defaultValue: '');
    final currentVersion = AppVersion.current;

    if (lastSeenVersion == currentVersion) return;

    final newVersions = versionHistoryForCurrent(currentVersion);
    if (newVersions.isEmpty) return;

    // 更新 lastSeenVersion
    setting.put(SettingBoxKey.lastSeenVersion, currentVersion);

    AppDialog.show<void>(
      builder: (context) => VersionChangelogDialog(versions: newVersions),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const LoadingWidget();
  }
}

class VersionChangelogDialog extends StatelessWidget {
  const VersionChangelogDialog({super.key, required this.versions});

  final List<VersionHistory> versions;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('版本更新日志'),
      content: VersionChangelogContent(versions: versions),
      actions: [
        TextButton(
          onPressed: () => AppDialog.dismiss<void>(),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

class VersionChangelogContent extends StatelessWidget {
  const VersionChangelogContent({super.key, required this.versions});

  final List<VersionHistory> versions;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final version in versions) ...[
            Text(
              'v${version.version}  ${version.releaseLabel}  ${version.date}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            for (final change in version.changes)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 2),
                child: Text(
                  '- $change',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Container());
  }
}
