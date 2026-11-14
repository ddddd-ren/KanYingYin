import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/utils/user_data_mutation_lock.dart';
import 'package:kanyingyin/modules/media/media_custom_tags.dart';
import 'package:kanyingyin/utils/storage.dart';

abstract interface class ILocalMediaTagRepository {
  Map<String, List<String>> getAll();

  Future<void> saveForSeries(String seriesKey, Iterable<String> tags);

  Future<void> reconcileSourceKeys(Map<String, Set<String>> completeSeries);
}

/// 保存本地媒体库作品的用户标签，不改动媒体索引和原始文件。
final class LocalMediaTagRepository implements ILocalMediaTagRepository {
  LocalMediaTagRepository({Box<Object?>? box}) : _providedBox = box;

  static const int maxTagLength = MediaCustomTags.maxTagLength;
  static const int maxTagsPerSeries = MediaCustomTags.maxTags;

  final Box<Object?>? _providedBox;

  Box<Object?> get _box => _providedBox ?? GStorage.setting;

  @override
  Map<String, List<String>> getAll() {
    try {
      final value = _box.get(
        SettingBoxKey.localMediaLibraryTags,
        defaultValue: const <String, List<String>>{},
      );
      if (value is! Map) return <String, List<String>>{};

      final result = <String, List<String>>{};
      for (final entry in value.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty || entry.value is! Iterable) continue;
        final tags = _normalizeTags(entry.value as Iterable<Object?>);
        if (tags.isNotEmpty) result[key] = tags;
      }
      return result;
    } on Object {
      return <String, List<String>>{};
    }
  }

  @override
  Future<void> saveForSeries(String seriesKey, Iterable<String> tags) =>
      userDataMutationLock.synchronized(() async {
        final key = seriesKey.trim();
        if (key.isEmpty) return;

        final next = getAll();
        final normalized = _normalizeTags(tags);
        if (normalized.isEmpty) {
          next.remove(key);
        } else {
          next[key] = normalized;
        }
        await _box.put(SettingBoxKey.localMediaLibraryTags, next);
      });

  @override
  Future<void> reconcileSourceKeys(Map<String, Set<String>> completeSeries) =>
      userDataMutationLock.synchronized(() async {
        final keys = completeSeries.keys.toSet();
        final owners = <String, Set<String>>{};
        final memberOwners = <String, Set<String>>{};
        for (final entry in completeSeries.entries) {
          for (final id in entry.value) {
            memberOwners.putIfAbsent(id, () => {}).add(entry.key);
          }
        }
        for (final key in keys) {
          final separator = key.indexOf('|');
          if (separator < 0) continue;
          owners.putIfAbsent(key.substring(separator + 1), () => {}).add(key);
        }
        final tags = getAll();
        var changed = false;
        for (final entry in tags.entries.toList()) {
          if (keys.contains(entry.key)) continue;
          final separator = entry.key.indexOf('|source|');
          final targets = separator < 0
              ? owners[entry.key]
              : memberOwners[
                  entry.key.substring(separator + '|source|'.length)];
          if (targets == null || targets.length != 1) continue;
          final target = targets.single;
          final combined = [...?tags[target], ...entry.value];
          if (combined.map((tag) => tag.toLowerCase()).toSet().length >
              maxTagsPerSeries) {
            continue;
          }
          tags[target] = _normalizeTags(combined);
          tags.remove(entry.key);
          changed = true;
        }
        if (changed) await _box.put(SettingBoxKey.localMediaLibraryTags, tags);
      });

  static List<String> normalizeTags(Iterable<Object?> values) {
    return _normalizeTags(values);
  }

  static List<String> _normalizeTags(Iterable<Object?> values) {
    return MediaCustomTags.normalize(values);
  }
}
