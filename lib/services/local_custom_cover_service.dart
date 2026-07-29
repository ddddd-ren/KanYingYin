import 'dart:io';

import 'package:kanyingyin/services/local_cover_finder.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef LocalCoverApplicationRootProvider = Future<Directory> Function();

class LocalCustomCoverService {
  LocalCustomCoverService({
    LocalCoverApplicationRootProvider? applicationRootProvider,
  }) : _applicationRootProvider =
            applicationRootProvider ?? getApplicationSupportDirectory;

  final LocalCoverApplicationRootProvider _applicationRootProvider;

  Future<String?> saveForVideo({
    required String videoPath,
    required String imagePath,
  }) async {
    final extension = p.extension(imagePath).toLowerCase();
    if (!LocalCoverFinder.posterExtensions.contains(extension)) {
      return null;
    }

    if (_isContentUri(videoPath)) {
      return _saveForDocument(
        videoUri: videoPath,
        imagePath: imagePath,
        extension: extension,
      );
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

  Future<String> _saveForDocument({
    required String videoUri,
    required String imagePath,
    required String extension,
  }) async {
    final root = await _applicationRootProvider();
    final directory = Directory(
      p.join(root.path, 'local_document_custom_covers'),
    );
    await directory.create(recursive: true);
    final baseName = _stableHash(videoUri);
    for (final candidate in LocalCoverFinder.posterExtensions) {
      final previous = File(p.join(directory.path, '$baseName$candidate'));
      if (await previous.exists() && !_samePath(previous.path, imagePath)) {
        await previous.delete();
      }
    }
    final target = p.join(directory.path, '$baseName$extension');
    if (!_samePath(target, imagePath)) {
      await File(imagePath).copy(target);
    }
    return target;
  }

  bool _isContentUri(String value) =>
      Uri.tryParse(value)?.scheme.toLowerCase() == 'content';

  bool _samePath(String left, String right) =>
      p.normalize(left).toLowerCase() == p.normalize(right).toLowerCase();

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
