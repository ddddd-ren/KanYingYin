import 'package:card_settings_ui/card_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/bean/appbar/sys_app_bar.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/core/app_version.dart';
import 'package:kanyingyin/services/local_image_cache_service.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:kanyingyin/utils/utils.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.cacheService});

  final LocalImageCacheService? cacheService;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final exitBehaviorTitles = <String>['退出看影音', '最小化至托盘', '每次都询问'];
  Box<Object?> setting = GStorage.setting;
  late int exitBehavior = setting.getTyped<int>(
    SettingBoxKey.exitBehavior,
    defaultValue: 2,
  );
  double _cacheSizeMB = -1;
  final MenuController menuController = MenuController();
  late final LocalImageCacheService _cacheService;

  @override
  void initState() {
    super.initState();
    _cacheService = widget.cacheService ?? LocalImageCacheService();
    _getCacheSize();
  }

  void onBackPressed(BuildContext context) {
    if (AppDialog.observer.hasAppDialog) {
      AppDialog.dismiss<void>();
      return;
    }
  }

  Future<void> _getCacheSize() async {
    try {
      final totalSizeBytes = await _cacheService.sizeBytes();
      if (!mounted) return;
      setState(() {
        _cacheSizeMB = totalSizeBytes / (1024 * 1024);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _cacheSizeMB = 0;
      });
    }
  }

  Future<bool> _clearCache() async {
    final cleared = await _cacheService.tryClear();
    if (cleared) await _getCacheSize();
    return cleared;
  }

  void _showCacheDialog() {
    AppDialog.show<void>(
      builder: (context) {
        return AlertDialog(
          title: const Text('缓存管理'),
          content: const Text('缓存用于显示本地媒体封面，清除后需要重新加载。确认要清除缓存吗？'),
          actions: [
            TextButton(
              onPressed: () {
                AppDialog.dismiss<void>();
              },
              child: Text(
                '取消',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () async {
                AppDialog.dismiss<void>();
                final cleared = await _clearCache();
                AppDialog.showToast(
                  message: cleared ? '缓存已清理' : '清理缓存失败，请稍后重试',
                );
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        onBackPressed(context);
      },
      child: Scaffold(
        appBar: const SysAppBar(title: Text('关于')),
        // backgroundColor: Colors.transparent,
        body: SettingsList(
          maxWidth: 1000,
          sections: [
            SettingsSection(
              title: Text(
                '开源许可与致谢',
                style: TextStyle(fontFamily: fontFamily),
              ),
              tiles: [
                SettingsTile<void>(
                  title: Text(
                    '界面与操作参考 Kazumi',
                    style: TextStyle(fontFamily: fontFamily),
                  ),
                ),
                SettingsTile<void>.navigation(
                  onPressed: (_) {
                    Modular.to.pushNamed('/settings/about/license');
                  },
                  title:
                      Text('开源许可证', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('查看所有开源许可证',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            if (Utils.isDesktop()) // 之后如果有非桌面平台的新选项可以移除
              SettingsSection(
                title: Text('默认行为', style: TextStyle(fontFamily: fontFamily)),
                tiles: [
                  SettingsTile<void>.navigation(
                    onPressed: (_) {
                      if (menuController.isOpen) {
                        menuController.close();
                      } else {
                        menuController.open();
                      }
                    },
                    title:
                        Text('关闭时', style: TextStyle(fontFamily: fontFamily)),
                    value: MenuAnchor(
                      consumeOutsideTap: true,
                      controller: menuController,
                      builder: (_, __, ___) {
                        return Text(exitBehaviorTitles[exitBehavior]);
                      },
                      menuChildren: [
                        for (int i = 0; i < 3; i++)
                          MenuItemButton(
                            requestFocusOnHover: false,
                            onPressed: () {
                              exitBehavior = i;
                              setting.put(SettingBoxKey.exitBehavior, i);
                              setState(() {});
                            },
                            child: Container(
                              height: 48,
                              constraints: BoxConstraints(minWidth: 112),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  exitBehaviorTitles[i],
                                  style: TextStyle(
                                    color: i == exitBehavior
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            SettingsSection(
              tiles: [
                SettingsTile<void>.navigation(
                  onPressed: (_) {
                    Modular.to.pushNamed('/settings/about/logs');
                  },
                  title: Text('错误日志', style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            SettingsSection(
              tiles: [
                SettingsTile<void>.navigation(
                  onPressed: (_) {
                    _showCacheDialog();
                  },
                  title: Text('清除缓存', style: TextStyle(fontFamily: fontFamily)),
                  value: _cacheSizeMB == -1
                      ? Text('统计中...', style: TextStyle(fontFamily: fontFamily))
                      : Text('${_cacheSizeMB.toStringAsFixed(2)}MB',
                          style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile<void>(
                  title: Text(
                    '当前版本',
                    style: TextStyle(fontFamily: fontFamily),
                  ),
                  trailing: Text(
                    AppVersion.current,
                    style: TextStyle(fontFamily: fontFamily),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
