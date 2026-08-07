import 'package:kanyingyin/platform/app_platform.dart';

class TvImageDecodeSize {
  const TvImageDecodeSize({required this.width, required this.height});

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is TvImageDecodeSize &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'TvImageDecodeSize($width×$height)';
}

class TvImageDecodePolicy {
  const TvImageDecodePolicy._();

  static TvImageDecodeSize? poster(
    AppPlatformCapabilities capabilities, {
    double devicePixelRatio = 1,
  }) {
    return _size(
      capabilities,
      logicalWidth: 360,
      maxWidth: 720,
      devicePixelRatio: devicePixelRatio,
    );
  }

  static TvImageDecodeSize? seasonThumbnail(
    AppPlatformCapabilities capabilities, {
    double devicePixelRatio = 1,
  }) {
    return _size(
      capabilities,
      logicalWidth: 184,
      maxWidth: 368,
      devicePixelRatio: devicePixelRatio,
    );
  }

  static TvImageDecodeSize? _size(
    AppPlatformCapabilities capabilities, {
    required int logicalWidth,
    required int maxWidth,
    required double devicePixelRatio,
  }) {
    if (!capabilities.isAndroidTv) return null;
    final effectiveRatio = devicePixelRatio.isFinite && devicePixelRatio > 0
        ? devicePixelRatio
        : 1.0;
    var width = (logicalWidth * effectiveRatio).round();
    if (width < 1) width = 1;
    if (width > maxWidth) width = maxWidth;
    return TvImageDecodeSize(
      width: width,
      height: (width * 3 / 2).round(),
    );
  }
}
