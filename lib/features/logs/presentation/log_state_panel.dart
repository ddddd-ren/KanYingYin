import 'package:flutter/material.dart';

enum LogStateKind { loading, empty, noResults, error }

class LogStatePanel extends StatelessWidget {
  const LogStatePanel({super.key, required this.kind});

  final LogStateKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, title, description) = switch (kind) {
      LogStateKind.loading => (
          Icons.hourglass_top_rounded,
          '正在读取运行记录',
          '正在整理最近的应用事件',
        ),
      LogStateKind.empty => (
          Icons.receipt_long_outlined,
          '暂无运行记录',
          '应用产生新的运行事件后会显示在这里',
        ),
      LogStateKind.noResults => (
          Icons.search_off_rounded,
          '没有匹配的记录',
          '可以更换关键词或选择其他等级',
        ),
      LogStateKind.error => (
          Icons.error_outline_rounded,
          '加载运行记录失败',
          '日志文件暂时无法读取，请稍后重新进入',
        ),
    };

    return Center(
      child: Container(
        key: ValueKey('log-state-${kind.name}'),
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 30),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (kind == LogStateKind.loading)
              const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              Icon(icon, size: 30, color: colors.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
