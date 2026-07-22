import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/bean/appbar/sys_app_bar.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/pages/menu/menu.dart';
import 'package:provider/provider.dart';

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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        onBackPressed(context);
      },
      child: Scaffold(
        appBar: const SysAppBar(
          title: Text('设置'),
          needTopOffset: false,
          showDesktopWindowControls: false,
        ),
        body: SettingsHubContent(
          onOpenPath: (path) => Modular.to.pushNamed(path),
        ),
      ),
    );
  }
}

/// 可独立验证的设置控制中心内容，不读取路由、存储或控制器。
class SettingsHubContent extends StatelessWidget {
  const SettingsHubContent({super.key, required this.onOpenPath});

  final ValueChanged<String> onOpenPath;

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    Text text(String value) => Text(
          value,
          style: TextStyle(fontFamily: fontFamily),
        );

    return KSettingsList(
      maxWidth: 1000,
      sections: [
        KSettingsSection(
          title: text('本地媒体库'),
          tiles: [
            KSettingsTile<void>.navigation(
              onPressed: (_) => onOpenPath('/settings/tmdb'),
              leading: const Icon(Icons.movie_filter_outlined),
              title: text('TMDB 刮削'),
              description: text('配置中文标题、海报、简介与影片信息刮削'),
            ),
            KSettingsTile<void>.navigation(
              onPressed: (_) => onOpenPath('/settings/cloud-sources'),
              leading: const Icon(Icons.cloud_outlined),
              title: text('网盘数据源'),
              description: text('添加和管理 OpenList、夸克与百度网盘媒体来源'),
            ),
            KSettingsTile<void>.navigation(
              onPressed: (_) => onOpenPath('/settings/media-recognition'),
              leading: const Icon(Icons.video_file_outlined),
              title: text('媒体识别'),
              description: text('设置本地与网盘视频的识别大小限制'),
            ),
          ],
        ),
        KSettingsSection(
          title: text('播放器设置'),
          tiles: [
            KSettingsTile<void>.navigation(
              onPressed: (_) => onOpenPath('/settings/player'),
              leading: const Icon(Icons.display_settings_rounded),
              title: text('播放设置'),
              description: text('调整解码、渲染、字幕与播放行为'),
            ),
            KSettingsTile<void>.navigation(
              onPressed: (_) => onOpenPath('/settings/keyboard'),
              leading: const Icon(Icons.keyboard_rounded),
              title: text('操作设置'),
              description: text('管理播放器键盘快捷键与操作映射'),
            ),
          ],
        ),
        KSettingsSection(
          title: text('应用与外观'),
          tiles: [
            KSettingsTile<void>.navigation(
              onPressed: (_) => onOpenPath('/settings/theme'),
              leading: const Icon(Icons.palette_outlined),
              title: text('外观设置'),
              description: text('管理主题、字体、OLED 与屏幕刷新率'),
            ),
            KSettingsTile<void>.navigation(
              onPressed: (_) => onOpenPath('/settings/interface'),
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: text('界面设置'),
              description: text('设置启动页面与桌面界面行为'),
            ),
          ],
        ),
        KSettingsSection(
          title: text('其他'),
          tiles: [
            KSettingsTile<void>.navigation(
              onPressed: (_) => onOpenPath('/settings/about/'),
              leading: const Icon(Icons.info_outline_rounded),
              title: text('关于'),
              description: text('查看版本、许可、日志与缓存管理'),
            ),
          ],
        ),
      ],
    );
  }
}
