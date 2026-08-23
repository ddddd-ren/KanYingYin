import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/bean/widget/glass_surface.dart';
import 'package:kanyingyin/features/app_update/application/windows_update_installer.dart';
import 'package:kanyingyin/features/app_update/domain/app_update_models.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:url_launcher/url_launcher.dart';

enum _UpdateDialogState { idle, downloading, error }

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.release,
    required this.installer,
    required this.capabilities,
  });

  final AppRelease release;
  final WindowsUpdateInstaller installer;
  final AppPlatformCapabilities capabilities;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  _UpdateDialogState _state = _UpdateDialogState.idle;
  int _received = 0;
  int _total = 0;
  String? _errorMessage;

  bool get _downloading => _state == _UpdateDialogState.downloading;

  Future<void> _downloadAndUpdate() async {
    if (!widget.capabilities.isWindows) {
      await launchUrl(
        Uri.parse(
          'https://github.com/ddddd-ren/KanYingYin/releases/tag/v${widget.release.version}',
        ),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    if (_downloading) return;
    setState(() {
      _state = _UpdateDialogState.downloading;
      _received = 0;
      _total = widget.release.windowsInstaller.size;
      _errorMessage = null;
    });
    try {
      final file = await widget.installer.downloadAndVerify(
        widget.release.windowsInstaller,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            if (total > 0) _total = total;
          });
        },
      );
      await widget.installer.launchAndExit(file);
    } on UpdatePackageVerificationException {
      _showError('安装包校验失败，请重新下载');
    } on ProcessException {
      _showError('无法启动安装程序，请稍后重试');
    } on Object {
      _showError('下载更新失败，请稍后重试');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _state = _UpdateDialogState.error;
      _errorMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    return PopScope(
      canPop: !_downloading,
      child: GlassDialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '发现新版本 ${release.version}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  '发布时间：${_formatDate(release.publishedAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      release.body.trim().isEmpty ? '本次版本暂无更新说明' : release.body,
                    ),
                  ),
                ),
                if (_downloading) ...[
                  const SizedBox(height: 18),
                  LinearProgressIndicator(value: _progressValue),
                  const SizedBox(height: 8),
                  Text(
                    '${_formatBytes(_received)} / ${_formatBytes(_total)}',
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _errorMessage!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _downloading ? null : () => AppDialog.dismiss<void>(),
                      child: const Text('稍后提醒'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _downloading ? null : _downloadAndUpdate,
                      child: Text(widget.capabilities.isWindows
                          ? (_state == _UpdateDialogState.error
                              ? '重试'
                              : '下载并更新')
                          : '打开下载页面'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double? get _progressValue {
    if (_total <= 0) return null;
    return (_received / _total).clamp(0, 1).toDouble();
  }

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  static String _formatBytes(int bytes) {
    final megabytes = bytes / (1024 * 1024);
    return '${megabytes.toStringAsFixed(2)} MB';
  }
}
