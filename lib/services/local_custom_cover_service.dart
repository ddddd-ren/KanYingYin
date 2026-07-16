import 'dart:io';

import 'package:kanyingyin/services/local_cover_finder.dart';
import 'package:path/path.dart' as p;

class LocalCustomCoverService {
  Future<String?> saveForVideo({
    required String videoPath,
    required String imagePath,
  }) async {
    final extension = p.extension(imagePath).toLowerCase();
    if (!LocalCoverFinder.posterExtensions.contains(extension)) {
      return null;
    }

    final directory = Directory(p.dirname(videoPath));
    if (!await directory.exists()) return null;

    final temporary = File(
      p.join(
        directory.path,
        '.kanyingyin_cover_${DateTime.now().microsecondsSinceEpoch}$extension',
      ),
    );
    await File(imagePath).copy(temporary.path);

    try {
      for (final candidate in LocalCoverFinder.posterExtensions) {
        final cover = File(p.join(directory.path, 'cover$candidate'));
        if (await cover.exists()) {
          await cover.delete();
        }
      }

      final target = p.join(directory.path, 'cover$extension');
      await temporary.rename(target);
      return target;
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }
}
