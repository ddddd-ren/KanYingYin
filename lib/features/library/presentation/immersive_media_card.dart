import 'package:flutter/material.dart';

enum ImmersiveMediaCardOverlayMode { hover, always }

class ImmersiveMediaCardBadge {
  const ImmersiveMediaCardBadge({
    required this.icon,
    required this.label,
    this.loading = false,
    this.key,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool loading;
  final Key? key;
  final VoidCallback? onTap;
}

/// 统一的媒体库卡片。海报负责吸引注意，标题和关键信息始终可读。
class ImmersiveMediaCard extends StatefulWidget {
  const ImmersiveMediaCard({
    super.key,
    required this.cover,
    required this.title,
    required this.overlayMode,
    this.subtitle = '',
    this.details = '',
    this.badges = const <ImmersiveMediaCardBadge>[],
    this.trailing,
    this.loading = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
  });

  final Widget cover;
  final String title;
  final String subtitle;
  final String details;
  final List<ImmersiveMediaCardBadge> badges;
  final Widget? trailing;
  final bool loading;
  final ImmersiveMediaCardOverlayMode overlayMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  @override
  State<ImmersiveMediaCard> createState() => _ImmersiveMediaCardState();
}

class _ImmersiveMediaCardState extends State<ImmersiveMediaCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hoverActionsVisible =
        widget.overlayMode == ImmersiveMediaCardOverlayMode.always || _hovered;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _hovered
                ? colors.primary.withValues(alpha: 0.55)
                : colors.outlineVariant.withValues(alpha: 0.42),
          ),
          boxShadow: _hovered
              ? <BoxShadow>[
                  BoxShadow(
                    color: colors.shadow.withValues(alpha: 0.22),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onSecondaryTap: widget.onSecondaryTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: _poster(context, hoverActionsVisible),
                ),
                Expanded(child: _metadata(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _poster(BuildContext context, bool hoverActionsVisible) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.cover,
        if (widget.badges.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 72,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.78)
                  ],
                ),
              ),
            ),
          ),
        if (widget.badges.isNotEmpty)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: widget.badges
                  .take(2)
                  .map((badge) => _buildBadge(context, badge))
                  .toList(growable: false),
            ),
          ),
        Center(
          child: IgnorePointer(
            ignoring: !hoverActionsVisible,
            child: AnimatedOpacity(
              key: const ValueKey<String>('media-card-hover-actions'),
              opacity: hoverActionsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.38),
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 30,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.loading)
          IgnorePointer(
            child: ColoredBox(
              color: colors.scrim.withValues(alpha: 0.46),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
        if (widget.trailing != null)
          Positioned(top: 5, right: 5, child: widget.trailing!),
      ],
    );
  }

  Widget _metadata(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasSubtitle = widget.subtitle.trim().isNotEmpty;
    final hasDetails = widget.details.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w600,
              height: 1.22,
            ),
          ),
          if (hasSubtitle || hasDetails) ...[
            const Spacer(),
            Row(
              children: [
                if (hasSubtitle)
                  Expanded(
                    flex: hasDetails ? 3 : 1,
                    child: Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                  ),
                if (hasSubtitle && hasDetails) const SizedBox(width: 6),
                if (hasDetails)
                  Expanded(
                    flex: hasSubtitle ? 2 : 1,
                    child: Text(
                      widget.details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: hasSubtitle ? TextAlign.end : TextAlign.start,
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge(
    BuildContext context,
    ImmersiveMediaCardBadge badge,
  ) {
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge.loading)
              const SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: Colors.white,
                ),
              )
            else
              Icon(badge.icon, size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              badge.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
    final onTap = badge.onTap;
    if (onTap == null) return content;
    return Material(
      key: badge.key,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: content,
      ),
    );
  }
}
