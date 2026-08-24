import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/widgets/cloud_poster_image.dart';

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
      find.byKey(const ValueKey<String>('cloud-poster-placeholder')),
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
