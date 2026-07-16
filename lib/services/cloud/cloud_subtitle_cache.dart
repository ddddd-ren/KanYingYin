import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/services/cloud/cloud_cache_directories.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/local_subtitle_matcher.dart';
import 'package:path/path.dart' as p;

typedef CloudResourceDownloader = Future<List<int>> Function(
  CloudPlaybackResource resource,
);

class CloudSubtitleCache {
  static final Map<String, Future<String?>> _inFlight =
      <String, Future<String?>>{};

  CloudSubtitleCache(
      {Directory? cacheRoot, required CloudResourceDownloader downloader})
      : _cacheRoot = cacheRoot,
        _downloader = downloader;

  static const int maxSubtitleSizeBytes = 20 * 1024 * 1024;
  final Directory? _cacheRoot;
  final CloudResourceDownloader _downloader;

  Future<String?> cacheBeforePlayback({
    required String sourceId,
    required CloudFileEntry subtitle,
    required CloudDriveClient client,
  }) async {
    if (subtitle.isDirectory ||
        subtitle.size > maxSubtitleSizeBytes ||
        !LocalSubtitleMatcher.isSupportedSubtitlePath(subtitle.name)) {
      return null;
    }
    final root = _cacheRoot ?? await defaultCloudCacheRoot();
    final cacheKey = _stableSegment(jsonEncode(<String, Object?>{
      'sourceId': sourceId,
      'stableId': subtitle.id,
      'remotePath': subtitle.remotePath,
      'modifiedAt': subtitle.modifiedAt?.toUtc().toIso8601String(),
      'size': subtitle.size,
    }));
    final extension = p.extension(subtitle.name).toLowerCase();
    final directory = CloudCacheDirectories.subtitleSource(root, sourceId);
    final sourceLease = CloudCacheOperationCoordinator.tryBegin(directory);
    if (sourceLease == null) return null;
    final file = File(p.join(directory.path, '$cacheKey$extension'));
    final flightKey = p.normalize(file.absolute.path).toLowerCase();
    final existing = _inFlight[flightKey];
    try {
      if (existing != null) return await existing;
      final operation = _downloadAtomically(
        directory: directory,
        file: file,
        subtitle: subtitle,
        client: client,
        isCurrent: () => sourceLease.isCurrent,
      );
      _inFlight[flightKey] = operation;
      try {
        return await operation;
      } finally {
        if (identical(_inFlight[flightKey], operation)) {
          _inFlight.remove(flightKey);
        }
      }
    } finally {
      sourceLease.release();
    }
  }

  Future<String?> _downloadAtomically({
    required Directory directory,
    required File file,
    required CloudFileEntry subtitle,
    required CloudDriveClient client,
    required bool Function() isCurrent,
  }) async {
    final temporary = File('${file.path}.download');
    try {
      if (!isCurrent()) return null;
      await directory.create(recursive: true);
      if (!isCurrent()) return null;
      if (await file.exists()) {
        await file.setLastModified(DateTime.now());
        return file.path;
      }
      final resource = await client.resolvePlayback(subtitle.remotePath);
      final bytes = await _downloader(resource);
      if (bytes.length > maxSubtitleSizeBytes || !isCurrent()) return null;
      if (await temporary.exists()) await temporary.delete();
      await temporary.writeAsBytes(bytes, flush: true);
      if (!isCurrent()) return null;
      await temporary.rename(file.path);
      return file.path;
    } on Object {
      return null;
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } on Object {
        // 临时文件清理失败不影响播放回退。
      }
    }
  }

  Future<int> cleanExpired({
    DateTime? now,
    Duration maxAge = const Duration(days: 30),
  }) async {
    final root = _cacheRoot ?? await defaultCloudCacheRoot();
    final directory = CloudCacheDirectories.subtitleRoot(root);
    if (!await directory.exists()) return 0;
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    var removed = 0;
    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
          removed++;
        }
      } on Object {
        continue;
      }
    }
    return removed;
  }

  Future<void> clearSource(String sourceId) async {
    final root = _cacheRoot ?? await defaultCloudCacheRoot();
    await clearSourceFromRoot(cacheRoot: root, sourceId: sourceId);
  }

  Future<void> removeSource(String sourceId) => clearSource(sourceId);

  static Future<void> removeSourceFromRoot({
    required Directory cacheRoot,
    required String sourceId,
  }) =>
      clearSourceFromRoot(cacheRoot: cacheRoot, sourceId: sourceId);

  static Future<void> clearSourceFromRoot({
    required Directory cacheRoot,
    required String sourceId,
  }) =>
      CloudCacheOperationCoordinator.clearSource(
        CloudCacheDirectories.subtitleSource(cacheRoot, sourceId),
      );

  static String _stableSegment(String value) =>
      sha256.convert(utf8.encode(value)).toString();
}
