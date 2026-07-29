import 'package:kanyingyin/modules/local/local_media_source.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/storage.dart';

abstract class ILocalMediaSourceRepository {
  List<LocalMediaSource> getAll();

  LocalMediaSource? getByPath(String path);

  LocalMediaSource? getByLocation(MediaLocation location) {
    for (final source in getAll()) {
      if (source.location == location) return source;
    }
    return null;
  }

  Future<LocalMediaSource> upsertPath(String path);

  Future<LocalMediaSource> upsertLocation(
    MediaLocation location, {
    required String displayName,
  }) {
    if (location.isFile) return upsertPath(location.value);
    throw UnsupportedError('仓库实现不支持 Android 文档来源');
  }

  Future<bool> removePath(String path);

  Future<bool> removeLocation(MediaLocation location) {
    if (location.isFile) return removePath(location.value);
    throw UnsupportedError('仓库实现不支持 Android 文档来源');
  }

  Future<void> updateScanSummary({
    required String path,
    required int fileCount,
    required int videoCount,
    required int directoryCount,
    required int skippedCount,
  });

  Future<void> updateScanSummaryForLocation({
    required MediaLocation location,
    required int fileCount,
    required int videoCount,
    required int directoryCount,
    required int skippedCount,
  }) {
    if (location.isFile) {
      return updateScanSummary(
        path: location.value,
        fileCount: fileCount,
        videoCount: videoCount,
        directoryCount: directoryCount,
        skippedCount: skippedCount,
      );
    }
    throw UnsupportedError('仓库实现不支持 Android 文档来源');
  }
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
          .whereType<Map<Object?, Object?>>()
          .map<LocalMediaSource?>((item) {
            try {
              return LocalMediaSource.fromJson(
                Map<String, dynamic>.from(item),
              );
            } on Object {
              return null;
            }
          })
          .whereType<LocalMediaSource>()
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
    return getByLocation(MediaLocation.file(path));
  }

  @override
  LocalMediaSource? getByLocation(MediaLocation location) {
    final id = location.stableId;
    for (final source in getAll()) {
      if (source.id == id) return source;
    }
    return null;
  }

  @override
  Future<LocalMediaSource> upsertPath(String path) async {
    final location = MediaLocation.file(path);
    return upsertLocation(
      location,
      displayName: LocalMediaSource.fromLocation(location).name,
    );
  }

  @override
  Future<LocalMediaSource> upsertLocation(
    MediaLocation location, {
    required String displayName,
  }) async {
    final sources = getAll();
    final id = location.stableId;
    final existingIndex = sources.indexWhere((source) => source.id == id);
    final now = DateTime.now();
    final source = existingIndex >= 0
        ? sources[existingIndex].copyWith(
            updatedAt: now,
            enabled: true,
          )
        : LocalMediaSource.fromLocation(
            location,
            displayName: displayName,
          );

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
    return removeLocation(MediaLocation.file(path));
  }

  @override
  Future<bool> removeLocation(MediaLocation location) async {
    final sources = getAll();
    final id = location.stableId;
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
    return updateScanSummaryForLocation(
      location: MediaLocation.file(path),
      fileCount: fileCount,
      videoCount: videoCount,
      directoryCount: directoryCount,
      skippedCount: skippedCount,
    );
  }

  @override
  Future<void> updateScanSummaryForLocation({
    required MediaLocation location,
    required int fileCount,
    required int videoCount,
    required int directoryCount,
    required int skippedCount,
  }) async {
    final sources = getAll();
    final id = location.stableId;
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
        : LocalMediaSource.fromLocation(location).copyWith(
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
