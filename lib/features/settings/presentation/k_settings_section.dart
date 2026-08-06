import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/widget/glass_surface.dart';

/// 设置项语义分区。
class KSettingsSection extends StatelessWidget {
  const KSettingsSection({
    super.key,
    this.title,
    this.description,
    this.bottomInfo,
    required this.tiles,
  });

  final Widget? title;
  final Widget? description;
  final Widget? bottomInfo;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null || description != null)
          Padding(
            padding:
                const EdgeInsets.fromLTRB(12, 0, 12, 12), // 从 (10,0,10,9) 调整
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  DefaultTextStyle.merge(
                    style: theme.textTheme.titleMedium?.copyWith(
                      // 从 labelLarge 升级到 titleMedium
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15, // 明确设置字号
                      letterSpacing: 0.2, // 添加字间距
                    ),
                    child: title!,
                  ),
                if (description != null) ...[
                  const SizedBox(height: 6), // 从 4 增加到 6
                  DefaultTextStyle.merge(
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5, // 添加行高
                    ),
                    child: description!,
                  ),
                ],
              ],
            ),
          ),
        GlassSurface(
          borderRadius: BorderRadius.circular(16), // 从 14 增加到 16
          blurSigma: 20, // 从 16 增加到 20（使用标准中度模糊）
          color: scheme.surfaceContainerLow
              .withValues(alpha: 0.68), // 从 0.62 增加到 0.68
          border: Border.all(
            color: scheme.outlineVariant
                .withValues(alpha: 0.52), // 从 0.62 调整到 0.52
            width: 1.2, // 添加边框宽度
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.08), // 从 0.06 增加到 0.08
              blurRadius: 24, // 从 18 增加到 24
              offset: const Offset(0, 8), // 从 (0,6) 调整到 (0,8)
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < tiles.length; index++) ...[
                tiles[index],
                if (index != tiles.length - 1)
                  Divider(
                    height: 1,
                    indent: 64,
                    color: scheme.outlineVariant
                        .withValues(alpha: 0.4), // 从 0.5 降低到 0.4
                  ),
              ],
            ],
          ),
        ),
        if (bottomInfo != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: DefaultTextStyle.merge(
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              child: bottomInfo!,
            ),
          ),
      ],
    );
  }
}
