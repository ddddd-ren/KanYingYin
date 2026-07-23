import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/card/palette_card.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/providers/theme_provider.dart';
import 'package:kanyingyin/bean/settings/color_type.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kanyingyin/theme/app_theme.dart';

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  Box<Object?> setting = GStorage.setting;
  late String defaultThemeMode;
  late String defaultThemeColor;
  late bool oledEnhance;
  late bool showWindowButton;
  late bool useSystemFont;
  late final ThemeProvider themeProvider;
  final MenuController menuController = MenuController();

  @override
  void initState() {
    super.initState();
    defaultThemeMode = setting.getTyped<String>(
      SettingBoxKey.themeMode,
      defaultValue: 'system',
    );
    defaultThemeColor = setting.getTyped<String>(
      SettingBoxKey.themeColor,
      defaultValue: 'default',
    );
    oledEnhance = setting.getTyped<bool>(
      SettingBoxKey.oledEnhance,
      defaultValue: false,
    );
    showWindowButton = setting.getTyped<bool>(
      SettingBoxKey.showWindowButton,
      defaultValue: false,
    );
    useSystemFont = setting.getTyped<bool>(
      SettingBoxKey.useSystemFont,
      defaultValue: false,
    );
    themeProvider = Provider.of<ThemeProvider>(context, listen: false);
  }

  void onBackPressed(BuildContext context) {
    if (AppDialog.observer.hasAppDialog) {
      AppDialog.dismiss<void>();
      return;
    }
  }

  void setTheme(Color? color) {
    final defaultDarkTheme = AppTheme.dark(
      fontFamily: themeProvider.currentFontFamily,
      seedColor: color,
    );
    final oledDarkTheme = AppTheme.withOledBackground(defaultDarkTheme);
    themeProvider.setTheme(
      AppTheme.light(
        fontFamily: themeProvider.currentFontFamily,
        seedColor: color,
      ),
      oledEnhance ? oledDarkTheme : defaultDarkTheme,
    );
    defaultThemeColor = color?.toARGB32().toRadixString(16) ?? 'default';
    setting.put(SettingBoxKey.themeColor, defaultThemeColor);
  }

  void resetTheme() {
    setTheme(null);
  }

  void updateTheme(String theme) async {
    if (theme == 'dark') {
      themeProvider.setThemeMode(ThemeMode.dark);
    }
    if (theme == 'light') {
      themeProvider.setThemeMode(ThemeMode.light);
    }
    if (theme == 'system') {
      themeProvider.setThemeMode(ThemeMode.system);
    }
    await setting.put(SettingBoxKey.themeMode, theme);
    setState(() {
      defaultThemeMode = theme;
    });

    // Update Windows title bar theme
    if (Platform.isWindows) {
      await windowManager.setBrightness(
          themeProvider.isEffectiveDark() ? Brightness.dark : Brightness.light);
    }
  }

  void updateOledEnhance() {
    oledEnhance = setting.getTyped<bool>(
      SettingBoxKey.oledEnhance,
      defaultValue: false,
    );
    setTheme(
      defaultThemeColor == 'default'
          ? null
          : Color(int.parse(defaultThemeColor, radix: 16)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        onBackPressed(context);
      },
      child: KSettingsScaffold(
        title: '外观设置',
        description: '管理主题、字体与桌面显示。',
        body: KSettingsList(
          maxWidth: 1000,
          sections: [
            KSettingsSection(
              title: Text('外观', style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                KSettingsTile<void>.navigation(
                  onPressed: (_) {
                    if (menuController.isOpen) {
                      menuController.close();
                    } else {
                      menuController.open();
                    }
                  },
                  title: Text('深色模式', style: TextStyle(fontFamily: fontFamily)),
                  value: MenuAnchor(
                    consumeOutsideTap: true,
                    controller: menuController,
                    builder: (_, __, ___) {
                      return Text(
                        defaultThemeMode == 'light'
                            ? '浅色'
                            : (defaultThemeMode == 'dark' ? '深色' : '跟随系统'),
                        style: TextStyle(fontFamily: fontFamily),
                      );
                    },
                    menuChildren: [
                      MenuItemButton(
                        requestFocusOnHover: false,
                        onPressed: () => updateTheme('system'),
                        child: Container(
                          height: 48,
                          constraints: BoxConstraints(minWidth: 112),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.brightness_auto_rounded,
                                  color: defaultThemeMode == 'system'
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '跟随系统',
                                  style: TextStyle(
                                    color: defaultThemeMode == 'system'
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                    fontFamily: fontFamily,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      MenuItemButton(
                        requestFocusOnHover: false,
                        onPressed: () => updateTheme('light'),
                        child: Container(
                          height: 48,
                          constraints: BoxConstraints(minWidth: 112),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.light_mode_rounded,
                                  color: defaultThemeMode == 'light'
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '浅色',
                                  style: TextStyle(
                                      color: defaultThemeMode == 'light'
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : null,
                                      fontFamily: fontFamily),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      MenuItemButton(
                        requestFocusOnHover: false,
                        onPressed: () => updateTheme('dark'),
                        child: Container(
                          height: 48,
                          constraints: BoxConstraints(minWidth: 112),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.dark_mode_rounded,
                                  color: defaultThemeMode == 'dark'
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  '深色',
                                  style: TextStyle(
                                    color: defaultThemeMode == 'dark'
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                    fontFamily: fontFamily,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                KSettingsTile<void>.navigation(
                  onPressed: (_) async {
                    AppDialog.show<void>(builder: (context) {
                      return AlertDialog(
                        title: Text('配色方案',
                            style: TextStyle(fontFamily: fontFamily)),
                        content: StatefulBuilder(builder:
                            (BuildContext context, StateSetter setState) {
                          final colorThemes = colorThemeTypes;
                          return Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: Utils.isDesktop() ? 8 : 0,
                            children: [
                              ...colorThemes.map(
                                (e) {
                                  final index = colorThemes.indexOf(e);
                                  return GestureDetector(
                                    onTap: () {
                                      index == 0
                                          ? resetTheme()
                                          : setTheme(e.color);
                                      AppDialog.dismiss<void>();
                                    },
                                    child: Column(
                                      children: [
                                        PaletteCard(
                                          color: e.color,
                                          selected: (e.color
                                                      .toARGB32()
                                                      .toRadixString(16) ==
                                                  defaultThemeColor ||
                                              (defaultThemeColor == 'default' &&
                                                  index == 0)),
                                        ),
                                        Text(e.label),
                                      ],
                                    ),
                                  );
                                },
                              )
                            ],
                          );
                        }),
                      );
                    });
                  },
                  title: Text('配色方案', style: TextStyle(fontFamily: fontFamily)),
                ),
                KSettingsTile<bool>.switchTile(
                  onToggle: (value) async {
                    useSystemFont = value ?? !useSystemFont;
                    await setting.put(
                        SettingBoxKey.useSystemFont, useSystemFont);
                    themeProvider.setFontFamily(useSystemFont);
                    setTheme(
                      defaultThemeColor == 'default'
                          ? null
                          : Color(int.parse(defaultThemeColor, radix: 16)),
                    );
                    setState(() {});
                  },
                  title:
                      Text('使用系统字体', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('关闭后使用 MI Sans 字体',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: useSystemFont,
                ),
              ],
              bottomInfo: Text('动态配色仅支持安卓12及以上和桌面平台',
                  style: TextStyle(fontFamily: fontFamily)),
            ),
            KSettingsSection(
              tiles: [
                KSettingsTile<bool>.switchTile(
                  onToggle: (value) async {
                    oledEnhance = value ?? !oledEnhance;
                    await setting.put(SettingBoxKey.oledEnhance, oledEnhance);
                    updateOledEnhance();
                    setState(() {});
                  },
                  title:
                      Text('OLED优化', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('深色模式下使用纯黑背景',
                      style: TextStyle(fontFamily: fontFamily)),
                  initialValue: oledEnhance,
                ),
              ],
            ),
            if (Utils.isDesktop())
              KSettingsSection(
                tiles: [
                  KSettingsTile<bool>.switchTile(
                    onToggle: (value) async {
                      showWindowButton = value ?? !showWindowButton;
                      await setting.put(
                          SettingBoxKey.showWindowButton, showWindowButton);
                      setState(() {});
                    },
                    title: Text('使用系统标题栏',
                        style: TextStyle(fontFamily: fontFamily)),
                    description: Text('重启应用生效',
                        style: TextStyle(fontFamily: fontFamily)),
                    initialValue: showWindowButton,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
