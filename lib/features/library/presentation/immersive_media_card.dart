import 'package:flutter/material.dart';
import 'package:kanyingyin/bean/widget/glass_surface.dart';
import 'package:kanyingyin/features/library/application/media_technical_badges.dart';
import 'package:kanyingyin/features/tv/presentation/tv_focus_surface.dart';

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
    this.technicalBadges = const <MediaTechnicalBadge>[],
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
  final List<MediaTechnicalBadge> technicalBadges;
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
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final overlayVisible =
        widget.overlayMode == ImmersiveMediaCardOverlayMode.always ||
            _hovered ||
            _focused;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: TvFocusSurface(
        enabled: widget.onTap != null && !widget.loading,
        onPressed: widget.onTap,
        reserveFocusSpace: false,
        onFocusChange: (focused) {
          if (mounted) setState(() => _focused = focused);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
          child: Focus(
            canRequestFocus: false,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12), // 从 8 增加到 12
              clipBehavior: Clip.antiAlias,
              elevation: _hovered ? 8 : 0,
              shadowColor: colors.shadow.withValues(alpha: 0.3),
              child: InkWell(
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                onSecondaryTap: widget.onSecondaryTap,
                canRequestFocus: false,
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
                          child:
                              const Center(child: CircularProgressIndicator()),
                        ),
                      ),
                    if (widget.technicalBadges.isNotEmpty)
                      Positioned(
                        left: 10,
                        top: 10,
                        right: widget.trailing == null ? 10 : 42,
                        child: IgnorePointer(
                          child: MediaTechnicalBadgeRow(
                            key: const ValueKey(
                              'media-technical-badges-poster',
                            ),
                            badges: widget.technicalBadges,
                            poster: true,
                          ),
                        ),
                      ),
                    if (widget.trailing != null)
                      Positioned(top: 4, right: 4, child: widget.trailing!),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.3),
                Colors.black.withValues(alpha: 0.88), // 从 0.82 增强到 0.88
              ],
              stops: const [0, 0.38, 1], // 从 [0, 0.42, 1] 调整
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10), // 从 8 增加到 10
            child: SizedBox(
              width: double.infinity,
              child: GlassSurface(
                borderRadius: BorderRadius.circular(10),
                blurSigma: 12, // 从 10 增加到 12
                color: Colors.black.withValues(alpha: 0.32), // 从 0.28 增强到 0.32
                border: Border.all(
                  color:
                      Colors.white.withValues(alpha: 0.18), // 从 0.16 增强到 0.18
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      12, 10, 12, 12), // 从 (10,8,10,10) 调整
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleLarge?.copyWith(
                          // 从 titleMedium 升级到 titleLarge
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          height: 1.2, // 从 1.15 调整到 1.2
                          fontSize: 16, // 明确设置字号
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
                            height: 1.3, // 从 1.25 调整到 1.3
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
              ),
            ),
          ),
        ),
      ],
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

class MediaTechnicalBadgeRow extends StatelessWidget {
  const MediaTechnicalBadgeRow({
    super.key,
    required this.badges,
    this.poster = false,
  });

  final List<MediaTechnicalBadge> badges;
  final bool poster;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final badge in badges)
          DecoratedBox(
            key: ValueKey('media-technical-badge-${badge.label}'),
            decoration: BoxDecoration(
              color: _color(badge.kind),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.24),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: poster ? 7 : 6,
                vertical: poster ? 4 : 3,
              ),
              child: Text(
                badge.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
              ),
            ),
          ),
      ],
    );
  }

  Color _color(MediaTechnicalBadgeKind kind) => switch (kind) {
        MediaTechnicalBadgeKind.resolution => const Color(0xE64338CA),
        MediaTechnicalBadgeKind.source => const Color(0xE647556B),
        MediaTechnicalBadgeKind.codec => const Color(0xE65B21B6),
        MediaTechnicalBadgeKind.bitrate => const Color(0xE6774B1B),
        MediaTechnicalBadgeKind.dolbyVision => const Color(0xE66D28D9),
        MediaTechnicalBadgeKind.hdr => const Color(0xE69A3412),
        MediaTechnicalBadgeKind.dolbyAtmos => const Color(0xE6036991),
        MediaTechnicalBadgeKind.audio => const Color(0xE616766E),
        MediaTechnicalBadgeKind.subtitles => const Color(0xE6654A1F),
        MediaTechnicalBadgeKind.frameRate => const Color(0xE64B5563),
        MediaTechnicalBadgeKind.bitDepth => const Color(0xE64D7C0F),
        MediaTechnicalBadgeKind.edition => const Color(0xE67C2D12),
        MediaTechnicalBadgeKind.releaseGroup => const Color(0xE64C1D95),
      };
}
