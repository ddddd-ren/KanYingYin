import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

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
    expect(
      collection.groups.last.videos.single.name,
      'TMDB 中文标题 S03E01.mkv',
    );
    expect(
      collection.groups.last.videos.single.remotePath,
      '/影视/作品/第3季/01.mkv',
    );
    expect(collection.groups.last.videos.single.id, 's3e1');
  });

  test('旧资源记录入口展示 TMDB 集名但保留远程引用', () {
    const entry = CloudFileEntry(
      id: 'episode-1',
      remotePath: '/影视/示例剧/示例剧.S01E01.mkv',
      name: '示例剧.S01E01.mkv',
      size: 200,
      modifiedAt: null,
      isDirectory: false,
    );
    final record = CloudResourceTmdbRecord.matched(
      sourceId: 'quark',
      remoteId: entry.id,
      remotePath: entry.remotePath,
      displayName: entry.name,
      resourceKind: CloudResourceKind.standaloneVideo,
      metadata: TmdbMetadata(
        id: 42,
        mediaType: TmdbMediaType.tv,
        title: '示例剧',
        language: 'zh-CN',
        matchedAt: DateTime.utc(2026, 8, 5),
        matchConfidence: 1,
        seasons: const <TmdbSeasonMetadata>[
          TmdbSeasonMetadata(
            id: 1,
            seasonNumber: 1,
            name: '第一季',
            episodeCount: 1,
            episodes: <TmdbEpisodeMetadata>[
              TmdbEpisodeMetadata(
                id: 11,
                episodeNumber: 1,
                name: '试播集',
              ),
            ],
          ),
        ],
      ),
      checkedAt: DateTime.utc(2026, 8, 5),
    );

    final collection = CloudResourceCollectionGrouper().group(
      sourceId: 'quark',
      entries: const <CloudFileEntry>[entry],
      records: <String, CloudResourceTmdbRecord>{record.stableKey: record},
      query: '',
    );

    final video = collection.groups.single.videos.single;
    expect(video.name, '示例剧 S01E01 试播集.mkv');
    expect(video.id, entry.id);
    expect(video.remotePath, entry.remotePath);
  });

  test('已匹配作品修改刮削名称后海报卡优先显示手动名称', () {
    final work = _workIdentity(seasonNumbers: const <int>[1]);
    final record = CloudWorkTmdbRecord.matched(
      sourceId: work.sourceId,
      workKey: work.workKey,
      workRootId: work.root.id,
      workRootPath: work.root.remotePath,
      remoteName: work.remoteName,
      scrapeTitleOverride: '回魂计',
      metadata: TmdbMetadata(
        id: 42,
        mediaType: TmdbMediaType.tv,
        title: '死而复生',
        originalTitle: 'The Resurrected',
        language: 'zh-CN',
        matchedAt: DateTime.utc(2026, 7, 27),
        matchConfidence: 1,
        seasons: const <TmdbSeasonMetadata>[
          TmdbSeasonMetadata(
            id: 421,
            seasonNumber: 1,
            name: '第一季',
            episodeCount: 1,
            episodes: <TmdbEpisodeMetadata>[
              TmdbEpisodeMetadata(
                id: 42101,
                episodeNumber: 1,
                name: '死而复生',
              ),
            ],
          ),
        ],
      ),
      checkedAt: DateTime.utc(2026, 7, 27),
    );
    final item = CloudMediaIndexItem(
      sourceId: work.sourceId,
      remoteId: 'episode-1',
      remotePath: '/影视/回魂计/01.mkv',
      name: '01.mkv',
      displayName: '回魂计 S01E01.mkv',
      workKey: work.workKey,
      workRootId: work.root.id,
      workRootPath: work.root.remotePath,
      size: 200,
      modifiedAt: null,
      seriesName: '回魂计',
      seasonNumber: 1,
      episodeNumber: 1,
      mediaType: CloudMediaType.episode,
    );

    final collection = CloudResourceCollectionGrouper().group(
      items: <CloudMediaIndexItem>[item],
      works: <CloudWorkIdentity>[work],
      recordsByWorkKey: <String, CloudWorkTmdbRecord>{work.workKey: record},
      query: '',
    );

    expect(collection.groups.single.displayName, '回魂计');
    expect(
      collection.groups.single.videos.single.name,
      '回魂计 S01E01 死而复生.mkv',
    );
  });

  test('作品只有第二季时海报标题仍保留季号', () {
    final work = _workIdentity(seasonNumbers: const <int>[2]);
    final item = CloudMediaIndexItem(
      sourceId: work.sourceId,
      remoteId: 'season-2-episode-1',
      remotePath: '/影视/作品/第二季/01.mkv',
      name: '01.mkv',
      displayName: '规则标题 S02E01.mkv',
      workKey: work.workKey,
      workRootId: work.root.id,
      workRootPath: work.root.remotePath,
      size: 200,
      modifiedAt: null,
      seriesName: '规则标题',
      seasonNumber: 2,
      episodeNumber: 1,
      mediaType: CloudMediaType.episode,
    );

    final collection = CloudResourceCollectionGrouper().group(
      items: <CloudMediaIndexItem>[item],
      works: <CloudWorkIdentity>[work],
      query: '',
    );

    expect(collection.groups.single.displayName, '规则标题 第 2 季');
  });

  test('电影作品多版本只产出一张卡并显示发布标签', () {
    const first = CloudFileEntry(
      id: 'a4k',
      remotePath: '/影视/示例电影/示例电影 2160p.mkv',
      name: '示例电影 2160p.mkv',
      size: 200,
      modifiedAt: null,
      isDirectory: false,
    );
    const second = CloudFileEntry(
      id: 'a1080',
      remotePath: '/影视/示例电影/示例电影 1080p.mkv',
      name: '示例电影 1080p.mkv',
      size: 200,
      modifiedAt: null,
      isDirectory: false,
    );
    const root = CloudFileEntry(
      id: 'movie-root',
      remotePath: '/影视/示例电影',
      name: '示例电影',
      size: 0,
      modifiedAt: null,
      isDirectory: true,
    );
    const work = CloudWorkIdentity(
      sourceId: 'quark',
      workKey: 'quark|movie|example',
      root: root,
      remoteName: '示例电影',
      displayTitle: '示例电影',
      titleCandidates: <String>['示例电影'],
      seasons: <CloudSeasonIdentity>[],
      standaloneVideos: <CloudFileEntry>[first, second],
    );
    final items = <CloudMediaIndexItem>[
      for (final entry in <CloudFileEntry>[first, second])
        CloudMediaIndexItem(
          sourceId: 'quark',
          remoteId: entry.id,
          remotePath: entry.remotePath,
          name: entry.name,
          workKey: work.workKey,
          workRootId: root.id,
          workRootPath: root.remotePath,
          size: entry.size,
          modifiedAt: null,
          seriesName: '示例电影',
          mediaType: CloudMediaType.movie,
          releaseTags: MediaReleaseTags(
            resolution: entry.id == 'a4k' ? '2160p' : '1080p',
          ),
        ),
    ];

    final collection = CloudResourceCollectionGrouper().group(
      items: items,
      works: const <CloudWorkIdentity>[work],
      query: '',
    );

    expect(collection.groups, hasLength(1));
    final group = collection.groups.single;
    expect(group.displayName, '示例电影');
    expect(group.isSeries, isFalse);
    expect(group.videos, hasLength(2));
    expect(
      group.videos.map((video) => video.variantLabel),
      containsAll(<String>['2160p', '1080p']),
    );
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

  test('百度作品按季度显示 TMDB 海报并保留同集多个版本', () {
    final work = _workIdentity(sourceId: 'baidu-a');
    final record = CloudWorkTmdbRecord.matched(
      sourceId: work.sourceId,
      workKey: work.workKey,
      workRootId: work.root.id,
      workRootPath: work.root.remotePath,
      remoteName: work.remoteName,
      metadata: _workMetadata,
      checkedAt: DateTime.utc(2026, 7, 21),
    );
    CloudMediaIndexItem item(
      String id,
      int season,
      int episode,
      String resolution,
    ) =>
        CloudMediaIndexItem(
          sourceId: work.sourceId,
          remoteId: id,
          remotePath: '/回魂计/第$season季/$id.mkv',
          name: '$id.mkv',
          displayName: '回魂计 S0${season}E0$episode.mkv',
          workKey: work.workKey,
          workRootId: work.root.id,
          workRootPath: work.root.remotePath,
          size: 200,
          modifiedAt: null,
          seriesName: '回魂计',
          seasonNumber: season,
          episodeNumber: episode,
          mediaType: CloudMediaType.episode,
          releaseTags: MediaReleaseTags(resolution: resolution),
        );

    final collection = CloudResourceCollectionGrouper().group(
      items: <CloudMediaIndexItem>[
        item('s1e1', 1, 1, '1080p'),
        item('s2e1-4k', 2, 1, '2160p'),
        item('s2e1-hd', 2, 1, '1080p'),
        item('s3e1', 3, 1, '2160p'),
      ],
      works: <CloudWorkIdentity>[work],
      recordsByWorkKey: <String, CloudWorkTmdbRecord>{work.workKey: record},
      query: '',
    );

    expect(
      collection.groups.map((group) => group.seasonMetadata?.posterUrl),
      <String?>['/season-1.jpg', '/season-2.jpg', '/season-3.jpg'],
    );
    expect(collection.groups[1].videos, hasLength(2));
    expect(
      collection.groups[1].videos.map((video) => video.id).toSet(),
      <String>{'s2e1-4k', 's2e1-hd'},
    );
  });

  test('回魂计按九个唯一集号展示并保留二十七个真实版本', () {
    final work = _workIdentity(seasonNumbers: const <int>[1]);
    final record = CloudWorkTmdbRecord.matched(
      sourceId: work.sourceId,
      workKey: work.workKey,
      workRootId: work.root.id,
      workRootPath: work.root.remotePath,
      remoteName: work.remoteName,
      metadata: _metadata,
      checkedAt: DateTime.utc(2026, 7, 20),
    );
    final items = <CloudMediaIndexItem>[];
    for (var episode = 1; episode <= 9; episode++) {
      final episodeToken = episode.toString().padLeft(2, '0');
      for (final (id, directory, tags) in <(String, String, MediaReleaseTags)>[
        (
          '4k',
          '4K 高码率',
          const MediaReleaseTags(resolution: '4K', bitrate: '高码率'),
        ),
        (
          'embedded',
          '【全9集】【1080P】【内封简繁英】',
          const MediaReleaseTags(
            resolution: '1080p',
            subtitles: <String>['内封简繁英'],
          ),
        ),
        (
          'burned-in',
          '【全9集】【1080P】【内嵌中字】',
          const MediaReleaseTags(
            resolution: '1080p',
            subtitles: <String>['内嵌中字'],
          ),
        ),
      ]) {
        items.add(
          CloudMediaIndexItem(
            sourceId: work.sourceId,
            remoteId: '$id-$episode',
            remotePath:
                '/影视/作品/$directory/The.Resurrected.S01E$episodeToken.mkv',
            name: 'The.Resurrected.S01E$episodeToken.mkv',
            displayName: '回魂计 S01E$episodeToken.mkv',
            workKey: work.workKey,
            workRootId: work.root.id,
            workRootPath: work.root.remotePath,
            size: 200,
            modifiedAt: null,
            seriesName: '回魂计',
            seasonNumber: 1,
            episodeNumber: episode,
            mediaType: CloudMediaType.episode,
            releaseTags: tags,
          ),
        );
      }
    }

    final collection = CloudResourceCollectionGrouper().group(
      items: items,
      works: <CloudWorkIdentity>[work],
      recordsByWorkKey: <String, CloudWorkTmdbRecord>{work.workKey: record},
      query: '',
    );

    final group = collection.groups.single;
    expect(group.displayName, '回魂计');
    expect(group.uniqueEpisodeCount, 9);
    expect(group.videos, hasLength(27));
    expect(group.videos.take(3).map((video) => video.name), <String>[
      '回魂计 S01E01 [4K 高码率].mkv',
      '回魂计 S01E01 [1080p 内封简繁英].mkv',
      '回魂计 S01E01 [1080p 内嵌中字].mkv',
    ]);
    expect(group.videos.map((video) => video.id).toSet(), hasLength(27));
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

  test('作品级手动匹配后按 TMDB 身份合并不同目录季度并使用各自海报', () {
    final first = _workIdentity(
      seasonNumbers: const <int>[1],
      workId: 'work-s1',
    );
    final second = _workIdentity(
      seasonNumbers: const <int>[2],
      workId: 'work-s2',
    );
    CloudWorkTmdbRecord record(
      CloudWorkIdentity work,
      TmdbSeasonMetadata season,
    ) {
      return CloudWorkTmdbRecord.matched(
        sourceId: work.sourceId,
        workKey: work.workKey,
        workRootId: work.root.id,
        workRootPath: work.root.remotePath,
        remoteName: work.remoteName,
        metadata: _workMetadata.copyWith(seasons: <TmdbSeasonMetadata>[season]),
        checkedAt: DateTime.utc(2026, 7, 20),
        tmdbMatchOrigin: TmdbMatchOrigin.manual,
      );
    }

    CloudMediaIndexItem item(
      CloudWorkIdentity work,
      String id,
      int season,
    ) {
      return CloudMediaIndexItem(
        sourceId: work.sourceId,
        remoteId: id,
        remotePath: '/影视/${work.root.id}/$id.mkv',
        name: '$id.mkv',
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
      );
    }

    final collection = CloudResourceCollectionGrouper().group(
      items: <CloudMediaIndexItem>[
        item(first, 's1e1', 1),
        item(second, 's2e1', 2),
      ],
      works: <CloudWorkIdentity>[first, second],
      recordsByWorkKey: <String, CloudWorkTmdbRecord>{
        first.workKey: record(
          first,
          _workMetadata.seasons.first,
        ),
        second.workKey: record(
          second,
          _workMetadata.seasons[1],
        ),
      },
      query: '',
    );

    expect(collection.groups, hasLength(2));
    expect(
      collection.groups.map((group) => group.seasonNumber),
      <int>[1, 2],
    );
    expect(
      collection.groups.map((group) => group.seasonMetadata?.posterUrl),
      <String?>['/season-1.jpg', '/season-2.jpg'],
    );
    expect(
        collection.groups.first.workKeys,
        containsAll(<String>[
          first.workKey,
          second.workKey,
        ]));
    expect(
      collection.groups
          .expand((group) => group.videos)
          .map((video) => video.id),
      unorderedEquals(<String>['s1e1', 's2e1']),
    );
  });

  test('同剧只有一个季度有 TMDB 记录时仍继承作品身份和季度海报', () {
    final seasonTwo = _workIdentity(
      seasonNumbers: const <int>[2],
      workId: 'work-s2-unmatched',
    );
    final seasonOne = _workIdentity(
      seasonNumbers: const <int>[1],
      workId: 'work-s1-matched',
    );
    final matchedRecord = CloudWorkTmdbRecord.matched(
      sourceId: seasonOne.sourceId,
      workKey: seasonOne.workKey,
      workRootId: seasonOne.root.id,
      workRootPath: seasonOne.root.remotePath,
      remoteName: seasonOne.remoteName,
      metadata: _workMetadata,
      checkedAt: DateTime.utc(2026, 8, 5),
      tmdbMatchOrigin: TmdbMatchOrigin.automatic,
    );

    CloudMediaIndexItem item(CloudWorkIdentity work, String id, int season) {
      return CloudMediaIndexItem(
        sourceId: work.sourceId,
        remoteId: id,
        remotePath: '/影视/${work.root.id}/$id.mkv',
        name: '$id.mkv',
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
      );
    }

    final collection = CloudResourceCollectionGrouper().group(
      items: <CloudMediaIndexItem>[
        item(seasonTwo, 's2e1-unmatched', 2),
        item(seasonOne, 's1e1-matched', 1),
      ],
      works: <CloudWorkIdentity>[seasonTwo, seasonOne],
      recordsByWorkKey: <String, CloudWorkTmdbRecord>{
        seasonOne.workKey: matchedRecord,
      },
      query: '',
    );

    expect(collection.groups, hasLength(2));
    expect(
      collection.groups.map((group) => group.stableKey),
      everyElement(startsWith('quark|tmdb|tv|42|season:')),
    );
    expect(
      collection.groups.map((group) => group.seasonMetadata?.posterUrl),
      <String?>['/season-1.jpg', '/season-2.jpg'],
    );
    expect(
      collection.groups.expand((group) => group.workKeys).toSet(),
      containsAll(<String>[seasonOne.workKey, seasonTwo.workKey]),
    );
  });

  test('索引中没有作品身份的季度资源仍在网盘媒体库中继承唯一匹配作品', () {
    final matchedWork = _workIdentity(
      seasonNumbers: const <int>[2],
      workId: 'work-s2-matched',
    );
    final matchedItem = CloudMediaIndexItem(
      sourceId: matchedWork.sourceId,
      remoteId: 's2e1-matched',
      remotePath: '/影视/规则标题/第2季/01.mkv',
      name: '01.mkv',
      displayName: '规则标题 S02E01.mkv',
      workKey: matchedWork.workKey,
      workRootId: matchedWork.root.id,
      workRootPath: matchedWork.root.remotePath,
      size: 200,
      modifiedAt: null,
      seriesName: '规则标题',
      seasonNumber: 2,
      episodeNumber: 1,
      mediaType: CloudMediaType.episode,
    );
    final orphanItem = CloudMediaIndexItem(
      sourceId: matchedWork.sourceId,
      remoteId: 's2e0-orphan',
      remotePath: '/来自：BT磁力链下载/规则标题 S02E00.mkv',
      name: '规则标题 S02E00.mkv',
      displayName: '规则标题 S02E00.mkv',
      workKey: 'quark|work|work-s2-orphan',
      workRootId: 'work-s2-orphan',
      workRootPath: '/来自：BT磁力链下载',
      size: 200,
      modifiedAt: null,
      seriesName: '规则标题',
      seasonNumber: null,
      episodeNumber: null,
      mediaType: CloudMediaType.movie,
    );
    final record = CloudWorkTmdbRecord.matched(
      sourceId: matchedWork.sourceId,
      workKey: matchedWork.workKey,
      workRootId: matchedWork.root.id,
      workRootPath: matchedWork.root.remotePath,
      remoteName: matchedWork.remoteName,
      metadata: _workMetadata,
      checkedAt: DateTime.utc(2026, 8, 5),
      tmdbMatchOrigin: TmdbMatchOrigin.manual,
    );

    final collection = CloudResourceCollectionGrouper().group(
      items: <CloudMediaIndexItem>[matchedItem, orphanItem],
      works: <CloudWorkIdentity>[matchedWork],
      recordsByWorkKey: <String, CloudWorkTmdbRecord>{
        matchedWork.workKey: record,
      },
      query: '',
    );

    expect(collection.groups, hasLength(1));
    final group = collection.groups.single;
    expect(group.stableKey, 'quark|tmdb|tv|42|season:2');
    expect(group.videos, hasLength(2));
    expect(group.seasonMetadata?.posterUrl, '/season-2.jpg');
    expect(
      group.workKeys,
      containsAll(<String>[matchedWork.workKey, orphanItem.workKey!]),
    );
  });

  test('第一季和第二季标题带不同季度后缀时仍共享 TMDB 作品海报', () {
    final seasonTwo = _workIdentity(
      seasonNumbers: const <int>[2],
      workId: 'work-isy-s2',
      displayTitle: 'Isekai Nonbiri Nouka 2',
      titleCandidates: const <String>['Isekai Nonbiri Nouka 2'],
    );
    final seasonOne = _workIdentity(
      seasonNumbers: const <int>[1],
      workId: 'work-isy-s1',
      displayTitle: 'Isekai Nonbiri Nouka',
      titleCandidates: const <String>['Isekai Nonbiri Nouka'],
    );
    final matchedRecord = CloudWorkTmdbRecord.matched(
      sourceId: seasonOne.sourceId,
      workKey: seasonOne.workKey,
      workRootId: seasonOne.root.id,
      workRootPath: seasonOne.root.remotePath,
      remoteName: seasonOne.remoteName,
      metadata: _workMetadata,
      checkedAt: DateTime.utc(2026, 8, 5),
      tmdbMatchOrigin: TmdbMatchOrigin.manual,
    );

    CloudMediaIndexItem item(CloudWorkIdentity work, String id, int season) {
      return CloudMediaIndexItem(
        sourceId: work.sourceId,
        remoteId: id,
        remotePath: '/影视/${work.root.id}/$id.mkv',
        name: '$id.mkv',
        displayName: '${work.displayTitle} S0${season}E01.mkv',
        workKey: work.workKey,
        workRootId: work.root.id,
        workRootPath: work.root.remotePath,
        size: 200,
        modifiedAt: null,
        seriesName: work.displayTitle,
        seasonNumber: season,
        episodeNumber: 1,
        mediaType: CloudMediaType.episode,
      );
    }

    final collection = CloudResourceCollectionGrouper().group(
      items: <CloudMediaIndexItem>[
        item(seasonTwo, 'isy-s2e1', 2),
        item(seasonOne, 'isy-s1e1', 1),
      ],
      works: <CloudWorkIdentity>[seasonTwo, seasonOne],
      recordsByWorkKey: <String, CloudWorkTmdbRecord>{
        seasonOne.workKey: matchedRecord,
      },
      query: '',
    );

    expect(collection.groups, hasLength(2));
    expect(
      collection.groups.map((group) => group.stableKey),
      everyElement(startsWith('quark|tmdb|tv|42|season:')),
    );
    expect(
      collection.groups.map((group) => group.seasonMetadata?.posterUrl),
      <String?>['/season-1.jpg', '/season-2.jpg'],
    );
  });
}

CloudWorkIdentity _workIdentity({
  String sourceId = 'quark',
  List<int> seasonNumbers = const <int>[1, 2, 3],
  String workId = 'work-id',
  String displayTitle = '规则标题',
  List<String> titleCandidates = const <String>['规则标题', 'Original Title'],
}) {
  final workKey = '$sourceId|work|$workId';
  final root = CloudFileEntry(
    id: workId,
    remotePath: workId == 'work-id' ? '/影视/作品' : '/影视/$workId',
    name: '作品原名',
    size: 0,
    modifiedAt: null,
    isDirectory: true,
  );
  return CloudWorkIdentity(
    sourceId: sourceId,
    workKey: workKey,
    root: root,
    remoteName: root.name,
    displayTitle: displayTitle,
    titleCandidates: titleCandidates,
    seasons: <CloudSeasonIdentity>[
      for (final season in seasonNumbers)
        CloudSeasonIdentity(
          workKey: workKey,
          seasonNumber: season,
          displayName: '$displayTitle 第 $season 季',
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
