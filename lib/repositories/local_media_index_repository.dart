import 'package:kanyingyin/legacy/local_index/legacy_local_media_index_parser.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/library_performance_trace.dart';
import 'package:kanyingyin/utils/storage.dart';

abstract class ILocalMediaIndexRepository {
  List<LocalMediaIndexItem> getAll();

  List<LocalMediaIndexItem> getBySourcePath(String sourcePath);

  LocalMediaIndexItem? getByPath(String path);

  Map<String, String> getDirectoryFingerprints(String sourcePath);

  Future<void> saveForSource(
    String sourcePath,
    List<LocalMediaIndexItem> items,
  );

  Future<void> updateItem(LocalMediaIndexItem item);

  Future<void> saveDirectoryFingerprints(
    String sourcePath,
    Map<String, String> fingerprints,
  );

  Future<void> removeSource(String sourcePath);

  Future<void> clear();
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
        _performanceTrace = performanceTrace ?? LibraryPerformanceTrace();

  final LocalMediaIndexStorage _storage;
  final LibraryPerformanceTrace _performanceTrace;
  List<LocalMediaIndexItem>? _cachedItems;

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
          if (value is! List) return const <LocalMediaIndexItem>[];

          final items = value
              .whereType<Map<Object?, Object?>>()
              .map(_readIndexItem)
              .where(
                (item) => item.path.isNotEmpty && item.sourcePath.isNotEmpty,
              )
              .toList();
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
      return _cachedItems = const <LocalMediaIndexItem>[];
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
    final sourceId = LocalMediaIndexItem.normalizePath(sourcePath);
    return getAll()
        .where((item) =>
            LocalMediaIndexItem.normalizePath(item.sourcePath) == sourceId)
        .toList(growable: false);
  }

  @override
  LocalMediaIndexItem? getByPath(String path) {
    final id = LocalMediaIndexItem.normalizePath(path);
    for (final item in getAll()) {
      if (item.id == id) return item;
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
  Future<void> saveForSource(
    String sourcePath,
    List<LocalMediaIndexItem> items,
  ) async {
    final sourceId = LocalMediaIndexItem.normalizePath(sourcePath);
    final allItems = getAll()
        .where((item) =>
            LocalMediaIndexItem.normalizePath(item.sourcePath) != sourceId)
        .toList();
    allItems.addAll(items);
    await _save(allItems);
  }

  @override
  Future<void> updateItem(LocalMediaIndexItem item) async {
    final items = getAll().toList();
    final index = items.indexWhere((current) => current.id == item.id);
    if (index >= 0) {
      items[index] = item;
    } else {
      items.add(item);
    }
    await _save(items);
  }

  @override
  Future<void> saveDirectoryFingerprints(
    String sourcePath,
    Map<String, String> fingerprints,
  ) async {
    final all = _readFingerprintPayload();
    all[LocalMediaIndexItem.normalizePath(sourcePath)] = fingerprints;
    await _storage.write(
      SettingBoxKey.localMediaDirectoryFingerprints,
      all,
    );
  }

  @override
  Future<void> removeSource(String sourcePath) async {
    final sourceId = LocalMediaIndexItem.normalizePath(sourcePath);
    final nextItems = getAll()
        .where((item) =>
            LocalMediaIndexItem.normalizePath(item.sourcePath) != sourceId)
        .toList(growable: false);
    await _save(nextItems);
    final all = _readFingerprintPayload();
    all.remove(sourceId);
    await _storage.write(
      SettingBoxKey.localMediaDirectoryFingerprints,
      all,
    );
  }

  @override
  Future<void> clear() async {
    await _save(const <LocalMediaIndexItem>[]);
    await _storage.delete(SettingBoxKey.localMediaDirectoryFingerprints);
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
        a.sourcePath.toLowerCase().compareTo(b.sourcePath.toLowerCase());
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
