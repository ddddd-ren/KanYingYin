import 'dart:io';

import 'package:kanyingyin/services/local_media_entry_provider.dart';
import 'package:kanyingyin/services/local_thumbnail_cache.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:path/path.dart' as p;

/// Shared cover/poster detection logic used by both
/// [LocalMediaScanner] and [LocalMediaIndexer].
class LocalCoverFinder {
  static const posterExtensions = ['.jpg', '.jpeg', '.png', '.webp'];
  static const int maxDocumentCoverBytes = 20 * 1024 * 1024;
  static const commonPosterNames = ['cover', 'poster', 'folder'];
  static const preferredDirectoryCoverName = 'cover';

  final Map<String, Map<String, String>> _posterFileCache = {};

  LocalMediaEntry? findForEntry({
    required LocalMediaEntry video,
    required List<LocalMediaEntry> siblings,
  }) {
    final byLowerName = <String, LocalMediaEntry>{};
    for (final entry in siblings) {
      if (entry.isDirectory || entry.size < 0) continue;
      if (entry.size > maxDocumentCoverBytes) continue;
      if (!posterExtensions.contains(p.extension(entry.name).toLowerCase())) {
        continue;
      }
      byLowerName[entry.name.toLowerCase()] = entry;
    }

    LocalMediaEntry? find(Iterable<String> baseNames) {
      for (final baseName in baseNames) {
        for (final extension in posterExtensions) {
          final entry = byLowerName['${baseName.toLowerCase()}$extension'];
          if (entry != null) return entry;
        }
      }
      return null;
    }

    return find(const <String>['tmdb-poster']) ??
        find(<String>[p.basenameWithoutExtension(video.name)]) ??
        find(commonPosterNames);
  }

  /// Find a cover image for a video file.
  Future<String?> findVideoCover(String videoPath) async {
    final dir = p.dirname(videoPath);
    final nameWithoutExt = p.basenameWithoutExtension(videoPath);

    final tmdbPoster = await _findPosterInDirectory(dir, const ['tmdb-poster']);
    if (tmdbPoster != null) return tmdbPoster;

    final seriesPoster = await _findPosterInDirectory(
        dir, [seriesCoverBaseNameForVideo(videoPath)]);
    if (seriesPoster != null) return seriesPoster;

    final sameNamePoster = await _findPosterInDirectory(dir, [nameWithoutExt]);
    if (sameNamePoster != null) return sameNamePoster;

    final commonPoster = await _findPosterInDirectory(dir, commonPosterNames);
    if (commonPoster != null) return commonPoster;

    final cachedThumbnail = LocalThumbnailCache.pathForVideo(videoPath);
    if (await File(cachedThumbnail).exists()) return cachedThumbnail;

    final parentDir = p.dirname(dir);
    final folderName = p.basename(dir);
    final legacyPoster = await _findPosterInDirectory(parentDir, [folderName]);
    if (legacyPoster == null) return null;
    return await _moveLegacyDirectoryPoster(
          legacyPoster: legacyPoster,
          dirPath: dir,
        ) ??
        legacyPoster;
  }

  static String seriesCoverBaseNameForVideo(String videoPath) {
    return '${p.basename(p.dirname(videoPath))}.poster';
  }

  /// Find a cover image for a directory.
  Future<String?> findDirCover(String dirPath) async {
    final tmdbPoster =
        await _findPosterInDirectory(dirPath, const ['tmdb-poster']);
    if (tmdbPoster != null) return tmdbPoster;

    final commonPoster =
        await _findPosterInDirectory(dirPath, commonPosterNames);
    if (commonPoster != null) return commonPoster;

    final parentDir = p.dirname(dirPath);
    final dirName = p.basename(dirPath);
    final legacyPoster = await _findPosterInDirectory(parentDir, [dirName]);
    if (legacyPoster == null) return null;
    return await _moveLegacyDirectoryPoster(
          legacyPoster: legacyPoster,
          dirPath: dirPath,
        ) ??
        legacyPoster;
  }

  static String directoryCoverPath(String dirPath,
      {String extension = '.jpg'}) {
    return p.join(dirPath, '$preferredDirectoryCoverName$extension');
  }

  Future<String?> _findPosterInDirectory(
      String dirPath, List<String> baseNames) async {
    final filesByLowerName = await _filesByLowerName(dirPath);
    for (final baseName in baseNames) {
      for (final ext in posterExtensions) {
        final posterPath = filesByLowerName['$baseName$ext'.toLowerCase()];
        if (posterPath != null) return posterPath;
      }
    }
    return null;
  }

  Future<String?> _moveLegacyDirectoryPoster({
    required String legacyPoster,
    required String dirPath,
  }) async {
    final extension = p.extension(legacyPoster).toLowerCase();
    final targetPath = directoryCoverPath(
      dirPath,
      extension: posterExtensions.contains(extension) ? extension : '.jpg',
    );
    final target = File(targetPath);
    try {
      if (await target.exists()) return targetPath;

      await target.parent.create(recursive: true);
      await File(legacyPoster).rename(targetPath);
      AppLogger().i('LocalCoverFinder: moved directory poster to $targetPath');
      return targetPath;
    } catch (e) {
      // 其他查找器可能已经完成迁移，不能回退到已不存在的旧路径。
      if (await target.exists()) return targetPath;
      AppLogger().w(
          'LocalCoverFinder: failed to move legacy poster $legacyPoster: $e');
      return null;
    } finally {
      _posterFileCache.remove(p.dirname(legacyPoster));
      _posterFileCache.remove(dirPath);
    }
  }

  Future<Map<String, String>> _filesByLowerName(String dirPath) async {
    final cached = _posterFileCache[dirPath];
    if (cached != null) return cached;

    final files = <String, String>{};
    try {
      await for (final entry in Directory(dirPath).list(followLinks: false)) {
        if (entry is File) {
          files[p.basename(entry.path).toLowerCase()] = entry.path;
        }
      }
    } catch (e) {
      AppLogger()
          .w('LocalCoverFinder: failed to cache posters in $dirPath: $e');
    }
    _posterFileCache[dirPath] = files;
    return files;
  }
}
