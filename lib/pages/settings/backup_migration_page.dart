import 'package:flutter/material.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';

class BackupMigrationPage extends StatelessWidget {
  const BackupMigrationPage({super.key, required this.onOpenPath});

  final ValueChanged<String> onOpenPath;

  @override
  Widget build(BuildContext context) => KSettingsScaffold(
        title: '备份与迁移',
        description: '视频和字幕需要自行保留；恢复到新设备时可以重新对应媒体目录。',
        body: KSettingsList(sections: [
          KSettingsSection(
            tiles: [
              KSettingsTile<void>.navigation(
                leading: const Icon(Icons.lock_outline),
                title: const Text('配置与观看记录'),
                description: const Text(
                  '加密备份 TMDB 密钥、网盘账号、收藏、待看、合集、书签、观看进度与历史、选轨和分类偏好。',
                ),
                onPressed: (_) => onOpenPath(
                  '/settings/cloud-sources/configuration-transfer',
                ),
              ),
              KSettingsTile<void>.navigation(
                leading: const Icon(Icons.movie_filter_outlined),
                title: const Text('刮削资料与封面'),
                description: const Text(
                  '迁移已识别的影片资料、海报和背景图，不包含账号凭据；新设备需先添加媒体来源并扫描。',
                ),
                onPressed: (_) => onOpenPath('/settings/tmdb/transfer'),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('不包含视频、字幕、媒体索引、普通缓存或 AI 接口密钥；播放器和外观设置不会整体备份。'),
          ),
        ]),
      );
}
