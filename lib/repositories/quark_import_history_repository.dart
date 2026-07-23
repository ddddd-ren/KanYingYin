import 'dart:convert';

import 'package:kanyingyin/modules/cloud/quark/quark_import_record.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:synchronized/synchronized.dart';

abstract interface class QuarkImportHistoryStorage {
  Object get synchronizationIdentity;
  Future<List<Object?>> read();
  Future<void> write(List<Object?> value);
}

class HiveQuarkImportHistoryStorage implements QuarkImportHistoryStorage {
  static final Object _identity = Object();

  @override
  Object get synchronizationIdentity => _identity;

  @override
  Future<List<Object?>> read() async {
    final value = GStorage.setting.get(
      SettingBoxKey.quarkImportHistory,
      defaultValue: const <Object?>[],
    );
    return value is List ? List<Object?>.from(value) : <Object?>[];
  }

  @override
  Future<void> write(List<Object?> value) =>
      GStorage.setting.put(SettingBoxKey.quarkImportHistory, value);
}

class MemoryQuarkImportHistoryStorage implements QuarkImportHistoryStorage {
  List<Object?> _value = <Object?>[];

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<List<Object?>> read() async => List<Object?>.from(_value);

  @override
  Future<void> write(List<Object?> value) async {
    _value = List<Object?>.from(value);
  }
}

class QuarkImportHistoryRepository {
  QuarkImportHistoryRepository({QuarkImportHistoryStorage? storage})
      : _storage = storage ?? HiveQuarkImportHistoryStorage() {
    final identity = _storage.synchronizationIdentity;
    _lock = _locks[identity] ??= Lock();
  }

  static final Expando<Lock> _locks = Expando<Lock>();
  final QuarkImportHistoryStorage _storage;
  late final Lock _lock;

  Future<List<QuarkImportRecord>> getAll() async =>
      _decode(await _storage.read());

  Future<bool> tryBegin(QuarkImportRecord record) =>
      tryBeginAll(<QuarkImportRecord>[record]);

  Future<bool> tryBeginAll(List<QuarkImportRecord> pending) =>
      _lock.synchronized(() async {
        if (pending.isEmpty) return false;
        final keys = pending.map((record) => record.idempotencyKey).toSet();
        if (keys.length != pending.length) return false;
        final records = _decode(await _storage.read());
        final blocked = records.any(
          (record) =>
              keys.contains(record.idempotencyKey) && record.blocksDuplicate,
        );
        if (blocked) return false;
        records.removeWhere(
          (record) => keys.contains(record.idempotencyKey),
        );
        records.addAll(pending);
        await _storage.write(records.map((item) => item.toJson()).toList());
        return true;
      });

  Future<void> save(QuarkImportRecord record) =>
      saveAll(<QuarkImportRecord>[record]);

  Future<void> saveAll(List<QuarkImportRecord> updates) =>
      _lock.synchronized(() async {
        final keys = updates.map((record) => record.idempotencyKey).toSet();
        final records = _decode(await _storage.read())
          ..removeWhere((record) => keys.contains(record.idempotencyKey))
          ..addAll(updates);
        await _storage.write(records.map((item) => item.toJson()).toList());
      });

  Future<String> exportJson() async => jsonEncode(
        (await getAll()).map((record) => record.toJson()).toList(),
      );

  static List<QuarkImportRecord> _decode(List<Object?> raw) {
    final records = <QuarkImportRecord>[];
    for (final value in raw.whereType<Map<Object?, Object?>>()) {
      try {
        records.add(
          QuarkImportRecord.fromJson(Map<String, Object?>.from(value)),
        );
      } on Object {
        // 损坏记录彼此隔离，不阻止其他转存历史读取。
      }
    }
    return records;
  }
}
