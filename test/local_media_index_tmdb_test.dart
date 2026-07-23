import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

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
      ),
      titleLocked: true,
      posterLocked: true,
      overviewLocked: true,
      scrapeStatus: TmdbScrapeStatus.matched,
    );

    final restored = LocalMediaIndexItem.fromJson(item.toJson());
    expect(restored.tmdb?.id, 123);
    expect(restored.tmdb?.title, '电影');
    expect(restored.titleLocked, isTrue);
    expect(restored.posterLocked, isTrue);
    expect(restored.overviewLocked, isTrue);
    expect(restored.scrapeStatus, TmdbScrapeStatus.matched);
  });

  test('旧 Bangumi 索引可以映射为 TMDB 迁移元数据', () {
    final restored = LocalMediaIndexItem.fromJson(_legacyIndexJson());

    expect(restored.tmdb?.id, 456);
    expect(restored.tmdb?.title, '旧中文名');
    expect(restored.tmdb?.overview, '旧简介');
  });

  test('迁移旧字段后新 JSON 不再写回旧键', () {
    final restored = LocalMediaIndexItem.fromJson(_legacyIndexJson());
    final encoded = restored.toJson();

    expect(restored.tmdb?.id, 456);
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
    final restored = LocalMediaIndexItem.fromJson(json);

    expect(restored.path, r'D:\Video\Movie.mkv');
    expect(restored.name, 'Movie.mkv');
    expect(restored.tmdb, isNull);
  });
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
