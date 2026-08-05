import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

void main() {
  test('旧版 TMDB JSON 缺少新增字段时保持兼容', () {
    final metadata = TmdbMetadata.fromJson(<String, dynamic>{
      'id': 42,
      'mediaType': 'tv',
      'title': '三体',
      'language': 'zh-CN',
      'matchedAtMillis': DateTime.utc(2026, 8, 5).millisecondsSinceEpoch,
      'matchConfidence': 1,
      'seasons': <Map<String, Object?>>[
        <String, Object?>{
          'id': 100,
          'seasonNumber': 1,
          'name': '第 1 季',
          'episodeCount': 30,
        },
      ],
    });

    expect(metadata.aliases, isEmpty);
    expect(metadata.popularity, isNull);
    expect(metadata.voteCount, isNull);
    expect(metadata.seasons.single.episodes, isEmpty);
  });

  test('TMDB 元数据 JSON 往返保留别名、热度和逐集资料', () {
    final metadata = TmdbMetadata(
      id: 42,
      mediaType: TmdbMediaType.tv,
      title: '三体',
      aliases: const <String>['The Three-Body Problem'],
      popularity: 12.5,
      voteCount: 321,
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 8, 5),
      matchConfidence: 0.98,
      seasons: const <TmdbSeasonMetadata>[
        TmdbSeasonMetadata(
          id: 100,
          seasonNumber: 1,
          name: '第 1 季',
          episodeCount: 1,
          episodes: <TmdbEpisodeMetadata>[
            TmdbEpisodeMetadata(
              id: 101,
              episodeNumber: 1,
              name: '第一个故事',
              overview: '集简介',
              airDate: '2023-01-15',
              stillUrl: '/episode-1.jpg',
              rating: 8.5,
            ),
          ],
        ),
      ],
    );

    final restored = TmdbMetadata.fromJson(metadata.toJson());

    expect(restored, metadata);
    expect(restored.toJson(), metadata.toJson());
  });
}
