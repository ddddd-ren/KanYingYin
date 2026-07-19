import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/services/cloud/cloud_cache_directories.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_subtitle_cache.dart';
import 'package:path/path.dart' as p;

void main() {
  test('云索引删除来源时原子清理全部目标数据并保留其他来源', () async {
    final repository =
        CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
    await repository.replaceSource(
      'source-a',
      [_item('source-a', '/A/E01.mkv')],
      const {'/A': 'fingerprint-a'},
      const {'/A': <CloudFileEntry>[]},
      const ['/A'],
    );
    await repository.replaceSource(
      'source-b',
      [_item('source-b', '/B/E01.mkv')],
      const {'/B': 'fingerprint-b'},
      const {'/B': <CloudFileEntry>[]},
      const ['/B'],
    );

    final removed = await repository.removeSource('source-a');

    expect(removed.items, hasLength(1));
    final first = await repository.snapshot('source-a');
    expect(first.items, isEmpty);
    expect(first.fingerprints, isEmpty);
    expect(first.directoryEntries, isEmpty);
    expect(first.indexedRoots, isEmpty);
    final second = await repository.snapshot('source-b');
    expect(second.items.single.remotePath, '/B/E01.mkv');
    expect(second.fingerprints, {'/B': 'fingerprint-b'});
    expect(second.indexedRoots, ['/B']);
  });

  test('云索引删除写入失败时完整保留原数据', () async {
    final storage = _FailingCloudMediaIndexStorage();
    final repository = CloudMediaIndexRepository(storage: storage);
    await repository.replaceSource(
      'source-a',
      [_item('source-a', '/A/E01.mkv')],
      const {'/A': 'fingerprint-a'},
      const {'/A': <CloudFileEntry>[]},
      const ['/A'],
    );
    storage.failNextWrite = true;

    await expectLater(repository.removeSource('source-a'), throwsStateError);

    final snapshot = await repository.snapshot('source-a');
    expect(snapshot.items, hasLength(1));
    expect(snapshot.fingerprints, {'/A': 'fingerprint-a'});
    expect(snapshot.indexedRoots, ['/A']);
  });

  test('海报缓存删除来源时只清理目标来源目录', () async {
    final root = await Directory.systemTemp.createTemp('cloud_poster_source_');
    addTearDown(() => root.delete(recursive: true));
    final cache =
        CloudPosterCache(cacheRoot: root, downloader: (_) async => [1]);
    final first = await cache.resolve(
        sourceId: 'source-a', stableId: 'a', url: 'https://a/1');
    final second = await cache.resolve(
        sourceId: 'source-b', stableId: 'b', url: 'https://b/1');

    await cache.removeSource('source-a');

    expect(File(first).existsSync(), isFalse);
    expect(File(second).existsSync(), isTrue);
  });

  test('字幕缓存删除来源时只清理目标来源目录', () async {
    final root = await Directory.systemTemp.createTemp('cloud_sub_source_');
    addTearDown(() => root.delete(recursive: true));
    final cache =
        CloudSubtitleCache(cacheRoot: root, downloader: (_) async => [1]);
    final client = _FakeCloudClient();
    final first = await cache.cacheBeforePlayback(
      sourceId: 'source-a',
      subtitle: _subtitle('a', '/A.srt'),
      client: client,
    );
    final second = await cache.cacheBeforePlayback(
      sourceId: 'source-b',
      subtitle: _subtitle('b', '/B.srt'),
      client: client,
    );

    await cache.removeSource('source-a');

    expect(File(first!).existsSync(), isFalse);
    expect(File(second!).existsSync(), isTrue);
  });

  test('Windows缓存路径由统一目录规则生成且不会使用临时目录别名', () {
    final root = Directory(r'C:\Users\tester\AppData\Local\看影音\cache');
    final windowsPath = p.Context(style: p.Style.windows);

    final posterRoot = CloudCacheDirectories.posterRoot(root);
    final subtitleRoot = CloudCacheDirectories.subtitleRoot(root);

    expect(posterRoot.path, windowsPath.join(root.path, 'cloud_posters'));
    expect(subtitleRoot.path, windowsPath.join(root.path, 'cloud_subtitles'));
  });

  test('海报写入与控制器删除复用同一注入缓存根目录', () async {
    final root = await Directory.systemTemp.createTemp('cloud_shared_root_');
    addTearDown(() => root.delete(recursive: true));
    const source = CloudSource(
      id: 'source-shared-root',
      type: CloudSourceType.openList,
      name: '共享缓存来源',
      baseUrl: 'https://drive.example.com',
      rootPaths: ['/'],
    );
    final posterCache =
        CloudPosterCache(cacheRoot: root, downloader: (_) async => [1]);
    final posterPath = await posterCache.resolve(
      sourceId: source.id,
      stableId: 'show',
      url: 'https://image.example.com/poster.jpg',
    );
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await sourceRepository.save(source);
    final controller = CloudLibraryController(
      repository: sourceRepository,
      credentialStore: MemoryCloudCredentialStore(),
      mediaIndexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      cacheRootProvider: () async => root,
      subtitleCacheCleaner: (_) async {},
    );

    await controller.delete(source.id);

    expect(File(posterPath).existsSync(), isFalse);
    expect(await sourceRepository.getById(source.id), isNull);
    controller.dispose();
  });

  test('海报下载进行中清理来源会等待并阻止目录重新创建', () async {
    final root = await Directory.systemTemp.createTemp('poster_clear_race_');
    addTearDown(() => root.delete(recursive: true));
    final started = Completer<void>();
    final release = Completer<List<int>>();
    final cache = CloudPosterCache(
      cacheRoot: root,
      downloader: (_) {
        started.complete();
        return release.future;
      },
    );
    const sourceId = 'source-racing-poster';
    const url = 'https://image.example.com/poster.jpg';
    final resolving =
        cache.resolve(sourceId: sourceId, stableId: 'show', url: url);
    await started.future;
    var cleared = false;
    final clearing = cache.clearSource(sourceId).whenComplete(() {
      cleared = true;
    });

    await Future<void>.delayed(Duration.zero);
    expect(cleared, isFalse);
    release.complete([1, 2, 3]);
    expect(await resolving, url);
    await clearing;

    final sourceDirectory = CloudCacheDirectories.posterSource(root, sourceId);
    expect(sourceDirectory.existsSync(), isFalse);
  });

  test('字幕下载进行中清理来源会等待并阻止目录重新创建', () async {
    final root = await Directory.systemTemp.createTemp('subtitle_clear_race_');
    addTearDown(() => root.delete(recursive: true));
    final started = Completer<void>();
    final release = Completer<List<int>>();
    final cache = CloudSubtitleCache(
      cacheRoot: root,
      downloader: (_) {
        started.complete();
        return release.future;
      },
    );
    const sourceId = 'source-racing-subtitle';
    final caching = cache.cacheBeforePlayback(
      sourceId: sourceId,
      subtitle: _subtitle('subtitle', '/Show/E01.srt'),
      client: _FakeCloudClient(),
    );
    await started.future;
    var cleared = false;
    final clearing = cache.clearSource(sourceId).whenComplete(() {
      cleared = true;
    });

    await Future<void>.delayed(Duration.zero);
    expect(cleared, isFalse);
    release.complete([1, 2, 3]);
    expect(await caching, isNull);
    await clearing;

    final sourceDirectory =
        CloudCacheDirectories.subtitleSource(root, sourceId);
    expect(sourceDirectory.existsSync(), isFalse);
  });
}

CloudMediaIndexItem _item(String sourceId, String remotePath) =>
    CloudMediaIndexItem(
      sourceId: sourceId,
      remoteId: remotePath,
      remotePath: remotePath,
      name: remotePath.split('/').last,
      size: 1024,
      modifiedAt: DateTime(2026),
      seriesName: 'Show',
      seasonNumber: 1,
      episodeNumber: 1,
      mediaType: CloudMediaType.episode,
    );

CloudFileEntry _subtitle(String id, String remotePath) => CloudFileEntry(
      id: id,
      remotePath: remotePath,
      name: remotePath.split('/').last,
      size: 1,
      modifiedAt: DateTime(2026),
      isDirectory: false,
    );

class _FailingCloudMediaIndexStorage extends MemoryCloudMediaIndexStorage {
  bool failNextWrite = false;

  @override
  Future<void> write(Map<String, Object?> value) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('模拟云索引写入失败');
    }
    await super.write(value);
  }
}

class _FakeCloudClient implements CloudDriveClient {
  @override
  Future<void> authenticate(
    CloudSource source,
    CloudCredential credential,
  ) async {}

  @override
  Future<void> close() async {}

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) =>
      throw UnimplementedError();

  @override
  Future<List<CloudFileEntry>> listDirectory(CloudRemoteRef directory) =>
      throw UnimplementedError();

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) async =>
      CloudPlaybackResource(uri: Uri.parse('https://example.com/subtitle'));
}
