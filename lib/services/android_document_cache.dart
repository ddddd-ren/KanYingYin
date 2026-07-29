import 'dart:io';

import 'package:kanyingyin/platform/android/android_document_provider.dart';
import 'package:kanyingyin/services/local_media_entry_provider.dart';
import 'package:kanyingyin/services/local_subtitle_matcher.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef AndroidDocumentCacheRootProvider = Future<Directory> Function();

class AndroidDocumentCacheException implements Exception {
  const AndroidDocumentCacheException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 将 SAF 小文件复制到应用缓存，不复制视频正文。
class AndroidDocumentCache {
  AndroidDocumentCache(
    this._documents, {
    AndroidDocumentCacheRootProvider? cacheRootProvider,
  }) : _cacheRootProvider = cacheRootProvider ?? getTemporaryDirectory;

  static const int maxSubtitleBytes = 10 * 1024 * 1024;
  static const int maxCoverBytes = 20 * 1024 * 1024;

  final AndroidDocumentProvider _documents;
  final AndroidDocumentCacheRootProvider _cacheRootProvider;

  Future<String> cacheSubtitle(LocalMediaEntry entry) {
    if (!LocalSubtitleMatcher.isSupportedSubtitlePath(entry.name)) {
      throw const AndroidDocumentCacheException('不支持该字幕格式');
    }
    return _cacheEntry(
      entry,
      directoryName: 'local_document_subtitles',
      maxBytes: maxSubtitleBytes,
    );
  }

  Future<String> cacheCover(LocalMediaEntry entry) {
    return _cacheEntry(
      entry,
      directoryName: 'local_document_covers',
      maxBytes: maxCoverBytes,
    );
  }

  Future<void> clearPlaybackFiles() async {
    final root = await _cacheRootProvider();
    final directory = Directory(p.join(root.path, 'local_document_subtitles'));
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<String> _cacheEntry(
    LocalMediaEntry entry, {
    required String directoryName,
    required int maxBytes,
  }) async {
    if (!entry.location.isDocument || entry.isDirectory) {
      throw const AndroidDocumentCacheException('只能缓存 Android 文档文件');
    }
    if (entry.size < 0 || entry.size > maxBytes) {
      throw AndroidDocumentCacheException('文件超过缓存大小限制：$maxBytes 字节');
    }
    final bytes = await _documents.readSmallFile(
      entry.location,
      maxBytes: maxBytes,
    );
    if (bytes.length > maxBytes) {
      throw AndroidDocumentCacheException('文件超过缓存大小限制：$maxBytes 字节');
    }
    final root = await _cacheRootProvider();
    final directory = Directory(p.join(root.path, directoryName));
    await directory.create(recursive: true);
    final extension = p.extension(entry.name).toLowerCase();
    final baseName = p
        .basenameWithoutExtension(entry.name)
        .replaceAll(RegExp(r'[^A-Za-z0-9\u4e00-\u9fff._-]+'), '_');
    final safeBaseName = baseName.isEmpty ? 'document' : baseName;
    final target = File(
      p.join(
        directory.path,
        '${safeBaseName}_${_stableHash(entry.location.stableId)}$extension',
      ),
    );
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
