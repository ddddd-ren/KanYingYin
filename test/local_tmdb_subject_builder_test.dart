import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/services/tmdb/local_tmdb_subject_builder.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

void main() {
  test('本地系列生成统一标题候选和季集证据', () {
    final items = <LocalMediaIndexItem>[
      _item('三体.S01E01.2160p.mkv', season: 1, episode: 1),
      _item('三体.S01E02.2160p.mkv', season: 1, episode: 2),
    ];

    final subject = const LocalTmdbSubjectBuilder().build(
      seriesName: '三体 第一季 WEB-DL',
      items: items,
    );

    expect(subject.stableKey, '三体 第一季 web-dl');
    expect(subject.titleCandidates.first, '三体 第一季 WEB-DL');
    expect(subject.seasonNumbers, <int>{1});
    expect(subject.episodeNumbers, <int>{1, 2});
    expect(subject.mediaEvidence, TmdbMediaEvidence.tv);
  });

  test('单个无季集证据的本地视频视为电影证据', () {
    final subject = const LocalTmdbSubjectBuilder().build(
      seriesName: '流浪地球 (2019)',
      items: <LocalMediaIndexItem>[_item('流浪地球.2019.mkv')],
    );

    expect(subject.mediaEvidence, TmdbMediaEvidence.movie);
  });
}

LocalMediaIndexItem _item(
  String name, {
  int? season,
  int? episode,
}) {
  return LocalMediaIndexItem(
    path: 'D:/Video/$name',
    name: name,
    parentPath: 'D:/Video',
    sourcePath: 'D:/Video',
    size: 1,
    modified: DateTime(2026),
    seriesName: '三体',
    seasonNumber: season,
    episodeNumber: episode,
    indexedAt: DateTime(2026),
  );
}
