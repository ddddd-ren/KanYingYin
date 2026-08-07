import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/cloud/cloud_tmdb_subject_builder.dart';
import 'package:kanyingyin/services/tmdb/local_tmdb_subject_builder.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

void main() {
  test('本地、网盘作品和网盘资源对同一输入生成相同搜索契约', () {
    final localItem = LocalMediaIndexItem(
      path: r'D:\Media\三体\三体 S01E01.mkv',
      name: '三体 S01E01.mkv',
      parentPath: r'D:\Media\三体',
      sourcePath: r'D:\Media',
      size: 10,
      modified: DateTime(2026),
      seriesName: '三体',
      seasonNumber: 1,
      episodeNumber: 1,
      indexedAt: DateTime(2026),
    );
    final work = CloudWorkIdentity(
      sourceId: 'source',
      workKey: 'work',
      root: const CloudFileEntry(
        id: 'root',
        remotePath: '/三体',
        name: '三体',
        size: 0,
        modifiedAt: null,
        isDirectory: true,
      ),
      remoteName: '三体',
      displayTitle: '三体',
      titleCandidates: const <String>['三体'],
      seasons: const <CloudSeasonIdentity>[
        CloudSeasonIdentity(
          workKey: 'work',
          seasonNumber: 1,
          displayName: '三体 第 1 季',
          remoteDirectories: <CloudFileEntry>[],
          episodes: <CloudEpisodeIdentity>[],
        ),
      ],
    );
    final resource = CloudResourceTmdbTarget(
      sourceId: 'source',
      remote: const CloudRemoteRef(id: 'episode', path: '/三体/三体 S01E01.mkv'),
      displayName: '三体 S01E01.mkv',
      resourceKind: CloudResourceKind.standaloneVideo,
      matchingTitle: '三体',
      matchingSeasonNumber: 1,
      matchingEpisodeNumber: 1,
    );

    final localSubject = const LocalTmdbSubjectBuilder().build(
      seriesName: '三体',
      items: <LocalMediaIndexItem>[localItem],
    );
    final subjects = <TmdbScrapeSubjectLike>[
      _SubjectLike(localSubject),
      _SubjectLike(const CloudTmdbSubjectBuilder().forWork(work)),
      _SubjectLike(const CloudTmdbSubjectBuilder().forResource(resource)),
    ];
    final plans = subjects
        .map(
          (value) => const TmdbScrapePolicy().build(
            value.subject,
            const TmdbScrapeOptions.defaults(),
          ),
        )
        .toList(growable: false);

    for (final plan in plans.skip(1)) {
      expect(plan.queries, plans.first.queries);
      expect(plan.year, plans.first.year);
      expect(plan.mediaTypes, plans.first.mediaTypes);
    }
    expect(plans.first.mediaTypes, const <TmdbMediaType>[TmdbMediaType.tv]);
  });

  test('本地和网盘电影发布名生成相同查询词、年份和媒体类型', () {
    const name = 'Annihilation.2018.BluRay.2160p.x265.10bit.HDR.mkv';
    final localItem = LocalMediaIndexItem(
      path: 'D:\\Media\\$name',
      name: name,
      parentPath: r'D:\Media',
      sourcePath: r'D:\Media',
      size: 10,
      modified: DateTime(2026),
      seriesName: name,
      indexedAt: DateTime(2026),
    );
    const remote = CloudFileEntry(
      id: 'movie',
      remotePath: '/Movies/$name',
      name: name,
      size: 10,
      modifiedAt: null,
      isDirectory: false,
    );
    const work = CloudWorkIdentity(
      sourceId: 'source',
      workKey: 'movie',
      root: remote,
      remoteName: name,
      displayTitle: name,
      titleCandidates: <String>[name],
      seasons: <CloudSeasonIdentity>[],
      standaloneVideos: <CloudFileEntry>[remote],
    );
    final policy = const TmdbScrapePolicy();
    const options = TmdbScrapeOptions.defaults();
    final localPlan = policy.build(
      const LocalTmdbSubjectBuilder().build(
        seriesName: name,
        items: <LocalMediaIndexItem>[localItem],
      ),
      options,
    );
    final cloudPlan = policy.build(
      const CloudTmdbSubjectBuilder().forWork(work),
      options,
    );

    expect(localPlan.queries, cloudPlan.queries);
    expect(localPlan.queries.first, 'Annihilation');
    expect(localPlan.year, 2018);
    expect(cloudPlan.year, 2018);
    expect(localPlan.mediaTypes, <TmdbMediaType>[TmdbMediaType.movie]);
    expect(cloudPlan.mediaTypes, localPlan.mediaTypes);
  });
}

abstract interface class TmdbScrapeSubjectLike {
  TmdbScrapeSubject get subject;
}

class _SubjectLike implements TmdbScrapeSubjectLike {
  const _SubjectLike(this.subject);

  @override
  final TmdbScrapeSubject subject;
}
