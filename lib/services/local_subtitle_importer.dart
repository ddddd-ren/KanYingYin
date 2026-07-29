import 'dart:io';

import 'package:kanyingyin/services/local_subtitle_matcher.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef LocalSubtitleApplicationRootProvider = Future<Directory> Function();

enum LocalSubtitleImportTarget {
  videoDirectory,
  subtitleDirectory,
}

class LocalSubtitleImportResult {
  final String sourcePath;
  final String targetPath;
  final bool renamed;

  const LocalSubtitleImportResult({
    required this.sourcePath,
    required this.targetPath,
    required this.renamed,
  });
}

class LocalSubtitleImportException implements Exception {
  final String message;

  const LocalSubtitleImportException(this.message);

  @override
  String toString() => message;
}

class LocalSubtitleImporter {
  LocalSubtitleImporter({
    LocalSubtitleApplicationRootProvider? applicationRootProvider,
  }) : _applicationRootProvider =
            applicationRootProvider ?? getApplicationSupportDirectory;

  static const String subtitleDirectoryName = '字幕';
  final LocalSubtitleApplicationRootProvider _applicationRootProvider;

  bool supportsVideoDirectory({required String videoPath}) =>
      !_isContentUri(videoPath);

  Future<LocalSubtitleImportResult> importForVideo({
    required String videoPath,
    required String subtitlePath,
    LocalSubtitleImportTarget target =
        LocalSubtitleImportTarget.subtitleDirectory,
  }) async {
    final sourceFile = File(subtitlePath);
    if (!await sourceFile.exists()) {
      throw const LocalSubtitleImportException('字幕文件不存在');
    }
    if (!LocalSubtitleMatcher.isSupportedSubtitlePath(subtitlePath)) {
      throw const LocalSubtitleImportException('仅支持 ass / ssa / srt / vtt 字幕');
    }

    if (!supportsVideoDirectory(videoPath: videoPath)) {
      if (target == LocalSubtitleImportTarget.videoDirectory) {
        throw const LocalSubtitleImportException('当前目录没有写入授权');
      }
      return _importForDocument(
        videoUri: videoPath,
        sourceFile: sourceFile,
      );
    }

    final videoFile = File(videoPath);
    final videoDirectory = videoFile.parent.path;
    final targetDirectory =
        target == LocalSubtitleImportTarget.subtitleDirectory
            ? Directory(p.join(videoDirectory, subtitleDirectoryName))
            : Directory(videoDirectory);
    await targetDirectory.create(recursive: true);

    final extension = p.extension(subtitlePath).toLowerCase();
    final baseName = p.basenameWithoutExtension(videoPath);
    final expectedPath = p.join(targetDirectory.path, '$baseName$extension');
    final targetPath = await _resolveTargetPath(expectedPath, sourceFile.path);

    if (!_samePath(sourceFile.path, targetPath)) {
      await sourceFile.copy(targetPath);
    }

    return LocalSubtitleImportResult(
      sourcePath: sourceFile.path,
      targetPath: targetPath,
      renamed: !_samePath(expectedPath, targetPath),
    );
  }

  Future<LocalSubtitleImportResult> _importForDocument({
    required String videoUri,
    required File sourceFile,
  }) async {
    final root = await _applicationRootProvider();
    final targetDirectory = Directory(
      p.join(root.path, 'local_document_imported_subtitles'),
    );
    await targetDirectory.create(recursive: true);
    final extension = p.extension(sourceFile.path).toLowerCase();
    final expectedPath = p.join(
      targetDirectory.path,
      '${_stableHash(videoUri)}$extension',
    );
    final targetPath = await _resolveTargetPath(expectedPath, sourceFile.path);
    if (!_samePath(sourceFile.path, targetPath)) {
      await sourceFile.copy(targetPath);
    }
    return LocalSubtitleImportResult(
      sourcePath: sourceFile.path,
      targetPath: targetPath,
      renamed: !_samePath(expectedPath, targetPath),
    );
  }

  bool _isContentUri(String value) =>
      Uri.tryParse(value)?.scheme.toLowerCase() == 'content';

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<String> _resolveTargetPath(
    String expectedPath,
    String sourcePath,
  ) async {
    if (!await File(expectedPath).exists() ||
        _samePath(expectedPath, sourcePath)) {
      return expectedPath;
    }

    final dir = p.dirname(expectedPath);
    final name = p.basenameWithoutExtension(expectedPath);
    final extension = p.extension(expectedPath);
    var index = 1;
    while (true) {
      final candidate = p.join(dir, '$name ($index)$extension');
      if (!await File(candidate).exists() || _samePath(candidate, sourcePath)) {
        return candidate;
      }
      index++;
    }
  }

  bool _samePath(String left, String right) {
    return p.normalize(left).toLowerCase() == p.normalize(right).toLowerCase();
  }
}
