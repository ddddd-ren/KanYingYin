import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_library_classification.dart';
import 'package:kanyingyin/features/library/application/media_library_query.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
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
        _series('local', 'A', const <String>['科幻']),
        _series('local', 'C', const <String>['动画']),
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

  test('人工确认动画电影的双分类且自定义标签仍参与综合筛选', () {
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
    final states = <String, MediaLibraryUserState>{
      local.key: const MediaLibraryUserState(
        categoryOverride: ['电影', '动漫'],
        genreOverride: ['动画', '科幻'],
      ),
    };

    expect(
      query.availableCategories(<MediaLibrarySeries>[local, other],
          sourceId: 'local', userStates: states),
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
            userStates: states,
          )
          .map((item) => item.title),
      const <String>['动漫电影'],
    );
  });

  test('动漫排除电视剧而动画电影仍需确认分类', () {
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
      isEmpty,
    );
    expect(
      query.categoriesForSeries(animatedTv),
      const <String>['动漫'],
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
        selectedCategories: const <String>{'电影'},
      ).map((item) => item.title),
      const <String>['网盘电影'],
    );
    expect(
      query.apply(
        series: <MediaLibrarySeries>[movie, anime, tv],
        selectedCategories: const <String>{'动漫'},
      ).map((item) => item.title),
      const <String>['网盘动画'],
    );
    expect(
      query.apply(
        series: <MediaLibrarySeries>[movie, anime, tv],
        selectedCategories: const <String>{'电视剧'},
      ).map((item) => item.title),
      const <String>['网盘电视剧'],
    );
  });

  test('主分类入口不受同名自定义标签影响', () {
    final anime = _series('quark', '动画', ['动画'], mediaType: TmdbMediaType.tv);
    final tv = _series('quark', '电视剧', ['剧情'], mediaType: TmdbMediaType.tv);

    final result = const MediaLibraryQuery().apply(
      series: [anime, tv],
      selectedCategories: {'电视剧'},
      extraTagsBySeries: {
        anime.seriesKey: ['电视剧']
      },
    );

    expect(result, [tv]);
  });

  test('自定义标签入口不接受同名分类和题材并与其他筛选取交集', () {
    final anime = _series('local', '动画', ['动画'], mediaType: TmdbMediaType.tv);
    final tv = _series('local', '电视剧', ['剧情'], mediaType: TmdbMediaType.tv);
    final custom = <String, Iterable<String>>{
      anime.seriesKey: ['电视剧', '剧情'],
    };
    const query = MediaLibraryQuery();

    for (final tag in ['电视剧', '剧情']) {
      expect(
        query.apply(
          series: [anime, tv],
          selectedCustomTags: {tag},
          extraTagsBySeries: custom,
        ),
        [anime],
      );
    }
    expect(
      query.apply(
        series: [anime, tv],
        selectedGenres: {'剧情'},
        selectedCustomTags: {'剧情'},
        extraTagsBySeries: custom,
      ),
      isEmpty,
    );
  });

  test('人工取消的题材不进入筛选项或综合标签', () {
    final series = _series('local', '电影', ['剧情']);
    final states = <String, MediaLibraryUserState>{
      series.key: const MediaLibraryUserState(genreOverride: []),
    };
    const query = MediaLibraryQuery();

    expect(query.genresForSeries(series, state: states[series.key]), isEmpty);
    expect(query.availableGenres([series], userStates: states), isEmpty);
    expect(query.availableTags([series], userStates: states), ['电影']);
    expect(
        query.apply(
            series: [series], userStates: states, selectedGenres: {'剧情'}),
        isEmpty);
  });

  test('全部查询入口采用同一门槛与稳定作品 key 的人工选择', () {
    const query = MediaLibraryQuery();
    final series = _series('local', '电影', ['剧情']);
    final states = <String, MediaLibraryUserState>{
      series.key: const MediaLibraryUserState(
        categoryOverride: ['动漫'],
        genreOverride: ['冒险'],
      ),
    };

    expect(
        query.categoriesForSeries(series, mode: MediaClassificationMode.manual),
        isEmpty);
    expect(
        query.availableCategories([series],
            classificationMode: MediaClassificationMode.manual),
        isEmpty);
    expect(
        query.availableGenres([series],
            classificationMode: MediaClassificationMode.manual),
        isEmpty);
    expect(
        query.availableTags([series],
            classificationMode: MediaClassificationMode.manual),
        isEmpty);
    expect(
        query.availableCategories([series],
            userStates: states,
            classificationMode: MediaClassificationMode.manual),
        ['动漫']);
    expect(
        query.availableGenres([series],
            userStates: states,
            classificationMode: MediaClassificationMode.manual),
        ['冒险']);
    expect(
        query.apply(
            series: [series],
            userStates: states,
            selectedCategories: {'动漫'},
            selectedGenres: {'冒险'},
            classificationMode: MediaClassificationMode.manual),
        [series]);
  });
}

MediaLibrarySeries _series(String sourceId, String title, List<String> genres,
    {TmdbMediaType mediaType = TmdbMediaType.movie}) {
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
    tmdbMetadata: TmdbMetadata(
      id: 1,
      mediaType: mediaType,
      title: title,
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 10, 11),
      matchConfidence: 1,
      genres: genres,
    ),
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
