import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/platform/android/android_document_provider.dart';
import 'package:kanyingyin/services/android_document_cache.dart';
import 'package:kanyingyin/services/local_media_entry_provider.dart';
import 'package:kanyingyin/services/local_media_indexer.dart';
import 'package:kanyingyin/services/local_media_probe.dart';
import 'package:kanyingyin/services/local_media_scanner.dart';

void main() {
  final root = MediaLocation.document(
    uri: 'content://media/document/root',
    treeUri: 'content://media/tree/root',
  );
  final season = MediaLocation.document(
    uri: 'content://media/document/season-1',
    treeUri: root.treeUri!,
  );
  final video = MediaLocation.document(
    uri: 'content://media/document/show-s01e02',
    treeUri: root.treeUri!,
  );

  test('Android 文档树递归扫描保留 content URI 和剧集信息', () async {
    final provider = _DocumentEntryProvider(
      entries: <MediaLocation, List<LocalMediaEntry>>{
        root: <LocalMediaEntry>[
          _entry(season, 'Season 1', isDirectory: true),
          _entry(
            MediaLocation.document(
              uri: 'content://media/document/hidden',
              treeUri: root.treeUri!,
            ),
            '.hidden.mkv',
          ),
          _entry(
            MediaLocation.document(
              uri: 'content://media/document/readme',
              treeUri: root.treeUri!,
            ),
            'readme.txt',
            mimeType: 'text/plain',
          ),
        ],
        season: <LocalMediaEntry>[
          _entry(video, 'Show S01E02.mkv'),
        ],
      },
    );
    final scanner = LocalMediaScanner(
      entryProviders: <LocalMediaEntryProvider>[provider],
      minRecognizedVideoSizeBytes: 0,
    );

    final result = await scanner.scanLocation(
      root,
      sortMode: LocalSortMode.name,
      ascending: true,
    );

    expect(result.currentPath, root.value);
    expect(result.items, hasLength(1));
    expect(result.items.single.location, video);
    expect(result.items.single.path, 'content://media/document/show-s01e02');
    expect(result.items.single.episodeInfo?.seriesName, 'Show');
    expect(result.items.single.episodeInfo?.seasonNumber, 1);
    expect(result.items.single.episodeInfo?.episodeNumber, 2);
    expect(result.skippedCount, 2);
  });

  test('Android 文档授权失效时保留已有索引', () async {
    final cacheRoot = await Directory.systemTemp.createTemp(
      'kanyingyin-index-document-cache-',
    );
    addTearDown(() => cacheRoot.delete(recursive: true));
    final storage = _MemoryIndexStorage();
    final repository = LocalMediaIndexRepository(storage: storage);
    final provider = _DocumentEntryProvider(
      entries: <MediaLocation, List<LocalMediaEntry>>{
        root: <LocalMediaEntry>[
          _entry(season, 'Season 1', isDirectory: true),
        ],
        season: <LocalMediaEntry>[
          _entry(video, 'Show S01E02.mkv'),
          _entry(
            MediaLocation.document(
              uri: 'content://media/document/show-s01e02-subtitle',
              treeUri: root.treeUri!,
            ),
            'Show S01E02.ass',
            mimeType: 'text/x-ssa',
          ),
          _entry(
            MediaLocation.document(
              uri: 'content://media/document/tmdb-poster',
              treeUri: root.treeUri!,
            ),
            'tmdb-poster.jpg',
            mimeType: 'image/jpeg',
          ),
        ],
      },
    );
    final mediaProbe = _RecordingDocumentMediaProbe();
    final indexer = LocalMediaIndexer(
      repository: repository,
      entryProviders: <LocalMediaEntryProvider>[provider],
      mediaProbe: mediaProbe,
      documentCache: AndroidDocumentCache(
        _DocumentBytesProvider(),
        cacheRootProvider: () async => cacheRoot,
      ),
      minRecognizedVideoSizeBytes: 0,
    );

    final first = await indexer.indexSourceLocation(
      root,
      enrichMediaInfo: true,
      generateThumbnails: true,
    );
    provider.accessible = false;
    final second = await indexer.indexSourceLocation(root);

    expect(first.addedCount, 1);
    expect(repository.getBySourceLocation(root), hasLength(1));
    expect(repository.getBySourceLocation(root).single.location, video);
    expect(mediaProbe.probedPaths, <String>[video.value]);
    expect(
      repository.getBySourceLocation(root).single.durationMillis,
      const Duration(minutes: 2).inMilliseconds,
    );
    expect(
      File(
        repository.getBySourceLocation(root).single.subtitlePath!,
      ).existsSync(),
      isTrue,
    );
    expect(
      File(repository.getBySourceLocation(root).single.cover!).existsSync(),
      isTrue,
    );
    expect(second.items, hasLength(1));
    expect(second.removedCount, 0);
    expect(second.failures, isNotEmpty);
  });
}

LocalMediaEntry _entry(
  MediaLocation location,
  String name, {
  bool isDirectory = false,
  String mimeType = 'video/x-matroska',
}) {
  return LocalMediaEntry(
    location: location,
    name: name,
    isDirectory: isDirectory,
    size: isDirectory ? 0 : 1024,
    modified: DateTime(2026, 7, 29),
    mimeType: isDirectory ? 'vnd.android.document/directory' : mimeType,
  );
}

class _DocumentEntryProvider implements LocalMediaEntryProvider {
  _DocumentEntryProvider({required this.entries});

  final Map<MediaLocation, List<LocalMediaEntry>> entries;
  bool accessible = true;

  @override
  bool supports(MediaLocation location) => location.isDocument;

  @override
  Future<bool> canAccess(MediaLocation location) async => accessible;

  @override
  Future<List<LocalMediaEntry>> listChildren(MediaLocation directory) async =>
      entries[directory] ?? const <LocalMediaEntry>[];
}

class _MemoryIndexStorage implements LocalMediaIndexStorage {
  final Map<String, Object?> _values = <String, Object?>{};

  @override
  Object? read(String key, {Object? defaultValue}) =>
      _values[key] ?? defaultValue;

  @override
  Future<void> write(String key, Object? value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _DocumentBytesProvider implements AndroidDocumentProvider {
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
  }) async =>
      Uint8List.fromList(<int>[1, 2, 3]);
}

class _RecordingDocumentMediaProbe implements ILocalMediaProbe {
  final List<String> probedPaths = <String>[];

  @override
  Future<LocalMediaInfo> probe(String filePath) async {
    probedPaths.add(filePath);
    return const LocalMediaInfo(duration: Duration(minutes: 2));
  }

  @override
  Future<String?> captureThumbnail(
    String filePath,
    String outputPath,
  ) async =>
      null;
}
