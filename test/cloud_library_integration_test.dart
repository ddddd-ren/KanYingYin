import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/local/library_sheet.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_tmdb_metadata_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:path/path.dart' as p;

void main() {
  group('CloudMediaLibraryAggregator', () {
    final local = LocalMediaIndexItem(
      path: r'D:\Media\Show\Show S01E01.mkv',
      name: 'Show S01E01.mkv',
      parentPath: r'D:\Media\Show',
      sourcePath: r'D:\Media',
      size: 10,
      modified: DateTime(2026),
      seriesName: 'Show',
      seasonNumber: 1,
      episodeNumber: 1,
      indexedAt: DateTime(2026),
    );
    final openList = _cloud('openlist', '/Show/Show S01E01.mkv');
    final quark = _cloud('quark', '/Show/Show S01E01.mkv');
    final sources = <CloudSource>[
      _source('openlist', '家庭网盘', enabled: true),
      _source('quark', '夸克归档', enabled: false, type: CloudSourceType.quark),
    ];

    test('聚合本地和两个远程来源且同名同路径不跨来源合并', () {
      final library = const CloudMediaLibraryAggregator().build(
        localItems: [local],
        cloudItems: [openList, quark],
        cloudSources: sources,
      );

      expect(library.series, hasLength(3));
      expect(library.series.map((item) => item.sourceId).toSet(),
          {'local', 'openlist', 'quark'});
      expect(library.series.map((item) => item.key).toSet(), hasLength(3));
      final remote = library.series
          .firstWhere((item) => item.sourceId == 'openlist')
          .episodes
          .single;
      expect(remote.sourceKind, MediaSourceKind.cloud);
      expect(remote.localItem, isNull);
      expect(remote.remotePath, '/Show/Show S01E01.mkv');
      expect(remote.isAvailable, isTrue);
      expect(
          library.series
              .firstWhere((item) => item.sourceId == 'quark')
              .isAvailable,
          isFalse);
    });

    test('来源筛选保留全部、本地和启用网盘来源', () {
      final library = const CloudMediaLibraryAggregator().build(
        localItems: [local],
        cloudItems: [openList, quark],
        cloudSources: sources,
      );

      expect(
          library.filters.map((item) => item.id), ['all', 'local', 'openlist']);
      expect(library.filterBySource('openlist'), hasLength(1));
      expect(library.filterBySource('local').single.sourceKind,
          MediaSourceKind.local);
    });

    test('同一云来源沿用季度和特别篇拆分', () {
      final library = const CloudMediaLibraryAggregator().build(
        localItems: const [],
        cloudItems: [
          _cloud('openlist', '/Show/Show S01E01.mkv'),
          _cloud('openlist', '/Show/Show S02E01.mkv', season: 2),
          _cloud('openlist', '/Show/Show Special.mkv',
              type: CloudMediaType.special, episode: null),
        ],
        cloudSources: sources,
      );
      expect(library.series.map((item) => item.title),
          ['Show S01', 'Show S02', 'Show 特别篇']);
    });

    test('云系列保留原始分组键但向界面提供 TMDB 信息', () {
      final enriched = openList.replaceTmdb(
        tmdbId: 42,
        tmdbTitle: '中文片名',
        tmdbOverview: '这是用户可见的简介',
        tmdbRating: 8.8,
        tmdbPosterUrl: '/poster.jpg',
        posterCachePath: r'C:\cache\poster.jpg',
      );

      final series = const CloudMediaLibraryAggregator()
          .build(
            localItems: const [],
            cloudItems: [enriched],
            cloudSources: sources,
          )
          .series
          .single;

      expect(series.seriesKey, 'Show');
      expect(series.title, '中文片名 S01');
      expect(series.tmdbRating, 8.8);
      expect(series.tmdbOverview, '这是用户可见的简介');
      expect(series.tmdbPosterUrl, '/poster.jpg');
      expect(series.posterCachePath, r'C:\cache\poster.jpg');
    });
  });

  group('CloudPosterCache', () {
    late Directory root;
    setUp(() async =>
        root = await Directory.systemTemp.createTemp('cloud-poster-'));
    tearDown(() async => root.delete(recursive: true));

    test('缓存路径只位于 cloud_posters 哈希目录且 URL 变化会更新', () async {
      var payload = <int>[1, 2, 3];
      final cache = CloudPosterCache(
        cacheRoot: root,
        downloader: (_) async => payload,
      );
      final first = await cache.resolve(
          sourceId: 'source/with/slash',
          stableId: '../remote',
          url: 'https://a/1.jpg');
      payload = <int>[4, 5];
      final second = await cache.resolve(
          sourceId: 'source/with/slash',
          stableId: '../remote',
          url: 'https://a/2.jpg');

      expect(first, second);
      expect(first,
          startsWith('${root.path}${Platform.pathSeparator}cloud_posters'));
      expect(await File(second).readAsBytes(), [4, 5]);
      expect(second, isNot(contains('remote')));
      expect(await File(first).exists(), isTrue);
    });

    test('跨实例单飞且下载失败回退旧缓存或网络 URL', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      Future<List<int>> download(String _) async {
        calls++;
        started.complete();
        await release.future;
        return [7];
      }

      final a = CloudPosterCache(cacheRoot: root, downloader: download);
      final b = CloudPosterCache(cacheRoot: root, downloader: download);
      final one = a.resolve(sourceId: 's', stableId: 'id', url: 'https://a/1');
      await started.future;
      final two = b.resolve(sourceId: 's', stableId: 'id', url: 'https://a/1');
      release.complete();
      expect(await Future.wait([one, two]), everyElement(isA<String>()));
      expect(calls, 1);

      final failing = CloudPosterCache(
          cacheRoot: root,
          downloader: (_) async => throw const SocketException('down'));
      expect(
          await failing.resolve(
              sourceId: 's', stableId: 'id', url: 'https://a/2'),
          endsWith('.jpg'));
      expect(
          await failing.resolve(
              sourceId: 'new', stableId: 'id', url: 'https://a/2'),
          'https://a/2');
    });

    test('同一海报不同 URL 并发仍只返回存在的单一版本', () async {
      final release = Completer<void>();
      var calls = 0;
      final cache = CloudPosterCache(
        cacheRoot: root,
        downloader: (_) async {
          calls++;
          await release.future;
          return [calls];
        },
      );
      final first =
          cache.resolve(sourceId: 's', stableId: 'same', url: 'https://a/1');
      final second =
          cache.resolve(sourceId: 's', stableId: 'same', url: 'https://a/2');
      release.complete();
      final paths = await Future.wait([first, second]);
      expect(paths[0], paths[1]);
      expect(await File(paths[0]).exists(), isTrue);
      expect(calls, 2);
      expect(await File(paths[0]).readAsBytes(), [2]);
      final files = await root
          .list(recursive: true)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      expect(files.where((file) => file.path.endsWith('.jpg')), hasLength(1));
      expect(files.where((file) => file.path.endsWith('.tmp')), isEmpty);
    });

    test('安装新版本失败会恢复旧图片和 sidecar 且无临时备份', () async {
      final initial =
          CloudPosterCache(cacheRoot: root, downloader: (_) async => [1, 2, 3]);
      final path = await initial.resolve(
          sourceId: 's', stableId: 'rollback', url: 'https://a/old');
      final sidecar = File('${p.withoutExtension(path)}.url');
      final oldVersion = await sidecar.readAsString();
      final failing = CloudPosterCache(
        cacheRoot: root,
        downloader: (_) async => [9, 9],
        beforeInstall: (_) async => throw const FileSystemException('install'),
      );

      expect(
          await failing.resolve(
              sourceId: 's', stableId: 'rollback', url: 'https://a/new'),
          path);
      expect(await File(path).readAsBytes(), [1, 2, 3]);
      expect(await sidecar.readAsString(), oldVersion);
      final residue = await root
          .list(recursive: true)
          .where((entity) =>
              entity.path.endsWith('.tmp') || entity.path.endsWith('.bak'))
          .toList();
      expect(residue, isEmpty);
    });

    test('图片备份后 sidecar 备份失败仍独立恢复两份旧文件', () async {
      final initial =
          CloudPosterCache(cacheRoot: root, downloader: (_) async => [3, 2, 1]);
      final path = await initial.resolve(
          sourceId: 's', stableId: 'backup-fail', url: 'https://a/old');
      final sidecar = File('${p.withoutExtension(path)}.url');
      final oldVersion = await sidecar.readAsString();
      final failing = CloudPosterCache(
        cacheRoot: root,
        downloader: (_) async => [8, 8],
        beforeMetadataBackup: (_) async =>
            throw const FileSystemException('metadata backup'),
      );

      expect(
          await failing.resolve(
              sourceId: 's', stableId: 'backup-fail', url: 'https://a/new'),
          path);
      expect(await File(path).readAsBytes(), [3, 2, 1]);
      expect(await sidecar.readAsString(), oldVersion);
      final residue = await root
          .list(recursive: true)
          .where((entity) =>
              entity.path.endsWith('.tmp') || entity.path.endsWith('.bak'))
          .toList();
      expect(residue, isEmpty);
    });

    test('提交后第二个备份清理失败不会回滚新图片和 sidecar', () async {
      final initial =
          CloudPosterCache(cacheRoot: root, downloader: (_) async => [1]);
      final path = await initial.resolve(
          sourceId: 's', stableId: 'cleanup-fail', url: 'https://a/old');
      final sidecar = File('${p.withoutExtension(path)}.url');
      final oldVersion = await sidecar.readAsString();
      final updating = CloudPosterCache(
        cacheRoot: root,
        downloader: (_) async => [7, 7],
        beforeBackupCleanup: (backupPath) async {
          if (backupPath.contains('.url.')) {
            throw const FileSystemException('cleanup');
          }
        },
      );

      expect(
          await updating.resolve(
              sourceId: 's', stableId: 'cleanup-fail', url: 'https://a/new'),
          path);
      expect(await File(path).readAsBytes(), [7, 7]);
      expect(await sidecar.readAsString(), isNot(oldVersion));
      expect(await File(path).exists(), isTrue);
      expect(await sidecar.exists(), isTrue);
    });

    test('大量不同海报完成后锁池归零', () async {
      final cache =
          CloudPosterCache(cacheRoot: root, downloader: (_) async => [1]);
      await Future.wait(List.generate(
        100,
        (index) => cache.resolve(
            sourceId: 's', stableId: 'id-$index', url: 'https://a/$index'),
      ));
      expect(CloudPosterCache.debugLockCount, 0);
    });
  });

  test('媒体条目工厂在 release 语义下拒绝非法云字段', () {
    expect(
      () => MediaLibraryEpisode.cloud(
        stableId: 'id',
        name: 'bad',
        sourceId: '',
        sourceName: 'bad',
        isAvailable: true,
        remotePath: '',
      ),
      throwsArgumentError,
    );
  });

  test('LocalController 从仓库读取旧云索引并按来源筛选', () async {
    final sourceStorage = MemoryCloudSourceStorage();
    final sourceRepository = CloudSourceRepository(storage: sourceStorage);
    await sourceRepository.save(_source('openlist', '家庭网盘', enabled: false));
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await indexRepository.replaceSource(
      'openlist',
      [_cloud('openlist', '/Show/Show S01E01.mkv')],
      const {},
      const {},
      const ['/'],
    );
    final controller = LocalController(
      cloudSourceRepository: sourceRepository,
      cloudMediaIndexRepository: indexRepository,
    );

    await controller.reloadCloudLibraryIndex();

    expect(controller.combinedMediaLibrary.series, hasLength(1));
    expect(controller.combinedMediaLibrary.series.single.isAvailable, isFalse);
    controller.selectLibrarySource('openlist');
    expect(controller.visibleMediaLibrarySeries, hasLength(1));
  });

  test('LocalController 总媒体数包含网盘并可在刷新后选中来源', () async {
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await sourceRepository.save(_source('openlist', '家庭网盘', enabled: true));
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await indexRepository.replaceSource(
      'openlist',
      <CloudMediaIndexItem>[_cloud('openlist', '/Show/E01.mkv')],
      const {},
      const {},
      const ['/'],
    );
    final controller = LocalController(
      cloudSourceRepository: sourceRepository,
      cloudMediaIndexRepository: indexRepository,
    );

    await controller.revealCloudLibrarySource('openlist');

    expect(controller.mediaLibraryVideoCount, 1);
    expect(controller.selectedLibrarySourceId, 'openlist');
    final page = File('lib/pages/local/local_page.dart').readAsStringSync();
    expect(page, contains('LibraryPathBar('));
    expect(
      page,
      contains('canOpenLibrary: localController.mediaLibraryVideoCount > 0'),
    );
  });

  test('云索引完整持久化 TMDB 元数据和海报缓存路径', () async {
    final repository =
        CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
    final item = _cloud('openlist', '/Show/E01.mkv').copyWith(
      tmdbId: 42,
      tmdbTitle: '中文名',
      tmdbOriginalTitle: 'Original',
      tmdbOverview: '简介',
      tmdbRating: 8.8,
      tmdbPosterUrl: '/poster.jpg',
      tmdbBackdropUrl: '/backdrop.jpg',
      posterCachePath: r'C:\cache\poster.jpg',
    );
    await repository
        .replaceSource('openlist', [item], const {}, const {}, const ['/']);

    final restored = (await repository.getBySource('openlist')).single;
    expect(restored.tmdbOriginalTitle, 'Original');
    expect(restored.tmdbOverview, '简介');
    expect(restored.posterCachePath, r'C:\cache\poster.jpg');
  });

  test('原子 TMDB 更新保留扫描新增条目并能清除旧可空字段', () async {
    final repository =
        CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
    final old = _cloud('openlist', '/Show/E01.mkv').replaceTmdb(
      tmdbId: 1,
      tmdbTitle: '旧标题',
      tmdbOverview: '旧简介',
      posterCachePath: 'old.jpg',
    );
    final added = _cloud('openlist', '/Other/E01.mkv');
    await repository.replaceSource(
        'openlist', [old, added], const {}, const {}, const ['/']);
    final count = await repository.updateMatching(
      'openlist',
      (item) => item.remotePath == '/Show/E01.mkv',
      (item) => item.replaceTmdb(tmdbId: 2, tmdbTitle: '新标题'),
    );
    final items = await repository.getBySource('openlist');
    expect(count, 1);
    expect(items, hasLength(2));
    final updated =
        items.firstWhere((item) => item.remotePath.contains('Show'));
    expect(updated.tmdbOverview, isNull);
    expect(updated.posterCachePath, isNull);
  });

  test('LocalController 按来源调用真实扫描后重读索引', () async {
    final sourceRepository =
        CloudSourceRepository(storage: MemoryCloudSourceStorage());
    await sourceRepository.save(_source('openlist', '家庭网盘', enabled: true));
    final indexRepository =
        CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
    final calls = <String>[];
    final controller = LocalController(
      cloudSourceRepository: sourceRepository,
      cloudMediaIndexRepository: indexRepository,
      scanCloudSource: (sourceId) async {
        calls.add(sourceId);
        await indexRepository.replaceSource(
            sourceId,
            [_cloud(sourceId, '/New/E01.mkv')],
            const {},
            const {},
            const ['/']);
      },
    );
    expect(await controller.refreshCloudLibrarySource('openlist'), isTrue);
    expect(calls, ['openlist']);
    expect(controller.cloudLibraryItems.single.remotePath, '/New/E01.mkv');
  });

  test('海报下载失败不会遗留临时文件', () async {
    final root = await Directory.systemTemp.createTemp('cloud-poster-fail-');
    addTearDown(() => root.delete(recursive: true));
    final cache = CloudPosterCache(
        cacheRoot: root,
        downloader: (_) async => throw const FileSystemException('partial'));
    await cache.resolve(sourceId: 's', stableId: 'id', url: 'https://a/1');
    final files =
        await root.list(recursive: true).where((e) => e is File).toList();
    expect(files.where((e) => e.path.endsWith('.tmp')), isEmpty);
  });

  test('云 TMDB 自动匹配和手动候选只更新云索引', () async {
    final repository =
        CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
    await repository.replaceSource('openlist',
        [_cloud('openlist', '/Show/E01.mkv')], const {}, const {}, const ['/']);
    final candidate = TmdbMetadata(
      id: 7,
      mediaType: TmdbMediaType.tv,
      title: 'Show',
      language: 'zh-CN',
      matchedAt: DateTime(2026),
      matchConfidence: 1,
      posterUrl: '/p.jpg',
    );
    final service = CloudTmdbMetadataService(
        repository: repository, client: _FakeTmdbClient(candidate));
    final outcome =
        await service.match(sourceId: 'openlist', seriesName: 'Show');
    expect(outcome.selected?.id, 7);
    expect((await repository.getBySource('openlist')).single.tmdbId, 7);
    expect(Directory('/Show').existsSync(), isFalse);
  });

  testWidgets('远程系列菜单提供 TMDB 刮削和重新匹配', (tester) async {
    final controller = LocalController();
    controller.cloudLibrarySources
        .add(_source('openlist', '家庭网盘', enabled: true));
    controller.cloudLibraryItems
        .add(_cloud('openlist', '/Show/Show S01E01.mkv'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibrarySheetContent(
          controller: controller,
          onPlay: (_, __) {},
          onRefresh: () {},
        ),
      ),
    ));
    await tester.tap(find.byTooltip('网盘系列操作'));
    await tester.pumpAndSettle();
    expect(find.text('TMDB 刮削'), findsOneWidget);
    expect(find.text('重新匹配'), findsOneWidget);
  });

  testWidgets('网盘来源为空时显示可操作的扫描诊断', (tester) async {
    final controller = LocalController();
    controller.cloudLibrarySources.add(CloudSource(
      id: 'openlist',
      type: CloudSourceType.openList,
      name: '家庭网盘',
      baseUrl: 'https://drive.example.com',
      rootPaths: const <String>['/动漫'],
      scanStatus: CloudScanStatus.completed,
      lastScannedAt: DateTime(2026, 7, 15),
    ));
    controller.selectLibrarySource('openlist');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibrarySheetContent(
          controller: controller,
          onPlay: (_, __) {},
          onRefresh: () {},
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('扫描目录中没有找到支持的视频'), findsOneWidget);
    expect(find.text('重新扫描网盘'), findsOneWidget);
  });

  testWidgets('云系列组件显示 TMDB 标题评分和简介', (tester) async {
    final controller = LocalController();
    controller.cloudLibrarySources
        .add(_source('openlist', '家庭网盘', enabled: true));
    controller.cloudLibraryItems.add(
      _cloud('openlist', '/Show/Show S01E01.mkv').replaceTmdb(
        tmdbId: 42,
        tmdbTitle: '中文片名',
        tmdbOverview: '这是用户可见的简介',
        tmdbRating: 8.8,
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibrarySheetContent(
          controller: controller,
          onPlay: (_, __) {},
          onRefresh: () {},
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('中文片名 S01'), findsOneWidget);
    expect(find.textContaining('8.8'), findsOneWidget);
    await tester.tap(find.text('中文片名 S01'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('这是用户可见的简介'), findsOneWidget);
  });
}

class _FakeTmdbClient implements ITmdbClient {
  const _FakeTmdbClient(this.metadata);
  final TmdbMetadata metadata;
  @override
  Future<TmdbMetadata> details(int id, TmdbMediaType mediaType,
          {String language = 'zh-CN'}) async =>
      metadata;
  @override
  Future<List<TmdbMetadata>> search(String query, TmdbMediaType mediaType,
          {String language = 'zh-CN'}) async =>
      [metadata];
}

CloudMediaIndexItem _cloud(String sourceId, String path,
    {int season = 1,
    int? episode = 1,
    CloudMediaType type = CloudMediaType.episode}) {
  return CloudMediaIndexItem(
    sourceId: sourceId,
    remoteId: path,
    remotePath: path,
    name: path.split('/').last,
    size: 10,
    modifiedAt: DateTime(2026),
    seriesName: 'Show',
    seasonNumber: season,
    episodeNumber: episode,
    mediaType: type,
  );
}

CloudSource _source(String id, String name,
    {required bool enabled, CloudSourceType type = CloudSourceType.openList}) {
  return CloudSource(
    id: id,
    type: type,
    name: name,
    baseUrl: 'https://example.com',
    rootPaths: const ['/'],
    enabled: enabled,
  );
}
