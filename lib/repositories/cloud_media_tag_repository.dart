import 'package:kanyingyin/utils/storage.dart';
import 'package:synchronized/synchronized.dart';

/// 网盘媒体标签的持久化边界，标签只保存到看影音本地设置，不改动网盘文件。
abstract interface class CloudMediaTagStorage {
  Object get synchronizationIdentity;

  Future<Map<String, Object?>> read();

  Future<void> write(Map<String, Object?> value);
}

class HiveCloudMediaTagStorage implements CloudMediaTagStorage {
  static final Object _identity = Object();

  @override
  Object get synchronizationIdentity => _identity;

  @override
  Future<Map<String, Object?>> read() async {
    final value = GStorage.setting.get(
      SettingBoxKey.cloudMediaLibraryTags,
      defaultValue: const <String, Object?>{},
    );
    return value is Map
        ? Map<String, Object?>.from(value)
        : <String, Object?>{};
  }

  @override
  Future<void> write(Map<String, Object?> value) => GStorage.setting.put(
        SettingBoxKey.cloudMediaLibraryTags,
        value,
      );
}

class MemoryCloudMediaTagStorage implements CloudMediaTagStorage {
  MemoryCloudMediaTagStorage([
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

abstract interface class ICloudMediaTagRepository {
  Future<Map<String, List<String>>> getBySource(String sourceId);

  Future<void> saveForResource(
    String sourceId,
    String resourceKey,
    Iterable<String> tags,
  );

  Future<void> removeSource(String sourceId);
}

/// 按来源和资源稳定键保存用户自定义标签。
final class CloudMediaTagRepository implements ICloudMediaTagRepository {
  CloudMediaTagRepository({CloudMediaTagStorage? storage})
      : _storage = storage ?? HiveCloudMediaTagStorage() {
    final identity = _storage.synchronizationIdentity;
    _lock = _locks[identity] ??= Lock();
  }

  static final Expando<Lock> _locks = Expando<Lock>();

  static const int maxTagLength = 32;
  static const int maxTagsPerResource = 30;

  final CloudMediaTagStorage _storage;
  late final Lock _lock;

  @override
  Future<Map<String, List<String>>> getBySource(String sourceId) async {
    final normalizedSource = sourceId.trim();
    if (normalizedSource.isEmpty) return <String, List<String>>{};
    final all = await _readAll();
    final source = all[normalizedSource];
    if (source == null) return <String, List<String>>{};
    return <String, List<String>>{
      for (final entry in source.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
  }

  @override
  Future<void> saveForResource(
    String sourceId,
    String resourceKey,
    Iterable<String> tags,
  ) {
    final normalizedSource = sourceId.trim();
    final normalizedKey = resourceKey.trim();
    if (normalizedSource.isEmpty || normalizedKey.isEmpty) {
      return Future<void>.value();
    }
    return _lock.synchronized(() async {
      final all = await _readAll();
      final source = all.putIfAbsent(
        normalizedSource,
        () => <String, List<String>>{},
      );
      final normalizedTags = normalizeTags(tags);
      if (normalizedTags.isEmpty) {
        source.remove(normalizedKey);
      } else {
        source[normalizedKey] = normalizedTags;
      }
      if (source.isEmpty) all.remove(normalizedSource);
      await _writeAll(all);
    });
  }

  @override
  Future<void> removeSource(String sourceId) {
    final normalizedSource = sourceId.trim();
    if (normalizedSource.isEmpty) return Future<void>.value();
    return _lock.synchronized(() async {
      final all = await _readAll();
      if (all.remove(normalizedSource) == null) return;
      await _writeAll(all);
    });
  }

  static List<String> normalizeTags(Iterable<Object?> values) {
    final result = <String>[];
    final identities = <String>{};
    for (final value in values) {
      final tag = value?.toString().trim() ?? '';
      if (tag.isEmpty || tag.length > maxTagLength) continue;
      if (!identities.add(tag.toLowerCase())) continue;
      result.add(tag);
      if (result.length == maxTagsPerResource) break;
    }
    return List<String>.unmodifiable(result);
  }

  Future<Map<String, Map<String, List<String>>>> _readAll() async {
    final raw = await _storage.read();
    final result = <String, Map<String, List<String>>>{};
    for (final sourceEntry in raw.entries) {
      final sourceId = sourceEntry.key.trim();
      final value = sourceEntry.value;
      if (sourceId.isEmpty || value is! Map) continue;
      final resources = <String, List<String>>{};
      for (final resourceEntry in value.entries) {
        final resourceKey = resourceEntry.key.toString().trim();
        if (resourceKey.isEmpty || resourceEntry.value is! Iterable) continue;
        final tags = normalizeTags(resourceEntry.value as Iterable<Object?>);
        if (tags.isNotEmpty) resources[resourceKey] = tags;
      }
      if (resources.isNotEmpty) result[sourceId] = resources;
    }
    return result;
  }

  Future<void> _writeAll(Map<String, Map<String, List<String>>> value) {
    return _storage.write(<String, Object?>{
      for (final sourceEntry in value.entries)
        sourceEntry.key: <String, Object?>{
          for (final resourceEntry in sourceEntry.value.entries)
            resourceEntry.key: resourceEntry.value,
        },
    });
  }
}
