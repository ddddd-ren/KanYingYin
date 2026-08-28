import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_media_library_adapter.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

void main() {
  test('网盘成品组转换后保留作品和剧集身份', () {
    const source = CloudSource(
      id: 'quark',
      type: CloudSourceType.quark,
      name: '夸克网盘',
      baseUrl: 'https://pan.quark.cn',
      rootPaths: <String>['/剧'],
    );
    final items = <CloudMediaIndexItem>[
      _episode('e1', '/剧/S01E01.mkv', 1),
      _episode('e2', '/剧/S01E02.mkv', 2),
    ];
    final record = CloudWorkTmdbRecord.matched(
      sourceId: source.id,
      workKey: 'quark|work|series',
      workRootId: 'series',
      workRootPath: '/剧',
      remoteName: '原始剧名',
      metadata: TmdbMetadata(
        id: 42,
        mediaType: TmdbMediaType.tv,
        title: '统一剧名',
        language: 'zh-CN',
        matchedAt: DateTime.utc(2026, 8, 28),
        matchConfidence: 1,
        genres: const <String>['动画'],
        posterUrl: '/series.jpg',
        seasons: const <TmdbSeasonMetadata>[
          TmdbSeasonMetadata(
            id: 4201,
            seasonNumber: 1,
            name: '第 1 季',
            episodeCount: 2,
            posterUrl: '/season-1.jpg',
            posterCachePath: r'C:\cache\season-1.jpg',
          ),
        ],
      ),
      checkedAt: DateTime.utc(2026, 8, 28),
    );
    final group = CloudResourceMediaGroup(
      stableKey: 'quark|tmdb|tv|42|season:1',
      workKey: record.workKey,
      displayName: '统一剧名',
      seriesName: '统一剧名',
      isSeries: true,
      seasonNumber: 1,
      videos: <CloudFileEntry>[
        _entry(items[0], '统一剧名 S01E01 第一集.mkv'),
        _entry(items[1], '统一剧名 S01E02 第二集.mkv'),
      ],
      seasons: const <CloudResourceSeasonGroup>[],
      record: null,
      workRecord: record,
      seasonMetadata: record.metadata!.seasons.single,
      isWorkScoped: true,
    );

    final series = const CloudResourceMediaLibraryAdapter().convert(
      source: source,
      collection: CloudResourceCollection(
        groups: <CloudResourceMediaGroup>[group],
      ),
      indexedItems: items,
    );

    expect(series, hasLength(1));
    expect(series.single.key, group.stableKey);
    expect(series.single.title, group.displayName);
    expect(series.single.mediaType, TmdbMediaType.tv);
    expect(series.single.genres, <String>['动画']);
    expect(series.single.tmdbPosterUrl, '/season-1.jpg');
    expect(series.single.posterCachePath, r'C:\cache\season-1.jpg');
    expect(series.single.episodes.map((item) => item.remoteId), <String>[
      'e1',
      'e2',
    ]);
    expect(series.single.episodes.first.subtitleRemoteRefs, isNotEmpty);
    expect(series.single.episodes.first.name, group.videos.first.name);
  });

  test('电影多版本保持网盘成品组的名称与顺序', () {
    const source = CloudSource(
      id: 'openlist',
      type: CloudSourceType.openList,
      name: 'OpenList',
      baseUrl: 'https://example.com',
      rootPaths: <String>['/电影'],
    );
    final first = _movie('version-2', '/电影/版本二.mkv');
    final second = _movie('version-1', '/电影/版本一.mkv');
    final group = CloudResourceMediaGroup(
      stableKey: 'openlist|movie|42',
      seriesName: '测试电影',
      displayName: '测试电影',
      isSeries: false,
      videos: <CloudFileEntry>[
        _entry(first, '测试电影 [4K].mkv'),
        _entry(second, '测试电影 [1080P].mkv'),
      ],
      seasons: const <CloudResourceSeasonGroup>[],
      record: null,
    );

    final result = const CloudResourceMediaLibraryAdapter().convert(
      source: source,
      collection: CloudResourceCollection(
        groups: <CloudResourceMediaGroup>[group],
      ),
      indexedItems: <CloudMediaIndexItem>[first, second],
    );

    expect(result.single.mediaType, TmdbMediaType.movie);
    expect(result.single.episodes.map((item) => item.name), <String>[
      '测试电影 [4K].mkv',
      '测试电影 [1080P].mkv',
    ]);
    expect(result.single.episodes.map((item) => item.remoteId), <String>[
      'version-2',
      'version-1',
    ]);
  });
}

CloudMediaIndexItem _episode(String id, String path, int episode) {
  return CloudMediaIndexItem(
    sourceId: 'quark',
    remoteId: id,
    remotePath: path,
    name: path.split('/').last,
    workKey: 'quark|work|series',
    workRootId: 'series',
    workRootPath: '/剧',
    size: 1024,
    modifiedAt: DateTime.utc(2026, 8, 28),
    seriesName: '原始剧名',
    seasonNumber: 1,
    episodeNumber: episode,
    mediaType: CloudMediaType.episode,
    subtitlePaths: <String>['/剧/S01E01.zh.srt'],
    subtitleRefs: <CloudRemoteRef>[
      const CloudRemoteRef(id: 'subtitle', path: '/剧/S01E01.zh.srt'),
    ],
  );
}

CloudMediaIndexItem _movie(String id, String path) {
  return CloudMediaIndexItem(
    sourceId: 'openlist',
    remoteId: id,
    remotePath: path,
    name: path.split('/').last,
    size: 2048,
    modifiedAt: DateTime.utc(2026, 8, 28),
    seriesName: '测试电影',
    mediaType: CloudMediaType.movie,
  );
}

CloudFileEntry _entry(CloudMediaIndexItem item, String displayName) {
  return CloudFileEntry(
    id: item.remoteId,
    remotePath: item.remotePath,
    name: displayName,
    size: item.size,
    modifiedAt: item.modifiedAt,
    isDirectory: false,
    seasonNumber: item.seasonNumber,
    episodeNumber: item.episodeNumber,
    releaseTags: item.releaseTags,
  );
}
