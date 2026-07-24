import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/pages/local/local_directory_picker.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';

class InterfaceSettingsPage extends StatefulWidget {
  const InterfaceSettingsPage({super.key});

  @override
  State<InterfaceSettingsPage> createState() => _InterfaceSettingsPageState();
}

class _InterfaceSettingsPageState extends State<InterfaceSettingsPage> {
  final TypedSettings setting = Modular.get<TypedSettings>();
  late String defaultPage;
  late String localDefaultPath;
  final MenuController defaultPageMenuController = MenuController();

  @override
  void initState() {
    super.initState();
    defaultPage = setting.getTyped<String>(
      SettingBoxKey.defaultStartupPage,
      defaultValue: defaultStartupPage,
    );
    if (!isValidStartupPage(defaultPage)) {
      defaultPage = defaultStartupPage;
    }
    localDefaultPath = setting.getTyped<String>(
      SettingBoxKey.localDefaultPath,
      defaultValue: '',
    );
  }

  void updateDefaultPage(String page) {
    setting.put(SettingBoxKey.defaultStartupPage, page);
    setState(() {
      defaultPage = page;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;

    return KSettingsScaffold(
      title: '界面设置',
      description: '选择启动页面和本地文件默认目录。',
      body: KSettingsList(
        sections: [
          KSettingsSection(tiles: [
            KSettingsTile<void>.navigation(
              onPressed: (_) async {
                if (defaultPageMenuController.isOpen) {
                  defaultPageMenuController.close();
                } else {
                  defaultPageMenuController.open();
                }
              },
              title: Text('启动时打开', style: TextStyle(fontFamily: fontFamily)),
              description: Text('选择看影音启动后显示的媒体库',
                  style: TextStyle(fontFamily: fontFamily)),
              value: MenuAnchor(
                consumeOutsideTap: true,
                controller: defaultPageMenuController,
                builder: (_, __, ___) {
                  return Text(
                    defaultStartupPageLabels[defaultPage] ?? '本地媒体库',
                    style: TextStyle(fontFamily: fontFamily),
                  );
                },
                menuChildren: [
                  for (final entry in defaultStartupPageLabels.entries)
                    MenuItemButton(
                      requestFocusOnHover: false,
                      onPressed: () => updateDefaultPage(entry.key),
                      child: Container(
                        height: 48,
                        constraints: BoxConstraints(minWidth: 112),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              color: entry.key == defaultPage
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                              fontFamily: fontFamily,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ]),
          KSettingsSection(tiles: [
            KSettingsTile<void>.navigation(
              onPressed: (_) async {
                final result = await LocalDirectoryPickerPage.pick(
                  context,
                  initialPath:
                      localDefaultPath.isEmpty ? null : localDefaultPath,
                );
                if (result != null) {
                  await setting.put(SettingBoxKey.localDefaultPath, result);
                  setState(() => localDefaultPath = result);
                }
              },
              title: Text('本地文件默认路径', style: TextStyle(fontFamily: fontFamily)),
              description: localDefaultPath.isNotEmpty
                  ? Text(localDefaultPath,
                      style: TextStyle(fontFamily: fontFamily, fontSize: 12))
                  : Text('未设置，请手动选择本地视频目录',
                      style: TextStyle(fontFamily: fontFamily, fontSize: 12)),
              value: localDefaultPath.isNotEmpty
                  ? IconButton(
                      tooltip: '清除',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () async {
                        await setting.delete(SettingBoxKey.localDefaultPath);
                        setState(() => localDefaultPath = '');
                      },
                    )
                  : const Icon(Icons.folder_open, size: 18),
            ),
          ]),
        ],
      ),
    );
  }
}
