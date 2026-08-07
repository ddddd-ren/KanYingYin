import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_archive_codec.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_transfer_service.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/pages/local/local_directory_picker.dart';
import 'package:kanyingyin/platform/app_file_picker_io.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';

typedef TransferSaveFilePicker = Future<String?> Function();
typedef TransferOpenFilePicker = Future<String?> Function();
typedef TransferTvOpenFilePicker = Future<String?> Function();
typedef TransferLocalDirectoryPicker = Future<String?> Function(
  BuildContext context,
  PortableLocalSource source,
);

class ScrapedMetadataTransferPage extends StatefulWidget {
  const ScrapedMetadataTransferPage({
    super.key,
    required this.service,
    this.saveFilePicker,
    this.openFilePicker,
    this.tvOpenFilePicker,
    this.localDirectoryPicker,
    this.capabilities,
  });

  final ScrapedMetadataTransferService service;
  final TransferSaveFilePicker? saveFilePicker;
  final TransferOpenFilePicker? openFilePicker;
  final TransferTvOpenFilePicker? tvOpenFilePicker;
  final TransferLocalDirectoryPicker? localDirectoryPicker;
  final AppPlatformCapabilities? capabilities;

  @override
  State<ScrapedMetadataTransferPage> createState() =>
      _ScrapedMetadataTransferPageState();
}

class _ScrapedMetadataTransferPageState
    extends State<ScrapedMetadataTransferPage> {
  bool _busy = false;

  AppPlatformCapabilities get _capabilities =>
      widget.capabilities ?? detectAppPlatform();

  Future<void> _export() async {
    final selected =
        await (widget.saveFilePicker ?? _defaultSaveFilePicker).call();
    if (selected == null || selected.trim().isEmpty) return;
    final outputPath = selected.toLowerCase().endsWith('.kyymeta')
        ? selected
        : '$selected.kyymeta';
    await _run(() async {
      final result = await widget.service.exportTo(File(outputPath));
      _showMessage(
        '导出完成：本地 ${result.localCount} 项，网盘 ${result.cloudCount} 项，'
        '图片 ${result.imageCount} 张，跳过 ${result.skippedCount} 项',
      );
    }, errorPrefix: '导出刮削资料失败');
  }

  Future<void> _import() async {
    ScrapedMetadataImportSession? session;
    String? tvCachePath;
    await _run(() async {
      final isTv = _capabilities.isAndroidTv;
      final selected = isTv
          ? await (widget.tvOpenFilePicker ?? _defaultTvOpenFilePicker).call()
          : await (widget.openFilePicker ?? _defaultOpenFilePicker).call();
      if (selected == null || selected.trim().isEmpty) return;
      if (isTv) tvCachePath = selected;
      session = await widget.service.inspect(File(selected));
      if (!mounted) {
        await session!.dispose();
        session = null;
        return;
      }
      final confirmed = await _showImportPreview(session!);
      if (!confirmed) {
        await session!.dispose();
        session = null;
        return;
      }
      final result = await widget.service.apply(session!);
      session = null;
      _showMessage(
        '导入完成：已恢复本地 ${result.localCount} 项、网盘 '
        '${result.cloudCount} 项、图片 ${result.imageCount} 张，'
        '未匹配 ${result.skippedCount} 项',
      );
    }, errorPrefix: '导入刮削资料失败');
    await session?.dispose();
    final cachePath = tvCachePath;
    if (cachePath != null) {
      try {
        final file = File(cachePath);
        if (await file.exists()) await file.delete();
      } on Object {
        // TV 文件选择通道只返回应用缓存文件，清理失败不覆盖导入结果。
      }
    }
  }

  Future<bool> _showImportPreview(
    ScrapedMetadataImportSession session,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final plan = session.plan;
            return AlertDialog(
              title: const Text('确认导入刮削资料'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('将覆盖 ${plan.matchedCount} 项现有刮削资料'),
                      Text('未找到 ${plan.missingMediaCount} 项对应媒体'),
                      Text('可恢复 ${plan.recoverableImageCount} 张图片'),
                      if (plan.unresolvedLocalSources.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          '需要映射的本地来源',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        for (final source in plan.unresolvedLocalSources)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(source.name),
                            subtitle: Text(source.originalRoot),
                            trailing: TextButton(
                              onPressed: () async {
                                final picker = widget.localDirectoryPicker ??
                                    _defaultLocalDirectoryPicker;
                                final path = await picker(context, source);
                                if (path == null || path.isEmpty) return;
                                await widget.service.remapLocal(
                                  session,
                                  source.exportId,
                                  path,
                                );
                                if (dialogContext.mounted) {
                                  setDialogState(() {});
                                }
                              },
                              child: const Text('选择当前目录'),
                            ),
                          ),
                      ],
                      if (plan.unresolvedCloudSources.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          '有 ${plan.unresolvedCloudSources.length} 个网盘来源'
                          '尚未配置或存在歧义，将跳过对应资料。',
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        '导入内容会覆盖目标设备同一媒体的现有刮削资料；'
                        '不会修改视频、字幕或网盘文件。',
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('确认导入'),
                ),
              ],
            );
          },
        );
      },
    );
    return result == true;
  }

  Future<void> _run(
    Future<void> Function() operation, {
    required String errorPrefix,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } on Object catch (error) {
      _showMessage('$errorPrefix：${_errorMessage(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = _busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : null;
    return KSettingsScaffold(
      title: '刮削资料迁移',
      description: '把同一批本地和个人网盘视频的 TMDB 结果迁移到另一台设备。',
      body: KSettingsList(
        sections: [
          KSettingsSection(
            title: const Text('迁移包'),
            description: const Text(
              '包含已确认的标题、简介、评分和缓存图片，不包含视频或账号凭据。',
            ),
            tiles: [
              KSettingsTile<void>.navigation(
                key: const ValueKey<String>('export-scraped-metadata'),
                enabled: !_busy,
                leading: const Icon(Icons.archive_outlined),
                title: const Text('导出刮削资料'),
                description: const Text('生成可离线使用的 .kyymeta 迁移包'),
                value: progress,
                onPressed: (_) => _export(),
              ),
              KSettingsTile<void>.navigation(
                key: const ValueKey<String>('import-scraped-metadata'),
                enabled: !_busy,
                leading: const Icon(Icons.unarchive_outlined),
                title: const Text('导入刮削资料'),
                description: const Text('新设备完成来源配置和扫描后导入'),
                value: progress,
                onPressed: (_) => _import(),
              ),
            ],
            bottomInfo: const Text(
              '导入会覆盖同一媒体的现有刮削资料；找不到对应视频的资料会安全跳过。',
            ),
          ),
        ],
      ),
    );
  }

  static Future<String?> _defaultSaveFilePicker() => FilePicker.saveFile(
        dialogTitle: '导出刮削资料',
        fileName: '看影音刮削资料-${_dateStamp()}.kyymeta',
        type: FileType.custom,
        allowedExtensions: const <String>['kyymeta'],
      );

  static Future<String?> _defaultOpenFilePicker() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: '导入刮削资料',
      type: FileType.custom,
      allowedExtensions: const <String>['kyymeta'],
      allowMultiple: false,
    );
    return result?.files.singleOrNull?.path;
  }

  static Future<String?> _defaultTvOpenFilePicker() async {
    return pickTvImportFile(
      title: '导入刮削资料',
      allowedExtensions: const <String>['kyymeta'],
      maxBytes: ScrapedMetadataArchiveCodec.maxExtractedBytes,
    );
  }

  static Future<String?> _defaultLocalDirectoryPicker(
    BuildContext context,
    PortableLocalSource source,
  ) async {
    final selected = await LocalDirectoryPickerPage.pick(
      context,
      initialPath: source.originalRoot,
    );
    return selected?.location.value;
  }

  static String _dateStamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}';
  }

  static String _errorMessage(Object error) {
    if (error is PlatformException) {
      return switch (error.code) {
        'PickerUnavailable' => '电视没有可用的系统文件选择器，请安装文件管理器后重试',
        'InvalidExtension' => '请选择 .kyymeta 刮削资料包',
        'FileTooLarge' => '刮削资料包超过允许的大小',
        'ReadFailed' => '无法读取所选刮削资料包，请重试',
        _ => '请检查迁移包和磁盘空间后重试',
      };
    }
    final text = error.toString().trim();
    if (text.startsWith('FormatException: ')) {
      return text.substring('FormatException: '.length);
    }
    if (error is FileSystemException) return '文件无法读取或写入';
    return '请检查迁移包和磁盘空间后重试';
  }
}
