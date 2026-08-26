import 'package:flutter/material.dart';

const double posterAspectRatio = 2 / 3;
const double posterDarkScale = 1.06;

class PosterCover extends StatelessWidget {
  const PosterCover({
    super.key,
    required this.child,
  });

  const PosterCover.placeholder({super.key}) : child = null;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final image = child;
    if (image == null) {
      final colors = Theme.of(context).colorScheme;
      return ColoredBox(
        key: const ValueKey<String>('poster-cover-placeholder'),
        color: colors.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.movie_outlined,
            size: 32,
            color: colors.outline,
          ),
        ),
      );
    }
    if (Theme.of(context).brightness != Brightness.dark) return image;
    return ClipRect(
      child: Transform.scale(
        scale: posterDarkScale,
        child: image,
      ),
    );
  }
}
