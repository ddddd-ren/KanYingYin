import 'dart:convert';

import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:synchronized/synchronized.dart';

abstract interface class CloudResourceTmdbStorage {
  Object get synchronizationIdentity;

  Future<List<Map<String, Object?>>> read();

  Future<void> write(List<Map<String, Object?>> records);
}

class HiveCloudResourceTmdbStorage implements CloudResourceTmdbStorage {
  static final Object _sharedSettingBoxIdentity = Object();

  @override
  Object get synchronizationIdentity => _sharedSettingBoxIdentity;

  @override
  Future<List<Map<String, Object?>>> read() async {
    final value = GStorage.setting.get(
      SettingBoxKey.cloudResourceTmdbRecords,
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
    return GStorage.setting.put(
      SettingBoxKey.cloudResourceTmdbRecords,
      records,
    );
  }
}

class MemoryCloudResourceTmdbStorage implements CloudResourceTmdbStorage {
  List<Map<String, Object?>> _records = <Map<String, Object?>>[];

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<List<Map<String, Object?>>> read() async {
    return _records
        .map((record) => Map<String, Object?>.from(record))
        .toList(growable: false);
  }

  @override
  Future<void> write(List<Map<String, Object?>> records) async {
    _records = records
        .map((record) => Map<String, Object?>.from(record))
        .toList(growable: false);
  }
}

class CloudResourceTmdbRepository {
  static final Expando<Lock> _storageLocks = Expando<Lock>();

  CloudResourceTmdbRepository({CloudResourceTmdbStorage? storage})
      : _storage = storage ?? HiveCloudResourceTmdbStorage() {
    final identity = _storage.synchronizationIdentity;
    _mutationLock = _storageLocks[identity] ??= Lock();
  }

  final CloudResourceTmdbStorage _storage;
  late final Lock _mutationLock;

  Future<List<CloudResourceTmdbRecord>> getAll() => _getAll();

  Future<CloudResourceTmdbRecord?> get(String stableKey) async {
    for (final record in await _getAll()) {
      if (record.stableKey == stableKey) return record;
    }
    return null;
  }

  Future<List<CloudResourceTmdbRecord>> getBySource(String sourceId) async {
    return (await _getAll())
        .where((record) => record.sourceId == sourceId)
        .toList(growable: false);
  }

  Future<void> upsert(
    CloudResourceTmdbRecord record, {
    void Function(CloudResourceTmdbRecord? current)? checkCurrent,
  }) {
    return _mutationLock.synchronized(() async {
      final records = await _getAll();
      final index = records.indexWhere(
        (current) => current.stableKey == record.stableKey,
      );
      checkCurrent?.call(index < 0 ? null : records[index]);
      if (index < 0) {
        records.add(record);
      } else {
        records[index] = record;
      }
      await _write(records);
    });
  }

  Future<void> upsertAll(Iterable<CloudResourceTmdbRecord> updates) {
    return _mutationLock.synchronized(() async {
      final records = await _getAll();
      final byKey = <String, CloudResourceTmdbRecord>{
        for (final record in records) record.stableKey: record,
        for (final record in updates) record.stableKey: record,
      };
      await _write(byKey.values.toList(growable: false));
    });
  }

  /// 只提交仍匹配原快照的目标；回滚跳过冲突并返回未恢复的键。
  Future<Set<String>> patchRecords(
    Map<String, CloudResourceTmdbRecord?> updates, {
    required Map<String, CloudResourceTmdbRecord?> originals,
    bool skipConflicts = false,
  }) {
    if (updates.length != originals.length ||
        updates.keys.any((key) => !originals.containsKey(key)) ||
        [...updates.entries, ...originals.entries].any((entry) =>
            entry.value != null && entry.value!.stableKey != entry.key)) {
      throw ArgumentError('条件更新必须提供同一组身份及完整原值');
    }
    return _mutationLock.synchronized(() async {
      if (updates.isEmpty) return <String>{};
      final payload = await _storage.read();
      final records = payload.map(CloudResourceTmdbRecord.fromJson).toList();
      final current = {for (final record in records) record.stableKey: record};
      if (current.length != records.length) {
        throw const FormatException('刮削记录身份重复，已停止覆盖');
      }
      final accepted = <String, CloudResourceTmdbRecord?>{};
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
            if (!accepted.containsKey(records[index].stableKey))
              payload[index]
            else if (accepted[records[index].stableKey] case final replacement?)
              replacement.toJson(),
          for (final entry in accepted.entries)
            if (!current.containsKey(entry.key) && entry.value != null)
              entry.value!.toJson(),
        ]);
      }
      return conflicts;
    });
  }

  Future<void> replaceAll(Iterable<CloudResourceTmdbRecord> replacements) {
    return _mutationLock.synchronized(
      () => _write(replacements.toList(growable: false)),
    );
  }

  Future<void> removeSource(String sourceId) {
    return _mutationLock.synchronized(() async {
      final records = await _getAll();
      final remaining = records
          .where((record) => record.sourceId != sourceId)
          .toList(growable: false);
      if (remaining.length == records.length) return;
      await _write(remaining);
    });
  }

  Future<List<CloudResourceTmdbRecord>> _getAll() async {
    final records = <CloudResourceTmdbRecord>[];
    for (final item in await _storage.read()) {
      try {
        final record = CloudResourceTmdbRecord.fromJson(item);
        if (record.sourceId.isNotEmpty) records.add(record);
      } on Object {
        continue;
      }
    }
    return records;
  }

  Future<void> _write(List<CloudResourceTmdbRecord> records) {
    return _storage.write(
      records.map((record) => record.toJson()).toList(growable: false),
    );
  }
}
