import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_series_match_rule.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_series_match_rule_repository.dart';

typedef _Patch<T> = Future<Set<String>> Function(Map<String, T?> updates,
    {required Map<String, T?> originals, bool skipConflicts});
typedef _Access<T> = ({
  _Patch<T> patch,
  Future<T?> Function(String) get,
  Future<void> Function(T) upsert,
  Future<void> Function(String) removeSource
});

void main() {
  _cases<CloudResourceTmdbRecord>(
      '资源',
      (id, revision) => CloudResourceTmdbRecord.unmatched(
          sourceId: id,
          remoteId: id,
          remotePath: '/$id',
          displayName: revision,
          resourceKind: CloudResourceKind.standaloneVideo,
          checkedAt: DateTime.utc(2026)),
      (value) => value.stableKey,
      (value) => value.toJson(), (storage) {
    final repository = CloudResourceTmdbRepository(storage: storage);
    return (
      patch: repository.patchRecords,
      get: repository.get,
      upsert: repository.upsert,
      removeSource: repository.removeSource
    );
  });
  _cases<CloudWorkTmdbRecord>(
      '作品',
      (id, revision) => CloudWorkTmdbRecord.unmatched(
          sourceId: id,
          workKey: '$id|work',
          workRootId: id,
          workRootPath: '/$id',
          remoteName: revision,
          checkedAt: DateTime.utc(2026)),
      (value) => value.workKey,
      (value) => value.toJson(), (storage) {
    final repository = CloudWorkTmdbRepository(storage: storage);
    return (
      patch: repository.patchRecords,
      get: repository.get,
      upsert: repository.upsert,
      removeSource: repository.removeSource
    );
  });
  _cases<CloudSeriesMatchRule>(
      '规则',
      (id, revision) => CloudSeriesMatchRule(
          sourceId: id,
          parentPath: '/$id',
          normalizedSeriesName: 'series',
          updatedAt: DateTime.utc(2026),
          metadata: TmdbMetadata(
              id: 42,
              mediaType: TmdbMediaType.tv,
              title: revision,
              language: 'zh-CN',
              matchedAt: DateTime.utc(2026),
              matchConfidence: 1)),
      (value) => value.stableKey,
      (value) => value.toJson(), (storage) {
    final repository = CloudSeriesMatchRuleRepository(storage: storage);
    return (
      patch: repository.patchRecords,
      get: repository.get,
      upsert: repository.upsert,
      removeSource: (id) async {
        await repository.removeSource(id);
      }
    );
  });
}

void _cases<T extends Object>(
    String label,
    T Function(String, String) make,
    String Function(T) key,
    Map<String, Object?> Function(T) json,
    _Access<T> Function(_Storage) create) {
  test('$label：非目标并发修改及未知字段保留，目标冲突整批不写', () async {
    final storage = _Storage();
    final first = create(storage);
    final second = create(storage);
    final a = make('a', '旧');
    final b = make('b', '旧');
    final nextA = make('a', '导入');
    final nextB = make('b', '导入');
    await first.upsert(a);
    await first.upsert(b);
    final other = make('other', '并发新增');
    await second.upsert(other);
    storage.records.last['futureField'] = '保留';
    await first.patch({key(a): nextA}, originals: {key(a): a});
    expect(json((await first.get(key(other)))!), json(other));
    expect(storage.records.last['futureField'], '保留');
    await expectLater(
        first.patch({key(a): a, key(b): nextB},
            originals: {key(a): a, key(b): b}),
        throwsStateError);
    expect(json((await first.get(key(b)))!), json(b));
  });

  test('$label：目标删除后不复活，回滚不覆盖并发编辑', () async {
    final storage = _Storage();
    final repository = create(storage);
    final old = make('a', '旧');
    final update = make('a', '导入');
    await repository.upsert(old);
    await repository.removeSource('a');
    await expectLater(
        repository.patch({key(old): update}, originals: {key(old): old}),
        throwsStateError);
    expect(await repository.get(key(old)), isNull);
    await repository.upsert(update);
    final oldB = make('b', '旧');
    final updateB = make('b', '导入');
    await repository.upsert(updateB);
    final manual = make('a', '人工');
    await repository.upsert(manual);
    final conflicts = await repository.patch({key(old): old, key(oldB): oldB},
        originals: {key(old): update, key(oldB): updateB}, skipConflicts: true);
    expect(conflicts, {key(old)});
    expect(json((await repository.get(key(old)))!), json(manual));
    expect(json((await repository.get(key(oldB)))!), json(oldB));
  });

  test('$label：新建可条件删除回滚，写后异常仍能恢复旧值', () async {
    final storage = _Storage();
    final repository = create(storage);
    final old = make('a', '旧');
    final update = make('a', '导入');
    await repository.upsert(old);
    storage.failAfterWrite = true;
    await expectLater(
        repository.patch({key(old): update}, originals: {key(old): old}),
        throwsStateError);
    expect(
        await repository.patch({key(old): old},
            originals: {key(old): update}, skipConflicts: true),
        isEmpty);
    expect(json((await repository.get(key(old)))!), json(old));
    final newRecord = make('new', '新增');
    await repository
        .patch({key(newRecord): newRecord}, originals: {key(newRecord): null});
    await repository.patch({key(newRecord): null},
        originals: {key(newRecord): newRecord}, skipConflicts: true);
    expect(await repository.get(key(newRecord)), isNull);
    expect(
        await repository.patch({key(old): old},
            originals: {key(old): update}, skipConflicts: true),
        isEmpty);
  });

  test('$label：共享写锁内重新读取，不丢等待期间的其它更新', () async {
    final storage = _Storage();
    final first = create(storage);
    final second = create(storage);
    final a = make('a', '旧');
    final b = make('b', '旧');
    await first.upsert(a);
    await first.upsert(b);
    storage.gate = Completer<void>();
    storage.started = Completer<void>();
    final firstWrite =
        first.patch({key(a): make('a', '新')}, originals: {key(a): a});
    await storage.started!.future;
    final secondWrite =
        second.patch({key(b): make('b', '新')}, originals: {key(b): b});
    storage.gate!.complete();
    await Future.wait([firstWrite, secondWrite]);
    expect(json((await first.get(key(a)))!), json(make('a', '新')));
    expect(json((await first.get(key(b)))!), json(make('b', '新')));
  });
}

class _Storage
    implements
        CloudResourceTmdbStorage,
        CloudWorkTmdbStorage,
        CloudSeriesMatchRuleStorage {
  List<Map<String, Object?>> records = [];
  bool failAfterWrite = false;
  Completer<void>? gate;
  Completer<void>? started;
  @override
  Object get synchronizationIdentity => this;
  @override
  Future<List<Map<String, Object?>>> read() async =>
      records.map((record) => Map<String, Object?>.from(record)).toList();
  @override
  Future<void> write(List<Map<String, Object?>> value) async {
    final waiting = gate;
    if (waiting != null) {
      started!.complete();
      await waiting.future;
      gate = null;
    }
    records = value.map((record) => Map<String, Object?>.from(record)).toList();
    if (failAfterWrite) {
      failAfterWrite = false;
      throw StateError('模拟落盘后异常');
    }
  }
}
