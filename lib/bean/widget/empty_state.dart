import 'package:flutter/material.dart';

/// 空状态组件，用于显示无数据、搜索无结果、操作失败等场景
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
    this.actionLabel,
    this.actionIcon,
    this.iconSize = 80,
  });

  final IconData icon;
  final String title;
  final String? description;
  final VoidCallback? action;
  final String? actionLabel;
  final IconData? actionIcon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: iconSize,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              if (description != null) ...[
                const SizedBox(height: 12),
                Text(
                  description!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null && actionLabel != null) ...[
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: action,
                  icon: Icon(actionIcon ?? Icons.add_circle_outline),
                  label: Text(actionLabel!),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 预定义的空状态场景
class EmptyStates {
  EmptyStates._();

  /// 无媒体源
  static Widget noMediaSources({
    required VoidCallback onAddSource,
  }) =>
      EmptyState(
        icon: Icons.video_library_outlined,
        title: '暂无媒体源',
        description: '添加本地文件夹或网盘账号，开始构建您的媒体库',
        action: onAddSource,
        actionLabel: '添加媒体源',
        actionIcon: Icons.add_circle_outline,
      );

  /// 搜索无结果
  static Widget noSearchResults({
    required String query,
  }) =>
      EmptyState(
        icon: Icons.search_off_outlined,
        title: '未找到"$query"',
        description: '尝试使用不同的关键词或检查拼写',
      );

  /// 扫描失败
  static Widget scanFailed({
    required VoidCallback onRetry,
  }) =>
      EmptyState(
        icon: Icons.error_outline,
        title: '扫描失败',
        description: '无法访问媒体源，请检查路径是否正确或网络连接',
        action: onRetry,
        actionLabel: '重新扫描',
        actionIcon: Icons.refresh,
      );

  /// 网络错误
  static Widget networkError({
    VoidCallback? onRetry,
  }) =>
      EmptyState(
        icon: Icons.cloud_off_outlined,
        title: '网络连接失败',
        description: '无法连接到服务器，请检查网络设置',
        action: onRetry,
        actionLabel: onRetry != null ? '重试' : null,
        actionIcon: Icons.refresh,
      );

  /// 空目录
  static Widget emptyDirectory() => const EmptyState(
        icon: Icons.folder_open_outlined,
        title: '此目录为空',
        description: '该文件夹中没有可识别的媒体文件',
      );

  /// 无观看历史
  static Widget noHistory() => const EmptyState(
        icon: Icons.history_outlined,
        title: '暂无观看记录',
        description: '您的观看历史将会显示在这里',
      );

  /// 无收藏
  static Widget noFavorites() => const EmptyState(
        icon: Icons.favorite_border_outlined,
        title: '暂无收藏',
        description: '收藏喜欢的影片，方便随时观看',
      );

  /// 加载失败
  static Widget loadFailed({
    required String message,
    VoidCallback? onRetry,
  }) =>
      EmptyState(
        icon: Icons.refresh_outlined,
        title: '加载失败',
        description: message,
        action: onRetry,
        actionLabel: onRetry != null ? '重试' : null,
        actionIcon: Icons.refresh,
      );
}
