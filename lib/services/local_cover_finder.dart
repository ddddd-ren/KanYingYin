import 'dart:io';

import 'package:kanyingyin/services/local_thumbnail_cache.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:path/path.dart' as p;

/// Shared cover/poster detection logic used by both
/// [LocalMediaScanner] and [LocalMediaIndexer].
class LocalCoverFinder {
  static const posterExtensions = ['.jpg', '.jpeg', '.png', '.webp'];
  static const commonPosterNames = ['cover', 'poster', 'folder'];
  static const preferredDirectoryCoverName = 'cover';

  final Map<String, Map<String, String>> _posterFileCache = {};

  /// Find a cover image for a video file.
  String? findVideoCover(String videoPath) {
    final dir = p.dirname(videoPath);
    final nameWithoutExt = p.basenameWithoutExtension(videoPath);

    final tmdbPoster = _findPosterInDirectory(dir, const ['tmdb-poster']);
    if (tmdbPoster != null) return tmdbPoster;

    final seriesPoster =
        _findPosterInDirectory(dir, [seriesCoverBaseNameForVideo(videoPath)]);
    if (seriesPoster != null) return seriesPoster;

    final sameNamePoster = _findPosterInDirectory(dir, [nameWithoutExt]);
    if (sameNamePoster != null) return sameNamePoster;

    final commonPoster = _findPosterInDirectory(dir, commonPosterNames);
    if (commonPoster != null) return commonPoster;

    final cachedThumbnail = LocalThumbnailCache.existingPathForVideo(videoPath);
    if (cachedThumbnail != null) return cachedThumbnail;

    final parentDir = p.dirname(dir);
    final folderName = p.basename(dir);
    final legacyPoster = _findPosterInDirectory(parentDir, [folderName]);
    if (legacyPoster == null) return null;
    return _moveLegacyDirectoryPoster(
          legacyPoster: legacyPoster,
          dirPath: dir,
        ) ??
        legacyPoster;
  }

  static String seriesCoverBaseNameForVideo(String videoPath) {
    return '${p.basename(p.dirname(videoPath))}.poster';
  }

  /// Find a cover image for a directory.
  String? findDirCover(String dirPath) {
    final tmdbPoster = _findPosterInDirectory(dirPath, const ['tmdb-poster']);
    if (tmdbPoster != null) return tmdbPoster;

    final commonPoster = _findPosterInDirectory(dirPath, commonPosterNames);
    if (commonPoster != null) return commonPoster;

    final parentDir = p.dirname(dirPath);
    final dirName = p.basename(dirPath);
    final legacyPoster = _findPosterInDirectory(parentDir, [dirName]);
    if (legacyPoster == null) return null;
    return _moveLegacyDirectoryPoster(
          legacyPoster: legacyPoster,
          dirPath: dirPath,
        ) ??
        legacyPoster;
  }

  static String directoryCoverPath(String dirPath,
      {String extension = '.jpg'}) {
    return p.join(dirPath, '$preferredDirectoryCoverName$extension');
  }

  String? _findPosterInDirectory(String dirPath, List<String> baseNames) {
    final filesByLowerName = _filesByLowerName(dirPath);
    for (final baseName in baseNames) {
      for (final ext in posterExtensions) {
        final posterPath = filesByLowerName['$baseName$ext'.toLowerCase()];
        if (posterPath != null) return posterPath;
      }
    }
    return null;
  }

  String? _moveLegacyDirectoryPoster({
    required String legacyPoster,
    required String dirPath,
  }) {
    try {
      final extension = p.extension(legacyPoster).toLowerCase();
      final targetPath = directoryCoverPath(
        dirPath,
        extension: posterExtensions.contains(extension) ? extension : '.jpg',
      );
      final target = File(targetPath);
      if (target.existsSync()) return targetPath;

      target.parent.createSync(recursive: true);
      File(legacyPoster).renameSync(targetPath);
      _posterFileCache.remove(p.dirname(legacyPoster));
      _posterFileCache.remove(dirPath);
      AppLogger().i('LocalCoverFinder: moved directory poster to $targetPath');
      return targetPath;
    } catch (e) {
      AppLogger().w(
          'LocalCoverFinder: failed to move legacy poster $legacyPoster: $e');
      return null;
    }
  }

  Map<String, String> _filesByLowerName(String dirPath) {
    final cached = _posterFileCache[dirPath];
    if (cached != null) return cached;

    final files = <String, String>{};
    try {
      for (final entry in Directory(dirPath).listSync(followLinks: false)) {
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
