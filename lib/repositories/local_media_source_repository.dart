import 'package:kanyingyin/modules/local/local_media_source.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/storage.dart';

abstract class ILocalMediaSourceRepository {
  List<LocalMediaSource> getAll();

  LocalMediaSource? getByPath(String path);

  Future<LocalMediaSource> upsertPath(String path);

  Future<bool> removePath(String path);

  Future<void> updateScanSummary({
    required String path,
    required int fileCount,
    required int videoCount,
    required int directoryCount,
    required int skippedCount,
  });
}

class LocalMediaSourceRepository implements ILocalMediaSourceRepository {
  static const int _maxSources = 50;

  @override
  List<LocalMediaSource> getAll() {
    try {
      final value = GStorage.setting.get(
        SettingBoxKey.localMediaSources,
        defaultValue: const <Map<String, dynamic>>[],
      );
      if (value is! List) return <LocalMediaSource>[];

      final sources = value
          .whereType<Map>()
          .map((item) => LocalMediaSource.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((source) => source.path.isNotEmpty)
          .toList();
      sources.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return sources;
    } catch (e, stackTrace) {
      AppLogger().w(
        'LocalMediaSourceRepository: failed to read sources',
        error: e,
        stackTrace: stackTrace,
      );
      return <LocalMediaSource>[];
    }
  }

  @override
  LocalMediaSource? getByPath(String path) {
    final id = LocalMediaSource.idForPath(path);
    for (final source in getAll()) {
      if (source.id == id) return source;
    }
    return null;
  }

  @override
  Future<LocalMediaSource> upsertPath(String path) async {
    final sources = getAll();
    final id = LocalMediaSource.idForPath(path);
    final existingIndex = sources.indexWhere((source) => source.id == id);
    final now = DateTime.now();
    final source = existingIndex >= 0
        ? sources[existingIndex].copyWith(
            updatedAt: now,
            enabled: true,
          )
        : LocalMediaSource.fromPath(path);

    if (existingIndex >= 0) {
      sources[existingIndex] = source;
    } else {
      sources.insert(0, source);
    }
    await _save(sources);
    return source;
  }

  @override
  Future<bool> removePath(String path) async {
    final sources = getAll();
    final id = LocalMediaSource.idForPath(path);
    final nextSources =
        sources.where((source) => source.id != id).toList(growable: false);
    if (nextSources.length == sources.length) return false;
    await _save(nextSources);
    return true;
  }

  @override
  Future<void> updateScanSummary({
    required String path,
    required int fileCount,
    required int videoCount,
    required int directoryCount,
    required int skippedCount,
  }) async {
    final sources = getAll();
    final id = LocalMediaSource.idForPath(path);
    final existingIndex = sources.indexWhere((source) => source.id == id);
    final now = DateTime.now();
    final source = existingIndex >= 0
        ? sources[existingIndex].copyWith(
            updatedAt: now,
            lastScannedAt: now,
            fileCount: fileCount,
            videoCount: videoCount,
            directoryCount: directoryCount,
            skippedCount: skippedCount,
          )
        : LocalMediaSource.fromPath(path).copyWith(
            updatedAt: now,
            lastScannedAt: now,
            fileCount: fileCount,
            videoCount: videoCount,
            directoryCount: directoryCount,
            skippedCount: skippedCount,
          );

    if (existingIndex >= 0) {
      sources[existingIndex] = source;
    } else {
      sources.insert(0, source);
    }
    await _save(sources);
  }

  Future<void> _save(List<LocalMediaSource> sources) async {
    sources.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final payload = sources
        .take(_maxSources)
        .map((source) => source.toJson())
        .toList(growable: false);
    await GStorage.setting.put(SettingBoxKey.localMediaSources, payload);
  }
}
