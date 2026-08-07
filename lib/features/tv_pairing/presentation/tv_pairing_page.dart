import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';
import 'package:kanyingyin/features/tv_pairing/application/tv_pairing_controller.dart';
import 'package:qr_flutter/qr_flutter.dart';

class TvPairingPage extends StatefulWidget {
  const TvPairingPage({
    super.key,
    required this.controller,
    this.onManualConfiguration,
    this.onCompleted,
    this.ownsController = true,
  });

  final TvPairingController controller;
  final VoidCallback? onManualConfiguration;
  final Future<void> Function()? onCompleted;
  final bool ownsController;

  @override
  State<TvPairingPage> createState() => _TvPairingPageState();
}

class _TvPairingPageState extends State<TvPairingPage> {
  bool _confirmationOpen = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    unawaited(widget.controller.start());
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.controller.state == TvPairingState.awaitingConfirmation &&
        !_confirmationOpen) {
      _confirmationOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showConfirmation());
      });
    }
  }

  Future<void> _showConfirmation() async {
    final summary = widget.controller.pendingSummary;
    if (summary == null || !mounted) {
      _confirmationOpen = false;
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认手机配置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('配置名称：${summary.deviceName}'),
            const SizedBox(height: 8),
            Text('网盘来源：${summary.cloudSourceCount} 个'),
            Text('新增来源：${summary.added} 个'),
            Text('更新来源：${summary.updated} 个'),
            Text('保留来源：${summary.preserved} 个'),
            Text('TMDB：${summary.hasTmdbKey ? '将更新' : '保持不变'}'),
            Text('需要选择媒体目录：${summary.requiresRootSelection} 个'),
            if (summary.hasConfigurationFile) const Text('配置文件：已从手机上传，将覆盖当前配置'),
            if (summary.hasScrapedMetadataFile) ...[
              const Text('刮削资料文件：已从手机上传'),
              Text('可匹配资料：${summary.metadataMatchedCount} 项'),
              Text('缺失媒体：${summary.metadataMissingMediaCount} 项'),
              Text('可恢复图片：${summary.metadataRecoverableImageCount} 张'),
            ],
          ],
        ),
        actions: <Widget>[
          TvSettingsFocusSurface(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('拒绝'),
            ),
          ),
          TvSettingsFocusSurface(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.check),
              label: const Text('确认写入'),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _confirmationOpen = false;
    if (accepted == true) {
      await widget.controller.confirmPending();
    } else {
      widget.controller.rejectPending();
    }
  }

  void _openManualConfiguration() {
    final callback = widget.onManualConfiguration;
    if (callback != null) {
      callback();
    } else {
      Modular.to.pop();
    }
  }

  Future<void> _returnToSources() async {
    try {
      await widget.onCompleted?.call();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配置已写入，但网盘来源列表刷新失败')),
        );
      }
      return;
    }
    if (mounted) await Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    if (widget.ownsController) {
      widget.controller.dispose();
    } else {
      unawaited(widget.controller.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KSettingsScaffold(
      title: '手机扫码配置',
      description: '手机和电视需连接同一个局域网。',
      maxWidth: 1040,
      body: AnimatedSwitcher(
        duration: SettingsMotion.contentDuration,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return switch (widget.controller.state) {
      TvPairingState.idle || TvPairingState.starting => const Center(
          key: ValueKey<String>('tv-pairing-starting'),
          child: CircularProgressIndicator(),
        ),
      TvPairingState.active => _ActivePairingView(
          key: const ValueKey<String>('tv-pairing-active'),
          controller: widget.controller,
          onCancel: () => unawaited(widget.controller.cancel()),
          onManualConfiguration: _openManualConfiguration,
        ),
      TvPairingState.phoneConnected ||
      TvPairingState.awaitingConfirmation =>
        _PhoneConnectedView(
          key: const ValueKey<String>('tv-pairing-phone-connected'),
          controller: widget.controller,
          onCancel: () => unawaited(widget.controller.cancel()),
        ),
      TvPairingState.applying => const Center(
          key: ValueKey<String>('tv-pairing-applying'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('正在写入配置和导入刮削资料'),
            ],
          ),
        ),
      TvPairingState.success => _PairingResultView(
          key: const ValueKey<String>('tv-pairing-success'),
          icon: Icons.check_circle_outline,
          title: '配置已写入',
          message:
              widget.controller.completedSummary?.requiresRootSelection == 0
                  ? '现在可以返回媒体库继续使用。'
                  : '部分网盘还没有选择媒体目录，请返回网盘数据源完成设置。',
          primaryLabel:
              widget.controller.completedSummary?.requiresRootSelection == 0
                  ? '返回'
                  : '返回网盘数据源选择目录',
          onPrimary: () => unawaited(_returnToSources()),
        ),
      TvPairingState.error => _PairingResultView(
          key: const ValueKey<String>('tv-pairing-error'),
          icon: Icons.error_outline,
          title: widget.controller.errorMessage ?? '配对失败',
          message: '请检查局域网连接后重试。',
          primaryLabel: '重试',
          onPrimary: () => unawaited(widget.controller.start()),
          secondaryLabel: '手动配置',
          onSecondary: _openManualConfiguration,
        ),
    };
  }
}

class _ActivePairingView extends StatelessWidget {
  const _ActivePairingView({
    super.key,
    required this.controller,
    required this.onCancel,
    required this.onManualConfiguration,
  });

  final TvPairingController controller;
  final VoidCallback onCancel;
  final VoidCallback onManualConfiguration;

  @override
  Widget build(BuildContext context) {
    final endpoint = controller.endpoint;
    if (endpoint == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final pairingUrl = endpoint.pairUri.toString();
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Wrap(
          spacing: 40,
          runSpacing: 28,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: QrImageView(
                key: const ValueKey<String>('tv-pairing-qr'),
                data: pairingUrl,
                size: 300,
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.white,
                semanticsLabel: '手机扫码配置二维码',
              ),
            ),
            SizedBox(
              width: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('等待手机连接',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  SelectableText(
                    pairingUrl,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  _RemainingTime(controller: controller),
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      TvSettingsFocusSurface(
                        key: const ValueKey<String>('tv-pairing-cancel-focus'),
                        autofocus: true,
                        onPressed: onCancel,
                        child: FilledButton.icon(
                          onPressed: onCancel,
                          icon: const Icon(Icons.close),
                          label: const Text('取消配对'),
                        ),
                      ),
                      TvSettingsFocusSurface(
                        key: const ValueKey<String>('tv-pairing-manual-focus'),
                        onPressed: onManualConfiguration,
                        child: OutlinedButton.icon(
                          onPressed: onManualConfiguration,
                          icon: const Icon(Icons.tune),
                          label: const Text('手动配置'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneConnectedView extends StatelessWidget {
  const _PhoneConnectedView({
    super.key,
    required this.controller,
    required this.onCancel,
  });

  final TvPairingController controller;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.phonelink_ring_rounded,
                size: 84,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                '手机已连接',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                controller.state == TvPairingState.awaitingConfirmation
                    ? '等待电视端确认配置'
                    : '等待手机填写并发送配置',
              ),
              const SizedBox(height: 16),
              _RemainingTime(controller: controller),
              const SizedBox(height: 28),
              TvSettingsFocusSurface(
                key: const ValueKey<String>('tv-pairing-cancel-focus'),
                autofocus: true,
                onPressed: onCancel,
                child: OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close),
                  label: const Text('取消配对'),
                ),
              ),
            ],
          ),
        ),
      );
}

class _RemainingTime extends StatelessWidget {
  const _RemainingTime({required this.controller});

  final TvPairingController controller;

  @override
  Widget build(BuildContext context) {
    final seconds = controller.remaining.inSeconds.clamp(0, 5 * 60);
    final minutesText = (seconds ~/ 60).toString().padLeft(2, '0');
    final secondsText = (seconds % 60).toString().padLeft(2, '0');
    return Text(
      '$minutesText:$secondsText',
      key: const ValueKey<String>('tv-pairing-countdown'),
      style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}

class _PairingResultView extends StatelessWidget {
  const _PairingResultView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon,
                  size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 28),
              Wrap(
                spacing: 12,
                children: <Widget>[
                  TvSettingsFocusSurface(
                    key: const ValueKey<String>(
                        'tv-pairing-result-primary-focus'),
                    autofocus: true,
                    onPressed: onPrimary,
                    child: FilledButton(
                      onPressed: onPrimary,
                      child: Text(primaryLabel),
                    ),
                  ),
                  if (secondaryLabel != null && onSecondary != null)
                    TvSettingsFocusSurface(
                      key: const ValueKey<String>(
                          'tv-pairing-result-secondary-focus'),
                      onPressed: onSecondary!,
                      child: OutlinedButton(
                        onPressed: onSecondary,
                        child: Text(secondaryLabel!),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
}
