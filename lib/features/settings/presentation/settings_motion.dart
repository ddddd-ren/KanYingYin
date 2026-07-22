import 'package:flutter/material.dart';

/// 设置中心统一动效时序。
abstract final class SettingsMotion {
  static const Duration hoverDuration = Duration(milliseconds: 280);
  static const Duration pressDuration = Duration(milliseconds: 90);
  static const Duration pageDuration = Duration(milliseconds: 260);
  static const Duration contentDuration = Duration(milliseconds: 220);
  static const Duration stateDuration = Duration(milliseconds: 180);
  static const Duration reducedDuration = Duration(milliseconds: 80);

  static const Curve hoverCurve = Curves.easeOutCubic;
  static const Curve pageCurve = Curves.easeOutCubic;

  static Duration duration(BuildContext context, Duration normal) {
    return MediaQuery.disableAnimationsOf(context) ? reducedDuration : normal;
  }

  static bool isReduced(BuildContext context) {
    return MediaQuery.disableAnimationsOf(context);
  }
}
