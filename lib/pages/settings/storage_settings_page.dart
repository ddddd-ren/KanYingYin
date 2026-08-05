import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kanyingyin/services/storage/app_data_migration_service.dart';
import 'package:kanyingyin/services/storage/storage_path_resolver.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';

class StorageSettingsPage extends StatefulWidget {
  const StorageSettingsPage({
    super.key,
    required this.resolver,
    this.migrationService = const AppDataMigrationService(),
  });

  final StoragePathResolver resolver;
  final AppDataMigrationService migrationService;

  @override
  State<StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends State<StorageSettingsPage> {
  late StoragePathResolver _resolver = widget.resolver;
  bool _working = false;
  bool _restartRequired = false;
  String? _status;

  Future<void> _chooseDataDirectory() async {
    await _chooseDirectory(isCache: false);
  }

  Future<void> _chooseCacheDirectory() async {
    await _chooseDirectory(isCache: true);
  }

  Future<void> _chooseDirectory({required bool isCache}) async {
    final selected = await FilePicker.getDirectoryPath(
      dialogTitle: isCache ? '选择缓存目录' : '选择应用数据目录',
      initialDirectory:
          (isCache ? _resolver.cacheRoot : _resolver.dataRoot).path,
    );
    if (selected == null || selected.trim().isEmpty) return;
    if (!mounted) return;
    final title = isCache ? '缓存目录' : '应用数据目录';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('迁移$title'),
        content: Text('将现有$title迁移到：\n$selected\n\n原目录会保留为备份。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('开始迁移'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _working = true;
      _status = '正在迁移$title…';
    });
    try {
      final next = _resolver.copyWith(
        dataRoot: isCache ? null : Directory(selected),
        cacheRoot: isCache ? Directory(selected) : null,
        isConfigured: true,
      );
      if (isCache) {
        await widget.migrationService.migrateDirectory(
          source: _resolver.cacheRoot,
          target: next.cacheRoot,
        );
        await next.save();
        StoragePathResolver.install(next);
        if (!mounted) return;
        setState(() {
          _resolver = next;
          _status = '缓存目录迁移完成，请重启应用以使用新目录。';
        });
      } else {
        await next.saveMigrationRequest(previous: _resolver);
        if (!mounted) return;
        setState(() {
          _restartRequired = true;
          _status = '应用数据目录已记录，将在重启后、打开数据库前安全迁移。';
        });
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = '$title迁移失败：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text('只删除海报、字幕和临时缓存，不会删除视频、索引、历史或刮削资料。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.migrationService.clearCache(_resolver.cacheRoot);
    setState(() => _status = '缓存已清理。');
  }

  @override
  Widget build(BuildContext context) {
    return KSettingsScaffold(
      title: '存储',
      description: '设置应用数据和可重建缓存的位置。',
      body: KSettingsList(
        maxWidth: 1000,
        sections: [
          KSettingsSection(
            title: const Text('目录'),
            tiles: [
              _pathTile(
                title: '应用数据目录',
                path: _resolver.dataRoot.path,
                onPressed:
                    _working || _restartRequired ? null : _chooseDataDirectory,
              ),
              _pathTile(
                title: '缓存目录',
                path: _resolver.cacheRoot.path,
                onPressed:
                    _working || _restartRequired ? null : _chooseCacheDirectory,
              ),
            ],
          ),
          KSettingsSection(
            title: const Text('维护'),
            tiles: [
              KSettingsTile<void>.navigation(
                enabled: !_working && !_restartRequired,
                onPressed:
                    _working || _restartRequired ? null : (_) => _clearCache(),
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('清理缓存'),
                description: const Text('仅删除可重建的下载、图片和播放中转缓存。'),
              ),
            ],
          ),
          if (_status != null)
            KSettingsSection(
              title: const Text('状态'),
              tiles: [
                KSettingsTile<void>(
                  leading: const Icon(Icons.info_outline),
                  title: Text(_status!),
                ),
              ],
            ),
        ],
      ),
    );
  }

  KSettingsTile<void> _pathTile({
    required String title,
    required String path,
    required VoidCallback? onPressed,
  }) {
    return KSettingsTile<void>.navigation(
      onPressed: onPressed == null ? null : (_) => onPressed(),
      leading: const Icon(Icons.folder_outlined),
      title: Text(title),
      description: Text(path, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}
