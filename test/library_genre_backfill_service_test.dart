import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/library_genre_backfill_service.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';
import 'package:kanyingyin/utils/storage.dart';

void main() {
  test('已匹配的网盘作品缺少题材时补齐且保留匹配信息', () async {
    final localRepository = _localRepository(const <LocalMediaIndexItem>[]);
    final cloudRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await cloudRepository.replaceSource(
      'openlist',
      <CloudMediaIndexItem>[
        _cloud('naruto-movie-01', 16907, CloudMediaType.movie),
      ],
      const <String, String>{},
      const <String, List<CloudFileEntry>>{},
      const <String>['/'],
    );
    final workRepository = CloudWorkTmdbRepository(
      storage: MemoryCloudWorkTmdbStorage(),
    );
    await workRepository.upsert(
      CloudWorkTmdbRecord.matched(
        sourceId: 'openlist',
        workKey: 'openlist|movie|naruto-01',
        workRootId: 'naruto-01',
        workRootPath: '/火影忍者 剧场版11部',
        remoteName: '火影忍者 剧场版11部',
        metadata: TmdbMetadata(
          id: 16907,
          mediaType: TmdbMediaType.movie,
          title: '火影忍者剧场版：大活剧！雪姬忍法帖',
          language: 'zh-CN',
          matchedAt: DateTime(2026),
          matchConfidence: 0.99,
        ),
        checkedAt: DateTime(2026),
        tmdbMatchOrigin: TmdbMatchOrigin.automatic,
        tmdbRuleVersion: currentTmdbRuleVersion,
      ),
    );
    final client = _FakeTmdbClient(<String, TmdbMetadata>{
      'movie:16907': _metadata(
        16907,
        TmdbMediaType.movie,
        const <String>['动画'],
      ),
    });

    final result = await LibraryGenreBackfillService(
      localRepository: localRepository,
      cloudRepository: cloudRepository,
      workRepository: workRepository,
      clientFactory: (_) => client,
    ).backfill(
      apiKey: 'key',
      localItems: const <LocalMediaIndexItem>[],
      cloudItems: await cloudRepository.getBySource('openlist'),
    );

    expect(client.detailKeys, const <String>['movie:16907']);
    expect(result.updatedWorks, 1);
    expect(result.failedWorks, 0);
    final updated = (await workRepository.getAll()).single;
    expect(updated.metadata!.genres, const <String>['动画']);
    expect(updated.metadata!.title, '火影忍者剧场版：大活剧！雪姬忍法帖');
    expect(updated.status, CloudWorkTmdbStatus.matched);
    expect(updated.tmdbMatchOrigin, TmdbMatchOrigin.automatic);
    expect(updated.tmdbRuleVersion, currentTmdbRuleVersion);
    expect(
      (await cloudRepository.getBySource('openlist')).single.tmdbGenres,
      const <String>['动画'],
    );
  });

  test('同一 TMDB 作品只请求一次并更新本地与网盘条目', () async {
    final localItems = <LocalMediaIndexItem>[
      _local('a', 42, TmdbMediaType.tv),
      _local('b', 42, TmdbMediaType.tv),
    ];
    final localRepository = _localRepository(localItems);
    final cloudRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await cloudRepository.replaceSource(
      'openlist',
      <CloudMediaIndexItem>[_cloud('cloud-a', 42, CloudMediaType.episode)],
      const <String, String>{},
      const <String, List<CloudFileEntry>>{},
      const <String>['/'],
    );
    final client = _FakeTmdbClient(<String, TmdbMetadata>{
      'tv:42': _metadata(42, TmdbMediaType.tv, const <String>['动画']),
    });

    final result = await LibraryGenreBackfillService(
      localRepository: localRepository,
      cloudRepository: cloudRepository,
      workRepository: CloudWorkTmdbRepository(
        storage: MemoryCloudWorkTmdbStorage(),
      ),
      clientFactory: (_) => client,
    ).backfill(
      apiKey: 'key',
      localItems: localItems,
      cloudItems: await cloudRepository.getBySource('openlist'),
    );

    expect(client.detailKeys, const <String>['tv:42']);
    expect(result.updatedWorks, 1);
    expect(result.failedWorks, 0);
    expect(
      localRepository
          .getAll()
          .every((item) => item.tmdb!.genres.contains('动画')),
      isTrue,
    );
    expect(
      (await cloudRepository.getBySource('openlist')).single.tmdbGenres,
      const <String>['动画'],
    );
  });

  test('无 Key 直接返回且单项失败不阻止其他作品', () async {
    final items = <LocalMediaIndexItem>[
      _local('movie', 7, TmdbMediaType.movie),
      _local('tv', 42, TmdbMediaType.tv),
    ];
    final localRepository = _localRepository(items);
    final cloudRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    final client = _FakeTmdbClient(<String, TmdbMetadata>{
      'tv:42': _metadata(42, TmdbMediaType.tv, const <String>['科幻']),
    })
      ..throwKeys.add('movie:7');
    final service = LibraryGenreBackfillService(
      localRepository: localRepository,
      cloudRepository: cloudRepository,
      workRepository: CloudWorkTmdbRepository(
        storage: MemoryCloudWorkTmdbStorage(),
      ),
      clientFactory: (_) => client,
    );

    final noKey = await service.backfill(
      apiKey: '',
      localItems: items,
      cloudItems: const <CloudMediaIndexItem>[],
    );
    expect(noKey.updatedWorks, 0);
    expect(noKey.failedWorks, 0);
    expect(client.detailKeys, isEmpty);

    final progress = <String>[];
    final result = await service.backfill(
      apiKey: 'key',
      localItems: items,
      cloudItems: const <CloudMediaIndexItem>[],
      onProgress: (current, total) => progress.add('$current/$total'),
    );
    expect(result.updatedWorks, 1);
    expect(result.failedWorks, 1);
    expect(progress, const <String>['1/2', '2/2']);
    expect(
      localRepository
          .getAll()
          .firstWhere((item) => item.name == 'tv.mkv')
          .tmdb!
          .genres,
      const <String>['科幻'],
    );
  });
}

LocalMediaIndexRepository _localRepository(List<LocalMediaIndexItem> items) {
  return LocalMediaIndexRepository(
    storage: _MemoryLocalStorage(<String, Object?>{
      SettingBoxKey.localMediaIndex:
          items.map((item) => item.toJson()).toList(growable: false),
    }),
  );
}

LocalMediaIndexItem _local(String name, int id, TmdbMediaType type) {
  return LocalMediaIndexItem(
    path: 'D:\\Media\\$name.mkv',
    name: '$name.mkv',
    parentPath: r'D:\Media',
    sourcePath: r'D:\Media',
    size: 10,
    modified: DateTime(2026),
    seriesName: name,
    indexedAt: DateTime(2026),
    scrapeStatus: TmdbScrapeStatus.matched,
    tmdb: _metadata(id, type, const <String>[]),
  );
}

CloudMediaIndexItem _cloud(String id, int tmdbId, CloudMediaType type) {
  return CloudMediaIndexItem(
    sourceId: 'openlist',
    remoteId: id,
    remotePath: '/$id.mkv',
    name: '$id.mkv',
    size: 10,
    modifiedAt: DateTime(2026),
    seriesName: id,
    mediaType: type,
    tmdbId: tmdbId,
    tmdbTitle: id,
  );
}

TmdbMetadata _metadata(int id, TmdbMediaType type, List<String> genres) {
  return TmdbMetadata(
    id: id,
    mediaType: type,
    title: '作品$id',
    language: 'zh-CN',
    matchedAt: DateTime(2026),
    matchConfidence: 1,
    genres: genres,
  );
}

class _FakeTmdbClient implements ITmdbClient {
  _FakeTmdbClient(this.detailsByKey);

  final Map<String, TmdbMetadata> detailsByKey;
  final Set<String> throwKeys = <String>{};
  final List<String> detailKeys = <String>[];

  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    final key = '${mediaType.name}:$id';
    detailKeys.add(key);
    if (throwKeys.contains(key)) throw StateError('fixture failure');
    return detailsByKey[key]!;
  }

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    return const <TmdbMetadata>[];
  }
}

class _MemoryLocalStorage implements LocalMediaIndexStorage {
  _MemoryLocalStorage(this.values);

  final Map<String, Object?> values;

  @override
  Object? read(String key, {Object? defaultValue}) =>
      values[key] ?? defaultValue;

  @override
  Future<void> write(String key, Object? value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
