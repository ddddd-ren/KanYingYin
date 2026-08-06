import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 统一的毛玻璃表面，负责裁剪、背景模糊、半透明色和细边框。
/// 标准化模糊参数：轻度模糊 10，中度 20，重度 30
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.color,
    this.border,
    this.boxShadow,
    this.blurSigma = 20, // 默认中度模糊，从 18 调整到 20
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? color;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;
  final double blurSigma;
  final Clip clipBehavior;

  /// 轻度模糊预设 (10)
  factory GlassSurface.light({
    Key? key,
    required Widget child,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(12)),
    Color? color,
    BoxBorder? border,
    List<BoxShadow>? boxShadow,
    Clip clipBehavior = Clip.antiAlias,
  }) {
    return GlassSurface(
      key: key,
      borderRadius: borderRadius,
      color: color,
      border: border,
      boxShadow: boxShadow,
      blurSigma: 10,
      clipBehavior: clipBehavior,
      child: child,
    );
  }

  /// 中度模糊预设 (20，默认)
  factory GlassSurface.medium({
    Key? key,
    required Widget child,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(12)),
    Color? color,
    BoxBorder? border,
    List<BoxShadow>? boxShadow,
    Clip clipBehavior = Clip.antiAlias,
  }) {
    return GlassSurface(
      key: key,
      borderRadius: borderRadius,
      color: color,
      border: border,
      boxShadow: boxShadow,
      blurSigma: 20,
      clipBehavior: clipBehavior,
      child: child,
    );
  }

  /// 重度模糊预设 (30)
  factory GlassSurface.heavy({
    Key? key,
    required Widget child,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(12)),
    Color? color,
    BoxBorder? border,
    List<BoxShadow>? boxShadow,
    Clip clipBehavior = Clip.antiAlias,
  }) {
    return GlassSurface(
      key: key,
      borderRadius: borderRadius,
      color: color,
      border: border,
      boxShadow: boxShadow,
      blurSigma: 30,
      clipBehavior: clipBehavior,
      child: child,
    );
  }

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
      child: GlassSurface.heavy(
        // 使用重度模糊预设
        borderRadius: BorderRadius.circular(16), // 从 12 增加到 16
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.48),
        ),
        child: child,
      ),
    );
  }
}
