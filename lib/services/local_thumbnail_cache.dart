import 'dart:io';

import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef LocalThumbnailCacheRootProvider = Future<Directory> Function();

class LocalThumbnailCache {
  static const directoryName = '.kanyingyin_thumbs';
  static const extension = '.jpg';

  static String pathForVideo(String videoPath) {
    final dir = p.dirname(videoPath);
    final baseName = p.basenameWithoutExtension(videoPath);
    final safeName = Uri.encodeComponent(baseName);
    return p.join(dir, directoryName, '$safeName$extension');
  }

  static String? existingPathForVideo(String videoPath) {
    final thumbnailPath = pathForVideo(videoPath);
    return File(thumbnailPath).existsSync() ? thumbnailPath : null;
  }

  static Future<String> pathForLocation(
    MediaLocation location, {
    LocalThumbnailCacheRootProvider? cacheRootProvider,
  }) async {
    if (location.isFile) return pathForVideo(location.value);
    final root = await (cacheRootProvider ?? getTemporaryDirectory)();
    final hash = _stableHash(location.stableId);
    return p.join(
      root.path,
      'local_document_thumbnails',
      '$hash$extension',
    );
  }

  static String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
