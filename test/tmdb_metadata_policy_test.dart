import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_metadata_merge_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_episode_title_resolver.dart';
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

  test('合并元数据时始终采用详情返回的类型', () {
    final existing = _metadata(
      title: '旧标题',
      genres: const <String>['剧情'],
    );
    final fetched = _metadata(
      title: '新标题',
      genres: const <String>['动画', '科幻'],
    );

    final merged = mergePolicy.merge(
      existing: existing,
      fetched: fetched,
      options: const TmdbScrapeOptions.defaults(),
      locks: const TmdbFieldLocks(title: true, overview: true, poster: true),
      matchConfidence: 0.9,
    );

    expect(merged.genres, const <String>['动画', '科幻']);
  });

  test('逐集资料按季度和集号采用本次 TMDB 集名', () {
    final existing = _metadata(
      title: '三体',
      type: TmdbMediaType.tv,
      seasons: <TmdbSeasonMetadata>[
        _season(
          1,
          '/cached.jpg',
          episodes: <TmdbEpisodeMetadata>[
            _episode(1, '用户集名'),
          ],
        ),
      ],
    );
    final fetched = _metadata(
      title: '三体',
      type: TmdbMediaType.tv,
      seasons: <TmdbSeasonMetadata>[
        _season(
          1,
          '/new.jpg',
          episodes: <TmdbEpisodeMetadata>[
            _episode(1, '第一集'),
            _episode(2, '第二集'),
          ],
        ),
      ],
    );

    final merged = mergePolicy.merge(
      existing: existing,
      fetched: fetched,
      options: const TmdbScrapeOptions.defaults().copyWith(fetchPoster: false),
      matchConfidence: 0.9,
    );

    expect(merged.seasons.single.posterUrl, '/cached.jpg');
    expect(merged.seasons.single.episodes, hasLength(2));
    expect(merged.seasons.single.episodes.first.name, '第一集');
  });

  test('关闭逐集名称时清空旧集名但保留季集资料', () {
    final existing = _metadata(
      title: '回魂计',
      type: TmdbMediaType.tv,
      seasons: <TmdbSeasonMetadata>[
        _season(
          1,
          null,
          episodes: <TmdbEpisodeMetadata>[_episode(1, '错误旧集名')],
        ),
      ],
    );
    final fetched = _metadata(
      title: '回魂计',
      type: TmdbMediaType.tv,
      seasons: <TmdbSeasonMetadata>[
        _season(
          1,
          null,
          episodes: <TmdbEpisodeMetadata>[_episode(1, '死而复生')],
        ),
      ],
    );

    final merged = mergePolicy.merge(
      existing: existing,
      fetched: fetched,
      options: const TmdbScrapeOptions.defaults().copyWith(
        scrapeEpisodeNames: false,
      ),
      matchConfidence: 1,
    );

    expect(merged.seasons.single.episodes.single.name, isEmpty);
  });

  test('首次刮削关闭逐集名称时不写入 TMDB 集名', () {
    final fetched = _metadata(
      title: '回魂计',
      type: TmdbMediaType.tv,
      seasons: <TmdbSeasonMetadata>[
        _season(
          1,
          null,
          episodes: <TmdbEpisodeMetadata>[_episode(1, '死而复生')],
        ),
      ],
    );

    final merged = mergePolicy.merge(
      existing: null,
      fetched: fetched,
      options: const TmdbScrapeOptions.defaults().copyWith(
        scrapeEpisodeNames: false,
      ),
      matchConfidence: 1,
    );

    expect(merged.seasons.single.episodes.single.name, isEmpty);
  });

  test('逐集标题解析器按证据提供稳定回退', () {
    const resolver = TmdbEpisodeTitleResolver();
    expect(
      resolver.resolve(
        seriesTitle: '三体',
        seasonNumber: 1,
        episodeNumber: 1,
        episodeName: '第一集',
        originalFileName: '01.mkv',
      ),
      '三体 S01E01 第一集',
    );
    expect(
      resolver.resolve(
        seriesTitle: '三体',
        seasonNumber: 1,
        episodeNumber: 2,
        episodeName: null,
        originalFileName: '02.mkv',
      ),
      '三体 S01E02',
    );
    expect(
      resolver.resolve(
        seriesTitle: '三体',
        seasonNumber: null,
        episodeNumber: 2,
        episodeName: null,
        originalFileName: '02.mkv',
      ),
      '三体 E02',
    );
    expect(
      resolver.resolve(
        seriesTitle: '',
        seasonNumber: null,
        episodeNumber: null,
        episodeName: null,
        originalFileName: '原始文件.mkv',
      ),
      '原始文件.mkv',
    );
  });
}

TmdbMetadata _metadata({
  required String title,
  TmdbMediaType type = TmdbMediaType.movie,
  String? overview,
  String? posterUrl,
  String? backdropUrl,
  List<String> genres = const <String>[],
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
    genres: genres,
    seasons: seasons,
  );
}

TmdbSeasonMetadata _season(
  int number,
  String? posterUrl, {
  List<TmdbEpisodeMetadata> episodes = const <TmdbEpisodeMetadata>[],
}) {
  return TmdbSeasonMetadata(
    id: number,
    seasonNumber: number,
    name: '第 $number 季',
    episodeCount: 8,
    posterUrl: posterUrl,
    episodes: episodes,
  );
}

TmdbEpisodeMetadata _episode(int number, String name) {
  return TmdbEpisodeMetadata(
    id: number,
    episodeNumber: number,
    name: name,
  );
}
