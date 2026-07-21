import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef ImageCacheDirectoryProvider = Future<Directory> Function();

class LocalImageCacheService {
  LocalImageCacheService({ImageCacheDirectoryProvider? directoryProvider})
      : _directoryProvider = directoryProvider ?? _defaultDirectory;

  final ImageCacheDirectoryProvider _directoryProvider;

  Future<int> sizeBytes() async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) return 0;
    return _directorySize(directory);
  }

  Future<void> clear() async {
    final directory = await _directoryProvider();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<bool> tryClear() async {
    try {
      await clear();
      return true;
    } on Object {
      return false;
    }
  }

  Future<int> _directorySize(Directory directory) async {
    var total = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      } else if (entity is Directory) {
        total += await _directorySize(entity);
      }
    }
    return total;
  }

  static Future<Directory> _defaultDirectory() async {
    final temporary = await getTemporaryDirectory();
    return Directory(p.join(temporary.path, 'libCachedImageData'));
  }
}
