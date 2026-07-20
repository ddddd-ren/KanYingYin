import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';

void main() {
  test('同作品旧文件记录一致时迁移一次且不重复请求 TMDB', () async {
    final legacyRepository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    await legacyRepository.upsertAll(<CloudResourceTmdbRecord>[
      _legacyEpisode('s1e1', seasonNumber: 1, tmdbId: 42),
      _legacyEpisode('s2e1', seasonNumber: 2, tmdbId: 42),
    ]);
    final fixture = _Fixture(legacyRepository: legacyRepository);
    final tree = _tree(<CloudWorkIdentity>[_work('work-id')]);

    await fixture.coordinator.loadAndSchedule(tree);

    final records = await fixture.repository.getBySource('quark-a');
    expect(records, hasLength(1));
    expect(records.single.metadata?.id, 42);
    expect(records.single.scrapeTitleOverride, '手动刮削名');
    expect(fixture.client.searchCalls, 0);
    expect(fixture.client.detailCalls, 0);
  });

  test('同作品旧记录 TMDB 冲突时不自动选择', () async {
    final legacyRepository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    await legacyRepository.upsertAll(<CloudResourceTmdbRecord>[
      _legacyEpisode('s1e1', seasonNumber: 1, tmdbId: 42),
      _legacyEpisode('s2e1', seasonNumber: 2, tmdbId: 99),
    ]);
    final fixture = _Fixture(legacyRepository: legacyRepository);

    await fixture.coordinator.loadAndSchedule(
      _tree(<CloudWorkIdentity>[_work('work-id')]),
    );

    expect(
      (await fixture.repository.getBySource('quark-a')).single.status,
      CloudWorkTmdbStatus.conflict,
    );
    expect(fixture.client.searchCalls, 0);
    expect(fixture.coordinator.totalCount, 0);
  });

  test('重复作品键只调度一次并保存匹配结果', () async {
    final fixture = _Fixture();
    final work = _work('work-id');

    await fixture.coordinator.loadAndSchedule(
      _tree(<CloudWorkIdentity>[work, work]),
    );

    expect(fixture.coordinator.totalCount, 1);
    expect(fixture.coordinator.completedCount, 1);
    expect(fixture.client.searchCalls, 1);
    expect(fixture.client.detailCalls, 1);
    expect(
      fixture.coordinator.recordsByWorkKey[work.workKey]?.status,
      CloudWorkTmdbStatus.matched,
    );
  });

  test('修改刮削名称只同步目标作品根', () async {
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    final first = _work('first', displayTitle: '同名作品');
    final second = _work('second', displayTitle: '同名作品');
    await indexRepository.replaceSource(
      'quark-a',
      <CloudMediaIndexItem>[
        _indexItem(first),
        _indexItem(second),
      ],
      const <String, String>{},
      const <String, List<CloudFileEntry>>{},
      const <String>['/影视'],
    );
    final fixture = _Fixture(
      apiKey: '',
      indexRepository: indexRepository,
    );
    await fixture.coordinator.loadAndSchedule(
      _tree(<CloudWorkIdentity>[first, second]),
    );

    await fixture.coordinator.saveScrapeTitle(first, '修正标题');

    final indexed = await indexRepository.getBySource('quark-a');
    expect(
      indexed.singleWhere((item) => item.workKey == first.workKey).seriesName,
      '修正标题',
    );
    expect(
      indexed.singleWhere((item) => item.workKey == second.workKey).seriesName,
      '同名作品',
    );
    expect(
      fixture.coordinator.recordsByWorkKey[first.workKey]?.scrapeTitleOverride,
      '修正标题',
    );
  });
}

class _Fixture {
  _Fixture({
    this.apiKey = 'key',
    CloudResourceTmdbRepository? legacyRepository,
    CloudMediaIndexRepository? indexRepository,
  })  : repository = CloudWorkTmdbRepository(
          storage: MemoryCloudWorkTmdbStorage(),
        ),
        legacyRepository = legacyRepository ??
            CloudResourceTmdbRepository(
              storage: MemoryCloudResourceTmdbStorage(),
            ),
        indexRepository = indexRepository ??
            CloudMediaIndexRepository(
              storage: MemoryCloudMediaIndexStorage(),
            ),
        client = _FakeTmdbClient() {
    final service = CloudWorkTmdbService(
      repository: repository,
      indexRepository: this.indexRepository,
      client: client,
      now: () => DateTime.utc(2026, 7, 20),
    );
    coordinator = CloudWorkTmdbCoordinator(
      repository: repository,
      legacyRepository: this.legacyRepository,
      indexRepository: this.indexRepository,
      serviceFactory: (_) => service,
      apiKeyProvider: () => apiKey,
      now: () => DateTime.utc(2026, 7, 20),
    );
  }

  final String apiKey;
  final CloudWorkTmdbRepository repository;
  final CloudResourceTmdbRepository legacyRepository;
  final CloudMediaIndexRepository indexRepository;
  final _FakeTmdbClient client;
  late final CloudWorkTmdbCoordinator coordinator;
}

CloudMediaTree _tree(List<CloudWorkIdentity> works) => CloudMediaTree(
      sourceId: 'quark-a',
      works: works,
      ignored: const <CloudFileEntry>[],
      conflicts: const <CloudMediaTreeConflict>[],
    );

CloudWorkIdentity _work(String rootId, {String displayTitle = '规范剧名'}) {
  final root = CloudFileEntry(
    id: rootId,
    remotePath: '/影视/$rootId',
    name: displayTitle,
    size: 0,
    modifiedAt: null,
    isDirectory: true,
  );
  final workKey = 'quark-a|work|$rootId';
  return CloudWorkIdentity(
    sourceId: 'quark-a',
    workKey: workKey,
    root: root,
    remoteName: root.name,
    displayTitle: displayTitle,
    titleCandidates: <String>[displayTitle],
    seasons: <CloudSeasonIdentity>[
      for (var season = 1; season <= 2; season++)
        CloudSeasonIdentity(
          workKey: workKey,
          seasonNumber: season,
          displayName: '$displayTitle 第 $season 季',
          remoteDirectories: const <CloudFileEntry>[],
          episodes: <CloudEpisodeIdentity>[
            CloudEpisodeIdentity(
              entry: CloudFileEntry(
                id: 's${season}e1',
                remotePath: '/影视/$rootId/第$season季/s${season}e1.mkv',
                name: 's${season}e1.mkv',
                size: 200,
                modifiedAt: null,
                isDirectory: false,
              ),
              remoteName: 's${season}e1.mkv',
              displayName: '$displayTitle S0${season}E01.mkv',
              seasonNumber: season,
              episodeNumber: 1,
              releaseTags: const MediaReleaseTags(),
            ),
          ],
        ),
    ],
  );
}

CloudResourceTmdbRecord _legacyEpisode(
  String id, {
  required int seasonNumber,
  required int tmdbId,
}) {
  return CloudResourceTmdbRecord.matched(
    sourceId: 'quark-a',
    remoteId: id,
    remotePath: '/影视/work-id/第$seasonNumber季/$id.mkv',
    displayName: '$id.mkv',
    resourceKind: CloudResourceKind.standaloneVideo,
    metadata: TmdbMetadata(
      id: tmdbId,
      mediaType: TmdbMediaType.tv,
      title: '规范剧名',
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 7, 20),
      matchConfidence: 1,
    ),
    checkedAt: DateTime.utc(2026, 7, 20),
    customTitle: '手动刮削名',
  );
}

CloudMediaIndexItem _indexItem(CloudWorkIdentity work) {
  return CloudMediaIndexItem(
    sourceId: work.sourceId,
    remoteId: '${work.root.id}-episode',
    remotePath: '${work.root.remotePath}/第一季/01.mkv',
    name: '01.mkv',
    displayName: '${work.displayTitle} S01E01.mkv',
    workKey: work.workKey,
    workRootId: work.root.id,
    workRootPath: work.root.remotePath,
    size: 200,
    modifiedAt: null,
    seriesName: work.displayTitle,
    seasonNumber: 1,
    episodeNumber: 1,
    mediaType: CloudMediaType.episode,
  );
}

class _FakeTmdbClient implements ITmdbClient {
  int searchCalls = 0;
  int detailCalls = 0;

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    searchCalls++;
    return <TmdbMetadata>[
      TmdbMetadata(
        id: 42,
        mediaType: mediaType,
        title: query,
        language: language,
        matchedAt: DateTime.utc(2026, 7, 20),
        matchConfidence: 1,
      ),
    ];
  }

  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    detailCalls++;
    return TmdbMetadata(
      id: id,
      mediaType: mediaType,
      title: 'TMDB 中文标题',
      language: language,
      matchedAt: DateTime.utc(2026, 7, 20),
      matchConfidence: 1,
      seasons: const <TmdbSeasonMetadata>[
        TmdbSeasonMetadata(
          id: 100,
          seasonNumber: 1,
          name: '第 1 季',
          episodeCount: 8,
        ),
        TmdbSeasonMetadata(
          id: 200,
          seasonNumber: 2,
          name: '第 2 季',
          episodeCount: 8,
        ),
      ],
    );
  }
}
