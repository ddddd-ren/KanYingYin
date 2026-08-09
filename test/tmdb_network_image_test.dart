import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/widgets/tmdb_network_image.dart';

void main() {
  testWidgets('通过统一加载器取得字节后显示内存图片', (tester) async {
    var requestedUrl = '';
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TmdbNetworkImage(
          url: 'https://image.tmdb.org/t/p/w342/poster.jpg',
          cacheWidth: 720,
          cacheHeight: 1080,
          filterQuality: FilterQuality.medium,
          bytesLoader: (url) async {
            requestedUrl = url;
            return pngBytes;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      requestedUrl,
      'https://image.tmdb.org/t/p/w342/poster.jpg',
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    final resized = image.image as ResizeImage;
    expect(resized.width, 720);
    expect(resized.height, 1080);
    expect(resized.imageProvider, isA<MemoryImage>());
    expect(image.filterQuality, FilterQuality.medium);
  });

  testWidgets('图片加载失败时显示调用方提供的占位', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TmdbNetworkImage(
          url: 'https://image.tmdb.org/t/p/w342/poster.jpg',
          bytesLoader: (_) async => throw StateError('network failed'),
          errorBuilder: (_, __, ___) => const Icon(
            Icons.broken_image_outlined,
            key: ValueKey<String>('tmdb-image-error'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('tmdb-image-error')),
      findsOneWidget,
    );
  });
}
