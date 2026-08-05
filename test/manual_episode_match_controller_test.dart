import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/episode_matching/application/manual_episode_match_controller.dart';
import 'package:kanyingyin/features/episode_matching/domain/manual_episode_match.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

void main() {
  test('只接受电视剧候选且电影不会发起详情请求', () async {
    var detailsCalls = 0;
    final controller = ManualEpisodeMatchController(
      selectedSeries: _metadata(TmdbMediaType.movie),
      items: const <ManualEpisodeMatchItem>[],
      loadDetails: (id, type, language) async {
        detailsCalls++;
        return _metadata(type);
      },
      loadSeason: (_, __, ___) async => _season(1),
    );

    await expectLater(controller.initialize(), throwsStateError);
    expect(detailsCalls, 0);
  });

  test('只按需加载所选季度并缓存已加载季度', () async {
    var detailsCalls = 0;
    final seasonCalls = <int>[];
    final controller = ManualEpisodeMatchController(
      selectedSeries: _metadata(TmdbMediaType.tv),
      items: const <ManualEpisodeMatchItem>[],
      loadDetails: (id, type, language) async {
        detailsCalls++;
        return _metadata(type);
      },
      loadSeason: (id, seasonNumber, language) async {
        seasonCalls.add(seasonNumber);
        return _season(seasonNumber);
      },
    );

    await controller.initialize();
    await controller.selectSeason(2);
    await controller.selectSeason(1);
    await controller.selectSeason(2);

    expect(detailsCalls, 1);
    expect(seasonCalls, <int>[2, 1]);
    expect(controller.selectedSeasonNumber, 2);
    expect(controller.episodes.single.name, '第 2 季第 1 集');
    expect(
      controller.metadata.seasons
          .firstWhere((season) => season.seasonNumber == 2)
          .episodes,
      isNotEmpty,
    );
  });

  test('自动预选、手动修改、保留原名和恢复自动识别状态独立', () async {
    final controller = ManualEpisodeMatchController(
      selectedSeries: _metadata(TmdbMediaType.tv),
      items: const <ManualEpisodeMatchItem>[
        ManualEpisodeMatchItem(
          resourceId: 'auto',
          originalName: 'Show.S01E01.mkv',
          automaticSeasonNumber: 1,
          automaticEpisodeNumber: 1,
        ),
        ManualEpisodeMatchItem(
          resourceId: 'manual',
          originalName: 'Show.1080p.mkv',
        ),
        ManualEpisodeMatchItem(
          resourceId: 'kept',
          originalName: 'Show.S01E03.mkv',
          manualOverride: true,
        ),
      ],
      loadDetails: (id, type, language) async => _metadata(type),
      loadSeason: (_, seasonNumber, __) async => _season(seasonNumber),
    );
    await controller.initialize();
    await controller.selectSeason(1);

    expect(controller.assignmentFor('auto')?.episodeNumber, 1);
    expect(
      controller.assignmentFor('kept')?.mode,
      ManualEpisodeAssignmentMode.keepOriginal,
    );

    controller.assignEpisode('manual', 1);
    controller.keepOriginal('auto');
    controller.restoreAutomatic('kept');

    expect(controller.assignmentFor('manual')?.episodeNumber, 1);
    expect(
      controller.assignmentFor('auto')?.mode,
      ManualEpisodeAssignmentMode.keepOriginal,
    );
    expect(
      controller.assignmentFor('kept')?.mode,
      ManualEpisodeAssignmentMode.restoreAutomatic,
    );
    expect(controller.assignments, hasLength(3));
  });
}

TmdbMetadata _metadata(TmdbMediaType type) {
  return TmdbMetadata(
    id: 196285,
    mediaType: type,
    title: '异世界悠闲农家',
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026, 8, 6),
    matchConfidence: 1,
    seasons: type == TmdbMediaType.tv
        ? const <TmdbSeasonMetadata>[
            TmdbSeasonMetadata(
              id: 1,
              seasonNumber: 1,
              name: '第 1 季',
              episodeCount: 2,
            ),
            TmdbSeasonMetadata(
              id: 2,
              seasonNumber: 2,
              name: '第 2 季',
              episodeCount: 1,
            ),
          ]
        : const <TmdbSeasonMetadata>[],
  );
}

TmdbSeasonMetadata _season(int seasonNumber) {
  return TmdbSeasonMetadata(
    id: seasonNumber,
    seasonNumber: seasonNumber,
    name: '第 $seasonNumber 季',
    episodeCount: seasonNumber == 1 ? 2 : 1,
    episodes: <TmdbEpisodeMetadata>[
      TmdbEpisodeMetadata(
        id: seasonNumber * 10 + 1,
        episodeNumber: 1,
        name: '第 $seasonNumber 季第 1 集',
      ),
      if (seasonNumber == 1)
        const TmdbEpisodeMetadata(
          id: 12,
          episodeNumber: 2,
          name: '第一位村民',
        ),
    ],
  );
}
