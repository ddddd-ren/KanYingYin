import 'package:kanyingyin/features/history/domain/playback_history_entry.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:synchronized/synchronized.dart';

abstract interface class PlaybackHistoryStorage {
  Object get synchronizationIdentity;
  Future<List<Object?>> read();
  Future<void> write(List<Object?> records);
}

class HivePlaybackHistoryStorage implements PlaybackHistoryStorage {
  static final Object _identity = Object();

  @override
  Object get synchronizationIdentity => _identity;

  @override
  Future<List<Object?>> read() async {
    final value = GStorage.setting.get(
      SettingBoxKey.playbackHistory,
      defaultValue: const <Object?>[],
    );
    return value is List ? List<Object?>.from(value) : <Object?>[];
  }

  @override
  Future<void> write(List<Object?> records) =>
      GStorage.setting.put(SettingBoxKey.playbackHistory, records);
}

class MemoryPlaybackHistoryStorage implements PlaybackHistoryStorage {
  MemoryPlaybackHistoryStorage([
    List<Object?> initialRecords = const <Object?>[],
  ]) : _records = List<Object?>.from(initialRecords);

  List<Object?> _records;

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<List<Object?>> read() async => List<Object?>.from(_records);

  @override
  Future<void> write(List<Object?> records) async {
    _records = List<Object?>.from(records);
  }
}

/// 观看历史仓储。损坏的单条记录不会阻塞其他历史读取。
class PlaybackHistoryRepository {
  PlaybackHistoryRepository({PlaybackHistoryStorage? storage})
      : _storage = storage ?? HivePlaybackHistoryStorage() {
    final identity = _storage.synchronizationIdentity;
    _lock = _locks[identity] ??= Lock();
  }

  static const int maxEntries = 100;
  static final Expando<Lock> _locks = Expando<Lock>();

  final PlaybackHistoryStorage _storage;
  late final Lock _lock;

  Future<List<PlaybackHistoryEntry>> getAll() => _lock.synchronized(_readAll);

  Future<List<PlaybackHistoryEntry>> _readAll() async {
    final result = <PlaybackHistoryEntry>[];
    for (final raw in await _storage.read()) {
      if (raw is! Map) continue;
      try {
        result.add(
            PlaybackHistoryEntry.fromJson(Map<Object?, Object?>.from(raw)));
      } on Object {
        // 单条损坏记录隔离处理。
      }
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Future<void> save(PlaybackHistoryEntry entry) => _lock.synchronized(() async {
        final records = await _readAll()
          ..removeWhere((item) => item.stableKey == entry.stableKey)
          ..insert(0, entry);
        if (records.length > maxEntries) {
          records.removeRange(maxEntries, records.length);
        }
        await _storage.write(
          records.map<Object?>((item) => item.toJson()).toList(growable: false),
        );
      });

  Future<void> replaceAll(Iterable<PlaybackHistoryEntry> entries) =>
      _lock.synchronized(() async {
        final unique = <String, PlaybackHistoryEntry>{};
        for (final entry in entries) {
          unique[entry.stableKey] = entry;
        }
        final records = unique.values.toList(growable: false)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        final retained = records.length > maxEntries
            ? records.sublist(0, maxEntries)
            : records;
        await _storage.write(
          retained
              .map<Object?>((item) => item.toJson())
              .toList(growable: false),
        );
      });

  Future<void> delete(String stableKey) => _lock.synchronized(() async {
        final records = await _readAll()
          ..removeWhere((item) => item.stableKey == stableKey);
        await _storage.write(
          records.map<Object?>((item) => item.toJson()).toList(growable: false),
        );
      });

  Future<void> clear() => _lock.synchronized(
        () => _storage.write(const <Object?>[]),
      );
}
