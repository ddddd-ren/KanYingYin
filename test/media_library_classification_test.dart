import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_library_classification.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';

void main() {
  const resolver = MediaClassificationResolver();

  test('可信动画剧集只自动归入动漫且不改动原始 TMDB 类型', () {
    final metadata = _metadata(genres: ['动画']);
    final series = _series(metadata: metadata);

    final result = resolver.resolve(series);

    expect(result.categories, ['动漫']);
    expect(result.genres, ['动画']);
    expect(result.categorySuggestions.single.confidence,
        MediaClassificationConfidence.high);
    expect(result.needsConfirmation, isFalse);
    expect(result.isManual, isFalse);
    expect(series.mediaType, TmdbMediaType.tv);
    expect(series.tmdbMetadata, same(metadata));
  });

  test('动画电影保留两个分类候选并等待用户选择', () {
    final result = resolver.resolve(_series(
      metadata: _metadata(type: TmdbMediaType.movie, genres: ['动画']),
    ));

    expect(result.categories, isEmpty);
    expect(
        result.categorySuggestions.map((value) => value.label), ['电影', '动漫']);
    expect(result.needsConfirmation, isTrue);
  });

  test('多个题材必须选择而非自动全选且不阻止明确的单分类', () {
    final result = resolver.resolve(_series(
      metadata: _metadata(genres: ['剧情', '悬疑']),
    ));

    expect(result.categories, ['电视剧']);
    expect(result.genres, isEmpty);
    expect(result.genreSuggestions.map((value) => value.label), ['剧情', '悬疑']);
    expect(result.needsConfirmation, isTrue);
  });

  test('标准模式接受单一中可信旧元数据而保守模式待确认', () {
    final series = _series(type: TmdbMediaType.tv, genres: ['剧情']);

    final conservative = resolver.resolve(series);
    final standard =
        resolver.resolve(series, mode: MediaClassificationMode.standard);

    expect(conservative.categories, isEmpty);
    expect(conservative.genres, isEmpty);
    expect(conservative.categorySuggestions.single.confidence,
        MediaClassificationConfidence.medium);
    expect(conservative.needsConfirmation, isTrue);
    expect(standard.categories, ['电视剧']);
    expect(standard.genres, ['剧情']);
    expect(standard.needsConfirmation, isFalse);
  });

  test('全手动模式保留建议但不自动分类或选择题材', () {
    final result = resolver.resolve(
      _series(metadata: _metadata(genres: ['动画'])),
      mode: MediaClassificationMode.manual,
    );

    expect(result.categories, isEmpty);
    expect(result.genres, isEmpty);
    expect(result.categorySuggestions.single.label, '动漫');
    expect(result.needsConfirmation, isTrue);
    expect(result.isManual, isFalse);
  });

  test('有 TV 类型但缺少题材不能高可信推断为电视剧', () {
    final result = resolver.resolve(
      _series(metadata: _metadata(genres: [])),
      mode: MediaClassificationMode.standard,
    );

    expect(result.categories, isEmpty);
    expect(result.categorySuggestions.single.confidence,
        MediaClassificationConfidence.low);
    expect(result.needsConfirmation, isTrue);
  });

  test('只有季集信息提供低可信建议且不会自动进入电视剧', () {
    final result = resolver.resolve(
      _series(episodes: [_episode(null, season: 1, episode: 1)]),
      mode: MediaClassificationMode.standard,
    );

    expect(result.categories, isEmpty);
    expect(result.categorySuggestions.single.label, '电视剧');
    expect(result.categorySuggestions.single.confidence,
        MediaClassificationConfidence.low);
  });

  test('完全没有分类证据仍可访问并标记待确认', () {
    final result = resolver.resolve(_series());

    expect(result.categories, isEmpty);
    expect(result.genres, isEmpty);
    expect(result.categorySuggestions, isEmpty);
    expect(result.needsConfirmation, isTrue);
  });

  test('匹配分数只参与证据分档而不作为分类概率', () {
    for (final score in [0.0, 0.3, double.nan, double.infinity, 1.2]) {
      final result = resolver.resolve(
        _series(metadata: _metadata(genres: ['剧情'], confidence: score)),
        mode: MediaClassificationMode.standard,
      );
      expect(result.categories, isEmpty, reason: '分数 $score 不可靠');
      expect(result.categorySuggestions.single.confidence,
          MediaClassificationConfidence.low);
      expect(result.categorySuggestions.single.reason, isNot(contains('%')));
      expect(result.categorySuggestions.single.reason, isNot(contains('概率')));
    }
    final medium = resolver.resolve(_series(
      metadata: _metadata(genres: ['剧情'], confidence: 0.7),
    ));
    expect(medium.categories, isEmpty);
    expect(medium.categorySuggestions.single.confidence,
        MediaClassificationConfidence.medium);
  });

  test('无效 TMDB 标识不产生高可信分类', () {
    final result = resolver.resolve(_series(
      metadata: _metadata(id: 0, genres: ['剧情']),
    ));

    expect(result.categories, isEmpty);
    expect(result.categorySuggestions.single.confidence,
        MediaClassificationConfidence.low);
  });

  for (final invalidType in <String, Map<String, Object?>>{
    '缺失': {},
    'null': {'mediaType': null},
    '空字符串': {'mediaType': ''},
    '未知名称': {'mediaType': 'person'},
    '大小写不符': {'mediaType': 'TV'},
    '数字': {'mediaType': 1},
    '布尔': {'mediaType': true},
    '列表': {
      'mediaType': ['tv']
    },
    '对象': {
      'mediaType': {'name': 'tv'}
    },
  }.entries) {
    test('反序列化${invalidType.key}类型保留历史结构但不得提升分类可信度', () {
      final metadata = TmdbMetadata.fromJson({
        'id': 1,
        'title': '测试作品',
        'genres': ['剧情'],
        'matchConfidence': 1,
        ...invalidType.value,
      });
      expect(metadata.mediaType, TmdbMediaType.tv);
      for (final value in [
        metadata,
        TmdbMetadata.fromJson(metadata.toJson())
      ]) {
        for (final mode in [
          MediaClassificationMode.conservative,
          MediaClassificationMode.standard,
        ]) {
          final result = resolver.resolve(_series(metadata: value), mode: mode);
          expect(result.categories, isEmpty);
          expect(result.genres, isEmpty);
          expect(result.categorySuggestions.single.confidence,
              MediaClassificationConfidence.low);
          expect(result.needsConfirmation, isTrue);
        }
      }
    });
  }

  test('合法 movie 和 tv 反序列化保留原始匹配证据与分类精度', () {
    for (final type in TmdbMediaType.values) {
      for (final score in [0.3, 0.7, 0.95]) {
        final metadata = TmdbMetadata.fromJson({
          'id': 1,
          'mediaType': type.name,
          'title': '测试作品',
          'genres': ['剧情'],
          'matchConfidence': score,
        });
        expect(metadata.mediaType, type);
        expect(metadata.matchConfidence, score);
        final result = resolver.resolve(_series(metadata: metadata));
        expect(
          result.categorySuggestions.single.confidence,
          score >= 0.8
              ? MediaClassificationConfidence.high
              : score >= 0.5
                  ? MediaClassificationConfidence.medium
                  : MediaClassificationConfidence.low,
        );
        expect(
            result.categories,
            score >= 0.8
                ? [type == TmdbMediaType.movie ? '电影' : '电视剧']
                : isEmpty);
      }
    }
  });

  test('本地每集元数据参与判定而不只信任作品首条', () {
    final animated = _metadata(genres: ['动画']);
    final drama = _metadata(genres: ['剧情']);
    final result = resolver.resolve(
      _series(
          metadata: animated, episodes: [_episode(animated), _episode(drama)]),
      mode: MediaClassificationMode.standard,
    );

    expect(result.categories, isEmpty);
    expect(result.genres, isEmpty);
    expect(result.categorySuggestions.map((value) => value.label), ['动漫']);
    expect(result.categorySuggestions.single.confidence,
        MediaClassificationConfidence.low);
    expect(result.categorySuggestions.single.reason, contains('冲突'));
    expect(result.needsConfirmation, isTrue);
  });

  test('同一类别但不同 TMDB 作品身份仍需确认', () {
    final first = _metadata(id: 1, genres: ['剧情']);
    final second = _metadata(id: 2, genres: ['剧情']);
    final result = resolver.resolve(
      _series(metadata: first, episodes: [_episode(first), _episode(second)]),
      mode: MediaClassificationMode.standard,
    );

    expect(result.categories, isEmpty);
    expect(result.genres, isEmpty);
    expect(result.needsConfirmation, isTrue);
  });

  test('人工选择优先并允许动画电影保留两个分类', () {
    final result = resolver.resolve(
      _series(
          metadata: _metadata(type: TmdbMediaType.movie, genres: ['动画', '冒险'])),
      state: const MediaLibraryUserState(
        categoryOverride: ['电影', '动漫'],
        genreOverride: ['冒险'],
      ),
      mode: MediaClassificationMode.manual,
    );

    expect(result.categories, ['电影', '动漫']);
    expect(result.genres, ['冒险']);
    expect(result.needsConfirmation, isFalse);
    expect(result.isManual, isTrue);
  });

  test('明确取消全部题材与分类不会被自动建议重新补回', () {
    final result = resolver.resolve(
      _series(metadata: _metadata(genres: ['动画'])),
      state:
          const MediaLibraryUserState(categoryOverride: [], genreOverride: []),
    );

    expect(result.categories, isEmpty);
    expect(result.genres, isEmpty);
    expect(result.needsConfirmation, isFalse);
    expect(result.isManual, isTrue);
  });

  test('人工覆盖的一维不会清除另一维待确认状态', () {
    final result = resolver.resolve(
      _series(
          metadata: _metadata(type: TmdbMediaType.movie, genres: ['动画', '冒险'])),
      state: const MediaLibraryUserState(categoryOverride: ['动漫']),
    );

    expect(result.categories, ['动漫']);
    expect(result.genres, isEmpty);
    expect(result.needsConfirmation, isTrue);
  });

  test('人工动漫与电视剧互斥且只允许已支持的分类', () {
    for (final categories in [
      ['动漫', '电视剧'],
      ['未知分类'],
    ]) {
      expect(
        () => resolver.resolve(
          _series(),
          state: MediaLibraryUserState(categoryOverride: categories),
        ),
        throwsArgumentError,
      );
    }
  });
}

TmdbMetadata _metadata({
  int id = 1,
  TmdbMediaType type = TmdbMediaType.tv,
  required List<String> genres,
  double confidence = 1,
}) =>
    TmdbMetadata(
      id: id,
      mediaType: type,
      title: '测试作品',
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 10, 11),
      matchConfidence: confidence,
      genres: genres,
    );

MediaLibrarySeries _series({
  TmdbMetadata? metadata,
  TmdbMediaType? type,
  List<String> genres = const [],
  List<MediaLibraryEpisode> episodes = const [],
}) =>
    MediaLibrarySeries(
      key: 'local|test',
      seriesKey: 'test',
      title: '测试作品',
      sourceKind: MediaSourceKind.local,
      sourceId: 'local',
      sourceName: '本地',
      isAvailable: true,
      episodes: episodes,
      mediaType: type ?? metadata?.mediaType,
      genres: metadata?.genres ?? genres,
      tmdbMetadata: metadata,
    );

MediaLibraryEpisode _episode(TmdbMetadata? metadata,
    {int? season, int? episode}) {
  final item = LocalMediaIndexItem(
    path: 'C:\\Media\\${metadata?.id ?? 0}-${episode ?? 1}.mkv',
    name: '测试文件.mkv',
    parentPath: r'C:\Media',
    sourcePath: r'C:\Media',
    size: 1,
    modified: DateTime.utc(2026, 10, 11),
    seriesName: '测试作品',
    indexedAt: DateTime.utc(2026, 10, 11),
    tmdb: metadata,
    seasonNumber: season,
    episodeNumber: episode,
  );
  return MediaLibraryEpisode.local(
      stableId: item.id, name: item.name, localItem: item);
}
