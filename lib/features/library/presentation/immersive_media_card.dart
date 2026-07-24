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
    final overlayVisible =
        widget.overlayMode == ImmersiveMediaCardOverlayMode.always || _hovered;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onSecondaryTap: widget.onSecondaryTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.cover,
              AnimatedOpacity(
                opacity: overlayVisible ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: _buildOverlay(context),
              ),
              if (_hovered)
                IgnorePointer(
                  child: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
              if (widget.loading)
                IgnorePointer(
                  child: ColoredBox(
                    color: colors.scrim.withValues(alpha: 0.34),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              if (widget.trailing != null)
                Positioned(top: 4, right: 4, child: widget.trailing!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.2),
            Colors.black.withValues(alpha: 0.82),
          ],
          stops: const [0, 0.42, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.15,
                shadows: const <Shadow>[
                  Shadow(color: Colors.black54, blurRadius: 4),
                ],
              ),
            ),
            if (widget.subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (widget.details.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                widget.details,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.78),
                  height: 1.25,
                ),
              ),
            ],
            if (widget.badges.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.badges
                    .map((badge) => _buildBadge(context, badge))
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(
    BuildContext context,
    ImmersiveMediaCardBadge badge,
  ) {
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge.loading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: Colors.white,
                ),
              )
            else
              Icon(badge.icon, size: 13, color: Colors.white),
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
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: content,
      ),
    );
  }
}
