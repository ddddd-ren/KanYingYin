import 'package:flutter/material.dart';
import 'package:kanyingyin/features/tv/presentation/tv_focus_surface.dart';

class TvEpisodeTileSurface extends StatelessWidget {
  const TvEpisodeTileSurface({
    super.key,
    required this.child,
    required this.onPressed,
    this.autofocus = false,
    this.current = false,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback onPressed;
  final bool autofocus;
  final bool current;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TvFocusSurface(
      autofocus: autofocus,
      focusNode: focusNode,
      focusedScale: 1.02,
      focusBorderWidth: 3,
      reserveFocusSpace: false,
      onPressed: onPressed,
      child: DecoratedBox(
        key: current
            ? const ValueKey<String>('tv-current-episode-surface')
            : null,
        decoration: BoxDecoration(
          color: current
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: current
              ? Border.all(
                  color: colors.primary.withValues(alpha: 0.78),
                  width: 1,
                )
              : null,
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(
                top: current ? 26 : 0,
                right: current ? 8 : 0,
              ),
              child: child,
            ),
            if (current)
              Positioned(
                top: 4,
                right: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      '正在播放',
                      style: TextStyle(
                        color: colors.onPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
