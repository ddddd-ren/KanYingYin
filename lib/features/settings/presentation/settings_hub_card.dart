import 'package:flutter/material.dart';
import 'package:kanyingyin/features/settings/presentation/settings_motion.dart';

abstract final class SettingsHubLayout {
  static int columnCountFor(double width) {
    if (width >= 1180) return 3;
    if (width >= 760) return 2;
    return 1;
  }
}

/// 设置控制中心功能卡。
class SettingsHubCard extends StatefulWidget {
  const SettingsHubCard({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    required this.onPressed,
    this.status,
    this.featured = false,
  });

  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onPressed;
  final String? status;
  final bool featured;

  @override
  State<SettingsHubCard> createState() => _SettingsHubCardState();
}

class _SettingsHubCardState extends State<SettingsHubCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduced = SettingsMotion.isReduced(context);
    final scale = reduced
        ? 1.0
        : (_pressed
            ? 0.99
            : _hovered
                ? 1.012
                : 1.0);
    final offset = reduced || !_hovered || _pressed ? 0.0 : -3.0;
    return MergeSemantics(
      child: Semantics(
        container: true,
        button: true,
        onTap: widget.onPressed,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: AnimatedSlide(
            offset: Offset(0, offset / 180),
            duration: SettingsMotion.duration(
              context,
              SettingsMotion.hoverDuration,
            ),
            curve: SettingsMotion.hoverCurve,
            child: AnimatedScale(
              scale: scale,
              duration: SettingsMotion.duration(
                context,
                _pressed
                    ? SettingsMotion.pressDuration
                    : SettingsMotion.hoverDuration,
              ),
              curve: SettingsMotion.hoverCurve,
              child: AnimatedContainer(
                duration: SettingsMotion.duration(
                  context,
                  SettingsMotion.hoverDuration,
                ),
                curve: SettingsMotion.hoverCurve,
                decoration: BoxDecoration(
                  gradient: widget.featured
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.primaryContainer.withValues(alpha: 0.55),
                            scheme.surfaceContainerLow,
                          ],
                        )
                      : null,
                  color: widget.featured ? null : scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _hovered
                        ? scheme.primary.withValues(alpha: 0.78)
                        : scheme.outlineVariant.withValues(alpha: 0.62),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(
                        alpha: _hovered ? 0.16 : 0.07,
                      ),
                      blurRadius: _hovered ? 28 : 16,
                      offset: Offset(0, _hovered ? 12 : 6),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.onPressed,
                    onHighlightChanged: (value) =>
                        setState(() => _pressed = value),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  widget.icon,
                                  color: scheme.onPrimaryContainer,
                                ),
                              ),
                              const Spacer(),
                              if (widget.status != null)
                                Text(
                                  widget.status!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            widget.eyebrow,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            widget.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                '进入',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 16,
                                color: scheme.primary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
