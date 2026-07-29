import 'dart:io';

import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/services/local_media_entry_provider.dart';
import 'package:path/path.dart' as p;

class FileSystemMediaEntryProvider implements LocalMediaEntryProvider {
  const FileSystemMediaEntryProvider();

  @override
  bool supports(MediaLocation location) => location.isFile;

  @override
  Future<bool> canAccess(MediaLocation location) async {
    if (!supports(location)) return false;
    return Directory(location.value).exists();
  }

  @override
  Future<List<LocalMediaEntry>> listChildren(
    MediaLocation directory,
  ) async {
    if (!supports(directory)) {
      throw const FileSystemException('不支持该媒体位置');
    }
    final entries = <LocalMediaEntry>[];
    await for (final entity in Directory(directory.value).list(
      followLinks: false,
    )) {
      if (entity is Link) continue;
      final stat = await entity.stat();
      entries.add(
        LocalMediaEntry(
          location: MediaLocation.file(entity.path),
          name: p.basename(entity.path),
          isDirectory: entity is Directory,
          size: entity is File ? stat.size : 0,
          modified: stat.modified,
        ),
      );
    }
    return entries;
  }
}
