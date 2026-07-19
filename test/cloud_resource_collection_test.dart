import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';

void main() {
  test('按作品合并剧集并隐藏非视频和不大于阈值的视频', () {
    final entries = <CloudFileEntry>[
      _entry('folder', '/影视/子目录', '子目录', 0, isDirectory: true),
      _entry('show-2', '/影视/Show.S01E02.mkv', 'Show.S01E02.mkv', 200),
      _entry('show-s2', '/影视/Show.S02E01.mkv', 'Show.S02E01.mkv', 200),
      _entry('show-1', '/影视/Show.S01E01.mkv', 'Show.S01E01.mkv', 200),
      _entry('other', '/影视/Other.S01E01.mkv', 'Other.S01E01.mkv', 200),
      _entry('movie', '/影视/Movie.2026.mkv', 'Movie.2026.mkv', 101),
      _entry('subtitle', '/影视/Show.S01E01.ass', 'Show.S01E01.ass', 10),
      _entry('image', '/影视/poster.jpg', 'poster.jpg', 1000),
      _entry('sample', '/影视/sample.mkv', 'sample.mkv', 100),
    ];
    final showRecord = CloudResourceTmdbRecord.matched(
      sourceId: 'quark',
      remoteId: 'show-2',
      remotePath: '/影视/Show.S01E02.mkv',
      displayName: 'Show.S01E02.mkv',
      resourceKind: CloudResourceKind.standaloneVideo,
      metadata: _metadata,
      checkedAt: DateTime.utc(2026, 7, 20),
    );
    final collection = CloudResourceCollectionGrouper().group(
      sourceId: 'quark',
      entries: entries,
      records: <String, CloudResourceTmdbRecord>{
        showRecord.stableKey: showRecord,
      },
      minSizeBytes: 100,
      query: '',
    );

    expect(collection.folders, isEmpty);
    expect(collection.groups, hasLength(3));
    final series = collection.groups.firstWhere(
      (group) => group.seriesName == 'Show',
    );
    expect(series.isSeries, isTrue);
    expect(series.record?.title, '回魂计');
    expect(series.videos.map((video) => video.name), <String>[
      'Show.S01E01.mkv',
      'Show.S01E02.mkv',
      'Show.S02E01.mkv',
    ]);
    expect(series.seasons.map((season) => season.seasonNumber), <int>[1, 2]);
    expect(series.seasons.first.videos.map((video) => video.id),
        <String>['show-1', 'show-2']);
    expect(series.seasons.last.metadata?.posterUrl, '/season-2.jpg');
    final visibleNames = collection.groups
        .expand((group) => group.videos)
        .map((video) => video.name);
    expect(visibleNames, isNot(contains('Show.S01E01.ass')));
    expect(visibleNames, isNot(contains('poster.jpg')));
    expect(visibleNames, isNot(contains('sample.mkv')));
    expect(visibleNames, contains('Movie.2026.mkv'));
  });

  test('查询同时匹配作品标题标准剧名和组内文件名', () {
    final customRecord = CloudResourceTmdbRecord.unchecked(
      sourceId: 'quark',
      remoteId: 'show-1',
      remotePath: '/影视/The.Show.S01E01.mkv',
      displayName: 'The.Show.S01E01.mkv',
      resourceKind: CloudResourceKind.standaloneVideo,
      checkedAt: DateTime.utc(2026, 7, 20),
      customTitle: '我的剧名',
    );
    final entries = <CloudFileEntry>[
      _entry(
        'show-1',
        '/影视/The.Show.S01E01.mkv',
        'The.Show.S01E01.mkv',
        200,
      ),
    ];
    final records = <String, CloudResourceTmdbRecord>{
      customRecord.stableKey: customRecord,
    };
    final grouper = CloudResourceCollectionGrouper();

    final byCustomTitle = grouper.group(
      sourceId: 'quark',
      entries: entries,
      records: records,
      minSizeBytes: 100,
      query: '我的',
    );
    expect(byCustomTitle.groups.single.record?.customTitle, '我的剧名');
    expect(byCustomTitle.folders, isEmpty);

    final byFileName = grouper.group(
      sourceId: 'quark',
      entries: entries,
      records: records,
      minSizeBytes: 100,
      query: 's01e01',
    );
    expect(byFileName.groups, hasLength(1));
  });

  test('同一 TMDB 剧集跨目录聚合且冲突 TMDB 身份不误并', () {
    final first = _entry(
      's1e1',
      '/剧集/第一季/Show.S01E01.mkv',
      'Show.S01E01.mkv',
      200,
    );
    final second = _entry(
      's2e1',
      '/剧集/第二季/Show.S02E01.mkv',
      'Show.S02E01.mkv',
      200,
    );
    final other = _entry(
      'other',
      '/其他/Show.S01E01.mkv',
      'Show.S01E01.mkv',
      200,
    );
    final showRecord = CloudResourceTmdbRecord.matched(
      sourceId: 'quark',
      remoteId: first.id,
      remotePath: first.remotePath,
      displayName: first.name,
      resourceKind: CloudResourceKind.standaloneVideo,
      metadata: _metadata,
      checkedAt: DateTime.utc(2026, 7, 20),
    );
    final otherRecord = CloudResourceTmdbRecord.matched(
      sourceId: 'quark',
      remoteId: other.id,
      remotePath: other.remotePath,
      displayName: other.name,
      resourceKind: CloudResourceKind.standaloneVideo,
      metadata: TmdbMetadata(
        id: 99,
        mediaType: TmdbMediaType.tv,
        title: '另一部剧',
        language: 'zh-CN',
        matchedAt: DateTime.utc(2026, 7, 20),
        matchConfidence: 1,
      ),
      checkedAt: DateTime.utc(2026, 7, 20),
    );

    final grouper = CloudResourceCollectionGrouper();
    final uniqueCollection = grouper.group(
      sourceId: 'quark',
      entries: <CloudFileEntry>[first, second],
      records: <String, CloudResourceTmdbRecord>{
        showRecord.stableKey: showRecord,
      },
      minSizeBytes: 100,
      query: '',
    );
    expect(uniqueCollection.groups, hasLength(1));
    expect(uniqueCollection.groups.single.stableKey, 'quark|tmdb|tv|42');
    expect(uniqueCollection.groups.single.videos.map((video) => video.id),
        <String>['s1e1', 's2e1']);

    final collection = grouper.group(
      sourceId: 'quark',
      entries: <CloudFileEntry>[first, second, other],
      records: <String, CloudResourceTmdbRecord>{
        showRecord.stableKey: showRecord,
        otherRecord.stableKey: otherRecord,
      },
      minSizeBytes: 100,
      query: '',
    );

    expect(collection.groups, hasLength(3));
    expect(
      collection.groups
          .singleWhere(
            (group) => group.record?.tmdbId == 42,
          )
          .stableKey,
      'quark|tmdb|tv|42',
    );
    expect(
      collection.groups
          .singleWhere(
            (group) => group.record?.tmdbId == 99,
          )
          .videos
          .single
          .id,
      'other',
    );
    expect(
      collection.groups
          .singleWhere((group) => group.record == null)
          .videos
          .single
          .id,
      's2e1',
    );
  });
}

CloudFileEntry _entry(
  String id,
  String path,
  String name,
  int size, {
  bool isDirectory = false,
}) {
  return CloudFileEntry(
    id: id,
    remotePath: path,
    name: name,
    size: size,
    modifiedAt: null,
    isDirectory: isDirectory,
  );
}

final _metadata = TmdbMetadata(
  id: 42,
  mediaType: TmdbMediaType.tv,
  title: '回魂计',
  language: 'zh-CN',
  matchedAt: DateTime.utc(2026, 7, 20),
  matchConfidence: 1,
  seasons: const <TmdbSeasonMetadata>[
    TmdbSeasonMetadata(
      id: 100,
      seasonNumber: 1,
      name: '第 1 季',
      episodeCount: 8,
      posterUrl: '/season-1.jpg',
    ),
    TmdbSeasonMetadata(
      id: 200,
      seasonNumber: 2,
      name: '第 2 季',
      episodeCount: 8,
      posterUrl: '/season-2.jpg',
    ),
  ],
);
