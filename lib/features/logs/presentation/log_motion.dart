import 'package:flutter/material.dart';

abstract final class LogMotion {
  static const expandDuration = Duration(milliseconds: 180);
  static const stateDuration = Duration(milliseconds: 160);
  static const reducedDuration = Duration(milliseconds: 80);
  static const curve = Curves.easeOutCubic;

  static Duration duration(BuildContext context, Duration normal) =>
      MediaQuery.disableAnimationsOf(context) ? reducedDuration : normal;
}
