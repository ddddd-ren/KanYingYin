import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_exporter.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_series_match_rule.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/local_media_source.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_series_match_rule_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/local_media_source_repository.dart';

void main() {
  test('只导出成功刮削记录并去重图片且不含敏感配置', () async {
    final temporary =
        await Directory.systemTemp.createTemp('kyymeta-export-test-');
    addTearDown(() => temporary.delete(recursive: true));
    final posterA = File('${temporary.path}${Platform.pathSeparator}a.jpg');
    final posterB = File('${temporary.path}${Platform.pathSeparator}b.jpg');
    final backdrop =
        File('${temporary.path}${Platform.pathSeparator}backdrop.png');
    await posterA.writeAsBytes(<int>[1, 2, 3]);
    await posterB.writeAsBytes(<int>[1, 2, 3]);
    await backdrop.writeAsBytes(<int>[4, 5, 6]);

    final localStorage = _MemoryLocalIndexStorage();
    final localRepository = LocalMediaIndexRepository(storage: localStorage);
    final matched = _local(
      path: r'D:\影视\三体\S01E01.mkv',
      cover: posterA.path,
      tmdb: _metadata,
      status: TmdbScrapeStatus.matched,
    );
    final unmatched = _local(
      path: r'D:\影视\未匹配.mkv',
      status: TmdbScrapeStatus.failed,
    );
    await localRepository.saveForSource(
      r'D:\影视',
      <LocalMediaIndexItem>[matched, unmatched],
    );

    final sourceStorage = MemoryCloudSourceStorage();
    final sourceRepository = CloudSourceRepository(storage: sourceStorage);
    final cloudSource = CloudSource(
      id: 'cloud-source',
      type: CloudSourceType.openList,
      name: '我的网盘',
      baseUrl: 'https://user:pass@example.com/list?token=secret#part',
      rootPaths: const <String>['/影视'],
    );
    await sourceRepository.save(cloudSource);

    final resourceRepository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    await resourceRepository.upsert(
      CloudResourceTmdbRecord.matched(
        sourceId: cloudSource.id,
        remoteId: 'remote-id',
        remotePath: '/影视/三体',
        displayName: '三体',
        resourceKind: CloudResourceKind.directory,
        metadata: _metadata,
        checkedAt: DateTime.utc(2026, 7, 30),
        posterCachePath: posterB.path,
      ),
    );
    await resourceRepository.upsert(
      CloudResourceTmdbRecord.unmatched(
        sourceId: cloudSource.id,
        remoteId: 'unmatched-id',
        remotePath: '/影视/未知',
        displayName: '未知',
        resourceKind: CloudResourceKind.directory,
        checkedAt: DateTime.utc(2026, 7, 30),
      ),
    );

    final workRepository = CloudWorkTmdbRepository(
      storage: MemoryCloudWorkTmdbStorage(),
    );
    await workRepository.upsert(
      CloudWorkTmdbRecord.matched(
        sourceId: cloudSource.id,
        workKey: 'work-key',
        workRootId: 'work-root',
        workRootPath: '/影视/三体',
        remoteName: '三体',
        metadata: _metadata,
        checkedAt: DateTime.utc(2026, 7, 30),
        posterCachePath: posterB.path,
      ),
    );
    final ruleRepository = CloudSeriesMatchRuleRepository(
      storage: MemoryCloudSeriesMatchRuleStorage(),
    );
    await ruleRepository.upsert(
      CloudSeriesMatchRule(
        sourceId: cloudSource.id,
        parentPath: '/影视/三体',
        normalizedSeriesName: '三体',
        metadata: _metadata,
        posterCachePath: posterB.path,
        updatedAt: DateTime.utc(2026, 7, 30),
      ),
    );

    final exporter = ScrapedMetadataExporter(
      localIndexRepository: localRepository,
      localSourceRepository: _LocalSourceRepository(
        <LocalMediaSource>[LocalMediaSource.fromPath(r'D:\影视')],
      ),
      cloudSourceRepository: sourceRepository,
      resourceRepository: resourceRepository,
      workRepository: workRepository,
      ruleRepository: ruleRepository,
      cachedImageLookup: _CachedImageLookup(<String, File>{
        _metadata.backdropUrl!: backdrop,
      }),
      appVersion: '2.1.93',
      clock: () => DateTime.utc(2026, 7, 30),
    );

    final result = await exporter.build();
    final encoded = jsonEncode(result.payload.toJson());

    expect(result.payload.localSources.single.records, hasLength(1));
    expect(result.payload.cloudSources.single.resourceRecords, hasLength(1));
    expect(result.payload.cloudSources.single.workRecords, hasLength(1));
    expect(result.payload.cloudSources.single.seriesRules, hasLength(1));
    expect(result.images, hasLength(2), reason: '相同海报应按 SHA-256 去重');
    expect(encoded, isNot(contains('password')));
    expect(encoded, isNot(contains('accessToken')));
    expect(encoded, isNot(contains('tmdbApiKey')));
    expect(encoded, isNot(contains(posterA.path)));
    expect(encoded, contains('https://example.com/list'));
    expect(encoded, isNot(contains('token=secret')));
    expect(encoded, isNot(contains('user:pass')));
  });
}

final TmdbMetadata _metadata = TmdbMetadata(
  id: 42,
  mediaType: TmdbMediaType.tv,
  title: '三体',
  language: 'zh-CN',
  matchedAt: DateTime.utc(2026, 7, 30),
  matchConfidence: 1,
  posterUrl: 'https://image.example/poster.jpg',
  backdropUrl: 'https://image.example/backdrop.jpg',
  seasons: const <TmdbSeasonMetadata>[
    TmdbSeasonMetadata(
      id: 1,
      seasonNumber: 1,
      name: '第一季',
      episodeCount: 30,
    ),
  ],
);

LocalMediaIndexItem _local({
  required String path,
  String? cover,
  TmdbMetadata? tmdb,
  required TmdbScrapeStatus status,
}) =>
    LocalMediaIndexItem(
      path: path,
      name: path.split('\\').last,
      parentPath: r'D:\影视',
      sourcePath: r'D:\影视',
      size: 1024,
      modified: DateTime.utc(2026, 7, 30),
      seriesName: '三体',
      tmdb: tmdb,
      cover: cover,
      scrapeStatus: status,
      indexedAt: DateTime.utc(2026, 7, 30),
    );

final class _MemoryLocalIndexStorage implements LocalMediaIndexStorage {
  final Map<String, Object?> values = <String, Object?>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Object? read(String key, {Object? defaultValue}) =>
      values[key] ?? defaultValue;

  @override
  Future<void> write(String key, Object? value) async => values[key] = value;
}

final class _LocalSourceRepository implements ILocalMediaSourceRepository {
  _LocalSourceRepository(this.sources);

  final List<LocalMediaSource> sources;

  @override
  List<LocalMediaSource> getAll() => sources;

  @override
  LocalMediaSource? getByLocation(MediaLocation location) =>
      sources.where((source) => source.location == location).firstOrNull;

  @override
  LocalMediaSource? getByPath(String path) =>
      getByLocation(MediaLocation.file(path));

  @override
  Future<bool> removeLocation(MediaLocation location) =>
      throw UnimplementedError();

  @override
  Future<bool> removePath(String path) => throw UnimplementedError();

  @override
  Future<void> updateScanSummary({
    required String path,
    required int fileCount,
    required int videoCount,
    required int directoryCount,
    required int skippedCount,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateScanSummaryForLocation({
    required MediaLocation location,
    required int fileCount,
    required int videoCount,
    required int directoryCount,
    required int skippedCount,
  }) =>
      throw UnimplementedError();

  @override
  Future<LocalMediaSource> upsertLocation(
    MediaLocation location, {
    required String displayName,
  }) =>
      throw UnimplementedError();

  @override
  Future<LocalMediaSource> upsertPath(String path) =>
      throw UnimplementedError();
}

final class _CachedImageLookup implements CachedImageLookup {
  const _CachedImageLookup(this.files);

  final Map<String, File> files;

  @override
  Future<File?> find(String url) async => files[url];
}
