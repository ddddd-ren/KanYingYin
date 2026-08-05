import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/episode_matching/application/manual_episode_match_controller.dart';
import 'package:kanyingyin/features/episode_matching/domain/manual_episode_match.dart';
import 'package:kanyingyin/features/episode_matching/presentation/manual_episode_match_dialog.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

void main() {
  testWidgets('显示原始视频和 TMDB 集名并批量完成', (tester) async {
    final controller = _controller();
    List<ManualEpisodeAssignment>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: ManualEpisodeMatchDialog<void>(
          controller: controller,
          onSave: (metadata, seasonNumber, assignments) async {
            saved = assignments;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('匹配剧集'), findsOneWidget);
    expect(find.text('Show.S01E01.mkv'), findsOneWidget);
    expect(find.textContaining('第 1 集 万能农具'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '完成'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.single.episodeNumber, 1);
  });

  testWidgets('取消不会调用保存回调', (tester) async {
    final controller = _controller();
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ManualEpisodeMatchDialog<void>(
          controller: controller,
          onSave: (_, __, ___) async => saved = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(saved, isFalse);
  });
}

ManualEpisodeMatchController _controller() {
  final metadata = TmdbMetadata(
    id: 196285,
    mediaType: TmdbMediaType.tv,
    title: '异世界悠闲农家',
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026, 8, 6),
    matchConfidence: 1,
    seasons: const <TmdbSeasonMetadata>[
      TmdbSeasonMetadata(
        id: 1,
        seasonNumber: 1,
        name: '第 1 季',
        episodeCount: 1,
      ),
    ],
  );
  return ManualEpisodeMatchController(
    selectedSeries: metadata,
    items: const <ManualEpisodeMatchItem>[
      ManualEpisodeMatchItem(
        resourceId: 'video-1',
        originalName: 'Show.S01E01.mkv',
        automaticSeasonNumber: 1,
        automaticEpisodeNumber: 1,
      ),
    ],
    loadDetails: (_, __, ___) async => metadata,
    loadSeason: (_, __, ___) async => const TmdbSeasonMetadata(
      id: 1,
      seasonNumber: 1,
      name: '第 1 季',
      episodeCount: 1,
      episodes: <TmdbEpisodeMetadata>[
        TmdbEpisodeMetadata(id: 11, episodeNumber: 1, name: '万能农具'),
      ],
    ),
  );
}
