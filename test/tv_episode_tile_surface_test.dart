import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/tv/presentation/tv_episode_tile_surface.dart';

void main() {
  testWidgets('TV 选集焦点和当前播放状态可同时辨认', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvEpisodeTileSurface(
            autofocus: true,
            current: true,
            onPressed: () {},
            child: const Text('第 1 集'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('tv-current-episode-surface')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('tv-focused-surface')),
        findsOneWidget);
    expect(find.text('正在播放'), findsOneWidget);
  });
}
