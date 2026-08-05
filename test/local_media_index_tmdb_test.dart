import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';

void main() {
  test('TMDB 元数据和锁定状态可以 JSON 往返', () {
    final item = LocalMediaIndexItem(
      path: r'D:\Video\Movie.mkv',
      name: 'Movie.mkv',
      parentPath: r'D:\Video',
      sourcePath: r'D:\Video',
      size: 100,
      modified: DateTime(2026),
      seriesName: 'Movie',
      indexedAt: DateTime(2026),
      tmdb: TmdbMetadata(
        id: 123,
        mediaType: TmdbMediaType.movie,
        title: '电影',
        originalTitle: 'Movie',
        overview: '简介',
        releaseDate: '2026-01-01',
        rating: 8.5,
        posterUrl: '/poster.jpg',
        backdropUrl: '/backdrop.jpg',
        language: 'zh-CN',
        matchedAt: DateTime(2026),
        matchConfidence: 0.95,
        genres: const <String>['动作', '科幻'],
      ),
      titleLocked: true,
      posterLocked: true,
      overviewLocked: true,
      scrapeStatus: TmdbScrapeStatus.matched,
    );

    final restored = LocalMediaIndexItem.fromJson(item.toJson());
    expect(restored.tmdb?.id, 123);
    expect(restored.tmdb?.title, '电影');
    expect(restored.tmdb?.genres, const <String>['动作', '科幻']);
    expect(restored.titleLocked, isTrue);
    expect(restored.posterLocked, isTrue);
    expect(restored.overviewLocked, isTrue);
    expect(restored.scrapeStatus, TmdbScrapeStatus.matched);

    final dirtyGenres = TmdbMetadata.fromJson(<String, dynamic>{
      ...item.tmdb!.toJson(),
      'genres': <Object?>['动作', '', '动作', 42, ' 科幻 '],
    });
    expect(dirtyGenres.genres, const <String>['动作', '科幻']);
  });

  test('本地剧集展示 TMDB 集名但保留原始播放路径和字幕', () {
    final item = LocalMediaIndexItem(
      path: r'D:\Video\三体\三体 S01E01.mkv',
      name: '三体 S01E01.mkv',
      parentPath: r'D:\Video\三体',
      sourcePath: r'D:\Video',
      size: 100,
      modified: DateTime(2026),
      seriesName: '三体',
      seasonNumber: 1,
      episodeNumber: 1,
      episodeTitle: '片源标题',
      subtitlePath: r'D:\Video\三体\三体 S01E01.ass',
      indexedAt: DateTime(2026),
      tmdb: TmdbMetadata(
        id: 1,
        mediaType: TmdbMediaType.tv,
        title: '三体',
        language: 'zh-CN',
        matchedAt: DateTime(2026),
        matchConfidence: 1,
        seasons: const <TmdbSeasonMetadata>[
          TmdbSeasonMetadata(
            id: 11,
            seasonNumber: 1,
            name: '第一季',
            episodeCount: 1,
            episodes: <TmdbEpisodeMetadata>[
              TmdbEpisodeMetadata(
                id: 111,
                episodeNumber: 1,
                name: '第一集',
              ),
            ],
          ),
        ],
      ),
    );

    expect(item.displayTitle, '三体 S01E01 第一集');
    expect(item.path, r'D:\Video\三体\三体 S01E01.mkv');
    expect(item.subtitlePath, r'D:\Video\三体\三体 S01E01.ass');

    final itemWithoutTmdbEpisodeName = item.copyWith(episodeNumber: 2);
    expect(itemWithoutTmdbEpisodeName.displayTitle, 'S01E02  片源标题');
  });

  test('领域模型只解析当前 TMDB 结构', () {
    final restored = LocalMediaIndexItem.fromJson(_legacyIndexJson());

    expect(restored.tmdb, isNull);
  });

  test('仓储读取边界把旧 Bangumi 索引迁移为 TMDB 元数据', () {
    final repository = LocalMediaIndexRepository(
      storage: _MemoryLocalMediaIndexStorage(
        <String, Object?>{
          SettingBoxKey.localMediaIndex: [_legacyIndexJson()],
        },
      ),
    );

    final restored = repository.getAll().single;
    final encoded = restored.toJson();

    expect(restored.tmdb?.id, 456);
    expect(restored.tmdb?.title, '旧中文名');
    expect(restored.tmdb?.overview, '旧简介');
    for (final key in const <String>[
      'bangumiId',
      'bangumiName',
      'bangumiNameCn',
      'bangumiRatingScore',
      'bangumiAirDate',
      'bangumiSummary',
      'bangumiCoverUrl',
    ]) {
      expect(encoded, isNot(contains(key)), reason: key);
    }
  });

  test('旧元数据损坏时仍保留视频索引', () {
    final json = _legacyIndexJson()..['bangumiId'] = <String>['bad'];
    final repository = LocalMediaIndexRepository(
      storage: _MemoryLocalMediaIndexStorage(
        <String, Object?>{
          SettingBoxKey.localMediaIndex: [json],
        },
      ),
    );
    final restored = repository.getAll().single;

    expect(restored.path, r'D:\Video\Movie.mkv');
    expect(restored.name, 'Movie.mkv');
    expect(restored.tmdb, isNull);
  });
}

class _MemoryLocalMediaIndexStorage implements LocalMediaIndexStorage {
  _MemoryLocalMediaIndexStorage(this.values);

  final Map<String, Object?> values;

  @override
  Object? read(String key, {Object? defaultValue}) =>
      values[key] ?? defaultValue;

  @override
  Future<void> write(String key, Object? value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

Map<String, dynamic> _legacyIndexJson() => <String, dynamic>{
      'path': r'D:\Video\Movie.mkv',
      'name': 'Movie.mkv',
      'parentPath': r'D:\Video',
      'sourcePath': r'D:\Video',
      'size': 100,
      'modifiedMillis': DateTime(2026).millisecondsSinceEpoch,
      'seriesName': 'Movie',
      'indexedAtMillis': DateTime(2026).millisecondsSinceEpoch,
      'bangumiId': 456,
      'bangumiName': 'Movie',
      'bangumiNameCn': '旧中文名',
      'bangumiSummary': '旧简介',
      'bangumiCoverUrl': 'https://example.com/cover.jpg',
    };
