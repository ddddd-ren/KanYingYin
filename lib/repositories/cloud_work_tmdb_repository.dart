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
