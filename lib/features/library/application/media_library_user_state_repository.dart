import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:synchronized/synchronized.dart';
import 'package:kanyingyin/utils/user_data_mutation_lock.dart';

abstract interface class MediaLibraryUserStateStorage {
  Object get synchronizationIdentity;

  Future<Map<String, Object?>> read();

  Future<void> write(Map<String, Object?> value);
}

class HiveMediaLibraryUserStateStorage implements MediaLibraryUserStateStorage {
  static final Object _identity = Object();

  @override
  Object get synchronizationIdentity => _identity;

  @override
  Future<Map<String, Object?>> read() async {
    final value = GStorage.setting.get(
      SettingBoxKey.mediaLibraryUserStates,
      defaultValue: const <String, Object?>{},
    );
    return value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
  }

  @override
  Future<void> write(Map<String, Object?> value) => GStorage.setting.put(
        SettingBoxKey.mediaLibraryUserStates,
        value,
      );
}

class MemoryMediaLibraryUserStateStorage
    implements MediaLibraryUserStateStorage {
  MemoryMediaLibraryUserStateStorage([
    Map<String, Object?> initialValue = const <String, Object?>{},
  ]) : _value = _copyValue(initialValue);

  Map<String, Object?> _value;

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<Map<String, Object?>> read() async => _copyValue(_value);

  @override
  Future<void> write(Map<String, Object?> value) async {
    _value = _copyValue(value);
  }

  static Map<String, Object?> _copyValue(Map<String, Object?> value) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key: entry.value is Map
            ? <String, Object?>{
                for (final nested in (entry.value as Map).entries)
                  nested.key.toString(): nested.value is Iterable
                      ? List<Object?>.from(nested.value as Iterable)
                      : nested.value,
              }
            : entry.value,
    };
  }
}

/// 按统一媒体库系列键保存收藏、待看和合集状态。
final class MediaLibraryUserStateRepository {
  MediaLibraryUserStateRepository({MediaLibraryUserStateStorage? storage})
      : _storage = storage ?? HiveMediaLibraryUserStateStorage() {
    final identity = _storage.synchronizationIdentity;
    _lock = _storage is HiveMediaLibraryUserStateStorage
        ? userDataMutationLock
        : (_locks[identity] ??= Lock());
  }

  static final Expando<Lock> _locks = Expando<Lock>();
  static final ValueNotifier<int> changes = ValueNotifier(0);

  final MediaLibraryUserStateStorage _storage;
  late final Lock _lock;

  Future<Map<String, MediaLibraryUserState>> getAll() =>
      _lock.synchronized(_readAll);

  Future<MediaLibraryUserState?> get(String key) async {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) return null;
    return (await getAll())[normalizedKey];
  }

  Future<void> save(
    String key,
    MediaLibraryUserState state, {
    bool preserveClassification = false,
  }) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) return Future<void>.value();
    return _lock.synchronized(() async {
      final all = await _readAll();
      final current = all[normalizedKey];
      // 普通标记保存保留锁内最新分类，避免旧界面快照覆盖人工确认。
      final next = preserveClassification
          ? state.copyWith(
              categoryOverride: current?.categoryOverride,
              genreOverride: current?.genreOverride,
              clearCategoryOverride: current?.categoryOverride == null,
              clearGenreOverride: current?.genreOverride == null,
            )
          : state;
      if (next.isEmpty) {
        all.remove(normalizedKey);
      } else {
        all[normalizedKey] = next;
      }
      await _writeAll(all);
    });
  }

  Future<void> remove(String key) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) return Future<void>.value();
    return _lock.synchronized(() async {
      final all = await _readAll();
      if (all.remove(normalizedKey) == null) return;
      await _writeAll(all);
    });
  }

  Future<void> saveClassification(
    String key, {
    required List<String>? categories,
    required List<String>? genres,
    required Iterable<String> mediaIds,
  }) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) return Future<void>.value();
    return _lock.synchronized(() async {
      final all = await _readAll();
      final state = (all[normalizedKey] ?? MediaLibraryUserState.empty).copyWith(
        categoryOverride: categories,
        genreOverride: genres,
        clearCategoryOverride: categories == null,
        clearGenreOverride: genres == null,
        mediaIds: mediaIds,
        updatedAt: DateTime.now(),
      );
      if (state.isEmpty) {
        all.remove(normalizedKey);
      } else {
        all[normalizedKey] = state;
      }
      await _writeAll(all);
    });
  }

  Future<void> replaceAll(Map<String, MediaLibraryUserState> states) {
    return _lock.synchronized(() async {
      final normalized = <String, MediaLibraryUserState>{};
      for (final entry in states.entries) {
        final key = entry.key.trim();
        if (key.isEmpty || entry.value.isEmpty) continue;
        normalized[key] = entry.value;
      }
      await _writeAll(normalized);
    });
  }

  Future<Map<String, MediaLibraryUserState>> reconcile(
    Map<String, Set<String>> identities,
  ) =>
      _lock.synchronized(() async {
        final all = await _readAll();
        final owners = <String, Set<String>>{};
        for (final entry in identities.entries) {
          for (final id in entry.value) {
            owners.putIfAbsent(id, () => <String>{}).add(entry.key);
          }
        }
        var changed = false;
        for (final entry in all.entries.toList()) {
          if (identities.containsKey(entry.key)) {
            final ids = {...entry.value.mediaIds, ...identities[entry.key]!};
            if (entry.value.mediaIds.toSet().difference(ids).isNotEmpty ||
                ids.difference(entry.value.mediaIds.toSet()).isNotEmpty) {
              all[entry.key] = all[entry.key]!.copyWith(mediaIds: ids);
              changed = true;
            }
            continue;
          }
          if (entry.value.mediaIds.any((id) => !owners.containsKey(id))) {
            continue;
          }
          final candidates = <String>{
            for (final id in entry.value.mediaIds) ...?owners[id],
          };
          if (candidates.length != 1) continue;
          final target = candidates.single;
          if ({
                ...entry.value.collections.map((name) => name.toLowerCase()),
                ...?all[target]?.collections.map((name) => name.toLowerCase())
              }.length >
              MediaLibraryUserState.maxCollections) {
            continue;
          }
          try {
            all[target] = _merge(all[target], entry.value, identities[target]!);
          } on MediaLibraryClassificationConflict {
            // 人工选择冲突时保留未关联记录，由用户确认后重试。
            continue;
          }
          all.remove(entry.key);
          changed = true;
        }
        if (changed) await _writeAll(all);
        return all;
      });

  Future<void> remapMediaIds(Map<String, String> aliases) =>
      _lock.synchronized(() async {
        if (aliases.isEmpty) return;
        final all = await _readAll();
        var changed = false;
        for (final entry in all.entries.toList()) {
          if (!entry.value.mediaIds.any(aliases.containsKey)) continue;
          all[entry.key] = entry.value.copyWith(
              mediaIds: entry.value.mediaIds.map((id) => aliases[id] ?? id));
          changed = true;
        }
        if (changed) await _writeAll(all);
      });

  Future<void> relink(String oldKey, String targetKey, Set<String> mediaIds) =>
      _lock.synchronized(() async {
        if (oldKey == targetKey ||
            targetKey.trim().isEmpty ||
            mediaIds.isEmpty) {
          throw ArgumentError('请选择有效的媒体作品');
        }
        final all = await _readAll();
        final old = all[oldKey];
        if (old == null) return;
        if ({
              ...old.collections.map((name) => name.toLowerCase()),
              ...?all[targetKey]?.collections.map((name) => name.toLowerCase())
            }.length >
            MediaLibraryUserState.maxCollections) {
          throw StateError('合并后合集超过 20 个，请先整理合集');
        }
        all[targetKey] = _merge(all[targetKey], old, mediaIds);
        all.remove(oldKey);
        await _writeAll(all);
      });

  static MediaLibraryUserState _merge(MediaLibraryUserState? target,
          MediaLibraryUserState old, Set<String> ids) =>
      MediaLibraryUserState(
        favorite: old.favorite || (target?.favorite ?? false),
        watchLater: old.watchLater || (target?.watchLater ?? false),
        collections: MediaLibraryUserState.normalizeCollections([
          ...old.collections,
          ...?target?.collections,
        ]),
        mediaIds: List<String>.unmodifiable(ids),
        updatedAt: DateTime.now(),
        categoryOverride: MediaLibraryUserState.mergeClassificationOverride(
            target?.categoryOverride, old.categoryOverride),
        genreOverride: MediaLibraryUserState.mergeClassificationOverride(
            target?.genreOverride, old.genreOverride),
      );

  Future<Map<String, MediaLibraryUserState>> _readAll() async {
    final raw = await _storage.read();
    final result = <String, MediaLibraryUserState>{};
    for (final entry in raw.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || entry.value is! Map) continue;
      try {
        final state = MediaLibraryUserState.fromJson(
          Map<Object?, Object?>.from(entry.value as Map),
        );
        if (!state.isEmpty) result[key] = state;
      } on Object {
        // 单条损坏记录隔离处理。
      }
    }
    return result;
  }

  Future<void> _writeAll(Map<String, MediaLibraryUserState> states) async {
    await _storage.write(<String, Object?>{
      for (final entry in states.entries) entry.key: entry.value.toJson(),
    });
    changes.value++;
  }
}
