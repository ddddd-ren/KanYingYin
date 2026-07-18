import 'package:card_settings_ui/card_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/bean/appbar/sys_app_bar.dart';
import 'package:kanyingyin/pages/menu/menu.dart';
import 'package:provider/provider.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  late NavigationBarState navigationBarState;

  void onBackPressed(BuildContext context) {
    if (AppDialog.observer.hasAppDialog) {
      AppDialog.dismiss<void>();
      return;
    }
    navigationBarState.updateSelectedIndex(0);
    Modular.to.navigate('/tab/local/');
  }

  @override
  void initState() {
    super.initState();
    navigationBarState =
        Provider.of<NavigationBarState>(context, listen: false);
  }

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          return;
        }
        onBackPressed(context);
      },
      child: Scaffold(
        appBar: const SysAppBar(
          title: Text('我的'),
          needTopOffset: false,
          showDesktopWindowControls: false,
        ),
        body: SettingsList(
          maxWidth: 1000,
          sections: [
            SettingsSection(
              title: Text('本地媒体库', style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile<void>.navigation(
                  onPressed: (_) {
                    Modular.to.pushNamed('/settings/tmdb');
                  },
                  leading: const Icon(Icons.movie_filter_outlined),
                  title:
                      Text('TMDB 刮削', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('配置本地媒体海报与信息刮削',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile<void>.navigation(
                  onPressed: (_) {
                    Modular.to.pushNamed('/settings/cloud-sources');
                  },
                  leading: const Icon(Icons.cloud_outlined),
                  title:
                      Text('网盘数据源', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('添加和管理 OpenList 媒体来源',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile<void>.navigation(
                  onPressed: (_) {
                    Modular.to.pushNamed('/settings/media-recognition');
                  },
                  leading: const Icon(Icons.video_file_outlined),
                  title: Text('媒体识别', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('设置本地与网盘视频的识别大小限制',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            SettingsSection(
              title: Text('播放器设置', style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile<void>.navigation(
                  onPressed: (_) {
                    Modular.to.pushNamed('/settings/player');
                  },
                  leading: const Icon(Icons.display_settings_rounded),
                  title: Text('播放设置', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('设置播放器相关参数',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile<void>.navigation(
                  onPressed: (_) {
                    Modular.to.pushNamed('/settings/keyboard');
                  },
                  leading: const Icon(Icons.keyboard_rounded),
                  title: Text('操作设置', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('设置播放器按键映射',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            SettingsSection(
              title: Text('应用与外观', style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile<void>.navigation(
                  onPressed: (_) {
                    Modular.to.pushNamed('/settings/theme');
                  },
                  leading: const Icon(Icons.palette_rounded),
                  title: Text('外观设置', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('设置应用主题和刷新率',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
                SettingsTile<void>.navigation(
                  onPressed: (_) {
                    Modular.to.pushNamed('/settings/interface');
                  },
                  leading: const Icon(Icons.pages_rounded),
                  title: Text('界面设置', style: TextStyle(fontFamily: fontFamily)),
                  description: Text('设置应用界面样式',
                      style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
            SettingsSection(
              title: Text('其他', style: TextStyle(fontFamily: fontFamily)),
              tiles: [
                SettingsTile<void>.navigation(
                  onPressed: (_) {
                    Modular.to.pushNamed('/settings/about/');
                  },
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text('关于', style: TextStyle(fontFamily: fontFamily)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
