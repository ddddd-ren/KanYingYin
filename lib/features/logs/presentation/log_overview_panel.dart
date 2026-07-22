import 'package:flutter/material.dart';

class LogOverviewPanel extends StatelessWidget {
  const LogOverviewPanel({
    super.key,
    required this.total,
    required this.warnings,
    required this.errors,
  });

  final int total;
  final int warnings;
  final int errors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, title, accent) = switch ((errors, warnings)) {
      (> 0, _) => (
          Icons.error_outline_rounded,
          '发现需要关注的问题',
          colors.error,
        ),
      (0, > 0) => (
          Icons.warning_amber_rounded,
          '有少量运行提醒',
          colors.tertiary,
        ),
      _ => (Icons.check_circle_outline_rounded, '运行状态良好', colors.primary),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 21),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _LogMetric(label: '全部', value: total),
          _LogMetric(label: '提醒', value: warnings),
          _LogMetric(label: '错误', value: errors),
        ],
      ),
    );
  }
}

class _LogMetric extends StatelessWidget {
  const _LogMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
