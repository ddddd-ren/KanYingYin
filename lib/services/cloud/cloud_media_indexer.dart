import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_series_match_rule_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_media_path_parser.dart';
import 'package:kanyingyin/services/cloud/cloud_media_tree_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_series_identity_resolver.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:kanyingyin/services/local_subtitle_matcher.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:path/path.dart' as p;

class CloudScanCancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class CloudScanInProgressException implements Exception {
  const CloudScanInProgressException(this.sourceId);
  final String sourceId;
}

class CloudMediaScanProgress {
  const CloudMediaScanProgress(
      {required this.scanned, required this.currentPath});
  final int scanned;
  final String currentPath;
}

class CloudMediaScanResult {
  const CloudMediaScanResult({
    required this.scanned,
    required this.skipped,
    required this.failures,
    required this.failedPaths,
    required this.cancelled,
    this.videoCount = 0,
    this.matchedSubtitleCount = 0,
  });
  final int scanned;
  final int skipped;
  final int failures;
  final List<String> failedPaths;
  final bool cancelled;
  final int videoCount;
  final int matchedSubtitleCount;
}

class CloudMediaIndexer {
  static const int _defaultMinRecognizedVideoSizeBytes = 1024 * 1024;
  static final Expando<Set<String>> _activeSourcesByStorage =
      Expando<Set<String>>();

  CloudMediaIndexer({
    required CloudMediaIndexRepository repository,
    CloudMediaPathParser? mediaPathParser,
    LocalEpisodeParser? episodeParser,
    CloudSeriesMatchRuleRepository? seriesMatchRuleRepository,
    CloudSeriesIdentityResolver? seriesIdentityResolver,
    CloudMediaTreeResolver? mediaTreeResolver,
    int Function()? minRecognizedVideoSizeBytesProvider,
    this.maxConcurrentDirectoryRequests = 3,
  })  : assert(maxConcurrentDirectoryRequests >= 2 &&
            maxConcurrentDirectoryRequests <= 4),
        _repository = repository,
        _mediaPathParser = mediaPathParser ?? CloudMediaPathParser(),
        _episodeParser = episodeParser ?? LocalEpisodeParser(),
        _seriesMatchRuleRepository = seriesMatchRuleRepository,
        _seriesIdentityResolver =
            seriesIdentityResolver ?? CloudSeriesIdentityResolver(),
        _mediaTreeResolver =
            mediaTreeResolver ?? const CloudMediaTreeResolver(),
        _minRecognizedVideoSizeBytesProvider =
            minRecognizedVideoSizeBytesProvider;

  final CloudMediaIndexRepository _repository;
  final CloudMediaPathParser _mediaPathParser;
  final LocalEpisodeParser _episodeParser;
  final CloudSeriesMatchRuleRepository? _seriesMatchRuleRepository;
  final CloudSeriesIdentityResolver _seriesIdentityResolver;
  final CloudMediaTreeResolver _mediaTreeResolver;
  final int Function()? _minRecognizedVideoSizeBytesProvider;
  final int maxConcurrentDirectoryRequests;

  Future<CloudMediaScanResult> scan({
    required CloudSource source,
    required CloudDriveClient client,
    CloudScanCancellationToken? cancellationToken,
    void Function(CloudMediaScanProgress progress)? onProgress,
  }) async {
    final activeSources =
        _activeSourcesByStorage[_repository.coordinationIdentity] ??=
            <String>{};
    if (!activeSources.add(source.id)) {
      throw CloudScanInProgressException(source.id);
    }
    final token = cancellationToken ?? CloudScanCancellationToken();
    try {
      final minSizeBytes = _minRecognizedVideoSizeBytesProvider?.call() ??
          _defaultMinRecognizedVideoSizeBytes;
      return await _scan(source, client, token, onProgress, minSizeBytes);
    } finally {
      activeSources.remove(source.id);
    }
  }

  Future<CloudMediaScanResult> _scan(
    CloudSource source,
    CloudDriveClient client,
    CloudScanCancellationToken token,
    void Function(CloudMediaScanProgress progress)? onProgress,
    int minSizeBytes,
  ) async {
    final previous = await _repository.snapshot(source.id);
    final rootRefs = source.remoteRoots
        .map((root) => CloudRemoteRef(
              id: root.id,
              path: _normalizePath(root.path),
            ))
        .toList(growable: false);
    final roots = rootRefs.map((root) => root.path).toList(growable: false);
    final queue = Queue<CloudRemoteRef>.from(rootRefs);
    final queued = <String>{
      for (final root in rootRefs) '${root.id}|${root.path}',
    };
    final directoryEntries = <String, List<CloudFileEntry>>{};
    final fingerprints = <String, String>{};
    final failedPaths = <String>[];
    var scanned = 0;
    var skipped = 0;
    final hasCachedPathsOutsideRoots = previous.directoryEntries.keys
            .any((path) => !_pathWithinRoots(path, roots)) ||
        previous.items.any((item) => !_pathWithinRoots(item.remotePath, roots));
    final recognitionStale =
        previous.items.any((item) => item.needsRecognitionRefresh);
    var changed = recognitionStale ||
        previous.directoryEntries.isEmpty ||
        !_sameStringSet(previous.indexedRoots, roots) ||
        hasCachedPathsOutsideRoots;

    while (queue.isNotEmpty && !token.isCancelled) {
      final batch = <CloudRemoteRef>[];
      while (
          queue.isNotEmpty && batch.length < maxConcurrentDirectoryRequests) {
        batch.add(queue.removeFirst());
      }
      final results = await Future.wait(batch.map((reference) async {
        try {
          return _DirectoryResult(
            reference,
            await client.listDirectory(reference),
          );
        } on Object {
          return _DirectoryResult(reference, null);
        }
      }));
      if (token.isCancelled) break;
      for (final result in results) {
        onProgress?.call(CloudMediaScanProgress(
          scanned: scanned,
          currentPath: result.reference.path,
        ));
        if (result.entries == null) {
          failedPaths.add(result.reference.path);
          _copyCachedSubtree(
            result.reference.path,
            previous,
            directoryEntries,
            fingerprints,
            minSizeBytes,
          );
          continue;
        }
        scanned++;
        final entries = <CloudFileEntry>[];
        for (final entry in result.entries!) {
          final normalizedPath = _normalizePath(entry.remotePath);
          if (!_isSafeEntryPath(entry.remotePath, normalizedPath, roots)) {
            failedPaths.add(entry.remotePath);
            changed = true;
            continue;
          }
          entries.add(CloudFileEntry(
            id: entry.id,
            remotePath: normalizedPath,
            name: entry.name,
            size: entry.size,
            modifiedAt: entry.modifiedAt,
            isDirectory: entry.isDirectory,
          ));
        }
        final directoryPath = result.reference.path;
        final fingerprint = _fingerprint(directoryPath, entries, minSizeBytes);
        fingerprints[directoryPath] = fingerprint;
        if (previous.fingerprints[directoryPath] == fingerprint) {
          skipped++;
        } else {
          changed = true;
        }
        directoryEntries[directoryPath] = List<CloudFileEntry>.from(entries);
        for (final entry in entries) {
          final path = _normalizePath(entry.remotePath);
          if (entry.isDirectory) {
            final key = '${entry.id}|$path';
            if (queued.add(key)) {
              queue.add(CloudRemoteRef(id: entry.id, path: path));
            }
          }
        }
      }
    }

    if (token.isCancelled) {
      return CloudMediaScanResult(
        scanned: scanned,
        skipped: skipped,
        failures: failedPaths.length,
        failedPaths: failedPaths,
        cancelled: true,
        videoCount: previous.items.length,
        matchedSubtitleCount: previous.items.fold<int>(
          0,
          (total, item) => total + item.subtitlePaths.length,
        ),
      );
    }
    if (!changed && failedPaths.isEmpty) {
      return CloudMediaScanResult(
        scanned: scanned,
        skipped: skipped,
        failures: 0,
        failedPaths: const <String>[],
        cancelled: false,
        videoCount: previous.items.length,
        matchedSubtitleCount: previous.items.fold<int>(
          0,
          (total, item) => total + item.subtitlePaths.length,
        ),
      );
    }
    final allEntries = <String, CloudFileEntry>{};
    for (final entries in directoryEntries.values) {
      for (final entry in entries) {
        if (!entry.isDirectory) {
          allEntries[_normalizePath(entry.remotePath)] = entry;
        }
      }
    }
    final videos = <CloudFileEntry>[];
    final subtitles = <CloudFileEntry>[];
    for (final entry in allEntries.values) {
      if (LocalVideoFileTypes.isRecognizedVideo(
        entry.name,
        size: entry.size,
        minSizeBytes: minSizeBytes,
      )) {
        videos.add(entry);
      } else if (LocalSubtitleMatcher.isSupportedSubtitlePath(entry.name)) {
        subtitles.add(entry);
      }
    }
    final tree = _mediaTreeResolver.resolve(
      sourceId: source.id,
      configuredRoots: roots,
      directoryEntries: directoryEntries,
      minSizeBytes: minSizeBytes,
    );
    final episodesByPath =
        <String, ({CloudWorkIdentity work, CloudEpisodeIdentity episode})>{
      for (final work in tree.works)
        for (final season in work.seasons)
          for (final episode in season.episodes)
            _normalizePath(episode.entry.remotePath): (
              work: work,
              episode: episode,
            ),
    };
    final standaloneWorksByPath = <String, CloudWorkIdentity>{
      for (final work in tree.works)
        for (final video in work.standaloneVideos)
          _normalizePath(video.remotePath): work,
    };
    final excludedPaths = <String>{
      ...tree.ignored.map((entry) => _normalizePath(entry.remotePath)),
      ...tree.conflicts.map(
        (conflict) => _normalizePath(conflict.entry.remotePath),
      ),
    };
    final items = <String, CloudMediaIndexItem>{};
    for (final entry in videos) {
      final normalizedPath = _normalizePath(entry.remotePath);
      if (excludedPaths.contains(normalizedPath)) continue;
      final pathMatch = _mediaPathParser.parse(entry.remotePath);
      if (pathMatch.hasSeasonConflict) {
        AppLogger().w(
          '网盘剧集季号冲突，采用文件名季号：${entry.remotePath} '
          '文件名=${pathMatch.seasonNumber} '
          '文件夹=${pathMatch.folderSeasonNumber}',
        );
      }
      final subtitleRefs = _matchSubtitles(entry, subtitles);
      final resolvedEpisode = episodesByPath[normalizedPath];
      final standaloneWork = standaloneWorksByPath[normalizedPath];
      final resolvedWork = resolvedEpisode?.work ??
          (pathMatch.isEpisode ? null : standaloneWork);
      final episodeIdentity = resolvedEpisode?.episode;
      final isSpecial = _isSpecial(entry.remotePath);
      items[normalizedPath] = CloudMediaIndexItem(
        sourceId: source.id,
        remoteId: entry.id,
        remotePath: normalizedPath,
        name: entry.name,
        remoteName: entry.name,
        displayName: episodeIdentity?.displayName ?? entry.name,
        workKey: resolvedWork?.workKey,
        workRootId: resolvedWork?.root.id,
        workRootPath: resolvedWork?.root.remotePath,
        size: entry.size,
        modifiedAt: entry.modifiedAt,
        seriesName: isSpecial
            ? _seriesName(entry.name, pathMatch.seriesName)
            : resolvedWork?.displayTitle ??
                _seriesName(entry.name, pathMatch.seriesName),
        seasonNumber: episodeIdentity?.seasonNumber ?? pathMatch.seasonNumber,
        episodeNumber:
            episodeIdentity?.episodeNumber ?? pathMatch.episodeNumber,
        mediaType: isSpecial
            ? CloudMediaType.special
            : episodeIdentity != null || pathMatch.isEpisode
                ? CloudMediaType.episode
                : CloudMediaType.movie,
        subtitlePaths: subtitleRefs.map((reference) => reference.path).toList(),
        subtitleRefs: subtitleRefs,
        recognitionVersion: CloudMediaIndexItem.currentRecognitionVersion,
        releaseTags: episodeIdentity?.releaseTags ?? const MediaReleaseTags(),
      );
    }
    final ruleRepository = _seriesMatchRuleRepository;
    if (ruleRepository != null) {
      final rules = await ruleRepository.getBySource(source.id);
      final rulesByKey = {
        for (final rule in rules) rule.stableKey: rule,
      };
      for (final entry in videos) {
        final identity = _seriesIdentityResolver.resolve(
          sourceId: source.id,
          remotePath: entry.remotePath,
          size: entry.size,
          minSizeBytes: minSizeBytes,
        );
        final rule = identity == null ? null : rulesByKey[identity.stableKey];
        final path = _normalizePath(entry.remotePath);
        final item = items[path];
        if (rule == null || item == null) continue;
        final metadata = rule.metadata;
        items[path] = item.replaceTmdb(
          tmdbId: metadata.id,
          tmdbTitle: metadata.title,
          tmdbOriginalTitle: metadata.originalTitle,
          tmdbOverview: metadata.overview,
          tmdbRating: metadata.rating,
          tmdbPosterUrl: metadata.posterUrl,
          tmdbBackdropUrl: metadata.backdropUrl,
          posterCachePath: rule.posterCachePath,
        );
      }
    }
    if (changed || failedPaths.isNotEmpty) {
      await _repository.replaceSource(
        source.id,
        items.values.toList(),
        fingerprints,
        directoryEntries,
        roots,
      );
    }
    return CloudMediaScanResult(
      scanned: scanned,
      skipped: skipped,
      failures: failedPaths.length,
      failedPaths: failedPaths,
      cancelled: false,
      videoCount: items.length,
      matchedSubtitleCount: items.values.fold<int>(
        0,
        (total, item) => total + item.subtitlePaths.length,
      ),
    );
  }

  static bool _isSpecial(String path) => RegExp(
        r'(^|[\s._\-/\[\]])(?:ova|oad|sp|special|nced|ncop|特别篇|番外)(?=$|[\s._\-/\[\]0-9])',
        caseSensitive: false,
      ).hasMatch(path);

  static String _seriesName(String fileName, String? parsed) {
    final value = parsed?.trim().isNotEmpty == true
        ? parsed!.trim()
        : p.basenameWithoutExtension(fileName);
    return value
        .replaceAll(
          RegExp(
              r'[\s._-]+(?:ova|oad|sp|special|nced|ncop|特别篇|番外)(?:[\s._-]*\d+)?$',
              caseSensitive: false),
          '',
        )
        .trim();
  }

  List<CloudRemoteRef> _matchSubtitles(
    CloudFileEntry video,
    List<CloudFileEntry> subtitles,
  ) {
    final videoEpisode = _episodeParser.parse(video.remotePath);
    final videoBase = p.basenameWithoutExtension(video.name).toLowerCase();
    final matches = <({CloudRemoteRef reference, int priority})>[];
    for (final subtitle in subtitles) {
      final videoDirectory = _normalizePath(p.posix.dirname(video.remotePath));
      final subtitleParent =
          _normalizePath(p.posix.dirname(subtitle.remotePath));
      final sameDirectory = subtitleParent == videoDirectory;
      final parentName = p.posix.basename(subtitleParent).toLowerCase();
      final inDirectSubtitleDirectory =
          _normalizePath(p.posix.dirname(subtitleParent)) == videoDirectory &&
              const <String>{
                'subs',
                'sub',
                'subtitle',
                'subtitles',
                '字幕',
                '字幕文件'
              }.contains(parentName);
      if (!sameDirectory && !inDirectSubtitleDirectory) continue;
      final sameName =
          p.basenameWithoutExtension(subtitle.name).toLowerCase() == videoBase;
      final subtitleEpisode = _episodeParser.parse(subtitle.remotePath);
      final episodeMatch = videoEpisode != null &&
          subtitleEpisode != null &&
          _normalizeSeriesName(videoEpisode.seriesName) ==
              _normalizeSeriesName(subtitleEpisode.seriesName) &&
          videoEpisode.episodeNumber == subtitleEpisode.episodeNumber &&
          (videoEpisode.seasonNumber == null ||
              subtitleEpisode.seasonNumber == null ||
              videoEpisode.seasonNumber == subtitleEpisode.seasonNumber);
      if (!sameName && !episodeMatch) continue;
      matches.add((
        reference: CloudRemoteRef(
          id: subtitle.id,
          path: _normalizePath(subtitle.remotePath),
        ),
        priority: sameName ? 0 : 1
      ));
    }
    matches.sort((a, b) {
      final priority = a.priority.compareTo(b.priority);
      return priority != 0
          ? priority
          : a.reference.path.compareTo(b.reference.path);
    });
    return matches.map((item) => item.reference).toList(growable: false);
  }

  static String _fingerprint(
    String path,
    List<CloudFileEntry> entries,
    int minSizeBytes,
  ) {
    final children = entries
        .map((entry) => <String, Object?>{
              'id': entry.id,
              'name': entry.name,
              'remotePath': _normalizePath(entry.remotePath),
              'isDirectory': entry.isDirectory,
              'size': entry.size,
              'modifiedAt': entry.modifiedAt?.toUtc().toIso8601String() ?? '',
            })
        .toList()
      ..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
    return sha256
        .convert(utf8.encode(jsonEncode(<String, Object?>{
          'path': _normalizePath(path),
          'minSizeBytes': minSizeBytes,
          'children': children,
        })))
        .toString();
  }

  static void _copyCachedSubtree(
    String directory,
    CloudMediaIndexSnapshot previous,
    Map<String, List<CloudFileEntry>> directoryEntries,
    Map<String, String> fingerprints,
    int minSizeBytes,
  ) {
    final normalized = _normalizePath(directory);
    final prefix = normalized == '/' ? '/' : '$normalized/';
    for (final entry in previous.directoryEntries.entries) {
      if (entry.key == normalized || entry.key.startsWith(prefix)) {
        directoryEntries[entry.key] = List<CloudFileEntry>.from(entry.value);
      }
    }
    for (final entry in previous.fingerprints.entries) {
      if (entry.key == normalized || entry.key.startsWith(prefix)) {
        final cachedEntries = previous.directoryEntries[entry.key];
        fingerprints[entry.key] = cachedEntries == null
            ? entry.value
            : _fingerprint(entry.key, cachedEntries, minSizeBytes);
      }
    }
  }

  static String _normalizePath(String value) {
    final normalized = p.posix.normalize(value.replaceAll('\\', '/'));
    return normalized.startsWith('/') ? normalized : '/$normalized';
  }

  static String _normalizeSeriesName(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s._\-\[\]\(\)\u3000]+'), '');

  static bool _isSafeEntryPath(
    String rawPath,
    String normalizedPath,
    List<String> roots,
  ) {
    final slashPath = rawPath.replaceAll('\\', '/');
    if (!slashPath.startsWith('/') || slashPath.split('/').contains('..')) {
      return false;
    }
    return _pathWithinRoots(normalizedPath, roots);
  }

  static bool _pathWithinRoots(String path, List<String> roots) => roots.any(
        (root) => root == '/' || path == root || path.startsWith('$root/'),
      );

  static bool _sameStringSet(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    final values = first.toSet();
    return values.length == second.length && second.every(values.contains);
  }
}

class _DirectoryResult {
  const _DirectoryResult(this.reference, this.entries);
  final CloudRemoteRef reference;
  final List<CloudFileEntry>? entries;
}
