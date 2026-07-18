import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/utils/logger.dart';
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

class LocalMediaIndexRepository implements ILocalMediaIndexRepository {
  @override
  List<LocalMediaIndexItem> getAll() {
    try {
      final value = GStorage.setting.get(
        SettingBoxKey.localMediaIndex,
        defaultValue: const <Map<String, dynamic>>[],
      );
      if (value is! List) return <LocalMediaIndexItem>[];

      final items = value
          .whereType<Map<Object?, Object?>>()
          .map((item) => LocalMediaIndexItem.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((item) => item.path.isNotEmpty && item.sourcePath.isNotEmpty)
          .toList();
      items.sort(_compareItems);
      return items;
    } catch (e, stackTrace) {
      AppLogger().w(
        'LocalMediaIndexRepository: failed to read index',
        error: e,
        stackTrace: stackTrace,
      );
      return <LocalMediaIndexItem>[];
    }
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
    final items = getAll();
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
    await GStorage.setting.put(
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
    await GStorage.setting.put(
      SettingBoxKey.localMediaDirectoryFingerprints,
      all,
    );
  }

  @override
  Future<void> clear() async {
    await _save(const <LocalMediaIndexItem>[]);
    await GStorage.setting
        .delete(SettingBoxKey.localMediaDirectoryFingerprints);
  }

  Future<void> _save(List<LocalMediaIndexItem> items) async {
    final deduplicated = <String, LocalMediaIndexItem>{};
    for (final item in items) {
      deduplicated[item.id] = item;
    }
    final payload = deduplicated.values.toList()..sort(_compareItems);
    await GStorage.setting.put(
      SettingBoxKey.localMediaIndex,
      payload.map((item) => item.toJson()).toList(growable: false),
    );
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
    final value = GStorage.setting.get(
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
