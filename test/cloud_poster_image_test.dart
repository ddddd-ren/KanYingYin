import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/widgets/cloud_poster_image.dart';
import 'package:kanyingyin/widgets/poster_cover.dart';

void main() {
  testWidgets('有效网盘缓存直接显示且不请求网络', (tester) async {
    var networkRequests = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: CloudPosterImage(
          cachePath: 'assets/images/logo/logo_rounded.png',
          url: 'https://image.tmdb.org/t/p/w500/poster.jpg',
          bytesLoader: (_) async {
            networkRequests++;
            return _pngBytes;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<FileImage>());
    expect(networkRequests, 0);
  });

  testWidgets('深色模式裁掉海报原图的亮色边缘', (tester) async {
    final repaintBoundaryKey = GlobalKey();
    final posterBytes = (await tester.runAsync(_borderedPosterBytes))!;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Center(
          child: RepaintBoundary(
            key: repaintBoundaryKey,
            child: SizedBox(
              width: 250,
              height: 375,
              child: CloudPosterImage(
                cachePath: null,
                url: 'https://image.tmdb.org/t/p/w500/poster.jpg',
                bytesLoader: (_) async => posterBytes,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (tester.widget<RawImage>(find.byType(RawImage)).image != null) break;
    }
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);

    final boundary = repaintBoundaryKey.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
    final renderedImage = await tester.runAsync(boundary.toImage);
    final pixels = await tester.runAsync(
      () => renderedImage!.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(pixels, isNotNull);

    final centerY = renderedImage!.height ~/ 2;
    final edgeReds = [
      for (var inset = 0; inset < 3; inset++)
        for (final x in [inset, renderedImage.width - inset - 1])
          pixels!.getUint8((centerY * renderedImage.width + x) * 4),
    ];
    expect(
      edgeReds,
      everyElement(lessThan(100)),
      reason: '海报左右边缘不应渲染出亮色细线',
    );

    renderedImage.dispose();
  });

  testWidgets('网盘海报通过共享封面层渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: CloudPosterImage(
          cachePath: null,
          url: 'https://image.tmdb.org/t/p/w500/poster.jpg',
          bytesLoader: (_) async => _pngBytes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PosterCover), findsOneWidget);
  });

  testWidgets('浅色模式不应用海报边缘放大', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: CloudPosterImage(
          cachePath: null,
          url: 'https://image.tmdb.org/t/p/w500/poster.jpg',
          bytesLoader: (_) async => _pngBytes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PosterCover), findsOneWidget);
    expect(find.byType(Transform), findsNothing);
  });

  testWidgets('首次海报未出帧时显示媒体占位而不是空白', (tester) async {
    final completer = Completer<List<int>>();

    await tester.pumpWidget(
      MaterialApp(
        home: CloudPosterImage(
          cachePath: null,
          url: 'https://image.tmdb.org/t/p/w500/poster.jpg',
          bytesLoader: (_) => completer.future,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('poster-cover-placeholder')),
      findsOneWidget,
    );

    completer.complete(_pngBytes);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('父级重建但海报身份不变时网络只加载一次', (tester) async {
    var requests = 0;
    Future<List<int>> loader(String _) async {
      requests++;
      return _pngBytes;
    }

    Widget app(String label) => MaterialApp(
          home: Column(
            children: [
              Text(label),
              SizedBox(
                width: 100,
                height: 150,
                child: CloudPosterImage(
                  cachePath: null,
                  url: 'https://image.tmdb.org/t/p/w500/same.jpg',
                  bytesLoader: loader,
                ),
              ),
            ],
          ),
        );

    await tester.pumpWidget(app('第一次'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app('第二次'));
    await tester.pumpAndSettle();

    expect(requests, 1);
  });

  testWidgets('网盘海报滑出网格后保留已显示状态', (tester) async {
    final posterKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: GridView.builder(
          cacheExtent: 0,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 1,
            mainAxisExtent: 500,
          ),
          itemCount: 3,
          itemBuilder: (context, index) => index == 0
              ? CloudPosterImage(
                  key: posterKey,
                  cachePath: 'assets/images/logo/logo_rounded.png',
                  url: null,
                )
              : const SizedBox.expand(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final originalState = posterKey.currentState;

    await tester.drag(find.byType(GridView), const Offset(0, -1000));
    await tester.pumpAndSettle();

    expect(posterKey.currentState, same(originalState));
  });

  test('网盘海报预热数量按视口增加一行并限制上限', () {
    expect(
      cloudPosterWarmupLimit(
        const Size(390, 844),
        maxCrossAxisExtent: 280,
        childAspectRatio: 0.68,
      ),
      8,
    );
    expect(
      cloudPosterWarmupLimit(
        const Size(1919, 958),
        maxCrossAxisExtent: 280,
        childAspectRatio: 0.68,
      ),
      28,
    );
    expect(
      cloudPosterWarmupLimit(
        const Size(10000, 10000),
        maxCrossAxisExtent: 280,
        childAspectRatio: 0.68,
      ),
      48,
    );
  });
}

final List<int> _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

Future<List<int>> _borderedPosterBytes() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const Color(0xFFFFFFFF), ui.BlendMode.src);
  canvas.drawRect(
    const Rect.fromLTWH(12, 0, 476, 750),
    Paint()..color = const Color(0xFF102030),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(500, 750);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) throw StateError('无法生成海报回归图片');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
