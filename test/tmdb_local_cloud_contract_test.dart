import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/cloud/cloud_tmdb_subject_builder.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/tmdb/local_tmdb_subject_builder.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_policy.dart';

void main() {
  const policy = TmdbScrapePolicy();
  const localBuilder = LocalTmdbSubjectBuilder();
  const cloudBuilder = CloudTmdbSubjectBuilder();

  test('相同电视剧在本地和网盘生成相同搜索计划', () {
    final local = localBuilder.build(
      seriesName: '三体 第一季 WEB-DL',
      items: <LocalMediaIndexItem>[
        _localItem('三体.S01E01.2160p.mkv', season: 1, episode: 1),
        _localItem('三体.S01E02.2160p.mkv', season: 1, episode: 2),
      ],
    );
    final cloud = cloudBuilder.forWork(_cloudWork());

    final localPlan = policy.build(
      local,
      const TmdbScrapeOptions.defaults(),
    );
    final cloudPlan = policy.build(
      cloud,
      const TmdbScrapeOptions.defaults(),
    );

    expect(cloudPlan.queries, localPlan.queries);
    expect(cloudPlan.year, localPlan.year);
    expect(cloudPlan.mediaTypes, localPlan.mediaTypes);
  });

  test('相同电影在本地和网盘生成相同搜索计划', () {
    final local = localBuilder.build(
      seriesName: '流浪地球 (2019) BluRay',
      items: <LocalMediaIndexItem>[
        _localItem('流浪地球.2019.BluRay.mkv'),
      ],
    );
    const target = CloudResourceTmdbTarget(
      sourceId: 'cloud',
      remote: CloudRemoteRef(
        id: 'movie',
        path: '/电影/流浪地球.2019.BluRay.mkv',
      ),
      displayName: '流浪地球.2019.BluRay.mkv',
      resourceKind: CloudResourceKind.standaloneVideo,
    );
    final cloud = cloudBuilder.forResource(target);

    final localPlan = policy.build(
      local,
      const TmdbScrapeOptions.defaults(),
    );
    final cloudPlan = policy.build(
      cloud,
      const TmdbScrapeOptions.defaults(),
    );

    expect(cloudPlan.queries, localPlan.queries);
    expect(cloudPlan.year, localPlan.year);
    expect(cloudPlan.mediaTypes, localPlan.mediaTypes);
  });
}

LocalMediaIndexItem _localItem(
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
    seriesName: name.startsWith('三体') ? '三体 第一季 WEB-DL' : '流浪地球 (2019) BluRay',
    seasonNumber: season,
    episodeNumber: episode,
    indexedAt: DateTime(2026),
  );
}

CloudWorkIdentity _cloudWork() {
  const root = CloudFileEntry(
    id: 'work',
    remotePath: '/电视剧/三体 第一季 WEB-DL',
    name: '三体 第一季 WEB-DL',
    size: 0,
    modifiedAt: null,
    isDirectory: true,
  );
  const episode1 = CloudFileEntry(
    id: 'e1',
    remotePath: '/电视剧/三体/三体.S01E01.2160p.mkv',
    name: '三体.S01E01.2160p.mkv',
    size: 1,
    modifiedAt: null,
    isDirectory: false,
    seasonNumber: 1,
    episodeNumber: 1,
  );
  const episode2 = CloudFileEntry(
    id: 'e2',
    remotePath: '/电视剧/三体/三体.S01E02.2160p.mkv',
    name: '三体.S01E02.2160p.mkv',
    size: 1,
    modifiedAt: null,
    isDirectory: false,
    seasonNumber: 1,
    episodeNumber: 2,
  );
  return const CloudWorkIdentity(
    sourceId: 'cloud',
    workKey: 'cloud|work',
    root: root,
    remoteName: '三体 第一季 WEB-DL',
    displayTitle: '三体 第一季 WEB-DL',
    titleCandidates: <String>['三体 第一季 WEB-DL'],
    seasons: <CloudSeasonIdentity>[
      CloudSeasonIdentity(
        workKey: 'cloud|work',
        seasonNumber: 1,
        displayName: '三体 第一季',
        remoteDirectories: <CloudFileEntry>[],
        episodes: <CloudEpisodeIdentity>[
          CloudEpisodeIdentity(
            entry: episode1,
            remoteName: '三体.S01E01.2160p.mkv',
            displayName: '三体 S01E01',
            seasonNumber: 1,
            episodeNumber: 1,
            releaseTags: MediaReleaseTags(),
          ),
          CloudEpisodeIdentity(
            entry: episode2,
            remoteName: '三体.S01E02.2160p.mkv',
            displayName: '三体 S01E02',
            seasonNumber: 1,
            episodeNumber: 2,
            releaseTags: MediaReleaseTags(),
          ),
        ],
      ),
    ],
  );
}
