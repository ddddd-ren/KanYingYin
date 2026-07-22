import 'package:flutter/material.dart';

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
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  DefaultTextStyle.merge(
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                    child: title!,
                  ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  DefaultTextStyle.merge(
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    child: description!,
                  ),
                ],
              ],
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.62),
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < tiles.length; index++) ...[
                  tiles[index],
                  if (index != tiles.length - 1)
                    Divider(
                      height: 1,
                      indent: 64,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                ],
              ],
            ),
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
