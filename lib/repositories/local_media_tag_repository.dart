import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/utils/storage.dart';

abstract interface class ILocalMediaTagRepository {
  Map<String, List<String>> getAll();

  Future<void> saveForSeries(String seriesKey, Iterable<String> tags);
}

/// 保存本地媒体库作品的用户标签，不改动媒体索引和原始文件。
final class LocalMediaTagRepository implements ILocalMediaTagRepository {
  LocalMediaTagRepository({Box<Object?>? box}) : _providedBox = box;

  static const int maxTagLength = 32;
  static const int maxTagsPerSeries = 30;

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
  Future<void> saveForSeries(String seriesKey, Iterable<String> tags) async {
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
  }

  static List<String> normalizeTags(Iterable<Object?> values) {
    return _normalizeTags(values);
  }

  static List<String> _normalizeTags(Iterable<Object?> values) {
    final result = <String>[];
    final normalized = <String>{};
    for (final value in values) {
      final tag = value?.toString().trim() ?? '';
      if (tag.isEmpty || tag.length > maxTagLength) continue;
      final identity = tag.toLowerCase();
      if (!normalized.add(identity)) continue;
      result.add(tag);
      if (result.length == maxTagsPerSeries) break;
    }
    return List<String>.unmodifiable(result);
  }
}
