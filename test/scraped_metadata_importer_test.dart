import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_archive_codec.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_importer.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_series_match_rule_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

void main() {
  test('导入覆盖刮削资料但保留当前媒体路径字幕和索引字段', () async {
    final fixture = await _fixture();
    final original = fixture.localRepository.getAll().single;

    final result = await fixture.importer.apply(fixture.plan, fixture.archive);

    final restored = fixture.localRepository.getAll().single;
    expect(restored.tmdb?.title, '三体');
    expect(restored.titleLocked, isTrue);
    expect(restored.path, original.path);
    expect(restored.subtitlePath, original.subtitlePath);
    expect(restored.durationMillis, original.durationMillis);
    expect(restored.indexedAt, original.indexedAt);
    expect(restored.cover, isNot(original.cover));
    expect(await File(restored.cover!).exists(), isTrue);
    expect(result.localCount, 1);
    expect(result.cloudCount, 2);
    expect(result.imageCount, 2);
  });

  test('导入的海报和背景图按原地址注册到离线图片缓存', () async {
    final cachedImages = <String, String>{};
    final fixture = await _fixture(
      networkImageInstaller: ({required url, required file}) async {
        cachedImages[url] = file.path;
      },
    );

    await fixture.importer.apply(fixture.plan, fixture.archive);

    expect(cachedImages[_newMetadata.posterUrl], isNotNull);
    expect(cachedImages[_newMetadata.backdropUrl], isNotNull);
    expect(
      await File(cachedImages[_newMetadata.backdropUrl]!).exists(),
      isTrue,
    );
  });

  test('网盘作品写入失败时恢复本地和全部网盘刮削快照', () async {
    final failingStorage = _FailOnceWorkStorage();
    final fixture = await _fixture(workStorage: failingStorage);
    final originalLocal = fixture.localRepository.getAll();
    final originalResources = await fixture.resourceRepository.getAll();
    final originalWorks = await fixture.workRepository.getAll();
    final originalRules = await fixture.ruleRepository.getAll();
    failingStorage.failNextWrite = true;

    await expectLater(
      fixture.importer.apply(fixture.plan, fixture.archive),
      throwsA(isA<ScrapedMetadataImportException>()),
    );

    expect(fixture.localRepository.getAll(), originalLocal);
    expect(await fixture.resourceRepository.getAll(), originalResources);
    expect(await fixture.workRepository.getAll(), originalWorks);
    expect(await fixture.ruleRepository.getAll(), originalRules);
    final importedDirectory = Directory(
      '${fixture.cacheRoot.path}${Platform.pathSeparator}scraped_metadata',
    );
    expect(
      await importedDirectory.exists()
          ? await importedDirectory.list().isEmpty
          : true,
      isTrue,
    );
  });
}

Future<_Fixture> _fixture({
  CloudWorkTmdbStorage? workStorage,
  TransferNetworkImageInstaller? networkImageInstaller,
}) async {
  final temporary =
      await Directory.systemTemp.createTemp('kyymeta-import-test-');
  final archiveDirectory =
      await Directory.systemTemp.createTemp('kyymeta-import-archive-');
  final cacheRoot =
      await Directory.systemTemp.createTemp('kyymeta-import-cache-');
  addTearDown(() async {
    for (final directory in <Directory>[
      temporary,
      archiveDirectory,
      cacheRoot,
    ]) {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });
  final image = File(
    '${archiveDirectory.path}${Platform.pathSeparator}poster.jpg',
  );
  await image.writeAsBytes(<int>[1, 2, 3]);
  final backdrop = File(
    '${archiveDirectory.path}${Platform.pathSeparator}backdrop.jpg',
  );
  await backdrop.writeAsBytes(<int>[4, 5, 6]);

  final localRepository = LocalMediaIndexRepository(
    storage: _MemoryLocalIndexStorage(),
  );
  final currentLocal = LocalMediaIndexItem(
    path: r'E:\媒体\影视\三体\S01E01.mkv',
    name: 'S01E01.mkv',
    parentPath: r'E:\媒体\影视\三体',
    sourcePath: r'E:\媒体\影视',
    size: 1024,
    modified: DateTime.utc(2026, 7, 30),
    seriesName: '三体',
    subtitlePath: r'E:\媒体\影视\三体\S01E01.zh.srt',
    durationMillis: 3600000,
    cover: 'old-cover.jpg',
    tmdb: _oldMetadata,
    scrapeStatus: TmdbScrapeStatus.matched,
    indexedAt: DateTime.utc(2026, 7, 30),
  );
  await localRepository.saveForSource(
    r'E:\媒体\影视',
    <LocalMediaIndexItem>[currentLocal],
  );

  final resourceRepository = CloudResourceTmdbRepository(
    storage: MemoryCloudResourceTmdbStorage(),
  );
  final oldResource = CloudResourceTmdbRecord.matched(
    sourceId: 'new-cloud',
    remoteId: 'new-remote',
    remotePath: '/影视/三体.mkv',
    displayName: '旧三体',
    resourceKind: CloudResourceKind.standaloneVideo,
    metadata: _oldMetadata,
    checkedAt: DateTime.utc(2026, 7, 30),
  );
  await resourceRepository.upsert(oldResource);

  final workRepository = CloudWorkTmdbRepository(
    storage: workStorage ?? MemoryCloudWorkTmdbStorage(),
  );
  final oldWork = CloudWorkTmdbRecord.matched(
    sourceId: 'new-cloud',
    workKey: 'new-work',
    workRootId: 'new-root',
    workRootPath: '/影视/三体',
    remoteName: '三体',
    metadata: _oldMetadata,
    checkedAt: DateTime.utc(2026, 7, 30),
  );
  await workRepository.upsert(oldWork);
  final ruleRepository = CloudSeriesMatchRuleRepository(
    storage: MemoryCloudSeriesMatchRuleStorage(),
  );

  final portableLocal = PortableLocalRecord(
    relativePath: '三体/S01E01.mkv',
    size: 1024,
    tmdb: _newMetadata.toJson(),
    scrapeStatus: 'matched',
    tmdbMatchOrigin: TmdbMatchOrigin.manual.name,
    tmdbRuleVersion: 3,
    titleLocked: true,
    posterLocked: true,
    posterImage: 'images/poster.jpg',
    backdropImage: 'images/backdrop.jpg',
  );
  final portableResourceJson = CloudResourceTmdbRecord.matched(
    sourceId: 'old-cloud',
    remoteId: 'old-remote',
    remotePath: '/影视/三体.mkv',
    displayName: '三体',
    resourceKind: CloudResourceKind.standaloneVideo,
    metadata: _newMetadata,
    checkedAt: DateTime.utc(2026, 7, 30),
  ).toJson();
  final portableResource = PortableCloudRecord(
    record: portableResourceJson,
    posterImage: 'images/poster.jpg',
  );
  final portableWork = PortableCloudRecord(
    record: CloudWorkTmdbRecord.matched(
      sourceId: 'old-cloud',
      workKey: 'old-work',
      workRootId: 'old-root',
      workRootPath: '/影视/三体',
      remoteName: '三体',
      metadata: _newMetadata,
      checkedAt: DateTime.utc(2026, 7, 30),
    ).toJson(),
    posterImage: 'images/poster.jpg',
  );
  final payload = ScrapedMetadataPayload(
    formatVersion: scrapedMetadataFormatVersion,
    exportedAt: DateTime.utc(2026, 7, 30),
    appVersion: '2.1.93',
    localSources: <PortableLocalSource>[
      PortableLocalSource(
        exportId: 'old-local',
        name: '影视',
        originalRoot: r'D:\影视',
        records: <PortableLocalRecord>[portableLocal],
      ),
    ],
    cloudSources: <PortableCloudSource>[
      PortableCloudSource(
        exportId: 'old-cloud',
        type: CloudSourceType.quark,
        name: '夸克',
        sanitizedBaseUrl: '',
        roots: const <PortableCloudRoot>[
          PortableCloudRoot(id: 'root', path: '/影视'),
        ],
        resourceRecords: <PortableCloudRecord>[portableResource],
        workRecords: <PortableCloudRecord>[portableWork],
        seriesRules: const <PortableCloudRecord>[],
      ),
    ],
  );
  final plan = ScrapedMetadataImportPlan(
    payload: payload,
    localMappings: const <String, String>{'old-local': 'new-local'},
    cloudMappings: const <String, String>{'old-cloud': 'new-cloud'},
    localMatches: <LocalImportMatch>[
      LocalImportMatch(portable: portableLocal, target: currentLocal),
    ],
    cloudResourceMatches: <CloudResourceImportMatch>[
      CloudResourceImportMatch(
        portable: portableResource,
        targetSourceId: 'new-cloud',
        targetRemoteId: 'new-remote',
        targetRemotePath: '/影视/三体.mkv',
      ),
    ],
    cloudWorkMatches: <CloudWorkImportMatch>[
      CloudWorkImportMatch(
        portable: portableWork,
        targetSourceId: 'new-cloud',
        targetWorkKey: 'new-work',
        targetWorkRootId: 'new-root',
        targetWorkRootPath: '/影视/三体',
      ),
    ],
    cloudSeriesRuleMatches: const <CloudSeriesRuleImportMatch>[],
    unresolvedLocalSources: const <PortableLocalSource>[],
    unresolvedCloudSources: const <PortableCloudSource>[],
    missingMediaCount: 0,
    recoverableImageCount: 2,
  );
  final archive = DecodedScrapedMetadataArchive(
    payload: payload,
    imageFiles: <String, File>{
      'images/poster.jpg': image,
      'images/backdrop.jpg': backdrop,
    },
    temporaryDirectory: archiveDirectory,
  );
  final importer = ScrapedMetadataImporter(
    localIndexRepository: localRepository,
    resourceRepository: resourceRepository,
    workRepository: workRepository,
    ruleRepository: ruleRepository,
    cacheRootProvider: () async => cacheRoot,
    networkImageInstaller:
        networkImageInstaller ?? ({required url, required file}) async {},
  );
  return _Fixture(
    localRepository: localRepository,
    resourceRepository: resourceRepository,
    workRepository: workRepository,
    ruleRepository: ruleRepository,
    importer: importer,
    plan: plan,
    archive: archive,
    cacheRoot: cacheRoot,
  );
}

final TmdbMetadata _oldMetadata = TmdbMetadata(
  id: 1,
  mediaType: TmdbMediaType.tv,
  title: '旧标题',
  language: 'zh-CN',
  matchedAt: DateTime.utc(2026, 7, 29),
  matchConfidence: 0.5,
);

final TmdbMetadata _newMetadata = TmdbMetadata(
  id: 42,
  mediaType: TmdbMediaType.tv,
  title: '三体',
  posterUrl: 'https://image.tmdb.org/t/p/w500/poster.jpg',
  backdropUrl: 'https://image.tmdb.org/t/p/original/backdrop.jpg',
  language: 'zh-CN',
  matchedAt: DateTime.utc(2026, 7, 30),
  matchConfidence: 1,
);

final class _Fixture {
  const _Fixture({
    required this.localRepository,
    required this.resourceRepository,
    required this.workRepository,
    required this.ruleRepository,
    required this.importer,
    required this.plan,
    required this.archive,
    required this.cacheRoot,
  });

  final LocalMediaIndexRepository localRepository;
  final CloudResourceTmdbRepository resourceRepository;
  final CloudWorkTmdbRepository workRepository;
  final CloudSeriesMatchRuleRepository ruleRepository;
  final ScrapedMetadataImporter importer;
  final ScrapedMetadataImportPlan plan;
  final DecodedScrapedMetadataArchive archive;
  final Directory cacheRoot;
}

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

final class _FailOnceWorkStorage implements CloudWorkTmdbStorage {
  List<Map<String, Object?>> records = <Map<String, Object?>>[];
  bool failNextWrite = false;

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<List<Map<String, Object?>>> read() async =>
      records.map(Map<String, Object?>.from).toList();

  @override
  Future<void> write(List<Map<String, Object?>> records) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw const FileSystemException('模拟写入失败');
    }
    this.records = records.map(Map<String, Object?>.from).toList();
  }
}
