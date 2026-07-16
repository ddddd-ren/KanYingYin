import 'dart:io';

import 'package:path/path.dart' as p;

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
}
