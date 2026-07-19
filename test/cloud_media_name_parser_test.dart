import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_media_name_parser.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

void main() {
  const parser = CloudMediaNameParser();

  test('单集名称识别标题、季号、集号和电视剧类型', () {
    final draft = parser.parse(
      originalName: 'Alice in Borderland S01E01.mkv',
      isDirectory: false,
    );

    expect(draft.originalName, 'Alice in Borderland S01E01.mkv');
    expect(draft.searchTitle, 'Alice in Borderland');
    expect(draft.mediaTypeMode, TmdbMediaTypeMode.tv);
    expect(draft.seasonNumber, 1);
    expect(draft.episodeNumber, 1);
    expect(draft.year, isNull);
  });

  test('发布标签被清理且括号年份被结构化', () {
    final draft = parser.parse(
      originalName: '弥留之国的爱丽丝 (2020) 2160p WEB-DL x265 HDR 全8集',
      isDirectory: true,
    );

    expect(draft.searchTitle, '弥留之国的爱丽丝');
    expect(draft.year, 2020);
  });

  test('自定义剧名优先但季集仍从原名称识别', () {
    final draft = parser.parse(
      originalName: 'Alice.in.Borderland.S02E03.1080p.mkv',
      isDirectory: false,
      preferredTitle: '弥留之国的爱丽丝',
    );

    expect(draft.searchTitle, '弥留之国的爱丽丝');
    expect(draft.seasonNumber, 2);
    expect(draft.episodeNumber, 3);
  });

  test('只删除已知发布标签并保留正式括号标题', () {
    final rec = parser.parse(
      originalName: '[REC] (2007).mkv',
      isDirectory: false,
    );
    final release = parser.parse(
      originalName: '作品【字幕组】[WEB-DL] 1080p.mkv',
      isDirectory: false,
    );

    expect(rec.searchTitle, '[REC]');
    expect(rec.year, 2007);
    expect(release.searchTitle, '作品');
  });

  test('未知名称不猜测结构字段', () {
    final draft = parser.parse(
      originalName: 'Untitled Video.mkv',
      isDirectory: false,
    );

    expect(draft.searchTitle, 'Untitled Video');
    expect(draft.year, isNull);
    expect(draft.seasonNumber, isNull);
    expect(draft.episodeNumber, isNull);
  });
}
