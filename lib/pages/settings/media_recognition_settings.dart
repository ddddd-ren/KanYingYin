import 'package:card_settings_ui/card_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/appbar/sys_app_bar.dart';
import 'package:kanyingyin/services/media_recognition_settings.dart';

class MediaRecognitionSettingsPage extends StatefulWidget {
  const MediaRecognitionSettingsPage({
    super.key,
    required this.settings,
    required this.onRescanLocal,
    required this.onRescanCloud,
  });

  final MediaRecognitionSettings settings;
  final Future<void> Function() onRescanLocal;
  final Future<void> Function() onRescanCloud;

  @override
  State<MediaRecognitionSettingsPage> createState() =>
      _MediaRecognitionSettingsPageState();
}

class _MediaRecognitionSettingsPageState
    extends State<MediaRecognitionSettingsPage> {
  MediaRecognitionTarget? _editingTarget;
  MediaRecognitionTarget? _scanningTarget;

  bool get _isBusy => _editingTarget != null || _scanningTarget != null;

  int get _localMegabytes => MediaRecognitionSettings.bytesToMegabytes(
        widget.settings.localMinSizeBytes,
        fallback: 800,
      );

  int get _cloudMegabytes => MediaRecognitionSettings.bytesToMegabytes(
        widget.settings.cloudMinSizeBytes,
        fallback: 1,
      );

  @override
  Widget build(BuildContext context) {
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    return Scaffold(
      appBar: const SysAppBar(
        title: Text('媒体识别'),
        showDesktopWindowControls: false,
      ),
      body: SettingsList(
        maxWidth: 1000,
        sections: [
          SettingsSection(
            title: Text('本地识别限制', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile.navigation(
                enabled: !_isBusy,
                onPressed: (_) =>
                    _showSizeChoices(MediaRecognitionTarget.local),
                leading: const Icon(Icons.folder_outlined),
                title: Text('本地媒体库', style: TextStyle(fontFamily: fontFamily)),
                description: Text('忽略小于或等于此大小的本地视频',
                    style: TextStyle(fontFamily: fontFamily)),
                value: Text(MediaRecognitionSettings.formatMegabytes(
                  _localMegabytes,
                )),
              ),
              if (_scanningTarget == MediaRecognitionTarget.local)
                SettingsTile(
                  title: const Text('正在重新扫描本地媒体库'),
                  description: const LinearProgressIndicator(),
                ),
            ],
          ),
          SettingsSection(
            title: Text('网盘识别限制', style: TextStyle(fontFamily: fontFamily)),
            tiles: [
              SettingsTile.navigation(
                enabled: !_isBusy,
                onPressed: (_) =>
                    _showSizeChoices(MediaRecognitionTarget.cloud),
                leading: const Icon(Icons.cloud_outlined),
                title: Text('网盘媒体库', style: TextStyle(fontFamily: fontFamily)),
                description: Text('忽略小于或等于此大小的网盘视频',
                    style: TextStyle(fontFamily: fontFamily)),
                value: Text(MediaRecognitionSettings.formatMegabytes(
                  _cloudMegabytes,
                )),
              ),
              if (_scanningTarget == MediaRecognitionTarget.cloud)
                SettingsTile(
                  title: const Text('正在重新扫描网盘媒体库'),
                  description: const LinearProgressIndicator(),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showSizeChoices(MediaRecognitionTarget target) async {
    if (_isBusy) return;
    setState(() => _editingTarget = target);
    try {
      final selected = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
              target == MediaRecognitionTarget.local ? '本地媒体识别大小' : '网盘媒体识别大小'),
          content: SizedBox(
            width: 360,
            height: 180,
            child: GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 2.1,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final value in MediaRecognitionSettings.presetMegabytes)
                  OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(value),
                    child:
                        Text(MediaRecognitionSettings.formatMegabytes(value)),
                  ),
                OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(-1),
                  child: const Text('自定义'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      if (!mounted || selected == null) return;
      final megabytes = selected == -1 ? await _showCustomInput() : selected;
      if (!mounted || megabytes == null) return;
      await _saveAndOfferRescan(target, megabytes);
    } finally {
      if (mounted) {
        setState(() => _editingTarget = null);
      } else {
        _editingTarget = null;
      }
    }
  }

  Future<int?> _showCustomInput() async {
    return showDialog<int>(
      context: context,
      builder: (_) => const _CustomRecognitionSizeDialog(),
    );
  }

  Future<void> _saveAndOfferRescan(
    MediaRecognitionTarget target,
    int megabytes,
  ) async {
    try {
      await widget.settings.saveMegabytes(target, megabytes);
    } catch (_) {
      if (mounted) _showError('保存媒体识别设置失败，请稍后重试');
      return;
    }
    if (!mounted) return;
    setState(() {});
    final scanNow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('是否立即重新扫描'),
        content: const Text('重新扫描后，新的识别大小限制将应用到媒体库。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('立即扫描'),
          ),
        ],
      ),
    );
    if (!mounted || scanNow != true || _scanningTarget != null) return;
    setState(() => _scanningTarget = target);
    try {
      final callback = target == MediaRecognitionTarget.local
          ? widget.onRescanLocal
          : widget.onRescanCloud;
      await callback();
    } catch (_) {
      if (mounted) {
        _showError(target == MediaRecognitionTarget.local
            ? '本地媒体库重新扫描失败，请稍后重试'
            : '网盘媒体库重新扫描失败，请检查连接后重试');
      }
    } finally {
      if (mounted) setState(() => _scanningTarget = null);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CustomRecognitionSizeDialog extends StatefulWidget {
  const _CustomRecognitionSizeDialog();

  @override
  State<_CustomRecognitionSizeDialog> createState() =>
      _CustomRecognitionSizeDialogState();
}

class _CustomRecognitionSizeDialogState
    extends State<_CustomRecognitionSizeDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    final value = int.tryParse(text);
    if (value == null || value < 0) {
      setState(() => _errorText = '请输入非负整数');
      return;
    }
    if (value > MediaRecognitionSettings.maxMegabytes) {
      setState(() => _errorText = '最大支持 1048576 MB');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自定义识别大小'),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '大小（MB）',
            errorText: _errorText,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
