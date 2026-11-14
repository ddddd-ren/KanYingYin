import 'dart:convert';

import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:synchronized/synchronized.dart';

abstract interface class CloudWorkTmdbStorage {
  Object get synchronizationIdentity;

  Future<List<Map<String, Object?>>> read();

  Future<void> write(List<Map<String, Object?>> records);
}

class HiveCloudWorkTmdbStorage implements CloudWorkTmdbStorage {
  static final Object _sharedSettingBoxIdentity = Object();

  @override
  Object get synchronizationIdentity => _sharedSettingBoxIdentity;

  @override
  Future<List<Map<String, Object?>>> read() async {
    final value = GStorage.setting.get(
      SettingBoxKey.cloudWorkTmdbRecords,
      defaultValue: const <Map<String, Object?>>[],
    );
    if (value is! List) return <Map<String, Object?>>[];
    return value
        .whereType<Map<Object?, Object?>>()
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }

  @override
  Future<void> write(List<Map<String, Object?>> records) {
    return GStorage.setting.put(SettingBoxKey.cloudWorkTmdbRecords, records);
  }
}

class MemoryCloudWorkTmdbStorage implements CloudWorkTmdbStorage {
  List<Map<String, Object?>> _records = <Map<String, Object?>>[];

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<List<Map<String, Object?>>> read() async => _records
      .map((record) => Map<String, Object?>.from(record))
      .toList(growable: false);

  @override
  Future<void> write(List<Map<String, Object?>> records) async {
    _records = records
        .map((record) => Map<String, Object?>.from(record))
        .toList(growable: false);
  }
}

class CloudWorkTmdbRepository {
  static final Expando<Lock> _locks = Expando<Lock>();

  CloudWorkTmdbRepository({CloudWorkTmdbStorage? storage})
      : _storage = storage ?? HiveCloudWorkTmdbStorage() {
    final identity = _storage.synchronizationIdentity;
    _mutationLock = _locks[identity] ??= Lock();
  }

  final CloudWorkTmdbStorage _storage;
  late final Lock _mutationLock;

  Future<List<CloudWorkTmdbRecord>> getAll() => _getAll();

  Future<List<CloudWorkTmdbRecord>> getBySource(String sourceId) async {
    return (await _getAll())
        .where((record) => record.sourceId == sourceId)
        .toList(growable: false);
  }

  Future<CloudWorkTmdbRecord?> get(String workKey) async {
    for (final record in await _getAll()) {
      if (record.workKey == workKey) return record;
    }
    return null;
  }

  Future<void> upsert(CloudWorkTmdbRecord record) {
    return _mutationLock.synchronized(() async {
      final records = await _getAll();
      final index = records.indexWhere(
        (existing) => existing.workKey == record.workKey,
      );
      if (index < 0) {
        records.add(record);
      } else {
        records[index] = record;
      }
      await _write(records);
    });
  }

  /// 在同一写锁内读取并合并最新记录，避免不同季度并发保存互相覆盖。
  Future<CloudWorkTmdbRecord> update(
    String workKey,
    CloudWorkTmdbRecord Function(CloudWorkTmdbRecord? current) transform,
  ) {
    return _mutationLock.synchronized(() async {
      final records = await _getAll();
      final index = records.indexWhere((record) => record.workKey == workKey);
      final updated = transform(index < 0 ? null : records[index]);
      if (updated.workKey != workKey) {
        throw ArgumentError('更新不能改变作品标识');
      }
      if (index < 0) {
        records.add(updated);
      } else {
        records[index] = updated;
      }
      await _write(records);
      return updated;
    });
  }

  Future<void> upsertAll(Iterable<CloudWorkTmdbRecord> updates) {
    return _mutationLock.synchronized(() async {
      final records = await _getAll();
      final byKey = <String, CloudWorkTmdbRecord>{
        for (final record in records) record.workKey: record,
        for (final record in updates) record.workKey: record,
      };
      await _write(byKey.values.toList(growable: false));
    });
  }

  /// 只提交仍匹配原快照的目标；回滚跳过冲突并返回未恢复的键。
  Future<Set<String>> patchRecords(
    Map<String, CloudWorkTmdbRecord?> updates, {
    required Map<String, CloudWorkTmdbRecord?> originals,
    bool skipConflicts = false,
  }) {
    if (updates.length != originals.length ||
        updates.keys.any((key) => !originals.containsKey(key)) ||
        [...updates.entries, ...originals.entries].any(
            (entry) => entry.value != null && entry.value!.workKey != entry.key)) {
      throw ArgumentError('条件更新必须提供同一组身份及完整原值');
    }
    return _mutationLock.synchronized(() async {
      if (updates.isEmpty) return <String>{};
      final payload = await _storage.read();
      final records = payload.map(CloudWorkTmdbRecord.fromJson).toList();
      final current = {for (final record in records) record.workKey: record};
      if (current.length != records.length) {
        throw const FormatException('刮削记录身份重复，已停止覆盖');
      }
      final accepted = <String, CloudWorkTmdbRecord?>{};
      final conflicts = <String>{};
      for (final entry in updates.entries) {
        final value = current[entry.key];
        final serialized = jsonEncode(value?.toJson());
        // 写前失败的回滚或重复提交可能已经处于目标状态。
        if (serialized == jsonEncode(entry.value?.toJson())) continue;
        if (serialized != jsonEncode(originals[entry.key]?.toJson())) {
          conflicts.add(entry.key);
        } else {
          accepted[entry.key] = entry.value;
        }
      }
      if (conflicts.isNotEmpty && !skipConflicts) {
        throw StateError('刮削记录已变化，请重新确认导入');
      }
      if (accepted.isNotEmpty) {
        await _storage.write([
          for (var index = 0; index < records.length; index++)
            if (!accepted.containsKey(records[index].workKey))
              payload[index]
            else if (accepted[records[index].workKey] case final replacement?)
              replacement.toJson(),
          for (final entry in accepted.entries)
            if (!current.containsKey(entry.key) && entry.value != null)
              entry.value!.toJson(),
        ]);
      }
      return conflicts;
    });
  }

  Future<void> replaceAll(Iterable<CloudWorkTmdbRecord> replacements) {
    return _mutationLock.synchronized(
      () => _write(replacements.toList(growable: false)),
    );
  }

  Future<void> replaceSource(
    String sourceId,
    Iterable<CloudWorkTmdbRecord> replacements,
  ) {
    return _mutationLock.synchronized(() async {
      final retained = (await _getAll())
          .where((record) => record.sourceId != sourceId)
          .toList();
      retained.addAll(
        replacements.where((record) => record.sourceId == sourceId),
      );
      await _write(retained);
    });
  }

  Future<void> removeSource(String sourceId) {
    return _mutationLock.synchronized(() async {
      final records = await _getAll();
      final retained = records
          .where((record) => record.sourceId != sourceId)
          .toList(growable: false);
      if (retained.length == records.length) return;
      await _write(retained);
    });
  }

  Future<List<CloudWorkTmdbRecord>> _getAll() async {
    final records = <CloudWorkTmdbRecord>[];
    for (final item in await _storage.read()) {
      try {
        final record = CloudWorkTmdbRecord.fromJson(item);
        if (record.sourceId.isNotEmpty && record.workKey.isNotEmpty) {
          records.add(record);
        }
      } on Object {
        continue;
      }
    }
    return records;
  }

  Future<void> _write(List<CloudWorkTmdbRecord> records) {
    return _storage.write(
      records.map((record) => record.toJson()).toList(growable: false),
    );
  }
}
