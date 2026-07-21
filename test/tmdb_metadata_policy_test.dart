import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_metadata_merge_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_poster_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

void main() {
  const mergePolicy = TmdbMetadataMergePolicy();
  const posterPolicy = TmdbPosterPolicy();

  test('字段锁定和覆盖选项统一保留已有内容', () {
    final existing = _metadata(
      title: '用户标题',
      overview: '用户简介',
      posterUrl: '/old.jpg',
      backdropUrl: '/old-backdrop.jpg',
    );
    final fetched = _metadata(
      title: 'TMDB 标题',
      overview: 'TMDB 简介',
      posterUrl: '/new.jpg',
      backdropUrl: '/new-backdrop.jpg',
    );

    final merged = mergePolicy.merge(
      existing: existing,
      fetched: fetched,
      options: const TmdbScrapeOptions.defaults(),
      locks: const TmdbFieldLocks(title: true),
      matchConfidence: 0.92,
    );

    expect(merged.title, '用户标题');
    expect(merged.overview, 'TMDB 简介');
    expect(merged.posterUrl, '/new.jpg');
    expect(merged.backdropUrl, '/new-backdrop.jpg');
    expect(merged.matchConfidence, 0.92);
  });

  test('关闭图片抓取时保留已有海报和背景图', () {
    final existing = _metadata(
      title: '旧标题',
      posterUrl: '/old.jpg',
      backdropUrl: '/old-backdrop.jpg',
    );
    final fetched = _metadata(
      title: '新标题',
      posterUrl: '/new.jpg',
      backdropUrl: '/new-backdrop.jpg',
    );

    final merged = mergePolicy.merge(
      existing: existing,
      fetched: fetched,
      options: const TmdbScrapeOptions.defaults().copyWith(
        fetchPoster: false,
        fetchBackdrop: false,
      ),
      matchConfidence: 0.8,
    );

    expect(merged.posterUrl, '/old.jpg');
    expect(merged.backdropUrl, '/old-backdrop.jpg');
  });

  test('只保留媒体库实际存在的季度并按季度号排序', () {
    final fetched = _metadata(
      title: '三体',
      type: TmdbMediaType.tv,
      seasons: <TmdbSeasonMetadata>[
        _season(3, '/s3.jpg'),
        _season(1, '/s1.jpg'),
        _season(2, '/s2.jpg'),
      ],
    );

    final merged = mergePolicy.merge(
      fetched: fetched,
      options: const TmdbScrapeOptions.defaults(),
      matchConfidence: 0.9,
      existingSeasons: const <int>{1, 3},
    );

    expect(
      merged.seasons.map((season) => season.seasonNumber),
      <int>[1, 3],
    );
  });

  test('电视剧优先季度海报且缺失时回退作品海报', () {
    final metadata = _metadata(
      title: '三体',
      type: TmdbMediaType.tv,
      posterUrl: '/work.jpg',
      seasons: <TmdbSeasonMetadata>[
        _season(1, '/s1.jpg'),
        _season(2, null),
      ],
    );

    expect(
      posterPolicy.select(
        metadata,
        seasonNumber: 1,
        options: const TmdbScrapeOptions.defaults(),
      ),
      '/s1.jpg',
    );
    expect(
      posterPolicy.select(
        metadata,
        seasonNumber: 2,
        options: const TmdbScrapeOptions.defaults(),
      ),
      '/work.jpg',
    );
  });

  test('海报锁定或关闭抓取时返回已有图片', () {
    final metadata = _metadata(
      title: '三体',
      type: TmdbMediaType.tv,
      posterUrl: '/work.jpg',
      seasons: <TmdbSeasonMetadata>[_season(1, '/s1.jpg')],
    );

    expect(
      posterPolicy.select(
        metadata,
        seasonNumber: 1,
        options: const TmdbScrapeOptions.defaults(),
        locks: const TmdbFieldLocks(poster: true),
        existingPoster: '/locked.jpg',
      ),
      '/locked.jpg',
    );
    expect(
      posterPolicy.select(
        metadata,
        seasonNumber: 1,
        options: const TmdbScrapeOptions.defaults().copyWith(
          fetchPoster: false,
        ),
        existingPoster: '/existing.jpg',
      ),
      '/existing.jpg',
    );
  });
}

TmdbMetadata _metadata({
  required String title,
  TmdbMediaType type = TmdbMediaType.movie,
  String? overview,
  String? posterUrl,
  String? backdropUrl,
  List<TmdbSeasonMetadata> seasons = const <TmdbSeasonMetadata>[],
}) {
  return TmdbMetadata(
    id: 1,
    mediaType: type,
    title: title,
    originalTitle: '$title Original',
    overview: overview,
    releaseDate: '2023-01-01',
    rating: 8.5,
    posterUrl: posterUrl,
    backdropUrl: backdropUrl,
    language: 'zh-CN',
    matchedAt: DateTime(2026),
    matchConfidence: 0,
    seasons: seasons,
  );
}

TmdbSeasonMetadata _season(int number, String? posterUrl) {
  return TmdbSeasonMetadata(
    id: number,
    seasonNumber: number,
    name: '第 $number 季',
    episodeCount: 8,
    posterUrl: posterUrl,
  );
}
