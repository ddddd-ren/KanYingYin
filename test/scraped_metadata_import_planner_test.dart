import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_import_planner.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/domain/scraped_metadata_transfer_models.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/local_media_source.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/local_media_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

void main() {
  test('本地盘符变化后按相对路径和大小匹配', () async {
    final fixture = await _fixture(
      localPath: r'E:\媒体\影视\三体\S01E01.mkv',
      localSize: 1024,
    );

    final plan = await fixture.planner.plan(
      _payload(),
      localOverrides: <String, String>{'old-local': r'E:\媒体\影视'},
    );

    expect(plan.localMatches, hasLength(1));
    expect(
      plan.localMatches.single.target.path,
      r'E:\媒体\影视\三体\S01E01.mkv',
    );
    expect(plan.unresolvedLocalSources, isEmpty);
  });

  test('同相对路径但大小变化时不匹配', () async {
    final fixture = await _fixture(
      localPath: r'E:\媒体\影视\三体\S01E01.mkv',
      localSize: 2048,
    );

    final plan = await fixture.planner.plan(
      _payload(),
      localOverrides: <String, String>{'old-local': r'E:\媒体\影视'},
    );

    expect(plan.localMatches, isEmpty);
    expect(plan.missingMediaCount, 1);
  });

  test('网盘来源 ID 变化后按类型和根目录映射且远程路径可回退', () async {
    final fixture = await _fixture(
      localPath: r'E:\媒体\影视\三体\S01E01.mkv',
      localSize: 1024,
      cloudSources: <CloudSource>[
        _cloudSource(id: 'new-source-id', rootId: 'new-root-id'),
      ],
      cloudItems: <CloudMediaIndexItem>[
        _cloudItem(
          sourceId: 'new-source-id',
          remoteId: 'changed-remote-id',
          remotePath: '/影视/三体.mkv',
        ),
      ],
    );

    final plan = await fixture.planner.plan(_payload(withCloud: true));

    expect(plan.cloudMappings['old-cloud'], 'new-source-id');
    expect(plan.cloudResourceMatches, hasLength(1));
    expect(
      plan.cloudResourceMatches.single.targetRemoteId,
      'changed-remote-id',
    );
  });

  test('同类型同根目录出现两个候选时保持未解决', () async {
    final fixture = await _fixture(
      localPath: r'E:\媒体\影视\三体\S01E01.mkv',
      localSize: 1024,
      cloudSources: <CloudSource>[
        _cloudSource(id: 'first', rootId: 'root'),
        _cloudSource(id: 'second', rootId: 'root'),
      ],
    );

    final plan = await fixture.planner.plan(_payload(withCloud: true));

    expect(plan.cloudMappings, isEmpty);
    expect(
      plan.unresolvedCloudSources.map((source) => source.exportId),
      contains('old-cloud'),
    );
  });

  test('网盘目录资料按已扫描媒体的作品根目录重新绑定', () async {
    final fixture = await _fixture(
      localPath: r'E:\媒体\影视\三体\S01E01.mkv',
      localSize: 1024,
      cloudSources: <CloudSource>[
        _cloudSource(id: 'new-source-id', rootId: 'new-root-id'),
      ],
      cloudItems: <CloudMediaIndexItem>[
        _cloudItem(
          sourceId: 'new-source-id',
          remoteId: 'episode-id',
          remotePath: '/影视/三体/S01E01.mkv',
          workKey: 'new-work',
          workRootId: 'new-directory-id',
          workRootPath: '/影视/三体',
        ),
      ],
    );

    final plan = await fixture.planner.plan(_directoryPayload());

    expect(plan.cloudResourceMatches, hasLength(1));
    expect(
      plan.cloudResourceMatches.single.targetRemoteId,
      'new-directory-id',
    );
    expect(
      plan.cloudResourceMatches.single.targetRemotePath,
      '/影视/三体',
    );
  });
}

ScrapedMetadataPayload _payload({bool withCloud = false}) =>
    ScrapedMetadataPayload(
      formatVersion: scrapedMetadataFormatVersion,
      exportedAt: DateTime.utc(2026, 7, 30),
      appVersion: '2.1.93',
      localSources: <PortableLocalSource>[
        PortableLocalSource(
          exportId: 'old-local',
          name: '影视',
          originalRoot: r'D:\影视',
          records: <PortableLocalRecord>[
            PortableLocalRecord(
              relativePath: '三体/S01E01.mkv',
              size: 1024,
              tmdb: <String, Object?>{'id': 42, 'title': '三体'},
              scrapeStatus: 'matched',
              tmdbMatchOrigin: 'manual',
              tmdbRuleVersion: 1,
            ),
          ],
        ),
      ],
      cloudSources: withCloud
          ? <PortableCloudSource>[
              PortableCloudSource(
                exportId: 'old-cloud',
                type: CloudSourceType.quark,
                name: '夸克',
                sanitizedBaseUrl: '',
                roots: const <PortableCloudRoot>[
                  PortableCloudRoot(id: 'old-root-id', path: '/影视'),
                ],
                resourceRecords: <PortableCloudRecord>[
                  PortableCloudRecord(
                    record: <String, Object?>{
                      'sourceId': 'old-cloud',
                      'remoteId': 'old-remote-id',
                      'remotePath': '/影视/三体.mkv',
                    },
                  ),
                ],
                workRecords: const <PortableCloudRecord>[],
                seriesRules: const <PortableCloudRecord>[],
              ),
            ]
          : const <PortableCloudSource>[],
    );

ScrapedMetadataPayload _directoryPayload() {
  final base = _payload();
  return ScrapedMetadataPayload(
    formatVersion: base.formatVersion,
    exportedAt: base.exportedAt,
    appVersion: base.appVersion,
    localSources: base.localSources,
    cloudSources: <PortableCloudSource>[
      PortableCloudSource(
        exportId: 'old-cloud',
        type: CloudSourceType.quark,
        name: '夸克',
        sanitizedBaseUrl: '',
        roots: const <PortableCloudRoot>[
          PortableCloudRoot(id: 'old-root-id', path: '/影视'),
        ],
        resourceRecords: <PortableCloudRecord>[
          PortableCloudRecord(
            record: <String, Object?>{
              'sourceId': 'old-cloud',
              'remoteId': 'old-directory-id',
              'remotePath': '/影视/三体',
              'resourceKind': 'directory',
            },
          ),
        ],
        workRecords: const <PortableCloudRecord>[],
        seriesRules: const <PortableCloudRecord>[],
      ),
    ],
  );
}

Future<_Fixture> _fixture({
  required String localPath,
  required int localSize,
  List<CloudSource> cloudSources = const <CloudSource>[],
  List<CloudMediaIndexItem> cloudItems = const <CloudMediaIndexItem>[],
}) async {
  final localStorage = _MemoryLocalIndexStorage();
  final localIndex = LocalMediaIndexRepository(storage: localStorage);
  await localIndex.saveForSource(
    r'E:\媒体\影视',
    <LocalMediaIndexItem>[
      LocalMediaIndexItem(
        path: localPath,
        name: 'S01E01.mkv',
        parentPath: r'E:\媒体\影视\三体',
        sourcePath: r'E:\媒体\影视',
        size: localSize,
        modified: DateTime.utc(2026, 7, 30),
        seriesName: '三体',
        indexedAt: DateTime.utc(2026, 7, 30),
      ),
    ],
  );
  final sourceRepository = CloudSourceRepository(
    storage: MemoryCloudSourceStorage(),
  );
  for (final source in cloudSources) {
    await sourceRepository.save(source);
  }
  final cloudIndex = CloudMediaIndexRepository(
    storage: MemoryCloudMediaIndexStorage(),
  );
  for (final source in cloudSources) {
    await cloudIndex.replaceSource(
      source.id,
      cloudItems.where((item) => item.sourceId == source.id).toList(),
      const <String, String>{},
      const {},
      source.rootPaths,
    );
  }
  return _Fixture(
    ScrapedMetadataImportPlanner(
      localSourceRepository: _LocalSourceRepository(
        <LocalMediaSource>[LocalMediaSource.fromPath(r'E:\媒体\影视')],
      ),
      localIndexRepository: localIndex,
      cloudSourceRepository: sourceRepository,
      cloudIndexRepository: cloudIndex,
    ),
  );
}

CloudSource _cloudSource({required String id, required String rootId}) =>
    CloudSource(
      id: id,
      type: CloudSourceType.quark,
      name: id,
      baseUrl: '',
      rootPaths: const <String>['/影视'],
      rootRefs: <CloudRemoteRef>[
        CloudRemoteRef(id: rootId, path: '/影视'),
      ],
    );

CloudMediaIndexItem _cloudItem({
  required String sourceId,
  required String remoteId,
  required String remotePath,
  String? workKey,
  String? workRootId,
  String? workRootPath,
}) =>
    CloudMediaIndexItem(
      sourceId: sourceId,
      remoteId: remoteId,
      remotePath: remotePath,
      name: '三体.mkv',
      workKey: workKey,
      workRootId: workRootId,
      workRootPath: workRootPath,
      size: 1024,
      modifiedAt: DateTime.utc(2026, 7, 30),
      seriesName: '三体',
    );

final class _Fixture {
  const _Fixture(this.planner);
  final ScrapedMetadataImportPlanner planner;
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

final class _LocalSourceRepository implements ILocalMediaSourceRepository {
  const _LocalSourceRepository(this.sources);
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
