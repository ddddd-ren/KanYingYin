import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';

void main() {
  test('并发更新不丢记录且按来源删除', () async {
    final repository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    final first = _record('source-a', 'folder-a', '/A');
    final second = _record('source-a', 'folder-b', '/B');
    final retained = _record('source-b', 'folder-c', '/C');

    await Future.wait(<Future<void>>[
      repository.upsert(first),
      repository.upsert(second),
      repository.upsert(retained),
    ]);

    expect(await repository.getBySource('source-a'), hasLength(2));
    expect(await repository.get(first.stableKey), first);
    await repository.removeSource('source-a');
    expect(await repository.getBySource('source-a'), isEmpty);
    expect(await repository.getBySource('source-b'), <CloudResourceTmdbRecord>[
      retained,
    ]);
  });

  test('更新相同稳定键时替换旧记录', () async {
    final repository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    final original = _record('source-a', 'folder-a', '/A');
    final updated = CloudResourceTmdbRecord.unmatched(
      sourceId: original.sourceId,
      remoteId: original.remoteId,
      remotePath: original.remotePath,
      displayName: '新名称',
      resourceKind: original.resourceKind,
      checkedAt: DateTime.utc(2026, 7, 20),
    );
    await repository.upsert(original);
    await repository.upsert(updated);

    expect(await repository.getBySource('source-a'), <CloudResourceTmdbRecord>[
      updated,
    ]);
  });

  test('仓库更新自定义剧名时保留稳定键和 TMDB 信息', () async {
    final repository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    final original = _matchedRecord();
    await repository.upsert(original);
    await repository.upsert(original.withCustomTitle('新剧名'));

    final stored = await repository.get(original.stableKey);
    expect(stored?.customTitle, '新剧名');
    expect(stored?.tmdbId, original.tmdbId);
    expect(stored?.stableKey, original.stableKey);
  });

  test('批量更新在一次写入中保存全部记录', () async {
    final storage = _RecordingTmdbStorage();
    final repository = CloudResourceTmdbRepository(storage: storage);
    final first = _record('source-a', 'first', '/first');
    final second = _record('source-a', 'second', '/second');

    await repository.upsertAll(<CloudResourceTmdbRecord>[first, second]);

    expect(storage.writeCount, 1);
    expect(await repository.get(first.stableKey), first);
    expect(await repository.get(second.stableKey), second);
  });

  test('批量写入失败时不会留下部分记录', () async {
    final original = _record('source-a', 'original', '/original');
    final storage = _RecordingTmdbStorage(
      initialRecords: <Map<String, Object?>>[original.toJson()],
      failNextWrite: true,
    );
    final repository = CloudResourceTmdbRepository(storage: storage);

    await expectLater(
      repository.upsertAll(<CloudResourceTmdbRecord>[
        _record('source-a', 'first', '/first'),
        _record('source-a', 'second', '/second'),
      ]),
      throwsStateError,
    );

    expect(await repository.getBySource('source-a'), <CloudResourceTmdbRecord>[
      original,
    ]);
  });
}

class _RecordingTmdbStorage implements CloudResourceTmdbStorage {
  _RecordingTmdbStorage({
    List<Map<String, Object?>> initialRecords = const <Map<String, Object?>>[],
    this.failNextWrite = false,
  }) : _records = initialRecords
            .map((record) => Map<String, Object?>.from(record))
            .toList();

  List<Map<String, Object?>> _records;
  bool failNextWrite;
  int writeCount = 0;

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<List<Map<String, Object?>>> read() async => _records
      .map((record) => Map<String, Object?>.from(record))
      .toList(growable: false);

  @override
  Future<void> write(List<Map<String, Object?>> records) async {
    writeCount++;
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('模拟批量写入失败');
    }
    _records = records
        .map((record) => Map<String, Object?>.from(record))
        .toList(growable: false);
  }
}

CloudResourceTmdbRecord _matchedRecord() => CloudResourceTmdbRecord.matched(
      sourceId: 'source-a',
      remoteId: 'folder-a',
      remotePath: '/影视/A',
      displayName: 'A',
      resourceKind: CloudResourceKind.directory,
      metadata: TmdbMetadata(
        id: 42,
        mediaType: TmdbMediaType.tv,
        title: 'TMDB 标题',
        language: 'zh-CN',
        matchedAt: DateTime.utc(2026, 7, 19),
        matchConfidence: 1,
      ),
      checkedAt: DateTime.utc(2026, 7, 19),
    );

CloudResourceTmdbRecord _record(
  String sourceId,
  String remoteId,
  String remotePath,
) =>
    CloudResourceTmdbRecord.unmatched(
      sourceId: sourceId,
      remoteId: remoteId,
      remotePath: remotePath,
      displayName: remotePath,
      resourceKind: CloudResourceKind.directory,
      checkedAt: DateTime.utc(2026, 7, 19),
    );
