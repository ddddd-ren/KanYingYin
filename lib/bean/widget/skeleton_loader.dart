import 'package:flutter/material.dart';

/// 骨架屏加载组件，提供平滑的Shimmer动画效果
/// 适用场景：媒体库加载、海报刮削、TMDB匹配
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.duration = const Duration(milliseconds: 1500),
    this.enabled = true,
  });

  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration duration;
  final bool enabled;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStartAnimation();
  }

  @override
  void didUpdateWidget(SkeletonLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.enabled != widget.enabled) {
      _maybeStartAnimation();
    }
  }

  void _maybeStartAnimation() {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.enabled && !disableAnimations) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseColor = widget.baseColor ??
        colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    final highlightColor = widget.highlightColor ??
        colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: [
                _controller.value - 0.3,
                _controller.value,
                _controller.value + 0.3,
              ].map((v) => v.clamp(0.0, 1.0)).toList(),
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

/// 媒体卡片骨架屏
class MediaCardSkeleton extends StatelessWidget {
  const MediaCardSkeleton({
    super.key,
    this.width = 260,
    this.height = 380,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final skeletonColor = colorScheme.surfaceContainerHigh;

    return SkeletonLoader(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: skeletonColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: skeletonColor.withValues(alpha: 0.7),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: width * 0.7,
                    height: 16,
                    decoration: BoxDecoration(
                      color: skeletonColor.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: width * 0.5,
                    height: 14,
                    decoration: BoxDecoration(
                      color: skeletonColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 列表项骨架屏
class ListTileSkeleton extends StatelessWidget {
  const ListTileSkeleton({
    super.key,
    this.showAvatar = true,
    this.showSubtitle = true,
  });

  final bool showAvatar;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final skeletonColor = colorScheme.surfaceContainerHigh;

    return SkeletonLoader(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (showAvatar)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: skeletonColor,
                  shape: BoxShape.circle,
                ),
              ),
            if (showAvatar) const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: skeletonColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  if (showSubtitle) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: 200,
                      height: 14,
                      decoration: BoxDecoration(
                        color: skeletonColor.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
