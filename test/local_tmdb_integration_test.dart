import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/tmdb_metadata_repository.dart';
import 'package:kanyingyin/services/tmdb/local_tmdb_scrape_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_prepared_search.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

void main() {
  test('本地准备搜索返回候选但不修改索引', () async {
    final original = _item('Season 2/a.mkv', seasonNumber: 2);
    final index = _MemoryIndexRepository(<LocalMediaIndexItem>[original]);
    final service = LocalTmdbScrapeService(
      indexRepository: index,
      metadataRepository: _MemoryMetadataRepository(),
      clientFactory: (_) => _FakeClient(),
      posterDownloader: _successfulDownload,
    );

    final outcome = await service.searchPrepared(
      apiKey: 'configured-key',
      seriesName: '流浪地球',
      request: const TmdbPreparedSearchRequest(
        queryTitle: '流浪地球',
        queryYear: 2019,
        mediaTypeMode: TmdbMediaTypeMode.tv,
        options: TmdbScrapeOptions.defaults(),
      ),
    );

    expect(outcome.ranked.candidates, isNotEmpty);
    expect(index.getByPath(original.path), same(original));
  });

  test('本地准备搜索没有 API Key 时明确提示且不创建客户端', () async {
    var clientCreated = false;
    final service = LocalTmdbScrapeService(
      indexRepository: _MemoryIndexRepository(<LocalMediaIndexItem>[
        _item('a.mkv'),
      ]),
      metadataRepository: _MemoryMetadataRepository(),
      clientFactory: (_) {
        clientCreated = true;
        return _FakeClient();
      },
      posterDownloader: _successfulDownload,
    );

    expect(
      () => service.searchPrepared(
        apiKey: '',
        seriesName: '流浪地球',
        request: const TmdbPreparedSearchRequest(
          queryTitle: '流浪地球',
          mediaTypeMode: TmdbMediaTypeMode.auto,
          options: TmdbScrapeOptions.defaults(),
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '请先在设置中填写 TMDB API Key',
        ),
      ),
    );
    expect(clientCreated, isFalse);
  });

  test('没有 API Key 时跳过刮削且不修改索引', () async {
    final index = _MemoryIndexRepository([_item('a.mkv')]);
    var clientCreated = false;
    final service = LocalTmdbScrapeService(
      indexRepository: index,
      metadataRepository: _MemoryMetadataRepository(),
      clientFactory: (_) {
        clientCreated = true;
        return _FakeClient();
      },
      posterDownloader: _successfulDownload,
    );

    final result = await service.scrapeSeries(
      apiKey: '',
      seriesName: '流浪地球',
    );

    expect(result.status, TmdbScrapeStatus.none);
    expect(clientCreated, isFalse);
    expect(index.getAll().single.tmdb, isNull);
  });

  test('匹配成功后更新同系列全部剧集', () async {
    final index = _MemoryIndexRepository([
      _item('a.mkv'),
      _item('b.mkv'),
    ]);
    final service = LocalTmdbScrapeService(
      indexRepository: index,
      metadataRepository: _MemoryMetadataRepository(),
      clientFactory: (_) => _FakeClient(),
      posterDownloader: _successfulDownload,
    );

    final result = await service.scrapeSeries(
      apiKey: 'configured-key',
      seriesName: '流浪地球',
      mediaType: TmdbMediaType.movie,
    );

    expect(result.status, TmdbScrapeStatus.matched);
    expect(index.getAll(), everyElement(isA<LocalMediaIndexItem>()));
    expect(index.getAll().map((item) => item.tmdb?.id), everyElement(1));
    expect(
      index.getAll().map((item) => item.tmdbMatchOrigin),
      everyElement(TmdbMatchOrigin.automatic),
    );
    expect(
      index.getAll().map((item) => item.tmdbRuleVersion),
      everyElement(currentTmdbRuleVersion),
    );
    expect(
      index.getAll().first.tmdb?.seasons.map((item) => item.seasonNumber),
      <int>[1, 2],
    );
  });

  test('重新刮削保留已锁定的标题', () async {
    final index = _MemoryIndexRepository([
      _item('a.mkv').copyWith(
        tmdb: TmdbMetadata(
          id: 9,
          mediaType: TmdbMediaType.movie,
          title: '我的标题',
          language: 'zh-CN',
          matchedAt: DateTime(2026),
          matchConfidence: 1,
        ),
        titleLocked: true,
      ),
    ]);
    final service = LocalTmdbScrapeService(
      indexRepository: index,
      metadataRepository: _MemoryMetadataRepository(),
      clientFactory: (_) => _FakeClient(),
      posterDownloader: _successfulDownload,
    );

    await service.scrapeSeries(
      apiKey: 'configured-key',
      seriesName: '流浪地球',
      mediaType: TmdbMediaType.movie,
      force: true,
    );

    expect(index.getAll().single.tmdb?.title, '我的标题');
  });

  test('手动选择候选后更新整个系列', () async {
    final index = _MemoryIndexRepository([_item('a.mkv'), _item('b.mkv')]);
    final service = LocalTmdbScrapeService(
      indexRepository: index,
      metadataRepository: _MemoryMetadataRepository(),
      clientFactory: (_) => _FakeClient(),
      posterDownloader: _successfulDownload,
    );
    final candidate =
        (await _FakeClient().search('流浪地球', TmdbMediaType.movie)).single;

    final selected = await service.selectCandidate(
      apiKey: 'configured-key',
      seriesName: '流浪地球',
      candidate: candidate,
    );

    expect(selected.metadata?.id, 1);
    expect(index.getAll().map((item) => item.tmdb?.id), everyElement(1));
    expect(
      index.getAll().map((item) => item.scrapeStatus),
      everyElement(TmdbScrapeStatus.matched),
    );
    expect(
      index.getAll().map((item) => item.tmdbMatchOrigin),
      everyElement(TmdbMatchOrigin.manual),
    );
  });

  test('旧匹配同一TMDB条目时按统一规则刷新并记录版本', () async {
    final index = _MemoryIndexRepository([
      _item('a.mkv').copyWith(
        tmdb: TmdbMetadata(
          id: 1,
          mediaType: TmdbMediaType.movie,
          title: '流浪地球',
          overview: '旧简介',
          language: 'zh-CN',
          matchedAt: DateTime(2025),
          matchConfidence: 0.8,
        ),
        scrapeStatus: TmdbScrapeStatus.matched,
      ),
    ]);
    final service = LocalTmdbScrapeService(
      indexRepository: index,
      metadataRepository: _MemoryMetadataRepository(),
      clientFactory: (_) => _FakeClient(),
      posterDownloader: _successfulDownload,
    );

    await service.scrapeSeries(
      apiKey: 'configured-key',
      seriesName: '流浪地球',
      mediaType: TmdbMediaType.movie,
    );

    final item = index.getAll().single;
    expect(item.tmdb?.id, 1);
    expect(item.tmdb?.overview, '简介');
    expect(item.tmdbMatchOrigin, TmdbMatchOrigin.automatic);
    expect(item.tmdbRuleVersion, currentTmdbRuleVersion);
  });

  test('旧匹配与统一规则结果冲突时保留旧数据并等待确认', () async {
    final index = _MemoryIndexRepository([
      _item('a.mkv').copyWith(
        tmdb: TmdbMetadata(
          id: 9,
          mediaType: TmdbMediaType.movie,
          title: '用户曾确认的旧结果',
          language: 'zh-CN',
          matchedAt: DateTime(2025),
          matchConfidence: 1,
        ),
        scrapeStatus: TmdbScrapeStatus.matched,
      ),
    ]);
    final service = LocalTmdbScrapeService(
      indexRepository: index,
      metadataRepository: _MemoryMetadataRepository(),
      clientFactory: (_) => _FakeClient(),
      posterDownloader: _successfulDownload,
    );

    final result = await service.scrapeSeries(
      apiKey: 'configured-key',
      seriesName: '流浪地球',
      mediaType: TmdbMediaType.movie,
    );

    final item = index.getAll().single;
    expect(result.status, TmdbScrapeStatus.pending);
    expect(item.tmdb?.id, 9);
    expect(item.tmdb?.title, '用户曾确认的旧结果');
    expect(item.scrapeStatus, TmdbScrapeStatus.pending);
    expect(item.tmdbRuleVersion, currentTmdbRuleVersion);
  });

  test('匹配成功后按目录去重下载 TMDB 海报并更新索引封面', () async {
    final index = _MemoryIndexRepository([
      _item('Season 1/a.mkv'),
      _item('Season 1/b.mkv'),
      _item('Season 2/c.mkv'),
    ]);
    final downloads = <String>[];
    final service = LocalTmdbScrapeService(
      indexRepository: index,
      metadataRepository: _MemoryMetadataRepository(),
      clientFactory: (_) => _FakeClient(),
      posterDownloader: (url, path) async {
        downloads.add(path);
        return path;
      },
    );

    final result = await service.scrapeSeries(
      apiKey: 'configured-key',
      seriesName: '流浪地球',
      mediaType: TmdbMediaType.movie,
    );

    expect(result.posterDownloadFailures, 0);
    expect(downloads, hasLength(2));
    expect(downloads, everyElement(endsWith('tmdb-poster.jpg')));
    expect(index.getAll().map((item) => item.cover), everyElement(isNotNull));
  });

  test('电视剧按季度下载对应 TMDB 海报且同目录只下载一次', () async {
    final index = _MemoryIndexRepository([
      _item('Season 1/a.mkv', seasonNumber: 1),
      _item('Season 1/b.mkv', seasonNumber: 1),
      _item('Season 2/c.mkv', seasonNumber: 2),
    ]);
    final downloads = <({String url, String path})>[];
    final service = LocalTmdbScrapeService(
      indexRepository: index,
      metadataRepository: _MemoryMetadataRepository(),
      clientFactory: (_) => _FakeClient(),
      posterDownloader: (url, path) async {
        downloads.add((url: url, path: path));
        return path;
      },
    );

    await service.scrapeSeries(
      apiKey: 'configured-key',
      seriesName: '流浪地球',
      mediaType: TmdbMediaType.tv,
    );

    expect(downloads.map((item) => item.url), <String>[
      'https://image.tmdb.org/t/p/w780/season-1.jpg',
      'https://image.tmdb.org/t/p/w780/season-2.jpg',
    ]);
    expect(
      downloads.map((item) => item.path),
      everyElement(endsWith('tmdb-poster.jpg')),
    );
  });

  test('季度海报缺失或季度未识别时回退作品总海报', () async {
    final index = _MemoryIndexRepository([
      _item('Season 3/a.mkv', seasonNumber: 3),
      _item('Unknown/b.mkv'),
    ]);
    final urls = <String>[];
    final service = LocalTmdbScrapeService(
      indexRepository: index,
      metadataRepository: _MemoryMetadataRepository(),
      clientFactory: (_) => _FakeClient(),
      posterDownloader: (url, path) async {
        urls.add(url);
        return path;
      },
    );

    await service.scrapeSeries(
      apiKey: 'configured-key',
      seriesName: '流浪地球',
      mediaType: TmdbMediaType.tv,
    );

    expect(
      urls,
      everyElement('https://image.tmdb.org/t/p/w780/poster.jpg'),
    );
  });

  test('部分 TMDB 海报下载失败时仍保留已刮削元数据', () async {
    final index = _MemoryIndexRepository([
      _item('Season 1/a.mkv'),
      _item('Season 2/b.mkv'),
    ]);
    var calls = 0;
    final service = LocalTmdbScrapeService(
      indexRepository: index,
      metadataRepository: _MemoryMetadataRepository(),
      clientFactory: (_) => _FakeClient(),
      posterDownloader: (url, path) async => ++calls == 1 ? path : null,
    );

    final result = await service.scrapeSeries(
      apiKey: 'configured-key',
      seriesName: '流浪地球',
      mediaType: TmdbMediaType.movie,
    );

    expect(result.posterDownloadFailures, 1);
    expect(index.getAll().map((item) => item.tmdb?.id), everyElement(1));
  });
}

Future<String?> _successfulDownload(String url, String path) async => path;

LocalMediaIndexItem _item(String name, {int? seasonNumber}) {
  return LocalMediaIndexItem(
    path: 'D:/Video/$name',
    name: name,
    parentPath: 'D:/Video',
    sourcePath: 'D:/Video',
    size: 100,
    modified: DateTime(2026),
    seriesName: '流浪地球',
    seasonNumber: seasonNumber,
    indexedAt: DateTime(2026),
  );
}

class _FakeClient implements ITmdbClient {
  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    return TmdbMetadata(
      id: id,
      mediaType: mediaType,
      title: '流浪地球',
      overview: '简介',
      posterUrl: '/poster.jpg',
      backdropUrl: '/backdrop.jpg',
      releaseDate: '2019-02-05',
      language: language,
      matchedAt: DateTime(2026),
      matchConfidence: 0,
      seasons: const <TmdbSeasonMetadata>[
        TmdbSeasonMetadata(
          id: 101,
          seasonNumber: 1,
          name: '第 1 季',
          episodeCount: 10,
          posterUrl: '/season-1.jpg',
        ),
        TmdbSeasonMetadata(
          id: 102,
          seasonNumber: 2,
          name: '第 2 季',
          episodeCount: 10,
          posterUrl: '/season-2.jpg',
        ),
      ],
    );
  }

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    return [await details(1, mediaType, language: language)];
  }
}

class _MemoryMetadataRepository implements ITmdbMetadataRepository {
  final values = <String, TmdbMetadata>{};

  @override
  TmdbMetadata? get(String mediaKey) => values[mediaKey];

  @override
  Future<void> remove(String mediaKey) async => values.remove(mediaKey);

  @override
  Future<void> save(String mediaKey, TmdbMetadata metadata) async {
    values[mediaKey] = metadata;
  }
}

class _MemoryIndexRepository implements ILocalMediaIndexRepository {
  final List<LocalMediaIndexItem> items;

  _MemoryIndexRepository(this.items);

  @override
  Future<void> clear() async => items.clear();

  @override
  List<LocalMediaIndexItem> getAll() => List.of(items);

  @override
  List<LocalMediaIndexItem> getBySourcePath(String sourcePath) =>
      items.where((item) => item.sourcePath == sourcePath).toList();

  @override
  Map<String, String> getDirectoryFingerprints(String sourcePath) => {};

  @override
  LocalMediaIndexItem? getByPath(String path) {
    for (final item in items) {
      if (item.path == path) return item;
    }
    return null;
  }

  @override
  Future<void> removeSource(String sourcePath) async =>
      items.removeWhere((item) => item.sourcePath == sourcePath);

  @override
  Future<void> saveDirectoryFingerprints(
    String sourcePath,
    Map<String, String> fingerprints,
  ) async {}

  @override
  Future<void> saveForSource(
    String sourcePath,
    List<LocalMediaIndexItem> next,
  ) async {
    items
      ..removeWhere((item) => item.sourcePath == sourcePath)
      ..addAll(next);
  }

  @override
  Future<void> updateItem(LocalMediaIndexItem item) async {
    final index = items.indexWhere((current) => current.id == item.id);
    if (index < 0) {
      items.add(item);
    } else {
      items[index] = item;
    }
  }
}
