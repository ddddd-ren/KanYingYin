import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/platform/android/android_document_provider.dart';
import 'package:kanyingyin/services/android_document_cache.dart';
import 'package:kanyingyin/services/local_media_entry_provider.dart';
import 'package:kanyingyin/services/local_playback_request_builder.dart';
import 'package:kanyingyin/services/local_thumbnail_cache.dart';

void main() {
  test('Android content URI 选集按文档父位置分组', () async {
    final root = MediaLocation.document(
      uri: 'content://provider/document/root',
      treeUri: 'content://provider/tree/root',
    );
    final otherRoot = MediaLocation.document(
      uri: 'content://provider/document/other',
      treeUri: root.treeUri!,
    );
    final episode1 = MediaLocation.document(
      uri: 'content://provider/document/show%3A01',
      treeUri: root.treeUri!,
    );
    final episode2 = MediaLocation.document(
      uri: 'content://provider/document/show%3A02',
      treeUri: root.treeUri!,
    );
    final unrelated = MediaLocation.document(
      uri: 'content://provider/document/other%3A01',
      treeUri: root.treeUri!,
    );

    final session = await LocalPlaybackRequestBuilder().buildSession(
      filePath: episode2.value,
      fileName: 'Show S01E02.mkv',
      playbackEntries: <LocalPlaybackEntry>[
        LocalPlaybackEntry(
          location: episode1,
          parentLocation: root,
          name: 'Show S01E01.mkv',
        ),
        LocalPlaybackEntry(
          location: episode2,
          parentLocation: root,
          name: 'Show S01E02.mkv',
        ),
        LocalPlaybackEntry(
          location: unrelated,
          parentLocation: otherRoot,
          name: 'Other S01E01.mkv',
        ),
      ],
      autoLoadSubtitle: false,
    );

    expect(session.seriesId, root.stableId);
    expect(
      session.episodes.map((episode) => episode.path),
      <String>[episode1.value, episode2.value],
    );
    expect(session.currentEpisodeId, episode2.stableId);
  });

  test('Android 文档字幕限制大小并缓存到应用目录', () async {
    final cacheRoot = await Directory.systemTemp.createTemp(
      'kanyingyin-document-cache-',
    );
    addTearDown(() => cacheRoot.delete(recursive: true));
    final documents = _ReadingDocumentProvider(<int>[1, 2, 3]);
    final cache = AndroidDocumentCache(
      documents,
      cacheRootProvider: () async => cacheRoot,
    );
    final subtitle = LocalMediaEntry(
      location: MediaLocation.document(
        uri: 'content://provider/document/subtitle%3A42',
        treeUri: 'content://provider/tree/root',
      ),
      name: 'Show S01E02.ass',
      isDirectory: false,
      size: 3,
      modified: DateTime(2026, 7, 29),
      mimeType: 'text/x-ssa',
    );

    final path = await cache.cacheSubtitle(subtitle);

    expect(documents.lastMaxBytes, 10 * 1024 * 1024);
    expect(await File(path).readAsBytes(), <int>[1, 2, 3]);
    expect(File(path).parent.path, contains('local_document_subtitles'));
  });

  test('Android 文档缩略图路径位于应用缓存而非 content URI', () async {
    final cacheRoot = await Directory.systemTemp.createTemp(
      'kanyingyin-thumbnail-cache-',
    );
    addTearDown(() => cacheRoot.delete(recursive: true));
    final location = MediaLocation.document(
      uri: 'content://provider/document/video%3A42',
      treeUri: 'content://provider/tree/root',
    );

    final path = await LocalThumbnailCache.pathForLocation(
      location,
      cacheRootProvider: () async => cacheRoot,
    );

    expect(path, startsWith(cacheRoot.path));
    expect(path, contains('local_document_thumbnails'));
    expect(path, isNot(contains('content:')));
    expect(path, endsWith('.jpg'));
  });
}

class _ReadingDocumentProvider implements AndroidDocumentProvider {
  _ReadingDocumentProvider(this.bytes);

  final List<int> bytes;
  int? lastMaxBytes;

  @override
  Future<bool> canAccess(MediaLocation location) async => true;

  @override
  Future<List<AndroidDocumentEntry>> listChildren(
    MediaLocation parent,
  ) async =>
      const <AndroidDocumentEntry>[];

  @override
  Future<({MediaLocation location, String name})?> pickDirectory() async =>
      null;

  @override
  Future<Uint8List> readSmallFile(
    MediaLocation location, {
    required int maxBytes,
  }) async {
    lastMaxBytes = maxBytes;
    return Uint8List.fromList(bytes);
  }
}
