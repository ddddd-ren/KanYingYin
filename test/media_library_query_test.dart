import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_library_query.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';

void main() {
  test('多个类型任一匹配并与来源关键词同时满足', () {
    final result = const MediaLibraryQuery().apply(
      series: <MediaLibrarySeries>[
        _series('local', '星际动画', const <String>['动画', '科幻']),
        _series('openlist', '太空纪录片', const <String>['纪录片']),
        _series('openlist', '科幻电影', const <String>['科幻']),
      ],
      sourceId: 'openlist',
      keyword: '电影',
      selectedGenres: const <String>{'动画', '科幻'},
    );

    expect(result.map((item) => item.title), const <String>['科幻电影']);
  });

  test('可用类型按中文名称排序且切换来源移除失效选择', () {
    const query = MediaLibraryQuery();
    final available = query.availableGenres(
      <MediaLibrarySeries>[
        _series('local', 'A', const <String>['科幻', '动画']),
        _series('openlist', 'B', const <String>['纪录片']),
      ],
      sourceId: 'local',
    );

    expect(available, const <String>['动画', '科幻']);
    expect(
      query.retainAvailableGenres(
        const <String>{'科幻', '纪录片'},
        available,
      ),
      const <String>{'科幻'},
    );
  });

  test('动画电影同时归入动漫和电影且自定义标签可参与多选筛选', () {
    final local = _localSeries(
      'local|动漫电影',
      '动漫电影',
      const <String>['动画', '科幻'],
    );
    final other = _series('local', '其他作品', const <String>['纪录片']);
    const query = MediaLibraryQuery();
    final custom = <String, Iterable<String>>{
      '动漫电影': const <String>['收藏'],
      '其他作品': const <String>['待看'],
    };

    expect(
      query.availableCategories(<MediaLibrarySeries>[local, other],
          sourceId: 'local'),
      const <String>['动漫', '电影'],
    );
    expect(
      query.availableCustomTags(<MediaLibrarySeries>[local, other],
          sourceId: 'local', customTagsBySeries: custom),
      const <String>['待看', '收藏'],
    );
    expect(
      query
          .apply(
            series: <MediaLibrarySeries>[local, other],
            sourceId: 'local',
            selectedTags: const <String>{'动漫', '收藏'},
            extraTagsBySeries: custom,
          )
          .map((item) => item.title),
      const <String>['动漫电影'],
    );
  });

  test('电影电视剧和动漫支持交叉分类', () {
    final movie = _series(
      'local',
      '普通电影',
      const <String>['剧情'],
      mediaType: TmdbMediaType.movie,
    );
    final animatedMovie = _series(
      'local',
      '动画电影',
      const <String>['动画'],
      mediaType: TmdbMediaType.movie,
    );
    final animatedTv = _series(
      'local',
      '动画剧集',
      const <String>['Animation'],
      mediaType: TmdbMediaType.tv,
    );
    final tv = _series(
      'local',
      '普通电视剧',
      const <String>['剧情'],
      mediaType: TmdbMediaType.tv,
    );
    const query = MediaLibraryQuery();

    expect(query.categoriesForSeries(movie), const <String>['电影']);
    expect(
      query.categoriesForSeries(animatedMovie),
      const <String>['电影', '动漫'],
    );
    expect(
      query.categoriesForSeries(animatedTv),
      const <String>['动漫', '电视剧'],
    );
    expect(query.categoriesForSeries(tv), const <String>['电视剧']);
  });

  test('网盘电影剧集和动画类型可直接用于三个主入口筛选', () {
    final movie = _series(
      'quark',
      '网盘电影',
      const <String>['剧情'],
      mediaType: TmdbMediaType.movie,
    );
    final anime = _series(
      'quark',
      '网盘动画',
      const <String>['动画'],
      mediaType: TmdbMediaType.tv,
    );
    final tv = _series(
      'quark',
      '网盘电视剧',
      const <String>['剧情'],
      mediaType: TmdbMediaType.tv,
    );
    const query = MediaLibraryQuery();

    expect(
      query.apply(
        series: <MediaLibrarySeries>[movie, anime, tv],
        selectedTags: const <String>{'电影'},
      ).map((item) => item.title),
      const <String>['网盘电影'],
    );
    expect(
      query.apply(
        series: <MediaLibrarySeries>[movie, anime, tv],
        selectedTags: const <String>{'动漫'},
      ).map((item) => item.title),
      const <String>['网盘动画'],
    );
    expect(
      query.apply(
        series: <MediaLibrarySeries>[movie, anime, tv],
        selectedTags: const <String>{'电视剧'},
      ).map((item) => item.title),
      const <String>['网盘动画', '网盘电视剧'],
    );
  });
}

MediaLibrarySeries _series(String sourceId, String title, List<String> genres,
    {TmdbMediaType? mediaType}) {
  return MediaLibrarySeries(
    key: '$sourceId|$title',
    seriesKey: title,
    title: title,
    sourceKind:
        sourceId == 'local' ? MediaSourceKind.local : MediaSourceKind.cloud,
    sourceId: sourceId,
    sourceName: sourceId == 'local' ? '本地' : '网盘',
    isAvailable: true,
    episodes: const <MediaLibraryEpisode>[],
    genres: genres,
    mediaType: mediaType,
  );
}

MediaLibrarySeries _localSeries(
  String key,
  String title,
  List<String> genres,
) {
  final item = LocalMediaIndexItem(
    path: 'C:\\Media\\$title\\$title.mkv',
    name: '$title.mkv',
    parentPath: 'C:\\Media\\$title',
    sourcePath: r'C:\Media',
    size: 1,
    modified: DateTime.utc(2026, 8, 4),
    seriesName: title,
    indexedAt: DateTime.utc(2026, 8, 4),
    tmdb: TmdbMetadata(
      id: 1,
      mediaType: TmdbMediaType.movie,
      title: title,
      genres: genres,
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 8, 4),
      matchConfidence: 1,
    ),
  );
  return MediaLibrarySeries(
    key: key,
    seriesKey: title,
    title: title,
    sourceKind: MediaSourceKind.local,
    sourceId: 'local',
    sourceName: '本地',
    isAvailable: true,
    episodes: <MediaLibraryEpisode>[
      MediaLibraryEpisode.local(
        stableId: item.id,
        name: item.name,
        localItem: item,
      ),
    ],
    genres: genres,
  );
}
