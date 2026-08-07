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
    return isAndroidTv ? 260 : fallback;
  }

  double gridSpacing(double fallback) {
    return isAndroidTv ? 16 : fallback;
  }

  SliverGridDelegate posterGridDelegate({
    required double fallbackMaxCrossAxisExtent,
    required double fallbackChildAspectRatio,
  }) {
    if (isAndroidTv) {
      return SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: gridSpacing(12),
        mainAxisSpacing: gridSpacing(12),
        childAspectRatio: 0.78,
      );
    }
    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: posterMaxCrossAxisExtent(fallbackMaxCrossAxisExtent),
      crossAxisSpacing: gridSpacing(12),
      mainAxisSpacing: gridSpacing(12),
      childAspectRatio: fallbackChildAspectRatio,
    );
  }

  EdgeInsets gridPadding(EdgeInsets fallback) {
    return isAndroidTv ? const EdgeInsets.fromLTRB(20, 16, 20, 24) : fallback;
  }

  double dialogMaxWidth(double fallback) {
    return isAndroidTv && fallback < 720 ? 720 : fallback;
  }
}
