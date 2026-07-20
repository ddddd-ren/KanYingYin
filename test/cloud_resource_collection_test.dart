import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';

void main() {
  test('作品集合直接产出三张季度卡和虚拟分集名', () {
    final work = _workIdentity();
    final record = CloudWorkTmdbRecord.matched(
      sourceId: work.sourceId,
      workKey: work.workKey,
      workRootId: work.root.id,
      workRootPath: work.root.remotePath,
      remoteName: work.remoteName,
      metadata: _workMetadata,
      checkedAt: DateTime.utc(2026, 7, 20),
    );
    final items = <CloudMediaIndexItem>[
      for (var season = 1; season <= 3; season++)
        CloudMediaIndexItem(
          sourceId: work.sourceId,
          remoteId: 's${season}e1',
          remotePath: '/影视/作品/第$season季/01.mkv',
          name: '01.mkv',
          remoteName: '01.mkv',
          displayName: '规则标题 S0${season}E01.mkv',
          workKey: work.workKey,
          workRootId: work.root.id,
          workRootPath: work.root.remotePath,
          size: 200,
          modifiedAt: null,
          seriesName: '规则标题',
          seasonNumber: season,
          episodeNumber: 1,
          mediaType: CloudMediaType.episode,
        ),
    ];

    final collection = CloudResourceCollectionGrouper().group(
      items: items,
      works: <CloudWorkIdentity>[work],
      recordsByWorkKey: <String, CloudWorkTmdbRecord>{work.workKey: record},
      query: '',
    );

    expect(collection.groups, hasLength(3));
    expect(
      collection.groups.map((group) => group.displayName),
      <String>[
        'TMDB 中文标题 第 1 季',
        'TMDB 中文标题 第 2 季',
        'TMDB 中文标题 第 3 季',
      ],
    );
    expect(
      collection.groups.map((group) => group.seasonMetadata?.posterUrl),
      <String?>['/season-1.jpg', '/season-2.jpg', '/season-3.jpg'],
    );
    expect(collection.groups.last.videos.single.name, '规则标题 S03E01.mkv');
    expect(
      collection.groups.last.videos.single.remotePath,
      '/影视/作品/第3季/01.mkv',
    );
    expect(collection.groups.last.videos.single.id, 's3e1');
  });

  test('同季同集多个版本使用发布规格区分虚拟名称', () {
    final work = _workIdentity();
    CloudMediaIndexItem version(
      String id,
      String path,
      MediaReleaseTags tags,
    ) {
      return CloudMediaIndexItem(
        sourceId: work.sourceId,
        remoteId: id,
        remotePath: path,
        name: path.split('/').last,
        displayName: '规则标题 S01E01.mkv',
        workKey: work.workKey,
        workRootId: work.root.id,
        workRootPath: work.root.remotePath,
        size: 200,
        modifiedAt: null,
        seriesName: '规则标题',
        seasonNumber: 1,
        episodeNumber: 1,
        mediaType: CloudMediaType.episode,
        releaseTags: tags,
      );
    }

    final collection = CloudResourceCollectionGrouper().group(
      items: <CloudMediaIndexItem>[
        version(
          'first',
          '/影视/作品/第一季/01-2160p.mkv',
          const MediaReleaseTags(resolution: '2160p', source: 'Web-DL'),
        ),
        version(
          'second',
          '/影视/作品/第一季/01-1080p.mkv',
          const MediaReleaseTags(resolution: '1080p'),
        ),
      ],
      works: <CloudWorkIdentity>[work],
      query: '',
    );

    expect(
      collection.groups.single.videos.map((video) => video.name),
      unorderedEquals(<String>[
        '规则标题 S01E01 [2160p Web-DL].mkv',
        '规则标题 S01E01 [1080p].mkv',
      ]),
    );
  });

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

CloudWorkIdentity _workIdentity() {
  const workKey = 'quark|work|work-id';
  const root = CloudFileEntry(
    id: 'work-id',
    remotePath: '/影视/作品',
    name: '作品原名',
    size: 0,
    modifiedAt: null,
    isDirectory: true,
  );
  return CloudWorkIdentity(
    sourceId: 'quark',
    workKey: workKey,
    root: root,
    remoteName: root.name,
    displayTitle: '规则标题',
    titleCandidates: const <String>['规则标题', 'Original Title'],
    seasons: <CloudSeasonIdentity>[
      for (var season = 1; season <= 3; season++)
        CloudSeasonIdentity(
          workKey: workKey,
          seasonNumber: season,
          displayName: '规则标题 第 $season 季',
          remoteDirectories: const <CloudFileEntry>[],
          episodes: const <CloudEpisodeIdentity>[],
        ),
    ],
  );
}

final _workMetadata = TmdbMetadata(
  id: 42,
  mediaType: TmdbMediaType.tv,
  title: 'TMDB 中文标题',
  originalTitle: 'Original Title',
  language: 'zh-CN',
  matchedAt: DateTime.utc(2026, 7, 20),
  matchConfidence: 1,
  seasons: <TmdbSeasonMetadata>[
    for (var season = 1; season <= 3; season++)
      TmdbSeasonMetadata(
        id: season * 100,
        seasonNumber: season,
        name: '第 $season 季',
        episodeCount: 8,
        posterUrl: '/season-$season.jpg',
      ),
  ],
);

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
