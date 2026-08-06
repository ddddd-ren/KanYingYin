import 'package:flutter/material.dart';
import 'package:kanyingyin/platform/app_platform.dart';

class TvLayoutPolicy {
  const TvLayoutPolicy._({required this.isAndroidTv});

  factory TvLayoutPolicy.forCapabilities(
    AppPlatformCapabilities capabilities,
  ) {
    return TvLayoutPolicy._(isAndroidTv: capabilities.isAndroidTv);
  }

  final bool isAndroidTv;

  double posterMaxCrossAxisExtent(double fallback) {
    return isAndroidTv ? 400 : fallback;
  }

  double gridSpacing(double fallback) {
    return isAndroidTv ? 20 : fallback;
  }

  EdgeInsets gridPadding(EdgeInsets fallback) {
    return isAndroidTv ? const EdgeInsets.fromLTRB(28, 20, 28, 28) : fallback;
  }

  double dialogMaxWidth(double fallback) {
    return isAndroidTv && fallback < 720 ? 720 : fallback;
  }
}
