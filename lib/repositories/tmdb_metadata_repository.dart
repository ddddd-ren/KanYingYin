import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/utils/storage.dart';

abstract class ITmdbMetadataRepository {
  TmdbMetadata? get(String mediaKey);
  Future<void> save(String mediaKey, TmdbMetadata metadata);
  Future<void> remove(String mediaKey);
}

class TmdbMetadataRepository implements ITmdbMetadataRepository {
  static const _storageKey = 'tmdbMetadataCache';

  @override
  TmdbMetadata? get(String mediaKey) {
    final cache = _readAll();
    final value = cache[mediaKey];
    return value == null ? null : TmdbMetadata.fromJson(value);
  }

  @override
  Future<void> save(String mediaKey, TmdbMetadata metadata) async {
    final cache = _readAll();
    cache[mediaKey] = metadata.toJson();
    await GStorage.setting.put(_storageKey, cache);
  }

  @override
  Future<void> remove(String mediaKey) async {
    final cache = _readAll()..remove(mediaKey);
    await GStorage.setting.put(_storageKey, cache);
  }

  Map<String, Map<String, dynamic>> _readAll() {
    final value = GStorage.setting.get(
      _storageKey,
      defaultValue: const <String, Map<String, dynamic>>{},
    );
    if (value is! Map) return {};
    return value.map((key, item) => MapEntry(
          key.toString(),
          Map<String, dynamic>.from(item as Map),
        ));
  }
}
