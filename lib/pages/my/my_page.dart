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
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final contentWidth = availableWidth.clamp(0.0, 1180.0);
        final columns = SettingsHubLayout.columnCountFor(contentWidth);
        final aspectRatio = switch (columns) {
          3 => 1.3,
          2 => 1.45,
          _ => 2.05,
        };
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '银幕档案馆',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '管理媒体资料、播放体验与应用外观',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 188,
                      child: SettingsHubCard(
                        featured: true,
                        eyebrow: '媒体资料',
                        title: 'TMDB 刮削',
                        description: '配置中文标题、海报、简介与影片信息刮削',
                        icon: Icons.movie_filter_outlined,
                        status: '资料中心',
                        onPressed: () => onOpenPath('/settings/tmdb'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: columns,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: aspectRatio,
                      children: [
                        SettingsHubCard(
                          eyebrow: '媒体来源',
                          title: '网盘数据源',
                          description: '添加和管理 OpenList、夸克与百度网盘媒体来源',
                          icon: Icons.cloud_outlined,
                          onPressed: () =>
                              onOpenPath('/settings/cloud-sources'),
                        ),
                        SettingsHubCard(
                          eyebrow: '识别规则',
                          title: '媒体识别',
                          description: '设置本地与网盘视频的识别大小限制',
                          icon: Icons.video_file_outlined,
                          onPressed: () =>
                              onOpenPath('/settings/media-recognition'),
                        ),
                        SettingsHubCard(
                          eyebrow: '播放器',
                          title: '播放设置',
                          description: '调整解码、渲染、字幕与播放行为',
                          icon: Icons.display_settings_rounded,
                          onPressed: () => onOpenPath('/settings/player'),
                        ),
                        SettingsHubCard(
                          eyebrow: '输入',
                          title: '操作设置',
                          description: '管理播放器键盘快捷键与操作映射',
                          icon: Icons.keyboard_rounded,
                          onPressed: () => onOpenPath('/settings/keyboard'),
                        ),
                        SettingsHubCard(
                          eyebrow: '应用外观',
                          title: '外观设置',
                          description: '管理主题、字体、OLED 与屏幕刷新率',
                          icon: Icons.palette_outlined,
                          onPressed: () => onOpenPath('/settings/theme'),
                        ),
                        SettingsHubCard(
                          eyebrow: '界面',
                          title: '界面设置',
                          description: '设置启动页面与桌面界面行为',
                          icon: Icons.dashboard_customize_outlined,
                          onPressed: () => onOpenPath('/settings/interface'),
                        ),
                        SettingsHubCard(
                          eyebrow: '应用信息',
                          title: '关于',
                          description: '查看版本、许可、日志与缓存管理',
                          icon: Icons.info_outline_rounded,
                          onPressed: () => onOpenPath('/settings/about/'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
