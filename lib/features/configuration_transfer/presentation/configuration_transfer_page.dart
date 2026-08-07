import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_archive_codec.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_transfer_service.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/platform/app_file_picker_io.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

typedef ConfigurationSaveFile = Future<String?> Function(
  Uint8List bytes,
  String fileName,
);
typedef ConfigurationOpenFile = Future<Uint8List?> Function();
typedef ConfigurationAndroidTvOpenFile = Future<String?> Function();
typedef ConfigurationShareEncryptedFile = Future<ConfigurationShareOutcome>
    Function(Uint8List bytes, String fileName);

enum ConfigurationShareOutcome { shared, dismissed }

class ConfigurationTransferPage extends StatefulWidget {
  const ConfigurationTransferPage({
    super.key,
    required this.service,
    this.saveFile,
    this.openFile,
    this.androidTvOpenFile,
    this.shareEncryptedFile,
    this.onImported,
    this.capabilities,
  });

  final ConfigurationTransferService service;
  final ConfigurationSaveFile? saveFile;
  final ConfigurationOpenFile? openFile;
  final ConfigurationAndroidTvOpenFile? androidTvOpenFile;
  final ConfigurationShareEncryptedFile? shareEncryptedFile;
  final Future<void> Function()? onImported;
  final AppPlatformCapabilities? capabilities;

  @override
  State<ConfigurationTransferPage> createState() =>
      _ConfigurationTransferPageState();
}

class _ConfigurationTransferPageState extends State<ConfigurationTransferPage> {
  bool _busy = false;

  AppPlatformCapabilities get _capabilities =>
      widget.capabilities ?? detectAppPlatform();

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final configuration = await widget.service.capture();
      if (!mounted) return;
      final password = await _showExportPassword(configuration);
      if (password == null || !mounted) return;
      final bytes = await widget.service.encrypt(
        configuration,
        password: password,
      );
      final fileName = '看影音配置-${_dateStamp()}.kyyconfig';
      String? savedPath;
      try {
        final saveFile = widget.saveFile ?? _defaultSaveFile;
        savedPath = await saveFile(bytes, fileName);
      } on PlatformException {
        if (!_capabilities.isAndroid) rethrow;
        final outcome = await _share(bytes, fileName);
        if (outcome == ConfigurationShareOutcome.dismissed) return;
        savedPath = fileName;
      } on UnimplementedError {
        if (!_capabilities.isAndroid) rethrow;
        final outcome = await _share(bytes, fileName);
        if (outcome == ConfigurationShareOutcome.dismissed) return;
        savedPath = fileName;
      }
      if (savedPath == null || savedPath.trim().isEmpty || !mounted) return;
      _showMessage(
        '导出完成：${path.basename(savedPath)}，网盘来源 '
        '${configuration.cloudSources.length} 个，TMDB '
        '${configuration.tmdbApiKey.isEmpty ? '未包含' : '已包含'}',
      );
    } on Object catch (error) {
      _showMessage(configurationTransferErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final openFile = widget.openFile ?? _defaultOpenFile;
      final bytes = await openFile();
      if (bytes == null || !mounted) return;
      if (bytes.length > ConfigurationArchiveCodec.maxEnvelopeBytes) {
        throw ConfigurationArchiveTooLargeException(bytes.length);
      }
      final password = await _showImportPassword();
      if (password == null || !mounted) return;
      final session = await widget.service.inspect(
        bytes,
        password: password,
      );
      if (!mounted) return;
      final confirmed = await _showImportPreview(session);
      if (!confirmed || !mounted) return;
      final result = await widget.service.apply(session);
      await widget.onImported?.call();
      if (!mounted) return;
      _showMessage(
        '导入完成：新增 ${result.added} 个，更新 ${result.updated} 个，'
        '保留 ${result.preserved} 个来源',
      );
    } on Object catch (error) {
      _showMessage(configurationTransferErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _showExportPassword(
    PortableAppConfiguration configuration,
  ) async {
    final password = TextEditingController();
    final confirmation = TextEditingController();
    String? errorText;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('导出加密配置'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                      'TMDB：${configuration.tmdbApiKey.isEmpty ? '未包含' : '已包含'}'),
                  Text('网盘来源：${configuration.cloudSources.length} 个'),
                  for (final type in CloudSourceType.values)
                    Text(
                      '${_sourceTypeLabel(type)}：'
                      '${configuration.cloudSources.where((record) => record.source.type == type).length} 个',
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey<String>('export-password'),
                    controller: password,
                    obscureText: true,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '导出密码',
                      helperText: '至少 8 个字符，应用不会保存或找回密码',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey<String>('export-password-confirm'),
                    controller: confirmation,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: '再次输入密码',
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (password.text.length <
                    ConfigurationArchiveCodec.minimumPasswordLength) {
                  setDialogState(() => errorText = '密码至少需要 8 个字符');
                  return;
                }
                if (password.text != confirmation.text) {
                  setDialogState(() => errorText = '两次输入的密码不一致');
                  return;
                }
                Navigator.of(dialogContext).pop(password.text);
              },
              child: const Text('开始导出'),
            ),
          ],
        ),
      ),
    );
    password.dispose();
    confirmation.dispose();
    return result;
  }

  Future<String?> _showImportPassword() async {
    final password = TextEditingController();
    String? errorText;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('输入配置密码'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: TextField(
              key: const ValueKey<String>('import-password'),
              controller: password,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '配置密码',
                errorText: errorText,
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (password.text.length <
                    ConfigurationArchiveCodec.minimumPasswordLength) {
                  setDialogState(() => errorText = '密码至少需要 8 个字符');
                  return;
                }
                Navigator.of(dialogContext).pop(password.text);
              },
              child: const Text('检查配置'),
            ),
          ],
        ),
      ),
    );
    password.dispose();
    return result;
  }

  Future<bool> _showImportPreview(ConfigurationImportSession session) async {
    final summary = session.summary;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认导入配置'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('新增来源：${summary.added} 个'),
              Text('更新来源：${summary.updated} 个'),
              Text('保留来源：${summary.preserved} 个'),
              Text('TMDB：${summary.tmdbWillUpdate ? '将更新' : '保留当前配置'}'),
              Text('需要选择媒体目录：${summary.requiresRootSelection} 个'),
              const SizedBox(height: 16),
              const Text(
                '导入只合并 TMDB 和个人网盘配置，不会修改或删除视频、字幕、媒体索引、缓存和播放历史。',
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<String?> _defaultSaveFile(Uint8List bytes, String fileName) async {
    if (_capabilities.isWindows) {
      final selected = await FilePicker.saveFile(
        dialogTitle: '导出看影音配置',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const <String>['kyyconfig'],
      );
      if (selected == null || selected.trim().isEmpty) return null;
      final outputPath = selected.toLowerCase().endsWith('.kyyconfig')
          ? selected
          : '$selected.kyyconfig';
      await File(outputPath).writeAsBytes(bytes, flush: true);
      return outputPath;
    }
    return FilePicker.saveFile(
      dialogTitle: '导出看影音配置',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const <String>['kyyconfig'],
      bytes: bytes,
    );
  }

  Future<Uint8List?> _defaultOpenFile() async {
    if (_capabilities.isAndroidTv) {
      final openFile = widget.androidTvOpenFile ?? _defaultAndroidTvOpenFile;
      final selectedPath = await openFile();
      if (selectedPath == null || selectedPath.trim().isEmpty) return null;
      final file = File(selectedPath);
      try {
        if (!path.basename(file.path).toLowerCase().endsWith('.kyyconfig')) {
          throw const ConfigurationFileExtensionException();
        }
        final length = await file.length();
        if (length > ConfigurationArchiveCodec.maxEnvelopeBytes) {
          throw ConfigurationArchiveTooLargeException(length);
        }
        return await file.readAsBytes();
      } finally {
        try {
          if (await file.exists()) await file.delete();
        } on Object {
          // TV 文件选择通道只返回应用缓存文件，清理失败不覆盖导入结果。
        }
      }
    }
    final result = await FilePicker.pickFiles(
      dialogTitle: '导入看影音配置',
      type: FileType.custom,
      allowedExtensions: const <String>['kyyconfig'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.length != 1) return null;
    final selected = result.files.single;
    if (!selected.name.toLowerCase().endsWith('.kyyconfig')) {
      throw const ConfigurationFileExtensionException();
    }
    if (selected.size > ConfigurationArchiveCodec.maxEnvelopeBytes) {
      throw ConfigurationArchiveTooLargeException(selected.size);
    }
    final memoryBytes = selected.bytes;
    if (memoryBytes != null) return memoryBytes;
    final filePath = selected.path;
    if (filePath == null || filePath.isEmpty) {
      throw const ConfigurationArchiveFormatException('unreadable_file');
    }
    final file = File(filePath);
    final length = await file.length();
    if (length > ConfigurationArchiveCodec.maxEnvelopeBytes) {
      throw ConfigurationArchiveTooLargeException(length);
    }
    return file.readAsBytes();
  }

  Future<String?> _defaultAndroidTvOpenFile() async {
    return pickTvImportFile(
      title: '导入看影音配置',
      allowedExtensions: const <String>['kyyconfig'],
      maxBytes: ConfigurationArchiveCodec.maxEnvelopeBytes,
    );
  }

  Future<ConfigurationShareOutcome> _share(
    Uint8List bytes,
    String fileName,
  ) async {
    final share = widget.shareEncryptedFile ?? _defaultShareEncryptedFile;
    return share(bytes, fileName);
  }

  static Future<ConfigurationShareOutcome> _defaultShareEncryptedFile(
    Uint8List bytes,
    String fileName,
  ) async {
    final directory = await getTemporaryDirectory();
    final file = File(path.join(directory.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          title: '分享看影音加密配置',
          subject: '看影音加密配置',
          text: '看影音加密配置文件，请通过可信方式传输并妥善保管密码。',
          files: <XFile>[
            XFile(file.path, mimeType: 'application/octet-stream'),
          ],
        ),
      );
      return result.status == ShareResultStatus.dismissed
          ? ConfigurationShareOutcome.dismissed
          : ConfigurationShareOutcome.shared;
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } on Object {
        // 临时文件清理失败不改变已经完成的系统分享结果。
      }
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
      title: '配置迁移',
      description: '用密码加密迁移 TMDB Key 和个人网盘来源、账号凭据。',
      body: KSettingsList(
        sections: <Widget>[
          KSettingsSection(
            title: const Text('加密配置文件'),
            description: const Text(
              '密码至少 8 个字符。应用不保存密码，也无法找回密码。',
            ),
            tiles: <Widget>[
              KSettingsTile<void>.navigation(
                key: const ValueKey<String>('export-configuration'),
                enabled: !_busy,
                leading: const Icon(Icons.file_upload_outlined),
                title: const Text('导出配置'),
                description: const Text('生成包含 TMDB 和网盘凭据的 .kyyconfig 文件'),
                value: progress,
                onPressed: (_) => _export(),
              ),
              KSettingsTile<void>.navigation(
                key: const ValueKey<String>('import-configuration'),
                enabled: !_busy,
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('导入配置'),
                description: const Text('先检查合并摘要，确认后再写入当前设备'),
                value: progress,
                onPressed: (_) => _import(),
              ),
            ],
            bottomInfo: const Text(
              '仅迁移配置，不迁移视频、字幕、媒体索引、缓存或播放历史。',
            ),
          ),
        ],
      ),
    );
  }

  static String _sourceTypeLabel(CloudSourceType type) => switch (type) {
        CloudSourceType.openList => 'OpenList',
        CloudSourceType.quark => '夸克',
        CloudSourceType.baidu => '百度',
        CloudSourceType.xunlei => '迅雷',
      };

  static String _dateStamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}';
  }
}

String configurationTransferErrorMessage(Object error) {
  if (error is PlatformException) {
    return switch (error.code) {
      'PickerUnavailable' => '电视没有可用的系统文件选择器，请安装文件管理器后重试',
      'InvalidExtension' => '请选择 .kyyconfig 配置文件',
      'FileTooLarge' => '配置文件超过允许的大小',
      'ReadFailed' => '无法读取所选配置文件，请重试',
      _ => '配置迁移失败，请检查文件后重试',
    };
  }
  if (error is ConfigurationArchivePasswordException) {
    return '密码至少需要 8 个字符';
  }
  if (error is ConfigurationArchiveAuthenticationException) {
    return '密码错误或配置文件已损坏';
  }
  if (error is ConfigurationArchiveUnsupportedVersionException) {
    return '此配置文件版本暂不支持';
  }
  if (error is ConfigurationArchiveTooLargeException) {
    return '配置文件超过 512 KiB';
  }
  if (error is ConfigurationFileExtensionException) {
    return '请选择 .kyyconfig 配置文件';
  }
  if (error is PortableConfigurationValidationException ||
      error is ConfigurationArchiveFormatException) {
    return '配置文件内容无效';
  }
  if (error is ConfigurationRollbackException) {
    return '配置写入失败，自动恢复未完整完成，请重新检查当前配置';
  }
  if (error is ConfigurationImportException) {
    return '配置写入失败，原配置已保留';
  }
  return '配置迁移失败，请检查文件后重试';
}

final class ConfigurationFileExtensionException implements Exception {
  const ConfigurationFileExtensionException();

  @override
  String toString() => 'ConfigurationFileExtensionException';
}
