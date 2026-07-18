import 'dart:async';
import 'dart:io';

import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:kanyingyin/services/local_media_index_metadata_refresher.dart';
import 'package:kanyingyin/services/local_media_probe.dart';
import 'package:kanyingyin/services/local_subtitle_matcher.dart';
import 'package:kanyingyin/services/local_cover_finder.dart';
import 'package:kanyingyin/services/local_thumbnail_cache.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:path/path.dart' as p;

typedef LocalMediaIndexProgressCallback = void Function(
  LocalMediaIndexProgress progress,
);

typedef LocalMediaIndexCancelChecker = bool Function();

abstract class ILocalMediaIndexer {
  Future<LocalMediaIndexResult> indexSource(
    String sourcePath, {
    LocalMediaIndexProgressCallback? onProgress,
    LocalMediaIndexCancelChecker? isCancelled,
    bool enrichMediaInfo,
    bool generateThumbnails,
  });
}

class LocalMediaIndexFailure {
  final String path;
  final String message;

  const LocalMediaIndexFailure({
    required this.path,
    required this.message,
  });
}

class LocalMediaIndexProgress {
  final String sourcePath;
  final String currentPath;
  final int current;
  final int total;
  final LocalMediaIndexPhase phase;

  const LocalMediaIndexProgress({
    required this.sourcePath,
    required this.currentPath,
    required this.current,
    required this.total,
    required this.phase,
  });

  double get progress {
    if (total <= 0) return 0;
    return (current / total).clamp(0, 1);
  }

  String get label {
    return switch (phase) {
      LocalMediaIndexPhase.collecting => '正在整理媒体文件',
      LocalMediaIndexPhase.indexing => '正在更新媒体库索引',
      LocalMediaIndexPhase.saving => '正在保存媒体库索引',
      LocalMediaIndexPhase.finished => '媒体库索引已更新',
    };
  }
}

enum LocalMediaIndexPhase {
  collecting,
  indexing,
  saving,
  finished,
}

class LocalMediaIndexResult {
  final String sourcePath;
  final List<LocalMediaIndexItem> items;
  final int addedCount;
  final int updatedCount;
  final int reusedCount;
  final int removedCount;
  final int skippedCount;
  final bool cancelled;
  final List<LocalMediaIndexFailure> failures;

  const LocalMediaIndexResult({
    required this.sourcePath,
    required this.items,
    required this.addedCount,
    required this.updatedCount,
    required this.reusedCount,
    required this.removedCount,
    required this.skippedCount,
    this.cancelled = false,
    this.failures = const <LocalMediaIndexFailure>[],
  });

  int get totalCount => items.length;
}

class LocalMediaIndexer implements ILocalMediaIndexer {
  LocalMediaIndexer({
    ILocalMediaIndexRepository? repository,
    LocalEpisodeParser? episodeParser,
    LocalSubtitleMatcher? subtitleMatcher,
    ILocalMediaProbe? mediaProbe,
    LocalCoverFinder? coverFinder,
    LocalMediaIndexMetadataRefresher? metadataRefresher,
    int minRecognizedVideoSizeBytes =
        LocalVideoFileTypes.minRecognizedVideoSizeBytes,
    int Function()? minRecognizedVideoSizeBytesProvider,
  })  : _repository = repository ?? LocalMediaIndexRepository(),
        _episodeParser = episodeParser ?? LocalEpisodeParser(),
        _subtitleMatcher = subtitleMatcher ?? LocalSubtitleMatcher(),
        _mediaProbe = mediaProbe ?? MediaKitLocalMediaProbe(),
        _coverFinder = coverFinder ?? LocalCoverFinder(),
        _metadataRefresher = metadataRefresher ??
            LocalMediaIndexMetadataRefresher(
              episodeParser: episodeParser,
              subtitleMatcher: subtitleMatcher,
            ),
        _minRecognizedVideoSizeBytesProvider =
            minRecognizedVideoSizeBytesProvider ??
                (() => minRecognizedVideoSizeBytes);

  final ILocalMediaIndexRepository _repository;
  final LocalEpisodeParser _episodeParser;
  final LocalSubtitleMatcher _subtitleMatcher;
  final ILocalMediaProbe _mediaProbe;
  final LocalCoverFinder _coverFinder;
  final LocalMediaIndexMetadataRefresher _metadataRefresher;
  final int Function() _minRecognizedVideoSizeBytesProvider;

  @override
  Future<LocalMediaIndexResult> indexSource(
    String sourcePath, {
    LocalMediaIndexProgressCallback? onProgress,
    LocalMediaIndexCancelChecker? isCancelled,
    bool enrichMediaInfo = false,
    bool generateThumbnails = false,
  }) async {
    final minSizeBytes = _minRecognizedVideoSizeBytesProvider();
    final sourceDir = Directory(sourcePath);
    if (!await sourceDir.exists()) {
      final removedCount = _repository.getBySourcePath(sourcePath).length;
      await _repository.removeSource(sourcePath);
      return LocalMediaIndexResult(
        sourcePath: sourcePath,
        items: const [],
        addedCount: 0,
        updatedCount: 0,
        reusedCount: 0,
        removedCount: removedCount,
        skippedCount: 0,
        failures: const <LocalMediaIndexFailure>[],
      );
    }

    onProgress?.call(LocalMediaIndexProgress(
      sourcePath: sourcePath,
      currentPath: sourcePath,
      current: 0,
      total: 0,
      phase: LocalMediaIndexPhase.collecting,
    ));

    final files = <File>[];
    final directoryFingerprints = <String, String>{};
    final previousDirectoryFingerprints =
        _repository.getDirectoryFingerprints(sourcePath);
    final previousByDirectory = <String, List<LocalMediaIndexItem>>{};
    for (final item in _repository.getBySourcePath(sourcePath)) {
      previousByDirectory
          .putIfAbsent(
              LocalMediaIndexItem.normalizePath(item.parentPath), () => [])
          .add(item);
    }
    final reusedDirectoryIds = <String>{};
    var skippedCount = 0;
    final failures = <LocalMediaIndexFailure>[];

    Future<void> collectDirectory(Directory directory) async {
      if (isCancelled?.call() == true) return;
      final dirId = LocalMediaIndexItem.normalizePath(directory.path);
      final entries = <FileSystemEntity>[];
      try {
        await for (final entity in directory.list(followLinks: false)) {
          entries.add(entity);
        }
      } catch (e) {
        skippedCount++;
        failures.add(LocalMediaIndexFailure(
          path: directory.path,
          message: e.toString(),
        ));
        AppLogger().w(
          'LocalMediaIndexer: skip directory ${directory.path}',
          error: e,
        );
        return;
      }

      final fingerprint = await _directoryFingerprint(
        entries,
        minSizeBytes: minSizeBytes,
      );
      directoryFingerprints[dirId] = fingerprint;
      final previousItems =
          previousByDirectory[dirId] ?? const <LocalMediaIndexItem>[];
      final unchanged = previousDirectoryFingerprints[dirId] == fingerprint &&
          previousItems.isNotEmpty &&
          previousItems
              .every((item) => !_metadataRefresher.needsRefresh(item)) &&
          previousItems.every((item) => LocalVideoFileTypes.isRecognizedVideo(
                item.name,
                size: item.size,
                minSizeBytes: minSizeBytes,
              ));
      if (unchanged) {
        reusedDirectoryIds.add(dirId);
        return;
      }

      for (final entity in entries) {
        if (isCancelled?.call() == true) return;
        try {
          final name = p.basename(entity.path);
          if (name.startsWith('.')) {
            skippedCount++;
            continue;
          }
          if (entity is Directory) {
            if (LocalVideoFileTypes.isWindowsSystemDirectory(name)) {
              skippedCount++;
              continue;
            }
            await collectDirectory(entity);
          } else if (entity is File) {
            if (!LocalVideoFileTypes.isVideoPath(name)) continue;
            final stat = await entity.stat();
            if (!LocalVideoFileTypes.isRecognizedVideoSize(
              stat.size,
              minSizeBytes: minSizeBytes,
            )) {
              skippedCount++;
              continue;
            }
            files.add(entity);
          }
        } catch (e) {
          skippedCount++;
          failures.add(LocalMediaIndexFailure(
            path: entity.path,
            message: e.toString(),
          ));
          AppLogger().w(
            'LocalMediaIndexer: skip entity ${entity.path}',
            error: e,
          );
        }
      }
    }

    await collectDirectory(sourceDir);
    if (isCancelled?.call() == true) {
      return LocalMediaIndexResult(
        sourcePath: sourcePath,
        items: _repository.getBySourcePath(sourcePath),
        addedCount: 0,
        updatedCount: 0,
        reusedCount: 0,
        removedCount: 0,
        skippedCount: skippedCount,
        cancelled: true,
        failures: failures,
      );
    }

    final previous = {
      for (final item in _repository.getBySourcePath(sourcePath)) item.id: item,
    };
    final indexed = <LocalMediaIndexItem>[];
    var addedCount = 0;
    var updatedCount = 0;
    var reusedCount = 0;

    for (final dirId in reusedDirectoryIds) {
      final items = previousByDirectory[dirId] ?? const <LocalMediaIndexItem>[];
      for (final item in items) {
        previous.remove(item.id);
        indexed.add(item.copyWith(indexedAt: DateTime.now()));
        reusedCount++;
      }
    }

    for (var i = 0; i < files.length; i++) {
      if (isCancelled?.call() == true) {
        return LocalMediaIndexResult(
          sourcePath: sourcePath,
          items: _repository.getBySourcePath(sourcePath),
          addedCount: addedCount,
          updatedCount: updatedCount,
          reusedCount: reusedCount,
          removedCount: 0,
          skippedCount: skippedCount,
          cancelled: true,
          failures: failures,
        );
      }
      final file = files[i];
      final current = i + 1;
      if (i == 0 || current % 25 == 0 || current == files.length) {
        onProgress?.call(LocalMediaIndexProgress(
          sourcePath: sourcePath,
          currentPath: file.path,
          current: current,
          total: files.length,
          phase: LocalMediaIndexPhase.indexing,
        ));
      }

      try {
        final stat = await file.stat();
        final oldItem =
            previous.remove(LocalMediaIndexItem.normalizePath(file.path));
        if (oldItem != null && oldItem.isSameFile(stat)) {
          if (_metadataRefresher.needsRefresh(oldItem)) {
            indexed.add(_metadataRefresher.refreshItem(
              oldItem,
              indexedAt: DateTime.now(),
            ));
            updatedCount++;
          } else {
            indexed.add(oldItem.copyWith(indexedAt: DateTime.now()));
            reusedCount++;
          }
          continue;
        }

        final mediaInfo =
            enrichMediaInfo ? await _mediaProbe.probe(file.path) : null;
        final cover = _coverFinder.findVideoCover(file.path) ??
            (generateThumbnails
                ? await _mediaProbe.captureThumbnail(
                    file.path,
                    LocalThumbnailCache.pathForVideo(file.path),
                  )
                : null);
        final episodeInfo = _episodeParser.parse(file.path);
        final item = LocalMediaIndexItem.fromFile(
          file: file,
          stat: stat,
          sourcePath: sourcePath,
          cover: cover,
          subtitlePath: _subtitleMatcher.findForVideo(file.path),
          episodeInfo: oldItem?.manualOverride == true
              ? oldItem?.episodeInfo
              : episodeInfo,
          duration: mediaInfo?.duration ?? oldItem?.toFileItem().duration,
          videoWidth: mediaInfo?.width ?? oldItem?.videoWidth,
          videoHeight: mediaInfo?.height ?? oldItem?.videoHeight,
        ).copyWith(
          releaseGroup: oldItem?.manualOverride == true
              ? oldItem?.releaseGroup
              : episodeInfo?.releaseGroup,
          resolution: oldItem?.manualOverride == true
              ? oldItem?.resolution
              : episodeInfo?.resolution,
          source: oldItem?.manualOverride == true
              ? oldItem?.source
              : episodeInfo?.source,
          codec: oldItem?.manualOverride == true
              ? oldItem?.codec
              : episodeInfo?.codec,
          manualOverride: oldItem?.manualOverride ?? false,
        );
        indexed.add(item);
        if (oldItem == null) {
          addedCount++;
        } else {
          updatedCount++;
        }
      } catch (e) {
        skippedCount++;
        failures.add(LocalMediaIndexFailure(
          path: file.path,
          message: e.toString(),
        ));
        AppLogger().w(
          'LocalMediaIndexer: failed to index ${file.path}',
          error: e,
        );
      }
    }

    indexed.sort(_compareItems);
    onProgress?.call(LocalMediaIndexProgress(
      sourcePath: sourcePath,
      currentPath: sourcePath,
      current: files.length,
      total: files.length,
      phase: LocalMediaIndexPhase.saving,
    ));
    if (isCancelled?.call() == true) {
      return LocalMediaIndexResult(
        sourcePath: sourcePath,
        items: _repository.getBySourcePath(sourcePath),
        addedCount: addedCount,
        updatedCount: updatedCount,
        reusedCount: reusedCount,
        removedCount: 0,
        skippedCount: skippedCount,
        cancelled: true,
        failures: failures,
      );
    }
    await _repository.saveForSource(sourcePath, indexed);
    if (isCancelled?.call() == true) {
      return LocalMediaIndexResult(
        sourcePath: sourcePath,
        items: indexed,
        addedCount: addedCount,
        updatedCount: updatedCount,
        reusedCount: reusedCount,
        removedCount: previous.length,
        skippedCount: skippedCount,
        cancelled: true,
        failures: failures,
      );
    }
    await _repository.saveDirectoryFingerprints(
      sourcePath,
      directoryFingerprints,
    );

    onProgress?.call(LocalMediaIndexProgress(
      sourcePath: sourcePath,
      currentPath: sourcePath,
      current: files.length,
      total: files.length,
      phase: LocalMediaIndexPhase.finished,
    ));

    return LocalMediaIndexResult(
      sourcePath: sourcePath,
      items: indexed,
      addedCount: addedCount,
      updatedCount: updatedCount,
      reusedCount: reusedCount,
      removedCount: previous.length,
      skippedCount: skippedCount,
      failures: failures,
    );
  }

  Future<String> _directoryFingerprint(
    List<FileSystemEntity> entries, {
    required int minSizeBytes,
  }) async {
    final parts = <String>[];
    for (final entity in entries) {
      try {
        final stat = await entity.stat();
        final type = entity is Directory ? 'D' : 'F';
        parts.add(
          '$type|${p.basename(entity.path).toLowerCase()}|${stat.size}|${stat.modified.millisecondsSinceEpoch}',
        );
      } catch (_) {
        parts.add('E|${p.basename(entity.path).toLowerCase()}');
      }
    }
    parts.sort();
    return 'minSizeBytes=$minSizeBytes\n${parts.join('\n')}';
  }

  int _compareItems(LocalMediaIndexItem a, LocalMediaIndexItem b) {
    final series =
        a.seriesKey.toLowerCase().compareTo(b.seriesKey.toLowerCase());
    if (series != 0) return series;
    final season = (a.seasonNumber ?? 0).compareTo(b.seasonNumber ?? 0);
    if (season != 0) return season;
    final episode = (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
    if (episode != 0) return episode;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}
