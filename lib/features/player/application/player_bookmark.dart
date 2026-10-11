import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/utils/user_data_mutation_lock.dart';
import 'package:synchronized/synchronized.dart';

abstract interface class PlayerBookmarkStorage {
  Object? read();

  Future<void> write(Object value);
}

class TypedSettingsPlayerBookmarkStorage implements PlayerBookmarkStorage {
  const TypedSettingsPlayerBookmarkStorage(this._settings,
      {this.storageKey = SettingBoxKey.playerBookmarks});

  final TypedSettings _settings;
  final String storageKey;

  @override
  Object? read() => _settings.readRaw(storageKey);

  @override
  Future<void> write(Object value) => _settings.write(storageKey, value);
}

class PlayerBookmark {
  const PlayerBookmark({
    required this.position,
    required this.label,
    required this.createdAt,
  });

  factory PlayerBookmark.fromJson(Map<Object?, Object?> json) {
    final millis = _asInt(json['positionMillis']);
    if (millis < 0) throw const FormatException('书签位置无效');
    return PlayerBookmark(
      position: Duration(milliseconds: millis),
      label: _normalizeLabel(json['label']?.toString() ?? ''),
      createdAt: _dateFromMillis(json['createdAtMillis']),
    );
  }

  final Duration position;
  final String label;
  final DateTime createdAt;

  Map<String, Object> toJson() => <String, Object>{
        'positionMillis': position.inMilliseconds,
        'label': label,
        'createdAtMillis': createdAt.millisecondsSinceEpoch,
      };
}

class PlayerBookmarkRepository {
  PlayerBookmarkRepository(this._storage)
      : _lock = _storage is TypedSettingsPlayerBookmarkStorage
            ? userDataMutationLock
            : Lock();

  static const int maxBookmarksPerMedia = 100;
  static const Duration mergeDistance = Duration(seconds: 2);

  final PlayerBookmarkStorage _storage;
  final Lock _lock;

  List<PlayerBookmark> load(String mediaKey) {
    final normalizedKey = mediaKey.trim();
    if (normalizedKey.isEmpty) return const <PlayerBookmark>[];
    final raw = _storage.read();
    if (raw is! Map) return const <PlayerBookmark>[];
    final values = raw[normalizedKey];
    if (values is! List) return const <PlayerBookmark>[];
    final result = <PlayerBookmark>[];
    for (final value in values) {
      if (value is! Map) continue;
      try {
        result.add(PlayerBookmark.fromJson(Map<Object?, Object?>.from(value)));
      } on Object {
        // 损坏的单条记录不应阻断其他书签读取。
      }
    }
    result.sort((a, b) => a.position.compareTo(b.position));
    return List<PlayerBookmark>.unmodifiable(result);
  }

  Future<List<PlayerBookmark>> add(
    String mediaKey,
    Duration position, {
    String label = '',
  }) =>
      _lock.synchronized(() async {
        final normalizedKey = mediaKey.trim();
        if (normalizedKey.isEmpty || position.isNegative) {
          return const <PlayerBookmark>[];
        }
        final all = _readAll();
        final values = load(normalizedKey).toList();
        final index = values.indexWhere(
          (item) => (item.position - position).abs() <= mergeDistance,
        );
        final normalizedLabel = _normalizeLabel(label);
        final bookmark = PlayerBookmark(
          position: position,
          label: index >= 0 && normalizedLabel.isEmpty
              ? values[index].label
              : normalizedLabel,
          createdAt: DateTime.now(),
        );
        if (index >= 0) {
          values[index] = bookmark;
        } else {
          values.add(bookmark);
        }
        values.sort((a, b) => a.position.compareTo(b.position));
        if (values.length > maxBookmarksPerMedia) {
          values.removeRange(0, values.length - maxBookmarksPerMedia);
        }
        all[normalizedKey] = values.map((item) => item.toJson()).toList();
        await _storage.write(all);
        return List<PlayerBookmark>.unmodifiable(values);
      });

  Future<List<PlayerBookmark>> remove(String mediaKey, PlayerBookmark target) =>
      _lock.synchronized(() async {
        final normalizedKey = mediaKey.trim();
        if (normalizedKey.isEmpty) return const <PlayerBookmark>[];
        final all = _readAll();
        final values = load(normalizedKey)
            .where((item) => item.position != target.position)
            .toList();
        if (values.isEmpty) {
          all.remove(normalizedKey);
        } else {
          all[normalizedKey] = values.map((item) => item.toJson()).toList();
        }
        await _storage.write(all);
        return List<PlayerBookmark>.unmodifiable(values);
      });

  Map<String, Object> _readAll() {
    final raw = _storage.read();
    if (raw is! Map) return <String, Object>{};
    final result = <String, Object>{};
    for (final entry in raw.entries) {
      if (entry.key is String && entry.value is List) {
        result[entry.key as String] = entry.value as List;
      }
    }
    return result;
  }
}

String _normalizeLabel(String value) {
  final normalized = value.trim();
  if (normalized.length <= 64) return normalized;
  return normalized.substring(0, 64);
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime _dateFromMillis(Object? value) {
  final millis = _asInt(value);
  if (millis <= 0) return DateTime.fromMillisecondsSinceEpoch(0);
  return DateTime.fromMillisecondsSinceEpoch(millis);
}
