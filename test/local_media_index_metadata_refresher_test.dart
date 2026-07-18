import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/local_media_index_metadata_refresher.dart';
import 'package:path/path.dart' as p;

void main() {
  test('LocalMediaIndexMetadataRefresher invalidates parser version 1', () {
    final item = LocalMediaIndexItem(
      path: r'D:\Anime\Show\Show [01].mkv',
      name: 'Show [01].mkv',
      parentPath: r'D:\Anime\Show',
      sourcePath: r'D:\Anime',
      size: 1024,
      modified: DateTime(2026),
      seriesName: 'Show',
      derivedMetadataVersion: 1,
      indexedAt: DateTime(2026),
    );

    expect(LocalMediaIndexMetadataRefresher().needsRefresh(item), isTrue);
  });

  test('LocalMediaIndexMetadataRefresher repairs version 2 fansub parsing', () {
    final path =
        r'D:\a TV\[SumiSora][Chu-2_Koi][BDRip]\[SumiSora][Chu-2_Koi][BDRip][01][x264_3flac](62A8611D).mkv';
    final item = LocalMediaIndexItem(
      path: path,
      name: p.basename(path),
      parentPath: p.dirname(path),
      sourcePath: r'D:\a TV',
      size: 1024,
      modified: DateTime(2026),
      seriesName: 'Chu',
      episodeNumber: 2,
      episodeTitle: 'Koi 01 x264 3flac 62A8611D',
      derivedMetadataVersion: 2,
      indexedAt: DateTime(2026),
    );
    final refresher = LocalMediaIndexMetadataRefresher();

    expect(refresher.needsRefresh(item), isTrue);
    final refreshed = refresher.refreshItem(item);
    expect(refreshed.seriesName, 'Chu 2 Koi');
    expect(refreshed.episodeNumber, 1);
  });

  test('LocalMediaIndexMetadataRefresher repairs stale parsed fields',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_metadata_refresh_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final video =
        File('${tempDir.path}${Platform.pathSeparator}Movie 2024 4K-kc.mkv');
    final subtitle =
        File('${tempDir.path}${Platform.pathSeparator}Movie 2024 4K-kc.srt');
    await video.writeAsString('video');
    await subtitle.writeAsString('subtitle');
    final stat = await video.stat();
    final repository = _MemoryMediaIndexRepository();
    await repository.saveForSource(tempDir.path, [
      LocalMediaIndexItem(
        path: video.path,
        name: p.basename(video.path),
        parentPath: tempDir.path,
        sourcePath: tempDir.path,
        size: stat.size,
        modified: stat.modified,
        seriesName: 'Movie 2024',
        episodeNumber: 4,
        episodeTitle: 'kc',
        pathFingerprint:
            LocalMediaIndexItem.buildPathFingerprint(video.path, stat),
        derivedMetadataVersion: 0,
        indexedAt: DateTime(2026),
      ),
    ]);

    final result =
        await LocalMediaIndexMetadataRefresher().refreshRepository(repository);

    expect(result.checkedCount, 1);
    expect(result.refreshedCount, 1);
    final item = repository.getAll().single;
    expect(item.hasCurrentDerivedMetadata, isTrue);
    expect(item.seriesName, p.basename(tempDir.path));
    expect(item.episodeNumber, isNull);
    expect(item.episodeTitle, isNull);
    expect(item.subtitlePath, subtitle.path);
  });

  test('LocalMediaIndexMetadataRefresher keeps manual episode overrides',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('kanyingyin_metadata_manual_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final video =
        File('${tempDir.path}${Platform.pathSeparator}Movie 2024 4K-kc.mkv');
    await video.writeAsString('video');
    final stat = await video.stat();
    final repository = _MemoryMediaIndexRepository();
    await repository.saveForSource(tempDir.path, [
      LocalMediaIndexItem(
        path: video.path,
        name: p.basename(video.path),
        parentPath: tempDir.path,
        sourcePath: tempDir.path,
        size: stat.size,
        modified: stat.modified,
        seriesName: '手动系列',
        seasonNumber: 2,
        episodeNumber: 9,
        episodeTitle: '手动标题',
        releaseGroup: 'ManualGroup',
        manualOverride: true,
        pathFingerprint:
            LocalMediaIndexItem.buildPathFingerprint(video.path, stat),
        derivedMetadataVersion: 0,
        indexedAt: DateTime(2026),
      ),
    ]);

    await LocalMediaIndexMetadataRefresher().refreshRepository(repository);

    final item = repository.getAll().single;
    expect(item.hasCurrentDerivedMetadata, isTrue);
    expect(item.seriesName, '手动系列');
    expect(item.seasonNumber, 2);
    expect(item.episodeNumber, 9);
    expect(item.episodeTitle, '手动标题');
    expect(item.releaseGroup, 'ManualGroup');
    expect(item.manualOverride, isTrue);
  });

  test('取消时允许在途 source 保存完成但不启动后续 source 保存', () async {
    final firstDir = await Directory.systemTemp.createTemp('metadata_first_');
    final secondDir = await Directory.systemTemp.createTemp('metadata_second_');
    addTearDown(() async {
      if (await firstDir.exists()) await firstDir.delete(recursive: true);
      if (await secondDir.exists()) await secondDir.delete(recursive: true);
    });
    final repository = _DelayedSaveRepository();
    for (final directory in <Directory>[firstDir, secondDir]) {
      final file = File(
        '${directory.path}${Platform.pathSeparator}Movie 2024.mkv',
      );
      await file.writeAsString('video');
      final stat = await file.stat();
      await repository.saveForSource(directory.path, <LocalMediaIndexItem>[
        LocalMediaIndexItem(
          path: file.path,
          name: p.basename(file.path),
          parentPath: directory.path,
          sourcePath: directory.path,
          size: stat.size,
          modified: stat.modified,
          seriesName: 'Movie 2024',
          derivedMetadataVersion: 0,
          indexedAt: DateTime(2026),
        ),
      ]);
    }
    repository.beginDelaying();
    var cancelled = false;

    final pending = LocalMediaIndexMetadataRefresher().refreshRepository(
      repository,
      isCancelled: () => cancelled,
    );
    await repository.saveStarted.future;
    cancelled = true;
    repository.completeSave();
    await pending;

    expect(repository.savedSources, <String>[firstDir.path]);
    expect(
        repository
            .getBySourcePath(firstDir.path)
            .single
            .hasCurrentDerivedMetadata,
        isTrue);
    expect(
      repository
          .getBySourcePath(secondDir.path)
          .single
          .hasCurrentDerivedMetadata,
      isFalse,
    );
  });
}

class _MemoryMediaIndexRepository implements ILocalMediaIndexRepository {
  final _items = <String, LocalMediaIndexItem>{};
  final _fingerprints = <String, Map<String, String>>{};

  @override
  List<LocalMediaIndexItem> getAll() {
    return _items.values.toList();
  }

  @override
  List<LocalMediaIndexItem> getBySourcePath(String sourcePath) {
    final sourceId = LocalMediaIndexItem.normalizePath(sourcePath);
    return _items.values
        .where((item) =>
            LocalMediaIndexItem.normalizePath(item.sourcePath) == sourceId)
        .toList(growable: false);
  }

  @override
  LocalMediaIndexItem? getByPath(String path) {
    return _items[LocalMediaIndexItem.normalizePath(path)];
  }

  @override
  Map<String, String> getDirectoryFingerprints(String sourcePath) {
    return Map<String, String>.from(
      _fingerprints[LocalMediaIndexItem.normalizePath(sourcePath)] ??
          const <String, String>{},
    );
  }

  @override
  Future<void> saveForSource(
    String sourcePath,
    List<LocalMediaIndexItem> items,
  ) async {
    final sourceId = LocalMediaIndexItem.normalizePath(sourcePath);
    _items.removeWhere(
      (_, item) =>
          LocalMediaIndexItem.normalizePath(item.sourcePath) == sourceId,
    );
    for (final item in items) {
      _items[item.id] = item;
    }
  }

  @override
  Future<void> updateItem(LocalMediaIndexItem item) async {
    _items[item.id] = item;
  }

  @override
  Future<void> saveDirectoryFingerprints(
    String sourcePath,
    Map<String, String> fingerprints,
  ) async {
    _fingerprints[LocalMediaIndexItem.normalizePath(sourcePath)] =
        Map<String, String>.from(fingerprints);
  }

  @override
  Future<void> removeSource(String sourcePath) async {
    final sourceId = LocalMediaIndexItem.normalizePath(sourcePath);
    _items.removeWhere(
      (_, item) =>
          LocalMediaIndexItem.normalizePath(item.sourcePath) == sourceId,
    );
    _fingerprints.remove(sourceId);
  }

  @override
  Future<void> clear() async {
    _items.clear();
    _fingerprints.clear();
  }
}

class _DelayedSaveRepository extends _MemoryMediaIndexRepository {
  final saveStarted = Completer<void>();
  final _allowSave = Completer<void>();
  final savedSources = <String>[];
  var _delayWrites = false;

  void beginDelaying() {
    _delayWrites = true;
    savedSources.clear();
  }

  @override
  Future<void> saveForSource(
    String sourcePath,
    List<LocalMediaIndexItem> items,
  ) async {
    if (_delayWrites) {
      savedSources.add(sourcePath);
      if (savedSources.length == 1) {
        saveStarted.complete();
        await _allowSave.future;
      }
    }
    await super.saveForSource(sourcePath, items);
  }

  void completeSave() => _allowSave.complete();
}
