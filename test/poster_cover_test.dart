import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/widgets/poster_cover.dart';

void main() {
  test('封面比例和深色裁边量固定', () {
    expect(posterAspectRatio, 2 / 3);
    expect(posterDarkScale, 1.06);
  });

  testWidgets('浅色模式不放大真实海报', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: const PosterCover(
          child: SizedBox(key: ValueKey<String>('poster-image')),
        ),
      ),
    );

    expect(find.byKey(const ValueKey<String>('poster-image')), findsOneWidget);
    expect(find.byType(Transform), findsNothing);
  });

  testWidgets('深色模式居中放大并裁切真实海报', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const PosterCover(
          child: SizedBox(key: ValueKey<String>('poster-image')),
        ),
      ),
    );

    final transform = tester.widget<Transform>(find.byType(Transform));
    expect(transform.transform.getMaxScaleOnAxis(), closeTo(1.06, 0.0001));
    expect(find.byType(ClipRect), findsOneWidget);
  });

  testWidgets('无图统一使用中性影片占位', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const SizedBox(
          width: 60,
          height: 90,
          child: PosterCover.placeholder(),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('poster-cover-placeholder')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
  });
}
