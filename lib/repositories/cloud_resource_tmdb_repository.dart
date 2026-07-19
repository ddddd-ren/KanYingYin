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

  Future<void> upsert(CloudResourceTmdbRecord record) {
    return _mutationLock.synchronized(() async {
      final records = await _getAll();
      final index = records.indexWhere(
        (current) => current.stableKey == record.stableKey,
      );
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
