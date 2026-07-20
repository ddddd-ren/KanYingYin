import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';

void main() {
  test('跨仓库并发更新不丢作品且按来源隔离删除', () async {
    final storage = MemoryCloudWorkTmdbStorage();
    final firstRepository = CloudWorkTmdbRepository(storage: storage);
    final secondRepository = CloudWorkTmdbRepository(storage: storage);
    final first = _record('source-a', 'work-a');
    final second = _record('source-a', 'work-b');
    final retained = _record('source-b', 'work-c');

    await Future.wait(<Future<void>>[
      firstRepository.upsert(first),
      secondRepository.upsert(second),
      firstRepository.upsert(retained),
    ]);

    expect(await firstRepository.getBySource('source-a'), hasLength(2));
    expect(await secondRepository.get(first.workKey), first);
    await secondRepository.removeSource('source-a');
    expect(await firstRepository.getBySource('source-a'), isEmpty);
    expect(
      await firstRepository.getBySource('source-b'),
      <CloudWorkTmdbRecord>[retained],
    );
  });

  test('替换来源记录不会影响其他来源', () async {
    final repository = CloudWorkTmdbRepository(
      storage: MemoryCloudWorkTmdbStorage(),
    );
    final old = _record('source-a', 'old');
    final replacement = _record('source-a', 'replacement');
    final retained = _record('source-b', 'retained');
    await repository.upsertAll(<CloudWorkTmdbRecord>[old, retained]);

    await repository.replaceSource(
      'source-a',
      <CloudWorkTmdbRecord>[replacement],
    );

    expect(
      await repository.getBySource('source-a'),
      <CloudWorkTmdbRecord>[replacement],
    );
    expect(await repository.get(retained.workKey), retained);
  });

  test('批量写入失败时不留下部分作品记录', () async {
    final original = _record('source-a', 'original');
    final storage = _RecordingWorkStorage(
      initialRecords: <Map<String, Object?>>[original.toJson()],
      failNextWrite: true,
    );
    final repository = CloudWorkTmdbRepository(storage: storage);

    await expectLater(
      repository.upsertAll(<CloudWorkTmdbRecord>[
        _record('source-a', 'first'),
        _record('source-a', 'second'),
      ]),
      throwsStateError,
    );

    expect(
      await repository.getBySource('source-a'),
      <CloudWorkTmdbRecord>[original],
    );
  });
}

CloudWorkTmdbRecord _record(String sourceId, String rootId) {
  return CloudWorkTmdbRecord.unmatched(
    sourceId: sourceId,
    workKey: '$sourceId|work|$rootId',
    workRootId: rootId,
    workRootPath: '/影视/$rootId',
    remoteName: rootId,
    checkedAt: DateTime.utc(2026, 7, 20),
  );
}

class _RecordingWorkStorage implements CloudWorkTmdbStorage {
  _RecordingWorkStorage({
    List<Map<String, Object?>> initialRecords = const <Map<String, Object?>>[],
    this.failNextWrite = false,
  }) : _records = initialRecords
            .map((record) => Map<String, Object?>.from(record))
            .toList();

  List<Map<String, Object?>> _records;
  bool failNextWrite;

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<List<Map<String, Object?>>> read() async => _records
      .map((record) => Map<String, Object?>.from(record))
      .toList(growable: false);

  @override
  Future<void> write(List<Map<String, Object?>> records) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('模拟作品批量写入失败');
    }
    _records = records
        .map((record) => Map<String, Object?>.from(record))
        .toList(growable: false);
  }
}
