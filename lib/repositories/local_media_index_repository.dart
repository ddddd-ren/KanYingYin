import 'dart:convert';

import 'package:synchronized/synchronized.dart';
import 'package:kanyingyin/legacy/local_index/legacy_local_media_index_parser.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/library_performance_trace.dart';
import 'package:kanyingyin/utils/storage.dart';

abstract class ILocalMediaIndexRepository {
  List<LocalMediaIndexItem> getAll();

  List<LocalMediaIndexItem> getBySourcePath(String sourcePath);

  List<LocalMediaIndexItem> getBySourceLocation(MediaLocation sourceLocation) =>
      getAll()
          .where((item) => item.sourceLocation == sourceLocation)
          .toList(growable: false);

  LocalMediaIndexItem? getByPath(String path);

  LocalMediaIndexItem? getByLocation(MediaLocation location) {
    for (final item in getAll()) {
      if (item.location == location) return item;
    }
    return null;
  }

  Map<String, String> getDirectoryFingerprints(String sourcePath);

  Map<String, String> getDirectoryFingerprintsForLocation(
    MediaLocation sourceLocation,
  ) {
    if (sourceLocation.isFile) {
      return getDirectoryFingerprints(sourceLocation.value);
    }
    return const <String, String>{};
  }

  Future<void> saveForSource(
    String sourcePath,
    List<LocalMediaIndexItem> items,
  );

  Future<void> saveForSourceLocation(
    MediaLocation sourceLocation,
    List<LocalMediaIndexItem> items,
  ) {
    if (sourceLocation.isFile) {
      return saveForSource(sourceLocation.value, items);
    }
    throw UnsupportedError('仓库实现不支持 Android 文档索引');
  }

  Future<void> updateItem(LocalMediaIndexItem item);

  /// 批量更新的默认实现，兼容只实现单项更新的轻量仓储。
  Future<void> updateItems(
    Map<String, LocalMediaIndexItem> itemsById,
  ) async {
    for (final item in itemsById.values) {
      await updateItem(item);
    }
  }

  Future<void> saveDirectoryFingerprints(
    String sourcePath,
    Map<String, String> fingerprints,
  );

  Future<void> saveDirectoryFingerprintsForLocation(
    MediaLocation sourceLocation,
    Map<String, String> fingerprints,
  ) {
    if (sourceLocation.isFile) {
      return saveDirectoryFingerprints(sourceLocation.value, fingerprints);
    }
    throw UnsupportedError('仓库实现不支持 Android 文档目录指纹');
  }

  Future<void> removeSource(String sourcePath);

  Future<void> removeSourceLocation(MediaLocation sourceLocation) {
    if (sourceLocation.isFile) return removeSource(sourceLocation.value);
    throw UnsupportedError('仓库实现不支持 Android 文档索引');
  }

  Future<void> clear();
}

/// 扫描开始时保留版本，删除来源后旧任务不能重新写入。
class LocalMediaSourceSnapshot {
  LocalMediaSourceSnapshot(this.location, this.items, this.generation);

  final MediaLocation location;
  final List<LocalMediaIndexItem> items;
  final int generation;
}

extension LocalMediaIndexMutation on ILocalMediaIndexRepository {
  LocalMediaSourceSnapshot captureSource(MediaLocation location) =>
      LocalMediaSourceSnapshot(
          location,
          getBySourceLocation(location),
          this is LocalMediaIndexRepository
              ? (this as LocalMediaIndexRepository)._generation(location)
              : 0);

  Future<bool> commitSource(
    LocalMediaSourceSnapshot snapshot,
    List<LocalMediaIndexItem> items, {
    Map<String, String>? fingerprints,
    Map<String, String> mediaIdAliases = const {},
  }) async {
    final repository = this;
    if (repository is LocalMediaIndexRepository) {
      return repository._commitSource(snapshot, items,
          fingerprints: fingerprints, mediaIdAliases: mediaIdAliases);
    }
    await saveForSourceLocation(snapshot.location, items);
    if (fingerprints != null) {
      await saveDirectoryFingerprintsForLocation(
          snapshot.location, fingerprints);
    }
    return true;
  }

  Future<void> patchItem(
          LocalMediaIndexItem original, LocalMediaIndexItem item) =>
      patchItems({item.id: item}, originals: {original.id: original});

  Future<void> patchItems(Map<String, LocalMediaIndexItem> updates,
      {required Map<String, LocalMediaIndexItem> originals}) {
    final repository = this;
    if (repository is LocalMediaIndexRepository) {
      return repository._patchItems(updates, originals);
    }
    return updateItems(updates);
  }
}

class _LocalMediaIndexState {
  final lock = Lock();
  List<LocalMediaIndexItem>? items;
  final generations = <String, int>{};
  final itemGenerations = Expando<int>();
  int clearGeneration = 0;
}

abstract interface class LocalMediaIndexStorage {
  Object? read(String key, {Object? defaultValue});

  Future<void> write(String key, Object? value);

  Future<void> delete(String key);
}

class _GStorageLocalMediaIndexStorage implements LocalMediaIndexStorage {
  const _GStorageLocalMediaIndexStorage();

  @override
  Object? read(String key, {Object? defaultValue}) =>
      GStorage.setting.get(key, defaultValue: defaultValue);

  @override
  Future<void> write(String key, Object? value) =>
      GStorage.setting.put(key, value);

  @override
  Future<void> delete(String key) => GStorage.setting.delete(key);
}

class LocalMediaIndexRepository implements ILocalMediaIndexRepository {
  LocalMediaIndexRepository({
    LocalMediaIndexStorage? storage,
    LibraryPerformanceTrace? performanceTrace,
  })  : _storage = storage ?? const _GStorageLocalMediaIndexStorage(),
        _performanceTrace = performanceTrace ?? LibraryPerformanceTrace() {
    _state = _states[_storage] ??= _LocalMediaIndexState();
  }

  static final _states = Expando<_LocalMediaIndexState>();
  late final _LocalMediaIndexState _state;

  final LocalMediaIndexStorage _storage;
  final LibraryPerformanceTrace _performanceTrace;
  List<LocalMediaIndexItem>? get _cachedItems => _state.items;
  set _cachedItems(List<LocalMediaIndexItem>? items) {
    _state.items = items;
    for (final item in items ?? const <LocalMediaIndexItem>[]) {
      _state.itemGenerations[item] ??= _generation(item.sourceLocation);
    }
  }

  int _generation(MediaLocation location) =>
      (_state.generations[location.stableId] ?? 0) + _state.clearGeneration;

  @override
  List<LocalMediaIndexItem> getAll() {
    final cached = _cachedItems;
    if (cached != null) return cached;
    try {
      final snapshot = _performanceTrace.measure(
        LibraryPerformanceStage.localIndexRead,
        () {
          final value = _storage.read(
            SettingBoxKey.localMediaIndex,
            defaultValue: const <Map<String, dynamic>>[],
          );
          if (value is! List) {
            throw const FormatException('本地媒体索引格式无效，已停止写入以保护原数据');
          }

          final items = <LocalMediaIndexItem>[];
          for (final raw in value) {
            if (raw is! Map<Object?, Object?>) {
              throw const FormatException('本地媒体索引条目格式无效');
            }
            final item = _readIndexItem(raw);
            if (item.path.isEmpty || item.sourcePath.isEmpty) {
              throw const FormatException('本地媒体索引条目缺少路径');
            }
            items.add(item);
          }
          items.sort(_compareItems);
          return List<LocalMediaIndexItem>.unmodifiable(items);
        },
        count: (items) => items.length,
      );
      _cachedItems = snapshot;
      return snapshot;
    } catch (e, stackTrace) {
      AppLogger().w(
        'LocalMediaIndexRepository: failed to read index',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  LocalMediaIndexItem _readIndexItem(Map<Object?, Object?> item) {
    final json = Map<String, dynamic>.from(item);
    if (json['tmdb'] is! Map) {
      final migratedTmdb = LegacyLocalMediaIndexParser.parseTmdb(json);
      if (migratedTmdb != null) json['tmdb'] = migratedTmdb.toJson();
    }
    return LocalMediaIndexItem.fromJson(json);
  }

  @override
  List<LocalMediaIndexItem> getBySourcePath(String sourcePath) {
    return getBySourceLocation(MediaLocation.file(sourcePath));
  }

  @override
  List<LocalMediaIndexItem> getBySourceLocation(
    MediaLocation sourceLocation,
  ) {
    final sourceId = sourceLocation.stableId;
    return getAll()
        .where((item) => item.sourceLocation.stableId == sourceId)
        .toList(growable: false);
  }

  @override
  LocalMediaIndexItem? getByPath(String path) {
    return getByLocation(MediaLocation.file(path));
  }

  @override
  LocalMediaIndexItem? getByLocation(MediaLocation location) {
    for (final item in getAll()) {
      if (item.location == location) return item;
    }
    return null;
  }

  @override
  Map<String, String> getDirectoryFingerprints(String sourcePath) {
    try {
      final all = _readFingerprintPayload();
      final sourceId = LocalMediaIndexItem.normalizePath(sourcePath);
      return Map<String, String>.from(
          all[sourceId] ?? const <String, String>{});
    } catch (e, stackTrace) {
      AppLogger().w(
        'LocalMediaIndexRepository: failed to read directory fingerprints',
        error: e,
        stackTrace: stackTrace,
      );
      return const <String, String>{};
    }
  }

  @override
  Map<String, String> getDirectoryFingerprintsForLocation(
    MediaLocation sourceLocation,
  ) {
    if (sourceLocation.isFile) {
      return getDirectoryFingerprints(sourceLocation.value);
    }
    try {
      final all = _readFingerprintPayload();
      return Map<String, String>.from(
        all[sourceLocation.stableId] ?? const <String, String>{},
      );
    } on Object catch (error, stackTrace) {
      AppLogger().w(
        'LocalMediaIndexRepository: failed to read document fingerprints',
        error: error,
        stackTrace: stackTrace,
      );
      return const <String, String>{};
    }
  }

  @override
  Future<void> saveForSource(
    String sourcePath,
    List<LocalMediaIndexItem> items,
  ) async {
    return saveForSourceLocation(MediaLocation.file(sourcePath), items);
  }

  @override
  Future<void> saveForSourceLocation(
    MediaLocation sourceLocation,
    List<LocalMediaIndexItem> items,
  ) =>
      _state.lock.synchronized(() async {
        final sourceId = sourceLocation.stableId;
        final allItems = getAll()
            .where((item) => item.sourceLocation.stableId != sourceId)
            .toList();
        allItems.addAll(items);
        await _save(allItems);
      });

  @override
  Future<void> updateItem(LocalMediaIndexItem item) =>
      _state.lock.synchronized(() async {
        final items = getAll().toList();
        final index = items.indexWhere((current) => current.id == item.id);
        if (index >= 0) {
          items[index] = item;
        }
        await _save(items);
      });

  @override
  Future<void> updateItems(
    Map<String, LocalMediaIndexItem> itemsById,
  ) =>
      _state.lock.synchronized(() async {
        if (itemsById.isEmpty) return;
        final items =
            getAll().map((item) => itemsById[item.id] ?? item).toList();
        await _save(items);
      });

  @override
  Future<void> saveDirectoryFingerprints(
    String sourcePath,
    Map<String, String> fingerprints,
  ) =>
      _state.lock.synchronized(() async {
        final all = _readFingerprintPayload();
        all[LocalMediaIndexItem.normalizePath(sourcePath)] = fingerprints;
        await _storage.write(
          SettingBoxKey.localMediaDirectoryFingerprints,
          all,
        );
      });

  @override
  Future<void> saveDirectoryFingerprintsForLocation(
    MediaLocation sourceLocation,
    Map<String, String> fingerprints,
  ) =>
      _state.lock
          .synchronized(() => _saveFingerprints(sourceLocation, fingerprints));

  Future<void> _saveFingerprints(
      MediaLocation location, Map<String, String> fingerprints) async {
    final all = _readFingerprintPayload();
    final key = location.isFile
        ? LocalMediaIndexItem.normalizePath(location.value)
        : location.stableId;
    all.remove(location.stableId);
    all[key] = Map.of(fingerprints);
    await _storage.write(SettingBoxKey.localMediaDirectoryFingerprints, all);
  }

  @override
  Future<void> removeSource(String sourcePath) async {
    return removeSourceLocation(MediaLocation.file(sourcePath));
  }

  @override
  Future<void> removeSourceLocation(MediaLocation sourceLocation) {
    final sourceId = sourceLocation.stableId;
    _state.generations
        .update(sourceId, (value) => value + 1, ifAbsent: () => 1);
    return _state.lock.synchronized(() async {
      await _save(getAll()
          .where((item) => item.sourceLocation.stableId != sourceId)
          .toList());
      final all = _readFingerprintPayload()..remove(sourceId);
      if (sourceLocation.isFile) {
        all.remove(LocalMediaIndexItem.normalizePath(sourceLocation.value));
      }
      await _storage.write(SettingBoxKey.localMediaDirectoryFingerprints, all);
    });
  }

  @override
  Future<void> clear() {
    _state.clearGeneration++;
    return _state.lock.synchronized(() async {
      await _save(const <LocalMediaIndexItem>[]);
      await _storage.delete(SettingBoxKey.localMediaDirectoryFingerprints);
    });
  }

  Future<void> _patchItems(Map<String, LocalMediaIndexItem> updates,
          Map<String, LocalMediaIndexItem> originals) =>
      _state.lock.synchronized(() async {
        if (updates.isEmpty) return;
        final items = getAll().map((current) {
          final update = updates[current.id];
          final original = originals[current.id];
          if (update == null ||
              original == null ||
              _state.itemGenerations[original] !=
                  _generation(current.sourceLocation)) {
            return current;
          }
          _state.itemGenerations[update] = _generation(current.sourceLocation);
          return _mergeChanges(original, update, current);
        }).toList();
        await _save(items);
      });

  Future<bool> _commitSource(
          LocalMediaSourceSnapshot snapshot, List<LocalMediaIndexItem> items,
          {Map<String, String>? fingerprints,
          required Map<String, String> mediaIdAliases}) =>
      _state.lock.synchronized(() async {
        if (_generation(snapshot.location) != snapshot.generation) return false;
        final current = {
          for (final item in getBySourceLocation(snapshot.location))
            item.id: item
        };
        final originals = {for (final item in snapshot.items) item.id: item};
        final previousIds = {
          for (final entry in mediaIdAliases.entries) entry.value: entry.key
        };
        final merged = items.where((item) {
          final oldId = previousIds[item.id] ?? item.id;
          return !originals.containsKey(oldId) || current.containsKey(oldId);
        }).map((item) {
          final oldId = previousIds[item.id] ?? item.id;
          final original = originals[oldId];
          final latest = current[oldId];
          return original != null && latest != null
              ? _mergeChanges(original, item, latest)
              : item;
        }).toList();
        // 另一轮扫描新增的条目不在本轮快照内，不应被整源替换删除。
        final ids = merged.map((item) => item.id).toSet();
        merged.addAll(current.values.where((item) =>
            !originals.containsKey(item.id) && !ids.contains(item.id)));
        await _save([
          ...getAll().where((item) => item.sourceLocation != snapshot.location),
          ...merged
        ]);
        if (fingerprints != null) {
          await _saveFingerprints(snapshot.location, fingerprints);
        }
        return true;
      });

  LocalMediaIndexItem _mergeChanges(LocalMediaIndexItem original,
      LocalMediaIndexItem update, LocalMediaIndexItem current) {
    final before = original.toJson();
    final incoming = update.toJson();
    final latest = current.toJson();
    if (identical(original, current) ||
        jsonEncode(before) == jsonEncode(latest)) {
      return update;
    }
    // 扫描或网络等待期间已发生的编辑优先，未修改字段保留任务的新结果。
    for (final key in {...before.keys, ...latest.keys}) {
      if (jsonEncode(before[key]) == jsonEncode(latest[key])) continue;
      if (key == 'tmdb' &&
          original.tmdb != null &&
          update.tmdb != null &&
          current.tmdb != null &&
          original.tmdb!.id == current.tmdb!.id &&
          update.tmdb!.id == current.tmdb!.id &&
          original.tmdb!.mediaType == current.tmdb!.mediaType &&
          update.tmdb!.mediaType == current.tmdb!.mediaType) {
        incoming[key] = _mergeMetadataChanges(original.tmdb!.toJson(),
            update.tmdb!.toJson(), current.tmdb!.toJson());
      } else if (latest.containsKey(key)) {
        incoming[key] = latest[key];
      } else {
        incoming.remove(key);
      }
    }
    return LocalMediaIndexItem.fromJson(incoming).copyWith(
      modified: original.modified == current.modified
          ? update.modified
          : current.modified,
      indexedAt: original.indexedAt == current.indexedAt
          ? update.indexedAt
          : current.indexedAt,
    );
  }

  Map<String, Object?> _mergeMetadataChanges(Map<String, Object?> before,
      Map<String, Object?> incoming, Map<String, Object?> latest) {
    final merged = Map<String, Object?>.of(incoming);
    for (final key in {...before.keys, ...latest.keys}) {
      if (jsonEncode(before[key]) == jsonEncode(latest[key])) continue;
      final nextValue = incoming[key];
      final latestValue = latest[key];
      final oldValue = before[key];
      if (nextValue is Map<String, Object?> &&
          (latestValue is Map<String, Object?> ||
              oldValue is Map<String, Object?>)) {
        merged[key] = _mergeMetadataChanges(
          oldValue is Map<String, Object?> ? oldValue : const {},
          nextValue,
          latestValue is Map<String, Object?> ? latestValue : const {},
        );
      } else if (latest.containsKey(key)) {
        merged[key] = latestValue;
      } else {
        merged.remove(key);
      }
    }
    return merged;
  }

  Future<void> _save(List<LocalMediaIndexItem> items) async {
    final deduplicated = <String, LocalMediaIndexItem>{};
    for (final item in items) {
      deduplicated[item.id] = item;
    }
    final payload = deduplicated.values.toList()..sort(_compareItems);
    await _storage.write(
      SettingBoxKey.localMediaIndex,
      payload.map((item) => item.toJson()).toList(growable: false),
    );
    _cachedItems = List<LocalMediaIndexItem>.unmodifiable(payload);
  }

  int _compareItems(LocalMediaIndexItem a, LocalMediaIndexItem b) {
    final source =
        a.sourceLocation.stableId.compareTo(b.sourceLocation.stableId);
    if (source != 0) return source;
    final series =
        a.seriesKey.toLowerCase().compareTo(b.seriesKey.toLowerCase());
    if (series != 0) return series;
    final season = (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0);
    if (season != 0) return season;
    final episode = (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
    if (episode != 0) return episode;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  Map<String, Map<String, String>> _readFingerprintPayload() {
    final value = _storage.read(
      SettingBoxKey.localMediaDirectoryFingerprints,
      defaultValue: const <String, Map<String, String>>{},
    );
    if (value is! Map) return <String, Map<String, String>>{};

    final result = <String, Map<String, String>>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final raw = entry.value;
      if (raw is! Map) continue;
      result[key] = raw.map(
        (dir, fingerprint) => MapEntry(dir.toString(), fingerprint.toString()),
      );
    }
    return result;
  }
}
