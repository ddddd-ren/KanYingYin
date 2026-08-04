import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 统一的毛玻璃表面，负责裁剪、背景模糊、半透明色和细边框。
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.color,
    this.border,
    this.boxShadow,
    this.blurSigma = 18,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? color;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;
  final double blurSigma;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decoration = BoxDecoration(
      color: color ?? scheme.surfaceContainerHigh.withValues(alpha: 0.68),
      border: border ??
          Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.42),
          ),
      boxShadow: boxShadow,
    );
    Widget surface = DecoratedBox(
      decoration: decoration,
      child: child,
    );
    if (blurSigma > 0) {
      surface = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: surface,
      );
    }
    return ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: clipBehavior,
      child: surface,
    );
  }
}

/// 毛玻璃对话框容器，内容区域由调用方自行决定尺寸和滚动方式。
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    super.key,
    required this.child,
    this.insetPadding = const EdgeInsets.all(40),
  });

  final Widget child;
  final EdgeInsets insetPadding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: scheme.shadow.withValues(alpha: 0.28),
      elevation: 0,
      insetPadding: insetPadding,
      clipBehavior: Clip.antiAlias,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(12),
        blurSigma: 24,
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.48),
        ),
        child: child,
      ),
    );
  }
}
