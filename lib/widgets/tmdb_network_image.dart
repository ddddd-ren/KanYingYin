import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kanyingyin/services/tmdb/tmdb_image_client.dart';

typedef TmdbImageBytesLoader = Future<List<int>> Function(String url);

/// 使用看影音统一网络配置加载 TMDB 图片，避免界面层绕过代理。
class TmdbNetworkImage extends StatefulWidget {
  const TmdbNetworkImage({
    super.key,
    required this.url,
    this.bytesLoader,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.low,
    this.cacheWidth,
    this.cacheHeight,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final String url;
  final TmdbImageBytesLoader? bytesLoader;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;
  final int? cacheWidth;
  final int? cacheHeight;
  final WidgetBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<TmdbNetworkImage> createState() => _TmdbNetworkImageState();
}

class _TmdbNetworkImageState extends State<TmdbNetworkImage> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _loadBytes();
  }

  @override
  void didUpdateWidget(covariant TmdbNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.bytesLoader != widget.bytesLoader) {
      _bytes = _loadBytes();
    }
  }

  Future<Uint8List> _loadBytes() async {
    final loader = widget.bytesLoader ?? TmdbImageClient.shared.downloadBytes;
    return Uint8List.fromList(await loader(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          return Image.memory(
            bytes,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            alignment: widget.alignment,
            filterQuality: widget.filterQuality,
            cacheWidth: widget.cacheWidth,
            cacheHeight: widget.cacheHeight,
            gaplessPlayback: true,
            errorBuilder: widget.errorBuilder,
          );
        }
        if (snapshot.hasError) {
          final errorBuilder = widget.errorBuilder;
          if (errorBuilder != null) {
            return errorBuilder(
              context,
              snapshot.error!,
              snapshot.stackTrace ?? StackTrace.empty,
            );
          }
        }
        return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
      },
    );
  }
}
