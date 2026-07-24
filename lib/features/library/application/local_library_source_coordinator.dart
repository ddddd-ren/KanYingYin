import 'dart:io';

import 'package:kanyingyin/modules/local/local_media_source.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/local_media_source_repository.dart';
import 'package:kanyingyin/utils/logger.dart';

typedef LocalMediaSourceAvailability = bool Function(LocalMediaSource source);

/// 编排媒体来源记录和派生索引清理，不接触用户原始文件。
class LocalLibrarySourceCoordinator {
  LocalLibrarySourceCoordinator({
    required ILocalMediaSourceRepository sourceRepository,
    required ILocalMediaIndexRepository indexRepository,
    LocalMediaSourceAvailability? isAvailable,
  })  : _sourceRepository = sourceRepository,
        _indexRepository = indexRepository,
        _isAvailable = isAvailable ?? _directoryExists;

  final ILocalMediaSourceRepository _sourceRepository;
  final ILocalMediaIndexRepository _indexRepository;
  final LocalMediaSourceAvailability _isAvailable;

  bool isAvailable(LocalMediaSource source) => _isAvailable(source);

  int unavailableCount(Iterable<LocalMediaSource> sources) =>
      sources.where((source) => !_isAvailable(source)).length;

  Future<bool> removeSource(
    String path, {
    required bool scanInProgress,
  }) async {
    if (scanInProgress) return false;
    final removed = await _sourceRepository.removePath(path);
    if (removed) await _removeDerivedIndex(path);
    return removed;
  }

  Future<int> removeUnavailableSources(
    Iterable<LocalMediaSource> sources, {
    required bool scanInProgress,
  }) async {
    if (scanInProgress) return 0;
    var removedCount = 0;
    for (final source in sources.where((source) => !_isAvailable(source))) {
      try {
        if (await _sourceRepository.removePath(source.path)) {
          await _removeDerivedIndex(source.path);
          removedCount++;
        }
      } on Object catch (error, stackTrace) {
        AppLogger().w(
          'LocalLibrarySourceCoordinator: failed to remove unavailable source',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return removedCount;
  }

  Future<void> _removeDerivedIndex(String path) async {
    try {
      await _indexRepository.removeSource(path);
    } on Object catch (error, stackTrace) {
      AppLogger().w(
        'LocalLibrarySourceCoordinator: failed to remove derived index',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static bool _directoryExists(LocalMediaSource source) =>
      Directory(source.path).existsSync();
}
