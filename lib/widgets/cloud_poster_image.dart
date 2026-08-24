import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kanyingyin/widgets/tmdb_network_image.dart';

/// 统一展示网盘海报，优先复用已经落盘的缓存。
class CloudPosterImage extends StatefulWidget {
  const CloudPosterImage({
    super.key,
    required this.cachePath,
    required this.url,
    this.bytesLoader,
    this.fit = BoxFit.cover,
    this.width = double.infinity,
    this.height = double.infinity,
    this.cacheWidth,
    this.cacheHeight,
    this.filterQuality = FilterQuality.medium,
    this.placeholderBuilder,
  });

  final String? cachePath;
  final String? url;
  final TmdbImageBytesLoader? bytesLoader;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final FilterQuality filterQuality;
  final WidgetBuilder? placeholderBuilder;

  @override
  State<CloudPosterImage> createState() => _CloudPosterImageState();
}

class _CloudPosterImageState extends State<CloudPosterImage>
    with AutomaticKeepAliveClientMixin {
  String? _failedCachePath;
  bool _hasDisplayedLocalFrame = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant CloudPosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_normalized(oldWidget.cachePath) != _normalized(widget.cachePath)) {
      _failedCachePath = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cachePath = _normalized(widget.cachePath);
    if (cachePath != null &&
        _failedCachePath != cachePath &&
        File(cachePath).existsSync()) {
      return Image.file(
        File(cachePath),
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
        filterQuality: widget.filterQuality,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            _hasDisplayedLocalFrame = true;
            return child;
          }
          return _hasDisplayedLocalFrame ? child : _placeholder(context);
        },
        errorBuilder: (context, _, __) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _failedCachePath == cachePath) return;
            setState(() => _failedCachePath = cachePath);
          });
          return _networkOrPlaceholder(context);
        },
      );
    }
    return _networkOrPlaceholder(context);
  }

  Widget _networkOrPlaceholder(BuildContext context) {
    final url = _normalized(widget.url);
    if (url == null) return _placeholder(context);
    return TmdbNetworkImage(
      url: url,
      bytesLoader: widget.bytesLoader,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      filterQuality: widget.filterQuality,
      loadingBuilder: _placeholder,
      errorBuilder: (context, _, __) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) =>
      widget.placeholderBuilder?.call(context) ??
      const CloudPosterPlaceholder();

  static String? _normalized(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}

class CloudPosterPlaceholder extends StatelessWidget {
  const CloudPosterPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const ValueKey<String>('cloud-poster-placeholder'),
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 48,
          color: colors.secondary,
        ),
      ),
    );
  }
}

/// 预解码当前视口需要的网盘本地海报，不发起网络请求。
Future<void> precacheCloudPosterFiles(
  BuildContext context,
  Iterable<String?> paths, {
  required int limit,
  int? cacheWidth,
  int? cacheHeight,
}) async {
  final uniquePaths = paths
      .map((path) => path?.trim() ?? '')
      .where((path) => path.isNotEmpty && File(path).existsSync())
      .toSet()
      .take(limit);
  await Future.wait(
    uniquePaths.map((path) {
      final provider = ResizeImage.resizeIfNeeded(
        cacheWidth,
        cacheHeight,
        FileImage(File(path)),
      );
      return precacheImage(provider, context, onError: (_, __) {});
    }),
  );
}

/// 计算可见海报数量并额外预热一行，避免预解码整个媒体库。
int cloudPosterWarmupLimit(
  Size viewport, {
  required double maxCrossAxisExtent,
  required double childAspectRatio,
  int maximum = 48,
}) {
  if (viewport.isEmpty ||
      maxCrossAxisExtent <= 0 ||
      childAspectRatio <= 0 ||
      maximum <= 0) {
    return 1;
  }
  final columns = math.max(1, (viewport.width / maxCrossAxisExtent).ceil());
  final cardWidth = viewport.width / columns;
  final cardHeight = cardWidth / childAspectRatio;
  final visibleRows = math.max(1, (viewport.height / cardHeight).ceil());
  return (columns * (visibleRows + 1)).clamp(1, maximum);
}
