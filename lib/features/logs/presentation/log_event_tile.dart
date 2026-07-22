import 'package:flutter/material.dart';

import 'log_event_view_data.dart';
import 'log_motion.dart';

class LogEventTile extends StatelessWidget {
  const LogEventTile({
    super.key,
    required this.event,
    required this.expanded,
    required this.onToggle,
  });

  final LogEventViewData event;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = switch (event.category) {
      LogEventCategory.warning => colors.tertiary,
      LogEventCategory.error => colors.error,
      LogEventCategory.normal => colors.primary,
      LogEventCategory.other => colors.onSurfaceVariant,
    };

    return Semantics(
      button: true,
      expanded: expanded,
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 7),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.summary,
                            maxLines: expanded ? null : 2,
                            overflow: expanded ? null : TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                _levelLabel(event.level),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _formatTime(event.timestamp),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: LogMotion.duration(
                        context,
                        LogMotion.expandDuration,
                      ),
                      curve: LogMotion.curve,
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: LogMotion.duration(
                    context,
                    LogMotion.expandDuration,
                  ),
                  curve: LogMotion.curve,
                  alignment: Alignment.topCenter,
                  child: expanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHighest.withValues(
                                alpha: 0.58,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectionArea(
                              child: Text(
                                event.rawText,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  height: 1.5,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime? timestamp) {
    if (timestamp == null) return '时间未知';
    final local = timestamp.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  static String _levelLabel(String level) => switch (level) {
        'WARNING' => '提醒',
        'ERROR' || 'FATAL' => '错误',
        'PLAYER' => '播放器',
        'OTHER' => '其他',
        _ => '普通',
      };
}
