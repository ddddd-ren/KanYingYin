import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

void main() {
  test('文件夹查询名移除编码和完结标记但保留年份', () {
    expect(
      CloudResourceTmdbService.queryName(
        'H-回-元异-计【台剧】 (2025) 4K 全6集 完结',
        isDirectory: true,
      ),
      'H-回-元异-计 (2025)',
    );
  });

  test('独立视频查询名移除画质编码和杜比声道尾缀', () {
    expect(
      CloudResourceTmdbService.queryName(
        '流浪地球2.2160p WEB-DL HEVC DDP 5.1.mkv',
        isDirectory: false,
      ),
      '流浪地球2',
    );
  });

  test('自动匹配保存详情、海报并同步文件夹子树索引', () async {
    final cacheRoot = await Directory.systemTemp.createTemp('resource-tmdb-');
    addTearDown(() => cacheRoot.delete(recursive: true));
    final resourceRepository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await indexRepository.replaceSource(
      'source-a',
      <CloudMediaIndexItem>[
        _item('/影视/流浪地球/流浪地球.mkv'),
        _item('/影视/流浪地球2/流浪地球2.mkv'),
      ],
      const <String, String>{},
      const <String, List<CloudFileEntry>>{},
      const <String>[],
    );
    final client = _FakeTmdbClient(
      searches: <TmdbMediaType, List<TmdbMetadata>>{
        TmdbMediaType.tv: <TmdbMetadata>[_candidate(TmdbMediaType.tv)],
      },
      detail: _candidate(TmdbMediaType.tv).copyWith(
        title: '中文片名',
        overview: '中文简介',
        posterUrl: '/poster.jpg',
      ),
    );
    final service = CloudResourceTmdbService(
      repository: resourceRepository,
      indexRepository: indexRepository,
      client: client,
      posterCache: CloudPosterCache(
        cacheRoot: cacheRoot,
        downloader: (_) async => <int>[1, 2, 3],
      ),
      now: () => DateTime.utc(2026, 7, 19),
    );
    final target = _target(
      path: '/影视/流浪地球',
      name: '流浪地球',
      kind: CloudResourceKind.directory,
    );

    final outcome = await service.match(target);

    expect(outcome.selected?.tmdbId, 42);
    expect(outcome.selected?.title, '中文片名');
    expect(await File(outcome.selected!.posterCachePath!).exists(), isTrue);
    final indexed = await indexRepository.getBySource('source-a');
    expect(indexed[0].tmdbId, 42);
    expect(indexed[1].tmdbId, isNull);
    expect(client.searchedTypes, <TmdbMediaType>[
      TmdbMediaType.tv,
      TmdbMediaType.movie,
    ]);
  });

  test('自动模式首选类型无候选时尝试另一类型', () async {
    final service = _service(
      _FakeTmdbClient(
        searches: <TmdbMediaType, List<TmdbMetadata>>{
          TmdbMediaType.movie: const <TmdbMetadata>[],
          TmdbMediaType.tv: <TmdbMetadata>[_candidate(TmdbMediaType.tv)],
        },
        detail: _candidate(TmdbMediaType.tv),
      ),
    );

    await service.service.searchCandidates(
      _target(
        path: '/影视/独立视频.mkv',
        name: '独立视频.mkv',
        kind: CloudResourceKind.standaloneVideo,
      ),
    );

    expect(service.client.searchedTypes, <TmdbMediaType>[
      TmdbMediaType.movie,
      TmdbMediaType.tv,
    ]);
  });

  test('无候选保存未匹配且手动选择保存用户候选', () async {
    final client = _FakeTmdbClient(
      searches: const <TmdbMediaType, List<TmdbMetadata>>{},
      detail: _candidate(TmdbMediaType.movie).copyWith(title: '手动选择标题'),
    );
    final service = _service(client);
    final target = _target(
      path: '/影视/未知.mkv',
      name: '未知.mkv',
      kind: CloudResourceKind.standaloneVideo,
    );

    final outcome = await service.service.match(target);
    expect(outcome.candidates, isEmpty);
    expect(
      (await service.repository.get(target.stableKey))?.status,
      CloudResourceTmdbStatus.unmatched,
    );

    final record = await service.service.select(
      target,
      _candidate(TmdbMediaType.movie),
    );
    expect(record.tmdbId, 42);
    expect(record.title, '手动选择标题');
  });

  test('自定义剧名成为 TMDB 查询词且不改变远程路径', () async {
    final client = _FakeTmdbClient(
      searches: const <TmdbMediaType, List<TmdbMetadata>>{},
      detail: _candidate(TmdbMediaType.tv),
    );
    final harness = _service(client);
    final target = _target(
      path: '/影视/原目录',
      name: '原目录',
      kind: CloudResourceKind.directory,
      customTitle: '自定义剧名',
    );

    await harness.service.searchCandidates(target);

    expect(client.queries.first, '自定义剧名');
    expect(target.remote.path, '/影视/原目录');
  });

  test('匹配和未匹配记录都保留自定义剧名', () async {
    final matchingClient = _FakeTmdbClient(
      searches: <TmdbMediaType, List<TmdbMetadata>>{
        TmdbMediaType.tv: <TmdbMetadata>[_candidate(TmdbMediaType.tv)],
      },
      detail: _candidate(TmdbMediaType.tv),
    );
    final matching = _service(matchingClient);
    final matchedTarget = _target(
      path: '/影视/流浪地球',
      name: '原目录',
      kind: CloudResourceKind.directory,
      customTitle: '流浪地球',
    );

    final outcome = await matching.service.match(matchedTarget);
    expect(outcome.selected?.customTitle, '流浪地球');
    expect(
      (await matching.repository.get(matchedTarget.stableKey))?.customTitle,
      '流浪地球',
    );

    final unmatchedClient = _FakeTmdbClient(
      searches: const <TmdbMediaType, List<TmdbMetadata>>{},
      detail: _candidate(TmdbMediaType.tv),
    );
    final unmatched = _service(unmatchedClient);
    final unmatchedTarget = _target(
      path: '/影视/未知',
      name: '原目录',
      kind: CloudResourceKind.directory,
      customTitle: '未知剧名',
    );
    await unmatched.service.match(unmatchedTarget);
    expect(
      (await unmatched.repository.get(unmatchedTarget.stableKey))?.customTitle,
      '未知剧名',
    );
  });

  test('准备搜索的自动类型同时查询电影和电视剧', () async {
    final client = _FakeTmdbClient(
      searches: <TmdbMediaType, List<TmdbMetadata>>{
        TmdbMediaType.movie: <TmdbMetadata>[
          _candidate(TmdbMediaType.movie),
        ],
        TmdbMediaType.tv: <TmdbMetadata>[_candidate(TmdbMediaType.tv)],
      },
      detail: _candidate(TmdbMediaType.tv),
    );
    final harness = _service(client);

    final outcome = await harness.service.searchPrepared(
      _target(
        path: '/影视/流浪地球',
        name: '流浪地球',
        kind: CloudResourceKind.directory,
      ),
      const CloudResourceTmdbSearchRequest(
        queryTitle: '流浪地球',
        queryYear: 2019,
        mediaTypeMode: TmdbMediaTypeMode.auto,
        options: TmdbScrapeOptions.defaults(),
      ),
    );

    expect(client.searchedTypes, <TmdbMediaType>[
      TmdbMediaType.tv,
      TmdbMediaType.movie,
    ]);
    expect(outcome.ranked.candidates, hasLength(2));
  });

  test('候选缓存命中后按新年份重评分且过期后重新请求', () async {
    var now = DateTime.utc(2026, 7, 19, 12);
    final client = _FakeTmdbClient(
      searches: <TmdbMediaType, List<TmdbMetadata>>{
        TmdbMediaType.movie: <TmdbMetadata>[
          _candidate(TmdbMediaType.movie),
        ],
      },
      detail: _candidate(TmdbMediaType.movie),
    );
    final service = CloudResourceTmdbService(
      repository: CloudResourceTmdbRepository(
        storage: MemoryCloudResourceTmdbStorage(),
      ),
      indexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      client: client,
      now: () => now,
    );
    final target = _target(
      path: '/影视/独立视频.mkv',
      name: '独立视频.mkv',
      kind: CloudResourceKind.standaloneVideo,
    );
    const options = TmdbScrapeOptions.defaults();

    final first = await service.searchPrepared(
      target,
      const CloudResourceTmdbSearchRequest(
        queryTitle: '独立视频',
        queryYear: 2019,
        mediaTypeMode: TmdbMediaTypeMode.movie,
        options: options,
      ),
    );
    final second = await service.searchPrepared(
      target,
      const CloudResourceTmdbSearchRequest(
        queryTitle: '独立视频',
        queryYear: 2025,
        mediaTypeMode: TmdbMediaTypeMode.movie,
        options: options,
      ),
    );

    expect(client.searchedTypes, <TmdbMediaType>[TmdbMediaType.movie]);
    expect(first.ranked.best!.score, greaterThan(second.ranked.best!.score));

    now = now.add(const Duration(minutes: 11));
    await service.searchPrepared(
      target,
      const CloudResourceTmdbSearchRequest(
        queryTitle: '独立视频',
        mediaTypeMode: TmdbMediaTypeMode.movie,
        options: options,
      ),
    );
    expect(client.searchedTypes, <TmdbMediaType>[
      TmdbMediaType.movie,
      TmdbMediaType.movie,
    ]);
  });

  test('候选缓存超过上限时淘汰最久未使用查询', () async {
    final client = _FakeTmdbClient(
      searches: const <TmdbMediaType, List<TmdbMetadata>>{},
      detail: _candidate(TmdbMediaType.movie),
    );
    final service = CloudResourceTmdbService(
      repository: CloudResourceTmdbRepository(
        storage: MemoryCloudResourceTmdbStorage(),
      ),
      indexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      client: client,
      maximumCachedSearches: 2,
    );
    final target = _target(
      path: '/影视/影片.mkv',
      name: '影片.mkv',
      kind: CloudResourceKind.standaloneVideo,
    );
    const options = TmdbScrapeOptions.defaults();
    Future<void> search(String title) => service.searchPrepared(
          target,
          CloudResourceTmdbSearchRequest(
            queryTitle: title,
            mediaTypeMode: TmdbMediaTypeMode.movie,
            options: options,
          ),
        );

    await search('影片一');
    await search('影片二');
    await search('影片三');
    await search('影片一');

    expect(client.queries, <String>['影片一', '影片二', '影片三', '影片一']);
  });

  test('海报缓存失败仍保存文字元数据', () async {
    final cacheRoot = await Directory.systemTemp.createTemp('tmdb-poster-');
    addTearDown(() => cacheRoot.delete(recursive: true));
    final repository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    final service = CloudResourceTmdbService(
      repository: repository,
      indexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      client: _FakeTmdbClient(
        searches: const <TmdbMediaType, List<TmdbMetadata>>{},
        detail: _candidate(TmdbMediaType.movie).copyWith(
          title: '中文标题',
          overview: '中文简介',
          posterUrl: '/poster.jpg',
        ),
      ),
      posterCache: CloudPosterCache(
        cacheRoot: cacheRoot,
        downloader: (_) => throw StateError('图片下载失败'),
      ),
    );
    final target = _target(
      path: '/影视/独立视频.mkv',
      name: '独立视频.mkv',
      kind: CloudResourceKind.standaloneVideo,
    );

    final outcome = await service.selectWithOutcome(
      target,
      _candidate(TmdbMediaType.movie),
    );

    expect(outcome.record.title, '中文标题');
    expect(outcome.record.posterUrl, '/poster.jpg');
    expect(outcome.record.posterCachePath, isNull);
    expect(outcome.posterCached, isFalse);
    final stored = await repository.get(target.stableKey);
    expect(stored?.tmdbId, outcome.record.tmdbId);
    expect(stored?.title, outcome.record.title);
  });

  test('选择电视剧候选会分别缓存主海报和季度海报', () async {
    final cacheRoot = await Directory.systemTemp.createTemp('tmdb-seasons-');
    addTearDown(() => cacheRoot.delete(recursive: true));
    final posterCache = _RecordingPosterCache(cacheRoot);
    final repository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    final service = CloudResourceTmdbService(
      repository: repository,
      indexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      client: _FakeTmdbClient(
        searches: const <TmdbMediaType, List<TmdbMetadata>>{},
        detail: TmdbMetadata(
          id: 42,
          mediaType: TmdbMediaType.tv,
          title: '弥留之国的爱丽丝',
          posterUrl: '/show.jpg',
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
        ),
      ),
      posterCache: posterCache,
    );
    final target = _target(
      path: '/影视/Show.S01E01.mkv',
      name: 'Show.S01E01.mkv',
      kind: CloudResourceKind.standaloneVideo,
    );

    final outcome = await service.selectWithOutcome(
      target,
      _candidate(TmdbMediaType.tv),
    );

    expect(posterCache.stableIds, <String>[
      target.stableKey,
      '${target.stableKey}|season:1',
      '${target.stableKey}|season:2',
    ]);
    expect(outcome.record.seasons[0].posterCachePath, 'cache-2.jpg');
    expect(outcome.record.seasons[1].posterCachePath, 'cache-3.jpg');
    expect(outcome.posterCached, isTrue);
    expect(
      (await repository.get(target.stableKey))?.seasons.last.posterCachePath,
      'cache-3.jpg',
    );
  });

  test('索引同步失败返回部分成功且保留资源记录', () async {
    final repository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    final indexStorage = _FailingCloudMediaIndexStorage();
    final indexRepository = CloudMediaIndexRepository(storage: indexStorage);
    await indexRepository.replaceSource(
      'source-a',
      <CloudMediaIndexItem>[_item('/影视/独立视频.mkv')],
      const <String, String>{},
      const <String, List<CloudFileEntry>>{},
      const <String>[],
    );
    indexStorage.failWrites = true;
    final service = CloudResourceTmdbService(
      repository: repository,
      indexRepository: indexRepository,
      client: _FakeTmdbClient(
        searches: const <TmdbMediaType, List<TmdbMetadata>>{},
        detail: _candidate(TmdbMediaType.movie),
      ),
    );
    final target = _target(
      path: '/影视/独立视频.mkv',
      name: '独立视频.mkv',
      kind: CloudResourceKind.standaloneVideo,
    );

    final outcome = await service.selectWithOutcome(
      target,
      _candidate(TmdbMediaType.movie),
    );

    expect(outcome.record.tmdbId, 42);
    expect(outcome.indexSynced, isFalse);
    final stored = await repository.get(target.stableKey);
    expect(stored?.tmdbId, outcome.record.tmdbId);
    expect(stored?.title, outcome.record.title);
  });
}

CloudResourceTmdbTarget _target({
  required String path,
  required String name,
  required CloudResourceKind kind,
  String? customTitle,
}) {
  return CloudResourceTmdbTarget(
    sourceId: 'source-a',
    remote: CloudRemoteRef(id: path, path: path),
    displayName: name,
    resourceKind: kind,
    customTitle: customTitle,
  );
}

CloudMediaIndexItem _item(String path) {
  return CloudMediaIndexItem(
    sourceId: 'source-a',
    remoteId: path,
    remotePath: path,
    name: path.split('/').last,
    size: 100,
    modifiedAt: null,
    seriesName: '流浪地球',
  );
}

TmdbMetadata _candidate(TmdbMediaType type) {
  return TmdbMetadata(
    id: 42,
    mediaType: type,
    title: type == TmdbMediaType.tv ? '流浪地球' : '独立视频',
    releaseDate: '2019-01-01',
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026, 7, 19),
    matchConfidence: 1,
  );
}

_ServiceHarness _service(_FakeTmdbClient client) {
  final repository = CloudResourceTmdbRepository(
    storage: MemoryCloudResourceTmdbStorage(),
  );
  return _ServiceHarness(
    repository: repository,
    client: client,
    service: CloudResourceTmdbService(
      repository: repository,
      indexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      client: client,
      now: () => DateTime.utc(2026, 7, 19),
    ),
  );
}

class _ServiceHarness {
  const _ServiceHarness({
    required this.repository,
    required this.client,
    required this.service,
  });

  final CloudResourceTmdbRepository repository;
  final _FakeTmdbClient client;
  final CloudResourceTmdbService service;
}

class _FakeTmdbClient implements ITmdbClient {
  _FakeTmdbClient({required this.searches, required this.detail});

  final Map<TmdbMediaType, List<TmdbMetadata>> searches;
  final TmdbMetadata detail;
  final List<TmdbMediaType> searchedTypes = <TmdbMediaType>[];
  final List<String> queries = <String>[];

  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    return detail;
  }

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    searchedTypes.add(mediaType);
    queries.add(query);
    return searches[mediaType] ?? const <TmdbMetadata>[];
  }
}

class _RecordingPosterCache extends CloudPosterCache {
  _RecordingPosterCache(Directory cacheRoot)
      : super(
          cacheRoot: cacheRoot,
          downloader: (_) async => <int>[1],
        );

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

class _FailingCloudMediaIndexStorage implements CloudMediaIndexStorage {
  Map<String, Object?> _value = <String, Object?>{};
  bool failWrites = false;

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<Map<String, Object?>> read() async =>
      Map<String, Object?>.from(_value);

  @override
  Future<void> write(Map<String, Object?> value) async {
    if (failWrites) throw StateError('索引写入失败');
    _value = Map<String, Object?>.from(value);
  }
}
