import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

void main() {
  test('一个作品只请求一次详情并缓存实际三季海报', () async {
    final cacheRoot = await Directory.systemTemp.createTemp('work-tmdb-');
    addTearDown(() => cacheRoot.delete(recursive: true));
    final work = _work();
    final workRepository = CloudWorkTmdbRepository(
      storage: MemoryCloudWorkTmdbStorage(),
    );
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await indexRepository.replaceSource(
      work.sourceId,
      <CloudMediaIndexItem>[
        for (var season = 1; season <= 3; season++)
          _item(
            work,
            id: 's${season}e1',
            seasonNumber: season,
          ),
        _item(
          work,
          id: 'other',
          seasonNumber: 1,
          workKey: '${work.sourceId}|work|other',
        ),
      ],
      const <String, String>{},
      const <String, List<CloudFileEntry>>{},
      const <String>['/影视'],
    );
    final client = _FakeTmdbClient(
      detail: _details(),
      searches: const <String, List<TmdbMetadata>>{},
    );
    final cache = _RecordingPosterCache(cacheRoot);
    final service = CloudWorkTmdbService(
      repository: workRepository,
      indexRepository: indexRepository,
      client: client,
      posterCache: cache,
      now: () => DateTime.utc(2026, 7, 20),
    );

    final outcome = await service.select(
      work,
      _candidate('规范剧名'),
      existingSeasons: const <int>{1, 2, 3},
    );

    expect(client.detailCalls, 1);
    expect(cache.stableIds, <String>[
      work.workKey,
      '${work.workKey}|season:1',
      '${work.workKey}|season:2',
      '${work.workKey}|season:3',
    ]);
    expect(
      outcome.record.seasons.map((season) => season.seasonNumber),
      <int>[1, 2, 3],
    );
    expect(outcome.record.seasons.last.posterCachePath, 'cache-4.jpg');
    expect(outcome.record.tmdbMatchOrigin, TmdbMatchOrigin.manual);
    expect(outcome.record.tmdbRuleVersion, currentTmdbRuleVersion);
    expect(outcome.updatedIndexItems, 3);
    expect(await workRepository.get(work.workKey), outcome.record);
    final indexed = await indexRepository.getBySource(work.sourceId);
    expect(
      indexed
          .where((item) => item.workKey == work.workKey)
          .every((item) => item.displayName.startsWith('TMDB 中文标题')),
      isTrue,
    );
    expect(
      indexed.singleWhere((item) => item.remoteId == 'other').tmdbId,
      isNull,
    );
  });

  test('刮削名称无结果时按作品标题别名继续搜索', () async {
    final work = _work(
      displayTitle: '规则标题',
      titleCandidates: const <String>['规则标题', '英文别名'],
    );
    final record = CloudWorkTmdbRecord.uncheckedFromWork(
      work,
      checkedAt: DateTime.utc(2026, 7, 20),
    ).copyWithScrapeTitle('手动刮削名');
    final client = _FakeTmdbClient(
      detail: _details(),
      searches: <String, List<TmdbMetadata>>{
        '英文别名': <TmdbMetadata>[_candidate('英文别名')],
      },
    );
    final service = CloudWorkTmdbService(
      repository: CloudWorkTmdbRepository(
        storage: MemoryCloudWorkTmdbStorage(),
      ),
      indexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      client: client,
    );

    final candidates = await service.searchCandidates(work, record: record);

    expect(client.queries, <String>['手动刮削名', '规则标题', '英文别名']);
    expect(client.searchedTypes, everyElement(TmdbMediaType.tv));
    expect(candidates.single.title, '英文别名');
    expect(service.requestFor(work, record).queryYear, isNull);
  });

  test('共同分集文件标题作为回魂计的第一搜索候选', () async {
    final work = _work(
      displayTitle: 'The Resurrected',
      titleCandidates: const <String>[
        'The Resurrected',
        'H-回-云鬼-计 台剧',
      ],
    );
    final client = _FakeTmdbClient(
      detail: _details(),
      searches: <String, List<TmdbMetadata>>{
        'The Resurrected': <TmdbMetadata>[_candidate('回魂计')],
      },
    );
    final service = CloudWorkTmdbService(
      repository: CloudWorkTmdbRepository(
        storage: MemoryCloudWorkTmdbStorage(),
      ),
      indexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      client: client,
    );

    final candidates = await service.searchCandidates(work);

    expect(client.queries.first, 'The Resurrected');
    expect(client.searchedTypes.first, TmdbMediaType.tv);
    expect(candidates.single.title, '回魂计');
  });

  test('单季海报缓存失败仍保留全部季度元数据和远程海报', () async {
    final work = _work();
    final service = CloudWorkTmdbService(
      repository: CloudWorkTmdbRepository(
        storage: MemoryCloudWorkTmdbStorage(),
      ),
      indexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      client: _FakeTmdbClient(
        detail: _details(),
        searches: const <String, List<TmdbMetadata>>{},
      ),
      posterCache: _PartiallyFailingPosterCache(),
    );

    final outcome = await service.select(
      work,
      _candidate('规范剧名'),
      existingSeasons: const <int>{1, 2, 3},
    );

    expect(outcome.posterCached, isFalse);
    expect(
      outcome.record.seasons.map((season) => season.seasonNumber),
      <int>[1, 2, 3],
    );
    expect(outcome.record.seasons[0].posterCachePath, isNotNull);
    expect(outcome.record.seasons[1].posterCachePath, isNull);
    expect(outcome.record.seasons[1].posterUrl, '/season-2.jpg');
    expect(outcome.record.seasons[2].posterCachePath, isNotNull);
    expect(outcome.record.status, CloudWorkTmdbStatus.matched);
  });

  test('作品自动匹配记录统一规则来源和版本', () async {
    final work = _work();
    final repository = CloudWorkTmdbRepository(
      storage: MemoryCloudWorkTmdbStorage(),
    );
    final service = CloudWorkTmdbService(
      repository: repository,
      indexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      client: _FakeTmdbClient(
        detail: _details(),
        searches: <String, List<TmdbMetadata>>{
          '规范剧名': <TmdbMetadata>[_candidate('规范剧名')],
        },
      ),
    );

    final outcome = await service.match(work);

    expect(outcome.selected?.tmdbMatchOrigin, TmdbMatchOrigin.automatic);
    expect(outcome.selected?.tmdbRuleVersion, currentTmdbRuleVersion);
  });
}

CloudWorkIdentity _work({
  String displayTitle = '规范剧名',
  List<String> titleCandidates = const <String>['规范剧名'],
}) {
  const root = CloudFileEntry(
    id: 'work-id',
    remotePath: '/影视/规范剧名',
    name: '规范剧名',
    size: 0,
    modifiedAt: null,
    isDirectory: true,
  );
  const workKey = 'quark-a|work|work-id';
  return CloudWorkIdentity(
    sourceId: 'quark-a',
    workKey: workKey,
    root: root,
    remoteName: root.name,
    displayTitle: displayTitle,
    titleCandidates: titleCandidates,
    seasons: <CloudSeasonIdentity>[
      for (var season = 1; season <= 3; season++)
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

CloudMediaIndexItem _item(
  CloudWorkIdentity work, {
  required String id,
  required int seasonNumber,
  String? workKey,
}) {
  return CloudMediaIndexItem(
    sourceId: work.sourceId,
    remoteId: id,
    remotePath: '/影视/规范剧名/第$seasonNumber季/$id.mkv',
    name: '$id.mkv',
    displayName: '旧标题 S${seasonNumber.toString().padLeft(2, '0')}E01.mkv',
    workKey: workKey ?? work.workKey,
    workRootId: work.root.id,
    workRootPath: work.root.remotePath,
    size: 200,
    modifiedAt: null,
    seriesName: '旧标题',
    seasonNumber: seasonNumber,
    episodeNumber: 1,
    mediaType: CloudMediaType.episode,
  );
}

TmdbMetadata _candidate(String title) => TmdbMetadata(
      id: 42,
      mediaType: TmdbMediaType.tv,
      title: title,
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 7, 20),
      matchConfidence: 1,
    );

TmdbMetadata _details() => TmdbMetadata(
      id: 42,
      mediaType: TmdbMediaType.tv,
      title: 'TMDB 中文标题',
      overview: '中文简介',
      posterUrl: '/poster.jpg',
      backdropUrl: '/backdrop.jpg',
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 7, 20),
      matchConfidence: 1,
      seasons: <TmdbSeasonMetadata>[
        for (var season = 0; season <= 4; season++)
          TmdbSeasonMetadata(
            id: season * 100,
            seasonNumber: season,
            name: season == 0 ? '特别篇' : '第 $season 季',
            episodeCount: 8,
            posterUrl: '/season-$season.jpg',
          ),
      ],
    );

class _FakeTmdbClient implements ITmdbClient {
  _FakeTmdbClient({required this.detail, required this.searches});

  final TmdbMetadata detail;
  final Map<String, List<TmdbMetadata>> searches;
  final List<String> queries = <String>[];
  final List<TmdbMediaType> searchedTypes = <TmdbMediaType>[];
  int detailCalls = 0;

  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    detailCalls++;
    return detail;
  }

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    queries.add(query);
    searchedTypes.add(mediaType);
    return searches[query] ?? const <TmdbMetadata>[];
  }
}

class _RecordingPosterCache extends CloudPosterCache {
  _RecordingPosterCache(Directory cacheRoot)
      : super(cacheRoot: cacheRoot, downloader: (_) async => <int>[1]);

  final List<String> stableIds = <String>[];

  @override
  Future<String> resolve({
    required String sourceId,
    required String stableId,
    required String url,
  }) async {
    stableIds.add(stableId);
    return 'cache-${stableIds.length}.jpg';
  }
}

class _PartiallyFailingPosterCache extends CloudPosterCache {
  _PartiallyFailingPosterCache()
      : super(
          cacheRoot: Directory.systemTemp,
          downloader: (_) async => const <int>[1],
        );

  @override
  Future<String> resolve({
    required String sourceId,
    required String stableId,
    required String url,
  }) async {
    if (stableId.endsWith('|season:2')) {
      throw const FileSystemException('季度海报缓存失败');
    }
    return 'cache-${stableId.hashCode}.jpg';
  }
}
