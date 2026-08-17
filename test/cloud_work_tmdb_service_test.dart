import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client_capabilities.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

void main() {
  test('多版本无季度作品只按电影类型搜索', () {
    final work = _movieWork();
    final service = CloudWorkTmdbService(
      repository: CloudWorkTmdbRepository(
        storage: MemoryCloudWorkTmdbStorage(),
      ),
      indexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      client: _FakeTmdbClient(
        detail: _movieDetails(),
        searches: const <String, List<TmdbMetadata>>{},
      ),
    );

    final request = service.requestFor(work, null);

    expect(request.queryTitle, '示例电影');
    expect(request.mediaTypeMode, TmdbMediaTypeMode.movie);
  });

  test('同一电影重新扫描且文件顺序变化时复用海报缓存', () async {
    final cacheRoot = await Directory.systemTemp.createTemp('movie-tmdb-');
    addTearDown(() => cacheRoot.delete(recursive: true));
    var downloadCalls = 0;
    final cache = CloudPosterCache(
      cacheRoot: cacheRoot,
      downloader: (_) async {
        downloadCalls++;
        return <int>[1, 2, 3];
      },
    );
    final work = _movieWork();
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await indexRepository.replaceSource(
      work.sourceId,
      <CloudMediaIndexItem>[
        for (final video in work.standaloneVideos) _movieItem(work, video),
      ],
      const <String, String>{},
      const <String, List<CloudFileEntry>>{},
      const <String>['/影视'],
    );
    final service = CloudWorkTmdbService(
      repository: CloudWorkTmdbRepository(
        storage: MemoryCloudWorkTmdbStorage(),
      ),
      indexRepository: indexRepository,
      client: _FakeTmdbClient(
        detail: _movieDetails(),
        searches: const <String, List<TmdbMetadata>>{},
      ),
      posterCache: cache,
    );

    final first = await service.select(
      work,
      _movieCandidate(),
      existingSeasons: const <int>{},
    );
    final rescanned = CloudWorkIdentity(
      sourceId: work.sourceId,
      workKey: work.workKey,
      root: work.root,
      remoteName: work.remoteName,
      displayTitle: work.displayTitle,
      titleCandidates: work.titleCandidates,
      seasons: const <CloudSeasonIdentity>[],
      standaloneVideos: work.standaloneVideos.reversed.toList(),
    );
    final second = await service.select(
      rescanned,
      _movieCandidate(),
      existingSeasons: const <int>{},
    );

    expect(second.record.workKey, first.record.workKey);
    expect(second.record.posterCachePath, first.record.posterCachePath);
    expect(await File(second.record.posterCachePath!).exists(), isTrue);
    expect(downloadCalls, 1);
  });

  test('一个作品只请求一次详情并缓存全部季度海报', () async {
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
      '${work.workKey}|season:4',
    ]);
    expect(
      outcome.record.seasons.map((season) => season.seasonNumber),
      <int>[1, 2, 3, 4],
    );
    expect(outcome.record.seasons.last.posterCachePath, 'cache-5.jpg');
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
      indexed
          .where((item) => item.workKey == work.workKey)
          .every((item) => item.tmdbGenres.join() == '科幻'),
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

  test('第二季度标题带末尾数字时搜索正剧并保留全部季度海报', () async {
    final cacheRoot = await Directory.systemTemp.createTemp('work-s02-tmdb-');
    addTearDown(() => cacheRoot.delete(recursive: true));
    final work = _work(
      displayTitle: 'Isekai Nonbiri Nouka 2',
      titleCandidates: const <String>['Isekai Nonbiri Nouka 2'],
      seasonNumbers: const <int>[2],
    );
    final cache = _RecordingPosterCache(cacheRoot);
    final client = _FakeTmdbClient(
      detail: _details(),
      searches: <String, List<TmdbMetadata>>{
        'Isekai Nonbiri Nouka': <TmdbMetadata>[
          _candidate('Isekai Nonbiri Nouka'),
        ],
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
      posterCache: cache,
    );

    final request = service.requestFor(work, null);
    expect(request.queryTitle, 'Isekai Nonbiri Nouka');

    final candidates = await service.searchCandidates(work);
    expect(candidates.single.title, 'Isekai Nonbiri Nouka');

    final outcome = await service.select(
      work,
      candidates.single,
      existingSeasons: const <int>{2},
    );

    expect(
      outcome.record.seasons.map((season) => season.seasonNumber),
      <int>[1, 2, 3, 4],
    );
    expect(outcome.record.seasons[1].posterUrl, '/season-2.jpg');
    expect(outcome.record.seasons[1].posterCachePath, isNotNull);
    expect(cache.stableIds, contains('${work.workKey}|season:2'));
  });

  test('单季度独立续作按集数将 TMDB 第1季逐集资料映射到本地第2季', () async {
    final work = _singleSeasonWork(
      displayTitle: '古灵精探B',
      localSeasonNumber: 2,
      episodeCount: 25,
    );
    final client = _SingleSeasonTmdbClient(
      detail: _singleSeasonDetails(episodeCount: 25),
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

    final outcome = await service.select(
      work,
      _candidate('古灵精探B'),
      existingSeasons: const <int>{2},
    );

    expect(client.seasonCalls, <int>[1]);
    expect(outcome.record.seasons, hasLength(1));
    expect(outcome.record.seasons.single.seasonNumber, 2);
    expect(outcome.record.seasons.single.episodes, hasLength(25));
    expect(outcome.record.seasons.single.episodes.first.name, '真相初现');
  });

  test('单季度集数冲突时不改写 TMDB 季号', () async {
    final work = _singleSeasonWork(
      displayTitle: '古灵精探B',
      localSeasonNumber: 2,
      episodeCount: 24,
    );
    final client = _SingleSeasonTmdbClient(
      detail: _singleSeasonDetails(episodeCount: 25),
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

    final outcome = await service.select(
      work,
      _candidate('古灵精探B'),
      existingSeasons: const <int>{2},
    );

    expect(client.seasonCalls, <int>[2]);
    expect(outcome.record.seasons.single.seasonNumber, 1);
    expect(outcome.record.seasons.single.episodes, isEmpty);
  });

  test('重新刮削时用映射后的逐集资料替换旧 TMDB 季度摘要', () async {
    final work = _singleSeasonWork(
      displayTitle: '古灵精探B',
      localSeasonNumber: 2,
      episodeCount: 25,
    );
    final repository = CloudWorkTmdbRepository(
      storage: MemoryCloudWorkTmdbStorage(),
    );
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await repository.upsert(
      CloudWorkTmdbRecord.matched(
        sourceId: work.sourceId,
        workKey: work.workKey,
        workRootId: work.root.id,
        workRootPath: work.root.remotePath,
        remoteName: work.remoteName,
        metadata: _singleSeasonDetails(episodeCount: 25),
        checkedAt: DateTime.utc(2026, 8, 16),
      ),
    );
    final service = CloudWorkTmdbService(
      repository: repository,
      indexRepository: indexRepository,
      client: _SingleSeasonTmdbClient(
        detail: _singleSeasonDetails(episodeCount: 25),
      ),
    );

    final outcome = await service.select(
      work,
      _candidate('古灵精探B'),
      existingSeasons: const <int>{2},
    );

    expect(outcome.record.seasons, hasLength(1));
    expect(outcome.record.seasons.single.seasonNumber, 2);
    expect(outcome.record.seasons.single.episodes, hasLength(25));
  });

  test('本地多季度作品不套用单季度季号映射', () async {
    final work = _work(seasonNumbers: const <int>[1, 2]);
    final client = _SingleSeasonTmdbClient(
      detail: _singleSeasonDetails(episodeCount: 25),
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

    final outcome = await service.select(
      work,
      _candidate('规范剧名'),
      existingSeasons: const <int>{1, 2},
    );

    expect(client.seasonCalls, unorderedEquals(<int>[1, 2]));
    expect(outcome.record.seasons.single.seasonNumber, 1);
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
      <int>[1, 2, 3, 4],
    );
    expect(outcome.record.seasons[0].posterCachePath, isNotNull);
    expect(outcome.record.seasons[1].posterCachePath, isNull);
    expect(outcome.record.seasons[1].posterUrl, '/season-2.jpg');
    expect(outcome.record.seasons[2].posterCachePath, isNotNull);
    expect(outcome.record.seasons[3].posterCachePath, isNotNull);
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
  List<int> seasonNumbers = const <int>[1, 2, 3],
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

CloudWorkIdentity _singleSeasonWork({
  required String displayTitle,
  required int localSeasonNumber,
  required int episodeCount,
}) {
  final root = CloudFileEntry(
    id: 'single-season-work',
    remotePath: '/视频/$displayTitle',
    name: displayTitle,
    size: 0,
    modifiedAt: null,
    isDirectory: true,
  );
  const workKey = 'quark-a|work|single-season-work';
  return CloudWorkIdentity(
    sourceId: 'quark-a',
    workKey: workKey,
    root: root,
    remoteName: root.name,
    displayTitle: displayTitle,
    titleCandidates: <String>[displayTitle],
    seasons: <CloudSeasonIdentity>[
      CloudSeasonIdentity(
        workKey: workKey,
        seasonNumber: localSeasonNumber,
        displayName: '$displayTitle 第 $localSeasonNumber 季',
        remoteDirectories: const <CloudFileEntry>[],
        episodes: <CloudEpisodeIdentity>[
          for (var episode = 1; episode <= episodeCount; episode++)
            CloudEpisodeIdentity(
              entry: CloudFileEntry(
                id: 'episode-$episode',
                remotePath: '/视频/$displayTitle/episode-$episode.mp4',
                name: 'episode-$episode.mp4',
                size: 100,
                modifiedAt: null,
                isDirectory: false,
              ),
              remoteName: 'episode-$episode.mp4',
              displayName: 'episode-$episode.mp4',
              seasonNumber: localSeasonNumber,
              episodeNumber: episode,
              releaseTags: const MediaReleaseTags(),
            ),
        ],
      ),
    ],
  );
}

CloudWorkIdentity _movieWork() {
  const root = CloudFileEntry(
    id: 'movie-root',
    remotePath: '/影视/示例电影',
    name: '示例电影',
    size: 0,
    modifiedAt: null,
    isDirectory: true,
  );
  const videos = <CloudFileEntry>[
    CloudFileEntry(
      id: 'movie-4k',
      remotePath: '/影视/示例电影/示例电影 2160p.mkv',
      name: '示例电影 2160p.mkv',
      size: 300,
      modifiedAt: null,
      isDirectory: false,
    ),
    CloudFileEntry(
      id: 'movie-1080',
      remotePath: '/影视/示例电影/示例电影 1080p.mkv',
      name: '示例电影 1080p.mkv',
      size: 200,
      modifiedAt: null,
      isDirectory: false,
    ),
  ];
  return const CloudWorkIdentity(
    sourceId: 'quark-a',
    workKey: 'quark-a|movie|stable',
    root: root,
    remoteName: '示例电影',
    displayTitle: '示例电影',
    titleCandidates: <String>['示例电影'],
    seasons: <CloudSeasonIdentity>[],
    standaloneVideos: videos,
  );
}

CloudMediaIndexItem _movieItem(
  CloudWorkIdentity work,
  CloudFileEntry video,
) =>
    CloudMediaIndexItem(
      sourceId: work.sourceId,
      remoteId: video.id,
      remotePath: video.remotePath,
      name: video.name,
      workKey: work.workKey,
      workRootId: work.root.id,
      workRootPath: work.root.remotePath,
      size: video.size,
      modifiedAt: video.modifiedAt,
      seriesName: work.displayTitle,
      mediaType: CloudMediaType.movie,
    );

TmdbMetadata _movieCandidate() => TmdbMetadata(
      id: 84,
      mediaType: TmdbMediaType.movie,
      title: '示例电影',
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 7, 27),
      matchConfidence: 1,
    );

TmdbMetadata _movieDetails() => TmdbMetadata(
      id: 84,
      mediaType: TmdbMediaType.movie,
      title: '示例电影',
      overview: '电影简介',
      posterUrl: '/movie-poster.jpg',
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 7, 27),
      matchConfidence: 1,
    );

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
      genres: const <String>['科幻'],
      overview: '中文简介',
      posterUrl: '/poster.jpg',
      backdropUrl: '/backdrop.jpg',
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 7, 20),
      matchConfidence: 1,
      seasons: <TmdbSeasonMetadata>[
        for (var season = 1; season <= 4; season++)
          TmdbSeasonMetadata(
            id: season * 100,
            seasonNumber: season,
            name: '第 $season 季',
            episodeCount: 8,
            posterUrl: '/season-$season.jpg',
          ),
      ],
    );

TmdbMetadata _singleSeasonDetails({required int episodeCount}) => TmdbMetadata(
      id: 42,
      mediaType: TmdbMediaType.tv,
      title: '古灵精探B',
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 8, 17),
      matchConfidence: 1,
      seasons: <TmdbSeasonMetadata>[
        TmdbSeasonMetadata(
          id: 100,
          seasonNumber: 1,
          name: '第 1 季',
          episodeCount: episodeCount,
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

class _SingleSeasonTmdbClient implements ITmdbClient, ITmdbClientCapabilities {
  _SingleSeasonTmdbClient({required this.detail});

  final TmdbMetadata detail;
  final List<int> seasonCalls = <int>[];

  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async =>
      detail;

  @override
  Future<TmdbSeasonMetadata> seasonDetails(
    int id,
    int seasonNumber, {
    String language = 'zh-CN',
  }) async {
    seasonCalls.add(seasonNumber);
    if (seasonNumber != 1) throw StateError('TMDB 不存在该季度');
    return TmdbSeasonMetadata(
      id: 100,
      seasonNumber: 1,
      name: '第 1 季',
      episodeCount: 25,
      episodes: <TmdbEpisodeMetadata>[
        for (var episode = 1; episode <= 25; episode++)
          TmdbEpisodeMetadata(
            id: 1000 + episode,
            episodeNumber: episode,
            name: episode == 1 ? '真相初现' : '第 $episode 集',
          ),
      ],
    );
  }

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async =>
      const <TmdbMetadata>[];

  @override
  Future<TmdbSearchPage> searchPage(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
    required int page,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<String>> alternativeTitles(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async =>
      const <String>[];
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
