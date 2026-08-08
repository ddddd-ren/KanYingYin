import 'dart:async';
import 'dart:io';

import 'package:kanyingyin/modules/local/local_episode_info.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/local_series_title_override_repository.dart';
import 'package:kanyingyin/services/android_document_cache.dart';
import 'package:kanyingyin/services/file_system_media_entry_provider.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:kanyingyin/services/local_media_entry_provider.dart';
import 'package:kanyingyin/services/local_media_index_metadata_refresher.dart';
import 'package:kanyingyin/services/local_media_probe.dart';
import 'package:kanyingyin/services/local_subtitle_matcher.dart';
import 'package:kanyingyin/services/local_cover_finder.dart';
import 'package:kanyingyin/services/local_thumbnail_cache.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';
import 'package:kanyingyin/services/media_name_analyzer.dart';
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

abstract interface class ILocalMediaLocationIndexer {
  Future<LocalMediaIndexResult> indexSourceLocation(
    MediaLocation sourceLocation, {
    LocalMediaIndexProgressCallback? onProgress,
    LocalMediaIndexCancelChecker? isCancelled,
    bool enrichMediaInfo = false,
    bool generateThumbnails = false,
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
  final bool sourceAccessible;
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
    this.sourceAccessible = true,
    this.failures = const <LocalMediaIndexFailure>[],
  });

  int get totalCount => items.length;
}

class LocalMediaIndexer
    implements ILocalMediaIndexer, ILocalMediaLocationIndexer {
  LocalMediaIndexer({
    ILocalMediaIndexRepository? repository,
    LocalEpisodeParser? episodeParser,
    LocalSubtitleMatcher? subtitleMatcher,
    ILocalMediaProbe? mediaProbe,
    LocalCoverFinder? coverFinder,
    LocalMediaIndexMetadataRefresher? metadataRefresher,
    ILocalSeriesTitleOverrideRepository? seriesTitleOverrideRepository,
    List<LocalMediaEntryProvider>? entryProviders,
    AndroidDocumentCache? documentCache,
    int minRecognizedVideoSizeBytes =
        LocalVideoFileTypes.minRecognizedVideoSizeBytes,
    int Function()? minRecognizedVideoSizeBytesProvider,
  })  : _repository = repository ?? LocalMediaIndexRepository(),
        _episodeParser = episodeParser ?? LocalEpisodeParser(),
        _subtitleMatcher = subtitleMatcher ?? LocalSubtitleMatcher(),
        _mediaProbe = mediaProbe ?? MediaKitLocalMediaProbe(),
        _coverFinder = coverFinder ?? LocalCoverFinder(),
        _entryProviders = entryProviders ??
            const <LocalMediaEntryProvider>[
              FileSystemMediaEntryProvider(),
            ],
        _documentCache = documentCache,
        _metadataRefresher = metadataRefresher ??
            LocalMediaIndexMetadataRefresher(
              episodeParser: episodeParser,
              subtitleMatcher: subtitleMatcher,
            ),
        _seriesTitleOverrideRepository = seriesTitleOverrideRepository ??
            LocalSeriesTitleOverrideRepository(),
        _minRecognizedVideoSizeBytesProvider =
            minRecognizedVideoSizeBytesProvider ??
                (() => minRecognizedVideoSizeBytes);

  final ILocalMediaIndexRepository _repository;
  final LocalEpisodeParser _episodeParser;
  final LocalSubtitleMatcher _subtitleMatcher;
  final ILocalMediaProbe _mediaProbe;
  final LocalCoverFinder _coverFinder;
  final List<LocalMediaEntryProvider> _entryProviders;
  final AndroidDocumentCache? _documentCache;
  final LocalMediaIndexMetadataRefresher _metadataRefresher;
  final MediaNameAnalyzer _nameAnalyzer = const MediaNameAnalyzer();
  final ILocalSeriesTitleOverrideRepository _seriesTitleOverrideRepository;
  final int Function() _minRecognizedVideoSizeBytesProvider;

  @override
  Future<LocalMediaIndexResult> indexSource(
    String sourcePath, {
    LocalMediaIndexProgressCallback? onProgress,
    LocalMediaIndexCancelChecker? isCancelled,
    bool enrichMediaInfo = false,
    bool generateThumbnails = false,
  }) async {
    return indexSourceLocation(
      MediaLocation.file(sourcePath),
      onProgress: onProgress,
      isCancelled: isCancelled,
      enrichMediaInfo: enrichMediaInfo,
      generateThumbnails: generateThumbnails,
    );
  }

  @override
  Future<LocalMediaIndexResult> indexSourceLocation(
    MediaLocation sourceLocation, {
    LocalMediaIndexProgressCallback? onProgress,
    LocalMediaIndexCancelChecker? isCancelled,
    bool enrichMediaInfo = false,
    bool generateThumbnails = false,
  }) async {
    final sourcePath = sourceLocation.value;
    final minSizeBytes = _minRecognizedVideoSizeBytesProvider();
    final provider = _providerFor(sourceLocation);
    final previousSourceItems = _repository.getBySourceLocation(sourceLocation);
    try {
      if (!await provider.canAccess(sourceLocation)) {
        if (sourceLocation.isDocument) {
          return _inaccessibleDocumentResult(
            sourceLocation,
            previousSourceItems,
            '目录授权已失效，请重新授权',
          );
        }
        final removedCount = previousSourceItems.length;
        await _repository.removeSourceLocation(sourceLocation);
        return LocalMediaIndexResult(
          sourcePath: sourcePath,
          items: const <LocalMediaIndexItem>[],
          addedCount: 0,
          updatedCount: 0,
          reusedCount: 0,
          removedCount: removedCount,
          skippedCount: 0,
          failures: const <LocalMediaIndexFailure>[],
        );
      }
    } on Object catch (error, stackTrace) {
      if (sourceLocation.isDocument) {
        AppLogger().w(
          'LocalMediaIndexer: document authorization check failed',
          error: error,
          stackTrace: stackTrace,
        );
        return _inaccessibleDocumentResult(
          sourceLocation,
          previousSourceItems,
          error.toString(),
        );
      }
      rethrow;
    }

    onProgress?.call(LocalMediaIndexProgress(
      sourcePath: sourcePath,
      currentPath: sourcePath,
      current: 0,
      total: 0,
      phase: LocalMediaIndexPhase.collecting,
    ));

    final files = <_LocatedMediaEntry>[];
    final directoryFingerprints = <String, String>{};
    final previousDirectoryFingerprints =
        _repository.getDirectoryFingerprintsForLocation(sourceLocation);
    final previousByDirectory = <String, List<LocalMediaIndexItem>>{};
    for (final item in previousSourceItems) {
      previousByDirectory
          .putIfAbsent(_directoryId(item.parentLocation), () => [])
          .add(item);
    }
    final reusedDirectoryIds = <String>{};
    var skippedCount = 0;
    final failures = <LocalMediaIndexFailure>[];

    Future<void> collectDirectory(
      MediaLocation directory,
      String logicalDirectory,
    ) async {
      if (isCancelled?.call() == true) return;
      final dirId = _directoryId(directory);
      List<LocalMediaEntry> entries;
      try {
        entries = await provider.listChildren(directory);
      } on Object catch (error, stackTrace) {
        skippedCount++;
        failures.add(LocalMediaIndexFailure(
          path: directory.value,
          message: error.toString(),
        ));
        AppLogger().w(
          'LocalMediaIndexer: skip directory ${directory.value}',
          error: error,
          stackTrace: stackTrace,
        );
        return;
      }

      final fingerprint = _directoryFingerprint(
        entries,
        minSizeBytes: minSizeBytes,
      );
      directoryFingerprints[dirId] = fingerprint;
      final previousItems =
          previousByDirectory[dirId] ?? const <LocalMediaIndexItem>[];
      final unchanged = previousDirectoryFingerprints[dirId] == fingerprint &&
          previousItems.isNotEmpty &&
          previousItems.every(
            (item) =>
                item.location.isDocument ||
                !_metadataRefresher.needsRefresh(item),
          ) &&
          previousItems.every((item) => LocalVideoFileTypes.isRecognizedVideo(
                item.name,
                size: item.size,
                minSizeBytes: minSizeBytes,
              ));
      if (unchanged) {
        reusedDirectoryIds.add(dirId);
        return;
      }

      for (final entry in entries) {
        if (isCancelled?.call() == true) return;
        try {
          final name = entry.name;
          if (name.startsWith('.')) {
            skippedCount++;
            continue;
          }
          if (entry.isDirectory) {
            if (LocalVideoFileTypes.isWindowsSystemDirectory(name)) {
              skippedCount++;
              continue;
            }
            await collectDirectory(
              entry.location,
              p.join(logicalDirectory, name),
            );
            continue;
          }
          if (!LocalVideoFileTypes.isVideoPath(name)) continue;
          if (!LocalVideoFileTypes.isRecognizedVideoSize(
            entry.size,
            minSizeBytes: minSizeBytes,
          )) {
            skippedCount++;
            continue;
          }
          String? subtitlePath;
          String? coverPath;
          final documentCache = _documentCache;
          if (entry.location.isDocument && documentCache != null) {
            final subtitle = _subtitleMatcher.findForEntry(
              video: entry,
              siblings: entries,
            );
            if (subtitle != null) {
              try {
                subtitlePath = await documentCache.cacheSubtitle(subtitle);
              } on Object catch (error, stackTrace) {
                failures.add(LocalMediaIndexFailure(
                  path: subtitle.location.value,
                  message: error.toString(),
                ));
                AppLogger().w(
                  'LocalMediaIndexer: failed to cache document subtitle',
                  error: error,
                  stackTrace: stackTrace,
                );
              }
            }
            final cover = _coverFinder.findForEntry(
              video: entry,
              siblings: entries,
            );
            if (cover != null) {
              try {
                coverPath = await documentCache.cacheCover(cover);
              } on Object catch (error, stackTrace) {
                failures.add(LocalMediaIndexFailure(
                  path: cover.location.value,
                  message: error.toString(),
                ));
                AppLogger().w(
                  'LocalMediaIndexer: failed to cache document cover',
                  error: error,
                  stackTrace: stackTrace,
                );
              }
            }
          }
          files.add(_LocatedMediaEntry(
            entry: entry,
            parentLocation: directory,
            logicalPath: entry.location.isFile
                ? entry.location.value
                : p.join(logicalDirectory, name),
            logicalParentPath: logicalDirectory,
            subtitlePath: subtitlePath,
            coverPath: coverPath,
          ));
        } on Object catch (error, stackTrace) {
          skippedCount++;
          failures.add(LocalMediaIndexFailure(
            path: entry.location.value,
            message: error.toString(),
          ));
          AppLogger().w(
            'LocalMediaIndexer: skip entity ${entry.location.value}',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }

    await collectDirectory(sourceLocation, '');
    if (isCancelled?.call() == true) {
      return LocalMediaIndexResult(
        sourcePath: sourcePath,
        items: previousSourceItems,
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
      for (final item in previousSourceItems) item.id: item,
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
          items: _repository.getBySourceLocation(sourceLocation),
          addedCount: addedCount,
          updatedCount: updatedCount,
          reusedCount: reusedCount,
          removedCount: 0,
          skippedCount: skippedCount,
          cancelled: true,
          failures: failures,
        );
      }
      final located = files[i];
      final entry = located.entry;
      final current = i + 1;
      if (i == 0 || current % 25 == 0 || current == files.length) {
        onProgress?.call(LocalMediaIndexProgress(
          sourcePath: sourcePath,
          currentPath: entry.location.value,
          current: current,
          total: files.length,
          phase: LocalMediaIndexPhase.indexing,
        ));
      }

      try {
        final oldItem = previous.remove(_entryId(entry));
        if (oldItem != null && _isSameEntry(oldItem, entry)) {
          if (entry.location.isFile &&
              _metadataRefresher.needsRefresh(oldItem)) {
            indexed.add(await _metadataRefresher.refreshItem(
              oldItem,
              indexedAt: DateTime.now(),
            ));
            updatedCount++;
          } else {
            final companionChanged = entry.location.isDocument &&
                ((located.subtitlePath != null &&
                        located.subtitlePath != oldItem.subtitlePath) ||
                    (located.coverPath != null &&
                        located.coverPath != oldItem.cover));
            indexed.add(oldItem.copyWith(
              subtitlePath: located.subtitlePath,
              cover: located.coverPath,
              indexedAt: DateTime.now(),
            ));
            if (companionChanged) {
              updatedCount++;
            } else {
              reusedCount++;
            }
          }
          continue;
        }

        final episodeInfo = _episodeParser.parse(located.logicalPath);
        final seriesTitleOverride = _seriesTitleOverrideRepository
            .getForDirectory(located.parentLocation.value);
        final effectiveEpisodeInfo =
            seriesTitleOverride == null || episodeInfo == null
                ? episodeInfo
                : LocalEpisodeInfo(
                    seriesName: seriesTitleOverride,
                    seasonNumber: episodeInfo.seasonNumber,
                    episodeNumber: episodeInfo.episodeNumber,
                    episodeTitle: episodeInfo.episodeTitle,
                    releaseGroup: episodeInfo.releaseGroup,
                    resolution: episodeInfo.resolution,
                    source: episodeInfo.source,
                    codec: episodeInfo.codec,
                  );
        final documentMediaInfo = entry.location.isDocument && enrichMediaInfo
            ? await _mediaProbe.probe(entry.location.value)
            : null;
        var documentCover = located.coverPath ?? oldItem?.cover;
        if (entry.location.isDocument &&
            documentCover == null &&
            generateThumbnails) {
          documentCover = await _mediaProbe.captureThumbnail(
            entry.location.value,
            await LocalThumbnailCache.pathForLocation(entry.location),
          );
        }
        final item = entry.location.isFile
            ? await _buildFileItem(
                entry,
                sourceLocation: sourceLocation,
                oldItem: oldItem,
                episodeInfo: effectiveEpisodeInfo,
                seriesNameOverride: _standaloneRootTitle(
                  entry,
                  sourceLocation: sourceLocation,
                  episodeInfo: effectiveEpisodeInfo,
                ),
                enrichMediaInfo: enrichMediaInfo,
                generateThumbnails: generateThumbnails,
              )
            : LocalMediaIndexItem(
                location: entry.location,
                name: entry.name,
                parentLocation: located.parentLocation,
                sourceLocation: sourceLocation,
                size: entry.size,
                modified: entry.modified,
                seriesName: seriesTitleOverride ??
                    episodeInfo?.seriesName ??
                    p.basename(located.logicalParentPath),
                seasonNumber: episodeInfo?.seasonNumber,
                episodeNumber: episodeInfo?.episodeNumber,
                episodeTitle: episodeInfo?.episodeTitle,
                releaseGroup: episodeInfo?.releaseGroup,
                resolution: episodeInfo?.resolution,
                source: episodeInfo?.source,
                codec: episodeInfo?.codec,
                cover: documentCover,
                subtitlePath: located.subtitlePath ?? oldItem?.subtitlePath,
                durationMillis: documentMediaInfo?.duration?.inMilliseconds ??
                    oldItem?.durationMillis,
                videoWidth: documentMediaInfo?.width ?? oldItem?.videoWidth,
                videoHeight: documentMediaInfo?.height ?? oldItem?.videoHeight,
                pathFingerprint: _entryFingerprint(entry),
                indexedAt: DateTime.now(),
              );
        final resolvedItem = item.copyWith(
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
          seriesName: seriesTitleOverride ?? item.seriesName,
          manualOverride: oldItem?.manualOverride ?? false,
        );
        indexed.add(resolvedItem);
        if (oldItem == null) {
          addedCount++;
        } else {
          updatedCount++;
        }
      } catch (e) {
        skippedCount++;
        failures.add(LocalMediaIndexFailure(
          path: entry.location.value,
          message: e.toString(),
        ));
        AppLogger().w(
          'LocalMediaIndexer: failed to index ${entry.location.value}',
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
        items: _repository.getBySourceLocation(sourceLocation),
        addedCount: addedCount,
        updatedCount: updatedCount,
        reusedCount: reusedCount,
        removedCount: 0,
        skippedCount: skippedCount,
        cancelled: true,
        failures: failures,
      );
    }
    await _repository.saveForSourceLocation(sourceLocation, indexed);
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
    await _repository.saveDirectoryFingerprintsForLocation(
      sourceLocation,
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

  String _directoryFingerprint(
    List<LocalMediaEntry> entries, {
    required int minSizeBytes,
  }) {
    final parts = <String>[];
    for (final entry in entries) {
      final type = entry.isDirectory ? 'D' : 'F';
      parts.add(
        '$type|${entry.location.stableId}|${entry.name.toLowerCase()}|${entry.size}|${entry.modified.millisecondsSinceEpoch}|${entry.mimeType ?? ''}',
      );
    }
    parts.sort();
    return 'minSizeBytes=$minSizeBytes\n${parts.join('\n')}';
  }

  Future<LocalMediaIndexItem> _buildFileItem(
    LocalMediaEntry entry, {
    required MediaLocation sourceLocation,
    required LocalMediaIndexItem? oldItem,
    required LocalEpisodeInfo? episodeInfo,
    String? seriesNameOverride,
    required bool enrichMediaInfo,
    required bool generateThumbnails,
  }) async {
    final file = File(entry.location.value);
    final stat = await file.stat();
    final mediaInfo =
        enrichMediaInfo ? await _mediaProbe.probe(file.path) : null;
    final cover = _coverFinder.findVideoCover(file.path) ??
        (generateThumbnails
            ? await _mediaProbe.captureThumbnail(
                file.path,
                LocalThumbnailCache.pathForVideo(file.path),
              )
            : null);
    final indexed = LocalMediaIndexItem.fromFile(
      file: file,
      stat: stat,
      sourcePath: sourceLocation.value,
      cover: cover,
      subtitlePath: await _subtitleMatcher.findForVideo(file.path),
      episodeInfo:
          oldItem?.manualOverride == true ? oldItem?.episodeInfo : episodeInfo,
      duration: mediaInfo?.duration ?? oldItem?.toFileItem().duration,
      videoWidth: mediaInfo?.width ?? oldItem?.videoWidth,
      videoHeight: mediaInfo?.height ?? oldItem?.videoHeight,
    );
    if (seriesNameOverride == null || seriesNameOverride.isEmpty) {
      return indexed;
    }
    return indexed.copyWith(seriesName: seriesNameOverride);
  }

  String? _standaloneRootTitle(
    LocalMediaEntry entry, {
    required MediaLocation sourceLocation,
    required LocalEpisodeInfo? episodeInfo,
  }) {
    if (episodeInfo != null || !entry.location.isFile) return null;
    final parent = p.normalize(p.dirname(entry.location.value));
    final source = p.normalize(sourceLocation.value);
    if (parent.toLowerCase() != source.toLowerCase()) return null;
    return _nameAnalyzer
        .analyze(entry.name, isDirectory: false)
        .titleCandidates
        .firstOrNull;
  }

  LocalMediaIndexResult _inaccessibleDocumentResult(
    MediaLocation sourceLocation,
    List<LocalMediaIndexItem> previousItems,
    String message,
  ) {
    return LocalMediaIndexResult(
      sourcePath: sourceLocation.value,
      items: previousItems,
      addedCount: 0,
      updatedCount: 0,
      reusedCount: previousItems.length,
      removedCount: 0,
      skippedCount: 1,
      sourceAccessible: false,
      failures: <LocalMediaIndexFailure>[
        LocalMediaIndexFailure(
          path: sourceLocation.value,
          message: message,
        ),
      ],
    );
  }

  LocalMediaEntryProvider _providerFor(MediaLocation location) {
    for (final provider in _entryProviders) {
      if (provider.supports(location)) return provider;
    }
    throw UnsupportedError('没有可用于该媒体位置的索引器: ${location.kind.name}');
  }

  String _directoryId(MediaLocation location) => location.isFile
      ? LocalMediaIndexItem.normalizePath(location.value)
      : location.stableId;

  String _entryId(LocalMediaEntry entry) => entry.location.isFile
      ? LocalMediaIndexItem.normalizePath(entry.location.value)
      : entry.location.stableId;

  bool _isSameEntry(LocalMediaIndexItem item, LocalMediaEntry entry) {
    return item.size == entry.size &&
        item.modified.millisecondsSinceEpoch ==
            entry.modified.millisecondsSinceEpoch &&
        item.pathFingerprint == _entryFingerprint(entry);
  }

  String _entryFingerprint(LocalMediaEntry entry) {
    return LocalMediaIndexItem.buildLocationFingerprint(
      location: entry.location,
      name: entry.name,
      size: entry.size,
      modified: entry.modified,
      mimeType: entry.mimeType,
    );
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

class _LocatedMediaEntry {
  const _LocatedMediaEntry({
    required this.entry,
    required this.parentLocation,
    required this.logicalPath,
    required this.logicalParentPath,
    this.subtitlePath,
    this.coverPath,
  });

  final LocalMediaEntry entry;
  final MediaLocation parentLocation;
  final String logicalPath;
  final String logicalParentPath;
  final String? subtitlePath;
  final String? coverPath;
}
