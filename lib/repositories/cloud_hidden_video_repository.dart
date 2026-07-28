import 'package:kanyingyin/modules/cloud/cloud_hidden_video.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:synchronized/synchronized.dart';

abstract interface class CloudHiddenVideoStorage {
  Object get synchronizationIdentity;
  Future<List<Object?>> read();
  Future<void> write(List<Object?> records);
}

class HiveCloudHiddenVideoStorage implements CloudHiddenVideoStorage {
  static final Object _identity = Object();

  @override
  Object get synchronizationIdentity => _identity;

  @override
  Future<List<Object?>> read() async {
    final value = GStorage.setting.get(
      SettingBoxKey.cloudPosterHiddenVideos,
      defaultValue: const <Object?>[],
    );
    return value is List ? List<Object?>.from(value) : <Object?>[];
  }

  @override
  Future<void> write(List<Object?> records) => GStorage.setting.put(
        SettingBoxKey.cloudPosterHiddenVideos,
        records,
      );
}

class MemoryCloudHiddenVideoStorage implements CloudHiddenVideoStorage {
  MemoryCloudHiddenVideoStorage([
    List<Object?> initialRecords = const <Object?>[],
  ]) : _records = _copyRecords(initialRecords);

  List<Object?> _records;

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<List<Object?>> read() async => _copyRecords(_records);

  @override
  Future<void> write(List<Object?> records) async {
    _records = _copyRecords(records);
  }

  static List<Object?> _copyRecords(List<Object?> records) => records
      .map<Object?>(
        (record) => record is Map ? Map<String, Object?>.from(record) : record,
      )
      .toList(growable: false);
}

abstract interface class ICloudHiddenVideoRepository {
  Future<List<CloudHiddenVideo>> getBySource(String sourceId);

  Future<void> replaceSource(
    String sourceId,
    List<CloudHiddenVideo> records,
  );

  Future<void> clearSource(String sourceId);
}

class CloudHiddenVideoRepository implements ICloudHiddenVideoRepository {
  static final Expando<Lock> _locks = Expando<Lock>();

  CloudHiddenVideoRepository({CloudHiddenVideoStorage? storage})
      : _storage = storage ?? HiveCloudHiddenVideoStorage() {
    final identity = _storage.synchronizationIdentity;
    _lock = _locks[identity] ??= Lock();
  }

  final CloudHiddenVideoStorage _storage;
  late final Lock _lock;

  @override
  Future<List<CloudHiddenVideo>> getBySource(String sourceId) async =>
      (await _readAll())
          .where((record) => record.sourceId == sourceId)
          .toList(growable: false);

  @override
  Future<void> replaceSource(
    String sourceId,
    List<CloudHiddenVideo> records,
  ) =>
      _lock.synchronized(() async {
        if (records.any((record) => record.sourceId != sourceId)) {
          throw ArgumentError.value(
            records,
            'records',
            '隐藏视频记录来源与目标来源不一致',
          );
        }
        final retained = (await _readAll())
            .where((record) => record.sourceId != sourceId)
            .toList();
        final unique = <String, CloudHiddenVideo>{};
        for (final record in records) {
          unique[record.identityKey] = record;
        }
        retained.addAll(unique.values);
        await _storage.write(
          retained.map<Object?>((record) => record.toJson()).toList(
                growable: false,
              ),
        );
      });

  @override
  Future<void> clearSource(String sourceId) =>
      replaceSource(sourceId, const <CloudHiddenVideo>[]);

  Future<List<CloudHiddenVideo>> _readAll() async {
    final records = <CloudHiddenVideo>[];
    for (final raw in await _storage.read()) {
      if (raw is! Map) continue;
      try {
        records.add(
          CloudHiddenVideo.fromJson(Map<String, Object?>.from(raw)),
        );
      } on Object {
        continue;
      }
    }
    return records;
  }
}
