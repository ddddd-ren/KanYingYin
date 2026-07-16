import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/services/local_subtitle_importer.dart';
import 'package:kanyingyin/utils/utils.dart';
import 'package:path/path.dart' as p;

class SubtitleSettingsOverlay extends StatelessWidget {
  const SubtitleSettingsOverlay({
    super.key,
    required this.playerController,
    required this.onClose,
    required this.onPickSubtitle,
    required this.onImportSubtitle,
  });

  final PlayerController playerController;
  final VoidCallback onClose;
  final Future<void> Function() onPickSubtitle;
  final Future<void> Function(LocalSubtitleImportTarget target)
      onImportSubtitle;

  static const _colorOptions = <Color>[
    Colors.white,
    Color(0xfffff3a3),
    Color(0xffa7f3d0),
    Color(0xff93c5fd),
    Color(0xfff9a8d4),
    Colors.black,
  ];

  static const _borderColorOptions = <Color>[
    Colors.black,
    Color(0xff1f2937),
    Color(0xff7f1d1d),
    Color(0xff172554),
    Colors.white,
  ];

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = MediaQuery.sizeOf(context);
          final isWide = Utils.isDesktop() && size.width >= 1320;
          final desktopMaxWidth =
              (size.width * 0.32).clamp(420.0, 480.0).toDouble();
          final panelWidth = isWide
              ? 440.0.clamp(420.0, desktopMaxWidth).toDouble()
              : (size.width - 24).clamp(280.0, 480.0).toDouble();
          final targetMaxHeight = isWide ? 520.0 : size.height * 0.7;
          final availableHeight = constraints.maxHeight <= 112
              ? constraints.maxHeight
              : (constraints.maxHeight - 112)
                  .clamp(0.0, targetMaxHeight)
                  .toDouble();
          final desktopTopLimit = constraints.maxHeight - availableHeight - 88;
          final top = isWide
              ? ((constraints.maxHeight - availableHeight) / 2 + 24)
                  .clamp(24.0, desktopTopLimit < 24 ? 24.0 : desktopTopLimit)
                  .toDouble()
              : null;

          return Stack(
            children: [
              if (isWide)
                Positioned(
                  right: 24,
                  top: top,
                  child: _buildPanel(context, panelWidth, availableHeight),
                )
              else
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 88,
                  child: _buildPanel(context, panelWidth, availableHeight),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPanel(BuildContext context, double width, double maxHeight) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.86),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(
            listTileTheme: const ListTileThemeData(
              iconColor: Colors.white,
              textColor: Colors.white,
            ),
            dividerColor: Colors.white24,
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Theme.of(context).colorScheme.primary;
                }
                return Colors.white70;
              }),
            ),
            sliderTheme: SliderTheme.of(context).copyWith(
              inactiveTrackColor: Colors.white24,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          child: Observer(builder: (context) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              shrinkWrap: true,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '字幕设置',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: onClose,
                      color: Colors.white,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _SubtitleSectionTitle(title: '当前字幕状态'),
                ListTile(
                  leading: Icon(
                    playerController.currentSubtitlePath.isEmpty
                        ? Icons.closed_caption_disabled_outlined
                        : Icons.closed_caption_rounded,
                  ),
                  title: Text(
                    playerController.currentSubtitlePath.isEmpty
                        ? '未加载字幕'
                        : p.basename(playerController.currentSubtitlePath),
                  ),
                  subtitle: const Text(
                    '如果关闭字幕后画面仍有字幕，可能是视频自带画面字幕',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                if (playerController.currentSubtitlePath.isEmpty &&
                    playerController.lastSubtitlePath.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.closed_caption_outlined),
                    title: const Text('重新开启上次字幕'),
                    subtitle: Text(
                      p.basename(playerController.lastSubtitlePath),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    onTap: () async {
                      final loaded =
                          await playerController.restoreLastSubtitle();
                      AppDialog.showToast(
                          message: loaded ? '字幕已重新开启' : '字幕重新开启失败');
                    },
                  ),
                if (playerController.isLocalPlayback) ...[
                  ListTile(
                    leading: const Icon(Icons.subtitles_off_outlined),
                    title: const Text('关闭字幕'),
                    subtitle: Text(
                      playerController.currentSubtitlePath.isEmpty
                          ? '当前未加载字幕'
                          : p.basename(playerController.currentSubtitlePath),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    onTap: () async {
                      await playerController.clearSubtitle();
                      AppDialog.showToast(message: '字幕已关闭');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.file_open_outlined),
                    title: const Text('手动选择字幕'),
                    subtitle: const Text(
                      '支持 ass / ssa / srt / vtt',
                      style: TextStyle(color: Colors.white70),
                    ),
                    onTap: onPickSubtitle,
                  ),
                  ListTile(
                    leading: const Icon(Icons.drive_folder_upload_outlined),
                    title: const Text('导入到“字幕”文件夹'),
                    subtitle: const Text(
                      '按当前视频文件名保存，方便下次自动识别',
                      style: TextStyle(color: Colors.white70),
                    ),
                    onTap: () => onImportSubtitle(
                      LocalSubtitleImportTarget.subtitleDirectory,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.create_new_folder_outlined),
                    title: const Text('导入到视频目录'),
                    subtitle: const Text(
                      '适合希望字幕与视频放在一起的目录',
                      style: TextStyle(color: Colors.white70),
                    ),
                    onTap: () => onImportSubtitle(
                      LocalSubtitleImportTarget.videoDirectory,
                    ),
                  ),
                  const Divider(),
                  _SubtitleSectionTitle(title: '附近字幕列表'),
                  if (playerController.subtitleCandidates.isEmpty)
                    const ListTile(
                      title: Text('未找到可用字幕'),
                      subtitle: Text(
                        '可手动选择或导入 ass / ssa / srt / vtt 字幕',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  else
                    for (final path in playerController.subtitleCandidates)
                      ListTile(
                        leading: Icon(
                          path == playerController.currentSubtitlePath
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text(
                          p.basename(path),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          p.dirname(path),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        onTap: () async {
                          final loaded =
                              await playerController.selectSubtitle(path);
                          AppDialog.showToast(
                              message: loaded ? '字幕已加载' : '字幕加载失败');
                        },
                      ),
                ] else ...[
                  ListTile(
                    leading: const Icon(Icons.file_open_outlined),
                    title: const Text('选择外部字幕'),
                    subtitle: const Text(
                      '支持 ass / ssa / srt / vtt',
                      style: TextStyle(color: Colors.white70),
                    ),
                    onTap: onPickSubtitle,
                  ),
                  ListTile(
                    leading: const Icon(Icons.subtitles_off_outlined),
                    title: const Text('关闭字幕'),
                    subtitle: Text(
                      playerController.currentSubtitlePath.isEmpty
                          ? '当前未加载字幕'
                          : p.basename(playerController.currentSubtitlePath),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    onTap: () async {
                      await playerController.clearSubtitle();
                      AppDialog.showToast(message: '字幕已关闭');
                    },
                  ),
                ],
                const Divider(),
                _buildTimingControls(context),
                const Divider(),
                _buildStyleControls(context),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildTimingControls(BuildContext context) {
    final delay = playerController.subtitleDelaySeconds;
    final label = delay < 0
        ? '提前 ${delay.abs().toStringAsFixed(1)} 秒'
        : delay > 0
            ? '延后 ${delay.toStringAsFixed(1)} 秒'
            : '同步';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SubtitleSectionTitle(title: '字幕时间'),
        _SubtitleSlider(
          title: '出现时间',
          value: delay,
          min: -30,
          max: 30,
          divisions: 120,
          label: label,
          onChanged: playerController.setSubtitleDelay,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              IconButton(
                tooltip: '字幕提前 0.5 秒',
                icon: const Icon(Icons.fast_rewind_rounded),
                onPressed: delay <= -30
                    ? null
                    : () => playerController.setSubtitleDelay(delay - 0.5),
              ),
              IconButton(
                tooltip: '字幕延后 0.5 秒',
                icon: const Icon(Icons.fast_forward_rounded),
                onPressed: delay >= 30
                    ? null
                    : () => playerController.setSubtitleDelay(delay + 0.5),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed:
                    delay == 0 ? null : playerController.resetSubtitleDelay,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('重置'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStyleControls(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SubtitleSectionTitle(title: '字幕样式设置'),
        SwitchListTile(
          title: const Text('强制套用样式'),
          subtitle: const Text(
            'ASS / SSA 字幕默认保留原样式，开启后使用下方设置覆盖',
            style: TextStyle(color: Colors.white70),
          ),
          value: playerController.subtitleForceStyle,
          onChanged: (value) =>
              playerController.applySubtitleStyle(forceStyle: value),
        ),
        _SubtitleSlider(
          title: '字号',
          value: playerController.subtitleFontSize,
          min: 18,
          max: 72,
          divisions: 54,
          label: playerController.subtitleFontSize.toStringAsFixed(0),
          onChanged: (value) =>
              playerController.applySubtitleStyle(fontSize: value),
        ),
        _SubtitleSlider(
          title: '位置',
          value: playerController.subtitlePosition,
          min: 60,
          max: 100,
          divisions: 40,
          label: '${playerController.subtitlePosition.toStringAsFixed(0)}%',
          onChanged: (value) =>
              playerController.applySubtitleStyle(position: value),
        ),
        const SizedBox(height: 8),
        _ColorChooser(
          title: '文字颜色',
          colors: _colorOptions,
          selectedColor: Color(playerController.subtitleColorValue),
          onSelected: (color) => playerController.applySubtitleStyle(
            colorValue: color.toARGB32(),
          ),
        ),
        const SizedBox(height: 12),
        _ColorChooser(
          title: '描边颜色',
          colors: _borderColorOptions,
          selectedColor: Color(playerController.subtitleBorderColorValue),
          onSelected: (color) => playerController.applySubtitleStyle(
            borderColorValue: color.toARGB32(),
          ),
        ),
        _SubtitleSlider(
          title: '描边粗细',
          value: playerController.subtitleBorderSize,
          min: 0,
          max: 8,
          divisions: 16,
          label: playerController.subtitleBorderSize.toStringAsFixed(1),
          onChanged: (value) =>
              playerController.applySubtitleStyle(borderSize: value),
        ),
        SwitchListTile(
          title: const Text('阴影'),
          value: playerController.subtitleShadowEnabled,
          onChanged: (value) =>
              playerController.applySubtitleStyle(shadowEnabled: value),
        ),
        _SubtitleSlider(
          title: '阴影偏移',
          value: playerController.subtitleShadowOffset,
          min: 0,
          max: 8,
          divisions: 16,
          label: playerController.subtitleShadowOffset.toStringAsFixed(1),
          onChanged: playerController.subtitleShadowEnabled
              ? (value) =>
                  playerController.applySubtitleStyle(shadowOffset: value)
              : null,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: playerController.resetSubtitleStyle,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('恢复默认'),
          ),
        ),
      ],
    );
  }
}

class _SubtitleSectionTitle extends StatelessWidget {
  const _SubtitleSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SubtitleSlider extends StatelessWidget {
  const _SubtitleSlider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Slider(
        value: value.clamp(min, max).toDouble(),
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
      ),
      trailing: SizedBox(
        width: 48,
        child: Text(
          label,
          textAlign: TextAlign.end,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

class _ColorChooser extends StatelessWidget {
  const _ColorChooser({
    required this.title,
    required this.colors,
    required this.selectedColor,
    required this.onSelected,
  });

  final String title;
  final List<Color> colors;
  final Color selectedColor;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(title, style: const TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in colors)
                  Tooltip(
                    message: _colorLabel(color),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onSelected(color),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          border: Border.all(
                            color: color.toARGB32() == selectedColor.toARGB32()
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white38,
                            width: color.toARGB32() == selectedColor.toARGB32()
                                ? 3
                                : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _colorLabel(Color color) {
    if (color.toARGB32() == Colors.white.toARGB32()) return '白色';
    if (color.toARGB32() == Colors.black.toARGB32()) return '黑色';
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }
}
