import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_page.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_tmdb_match_dialog.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/repositories/cloud_hidden_video_repository.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_media_tag_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_media_tree_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client_capabilities.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const captureToolbar = bool.fromEnvironment('CAPTURE_TOOLBAR_LAYOUT');
  if (captureToolbar) {
    setUpAll(() async {
      for (final font in <String, String>{
        'ToolbarQA': 'C:/Windows/Fonts/msyh.ttc',
        'MaterialIcons':
            'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      }.entries) {
        final bytes = await File(font.value).readAsBytes();
        await (FontLoader(font.key)
              ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes))))
            .load();
      }
    });
  }

  test('重新刮削第一季只请求并保存该季，其他四季和公共资料不变', () async {
    final fixture = await _Fixture.create();
    final before = await fixture.repository.getAll();
    final indexBefore = jsonEncode(await fixture.indexStorage.read());
    final postersBefore = await fixture.posterFiles();

    await fixture.refreshSeason(1);

    expect(fixture.client.seasonCalls, <int>[1]);
    expect(fixture.downloads,
        <String>['https://image.tmdb.org/t/p/w500/new-1.jpg']);
    final updated = (await fixture.repository.getAll()).single;
    expect(updated.seasons.first.posterUrl, '/new-1.jpg');
    expect(updated.seasons.skip(1), before.single.seasons.skip(1));
    expect(
      updated.metadata!.copyWith(seasons: before.single.seasons),
      before.single.metadata,
    );
    expect(
      jsonEncode(await fixture.indexStorage.read()),
      indexBefore,
    );
    final postersAfter = await fixture.posterFiles();
    for (final season in before.single.seasons.skip(1)) {
      expect(postersAfter[season.posterCachePath],
          postersBefore[season.posterCachePath]);
    }
    await fixture.controller.load(startScan: false);
    expect(fixture.group(1).seasonMetadata!.posterUrl, '/new-1.jpg');
    expect(fixture.group(5).seasonMetadata!.posterUrl, '/old-5.jpg');
  });

  test('季度请求失败保留原记录和全部海报', () async {
    final fixture = await _Fixture.create();
    final before = await fixture.repository.getAll();
    final postersBefore = await fixture.posterFiles();
    fixture.client.failSeasons.add(1);

    await expectLater(fixture.refreshSeason(1), throwsStateError);

    expect(await fixture.repository.getAll(), before);
    expect(await fixture.posterFiles(), postersBefore);
    expect(fixture.controller.tmdbScrapingKeys, isEmpty);
  });

  test('跨目录合并优先使用该季所属记录，刷新第二季不覆盖其他目录', () async {
    final fixture = await _Fixture.create(separateDirectories: true);
    expect(fixture.tree.works, hasLength(5));
    for (var season = 1; season <= 5; season++) {
      expect(
          fixture.group(season).seasonMetadata!.posterUrl, '/old-$season.jpg');
    }
    final before = await fixture.repository.getAll();

    await fixture.refreshSeason(2);

    expect(fixture.client.seasonCalls, <int>[2]);
    final after = await fixture.repository.getAll();
    for (final work in fixture.tree.works) {
      if (work.seasons.single.seasonNumber == 2) continue;
      expect(
        after.singleWhere((record) => record.workKey == work.workKey),
        before.singleWhere((record) => record.workKey == work.workKey),
      );
    }
    await fixture.controller.load(startScan: false);
    expect(fixture.group(2).seasonMetadata!.posterUrl, '/new-2.jpg');
    expect(fixture.group(1).seasonMetadata!.posterUrl, '/old-1.jpg');
  });

  test('同剧两季并发刷新分别保留结果且忙碌状态不扩散到其他季', () async {
    final fixture = await _Fixture.create();
    fixture.client.pause = Completer<void>();
    final first = fixture.refreshSeason(1);
    final second = fixture.refreshSeason(2);
    await fixture.client.started.future;
    final busy = Set<String>.of(fixture.controller.tmdbScrapingKeys);
    fixture.client.pause!.complete();
    await Future.wait(<Future<void>>[first, second]);

    final workKey = fixture.tree.works.single.workKey;
    expect(busy, contains('$workKey|season:1'));
    expect(busy, contains('$workKey|season:2'));
    expect(busy, isNot(contains(workKey)));
    final updated = (await fixture.repository.getAll()).single;
    expect(updated.seasons[0].posterUrl, '/new-1.jpg');
    expect(updated.seasons[1].posterUrl, '/new-2.jpg');
    expect(updated.seasons[2].posterUrl, '/old-3.jpg');
    expect(fixture.controller.tmdbScrapingKeys, isEmpty);
  });

  test('重新加载快照仍保留正在进行的单季状态', () async {
    final fixture = await _Fixture.create();
    fixture.client.pause = Completer<void>();
    final refreshing = fixture.refreshSeason(1);
    await fixture.client.started.future;
    await fixture.coordinator.loadAndSchedule(fixture.tree);
    final busy = Set<String>.of(fixture.controller.tmdbScrapingKeys);
    fixture.client.pause!.complete();
    await refreshing;
    expect(busy, contains('${fixture.tree.works.single.workKey}|season:1'));
    expect(fixture.client.seasonCalls, <int>[1]);
  });

  test('单季操作拒绝更换整剧 TMDB 身份且不写入任何记录', () async {
    final fixture = await _Fixture.create();
    final before = await fixture.repository.getAll();
    await expectLater(
      fixture.refreshSeason(1, candidate: _metadata(id: 999)),
      throwsStateError,
    );
    expect(await fixture.repository.getAll(), before);
    expect(fixture.downloads, isEmpty);
  });

  test('手动重刮后重载不再用旧自动规则重刮整剧', () async {
    final fixture = await _Fixture.create();
    final previous = (await fixture.repository.getAll()).single;
    await fixture.repository.upsert(CloudWorkTmdbRecord.matched(
      sourceId: previous.sourceId,
      workKey: previous.workKey,
      workRootId: previous.workRootId,
      workRootPath: previous.workRootPath,
      remoteName: previous.remoteName,
      metadata: previous.metadata!,
      checkedAt: previous.checkedAt,
      tmdbMatchOrigin: TmdbMatchOrigin.automatic,
      tmdbRuleVersion: 0,
    ));
    await fixture.refreshSeason(1);
    await fixture.coordinator.loadAndSchedule(fixture.tree);
    final updated = (await fixture.repository.getAll()).single;
    expect(updated.status, CloudWorkTmdbStatus.matched);
    expect(updated.tmdbMatchOrigin, TmdbMatchOrigin.manual);
    expect(updated.seasons.skip(1), previous.seasons.skip(1));
    expect(fixture.client.seasonCalls, <int>[1]);
  });

  test('目标季海报下载失败时保留全部原资料和缓存文件', () async {
    final fixture = await _Fixture.create();
    final before = await fixture.repository.getAll();
    final postersBefore = await fixture.posterFiles();
    fixture.failDownload = true;
    await expectLater(fixture.refreshSeason(1), throwsStateError);
    expect(await fixture.repository.getAll(), before);
    expect(await fixture.posterFiles(), postersBefore);
  });

  test('明确指定整剧更新时仍处理全部季度', () async {
    final fixture = await _Fixture.create();
    await fixture.refreshSeason(1, wholeWork: true);
    expect(fixture.client.seasonCalls, unorderedEquals(<int>[1, 2, 3, 4, 5]));
    expect(
        (await fixture.repository.getAll())
            .single
            .seasons
            .map((season) => season.posterUrl),
        <String>[
          for (var season = 1; season <= 5; season++) '/new-$season.jpg',
        ]);
  });

  test('请求期间作品被移除时不重新创建旧记录', () async {
    final fixture = await _Fixture.create();
    fixture.client.pause = Completer<void>();
    final refreshing = fixture.refreshSeason(1);
    final rejected = expectLater(refreshing, throwsStateError);
    await fixture.client.started.future;
    await fixture.repository.removeSource('quark-season');
    fixture.client.pause!.complete();
    await rejected;
    expect(await fixture.repository.getAll(), isEmpty);
  });

  test('多季作品首次建立剧目身份也必须确认整剧范围', () async {
    final fixture = await _Fixture.create();
    final unchecked = CloudWorkTmdbRecord.uncheckedFromWork(
      fixture.tree.works.single,
      checkedAt: DateTime.utc(2026, 9, 5),
    );
    await fixture.repository.upsert(unchecked);
    await expectLater(fixture.refreshSeason(1), throwsStateError);
    expect(await fixture.repository.getAll(), <CloudWorkTmdbRecord>[unchecked]);
    expect(fixture.client.seasonCalls, isEmpty);
  });

  for (final size in <Size>[
    const Size(320, 720),
    const Size(390, 844),
    const Size(600, 800),
    const Size(1280, 800),
  ]) {
    testWidgets('网盘工具栏及整剧确认适配完整页面 ${size.width}', (tester) async {
      final fixture =
          (await tester.runAsync(() => _Fixture.create(renderPosters: true)))!;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final captureKey = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: captureToolbar ? ThemeData(fontFamily: 'ToolbarQA') : null,
        home: RepaintBoundary(
          key: captureKey,
          child: CloudResourcesPage(
            controller: fixture.controller,
            capabilities: AppPlatformCapabilities.windows,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final tooltip in <String>[
        '添加网盘',
        '管理网盘来源',
        '刷新当前来源',
        '更多网盘操作',
      ]) {
        final control = find.byTooltip(tooltip);
        expect(control, findsOneWidget);
        expect(tester.getRect(control).right, lessThanOrEqualTo(size.width));
      }
      if (captureToolbar && (size.width == 390 || size.width == 1280)) {
        final boundary = captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = (await tester.runAsync(boundary.toImage))!;
        final png = (await tester
            .runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
        await tester.runAsync(() async {
          await Directory('build/toolbar-layout-qa').create(recursive: true);
          await File(
                  'build/toolbar-layout-qa/toolbar-${size.width.toInt()}.png')
              .writeAsBytes(png.buffer.asUint8List());
        });
        image.dispose();
      }
      await tester.tap(find.byTooltip('添加网盘'));
      await tester.pumpAndSettle();
      expect(find.text('添加夸克网盘'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final titleY = tester.getCenter(find.text('网盘媒体库')).dy;
      final sourceY = tester
          .getCenter(find.byKey(
            const ValueKey<String>('cloud-source-selector'),
          ))
          .dy;
      expect(
          sourceY, size.width < 632 ? greaterThan(titleY) : closeTo(titleY, 1));
      await tester.tap(find.byTooltip('资源操作').first);
      await tester.pumpAndSettle();
      expect(find.text('重新刮削本季'), findsOneWidget);
      await tester.tap(find.text('重新刮削整部剧'));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey<String>('cloud-whole-work-confirmation')),
          findsOneWidget);
      expect(find.textContaining('5 季资料与海报'), findsOneWidget);
      expect(fixture.client.seasonCalls, isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('tmdb-match-dialog')),
          findsNothing);
      expect(fixture.downloads, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  for (final width in <double>[320, 1280]) {
    testWidgets('网盘工具栏长来源名不会挤出操作或撑破选择菜单 $width', (tester) async {
      const sourceName = '家庭影音收藏与蓝光原盘备份专用网盘来源';
      final fixture = (await tester.runAsync(() => _Fixture.create(
            renderPosters: true,
            sourceName: sourceName,
          )))!;
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          home: CloudResourcesPage(
        controller: fixture.controller,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final selector =
          find.byKey(const ValueKey<String>('cloud-source-selector'));
      expect(tester.getRect(selector).right, lessThan(width));
      expect(tester.getRect(find.byTooltip('更多网盘操作')).right,
          lessThanOrEqualTo(width));
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(sourceName), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('单季选择其他剧目必须确认整剧范围，取消保留原资料', (tester) async {
    final fixture =
        (await tester.runAsync(() => _Fixture.create(renderPosters: true)))!;
    await tester.pumpWidget(
        MaterialApp(home: CloudResourcesPage(controller: fixture.controller)));
    await tester.pump();
    await tester.tap(find.byTooltip('资源操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新刮削本季'));
    await tester.pumpAndSettle();
    final dialog =
        tester.widget<CloudTmdbMatchDialog>(find.byType(CloudTmdbMatchDialog));
    final applying = dialog.onApply(
      TmdbRankedCandidate(
          metadata: _metadata(id: 999),
          score: 1,
          titleMatched: true,
          yearMatched: true,
          typeMatched: true),
      const TmdbScrapeOptions.defaults(),
    );
    final rejected = expectLater(applying, throwsStateError);
    await tester.pumpAndSettle();
    expect(find.text('更换整部剧匹配'), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey<String>('cloud-whole-work-confirmation')),
      matching: find.text('取消'),
    ));
    await tester.pumpAndSettle();
    await rejected;
    expect(fixture.client.seasonCalls, isEmpty);
    expect(
        fixture.controller.collection.groups
            .every((group) => group.workRecord?.metadata?.id == 66732),
        isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('整剧更新失败后重新应用原剧目仍默认只更新本季', (tester) async {
    final fixture =
        (await tester.runAsync(() => _Fixture.create(renderPosters: true)))!;
    await tester.pumpWidget(
        MaterialApp(home: CloudResourcesPage(controller: fixture.controller)));
    await tester.pump();
    await tester.tap(find.byTooltip('资源操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新刮削本季'));
    await tester.pumpAndSettle();
    final dialog =
        tester.widget<CloudTmdbMatchDialog>(find.byType(CloudTmdbMatchDialog));
    TmdbRankedCandidate candidate(int id) => TmdbRankedCandidate(
          metadata: _metadata(id: id),
          score: 1,
          titleMatched: true,
          yearMatched: true,
          typeMatched: true,
        );
    fixture.client.failDetails = true;
    final applying =
        dialog.onApply(candidate(999), const TmdbScrapeOptions.defaults());
    final failed = expectLater(applying, throwsStateError);
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续整剧更新'));
    await tester.runAsync(() => failed);
    await tester.pumpAndSettle();
    fixture.client.failDetails = false;
    await tester.runAsync(() =>
        dialog.onApply(candidate(66732), const TmdbScrapeOptions.defaults()));
    expect(fixture.client.seasonCalls, <int>[1]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

class _Fixture {
  _Fixture(this.root);

  final Directory root;
  final repository =
      CloudWorkTmdbRepository(storage: MemoryCloudWorkTmdbStorage());
  final indexStorage = MemoryCloudMediaIndexStorage();
  late final indexRepository = CloudMediaIndexRepository(storage: indexStorage);
  final client = _Client();
  final downloads = <String>[];
  bool failDownload = false;
  late final CloudResourcesController controller;
  late final CloudWorkTmdbCoordinator coordinator;
  late final CloudMediaTree tree;

  CloudResourceMediaGroup group(int season) => controller.collection.groups
      .singleWhere((group) => group.seasonNumber == season);

  Future<void> refreshSeason(int season,
      {TmdbMetadata? candidate, bool wholeWork = false}) async {
    await controller.applyWorkTmdbCandidate(
      group(season),
      TmdbRankedCandidate(
        metadata: candidate ?? _metadata(),
        score: 1,
        titleMatched: true,
        yearMatched: true,
        typeMatched: true,
      ),
      options: const TmdbScrapeOptions.defaults(),
      wholeWork: wholeWork,
    );
  }

  Future<Map<String, String>> posterFiles() async => <String, String>{
        for (final file in root.listSync(recursive: true).whereType<File>())
          if (file.path.endsWith('.jpg'))
            file.path: base64Encode(await file.readAsBytes()),
      };

  static Future<_Fixture> create(
      {bool separateDirectories = false,
      bool renderPosters = false,
      String sourceName = '测试媒体库'}) async {
    final fixture =
        _Fixture(await Directory.systemTemp.createTemp('cloud-season-scrape-'));
    final imageBytes = renderPosters
        ? await File('assets/images/logo/logo_rounded.png').readAsBytes()
        : null;
    final roots = separateDirectories
        ? <String>[for (var season = 1; season <= 5; season++) '/影视/收藏$season']
        : <String>['/影视'];
    final source = CloudSource(
      id: 'quark-season',
      type: CloudSourceType.quark,
      name: sourceName,
      baseUrl: 'https://pan.quark.cn',
      rootPaths: roots,
      rootRefs: <CloudRemoteRef>[
        for (final path in roots) CloudRemoteRef(id: path, path: path),
      ],
    );
    final directories = <String, List<CloudFileEntry>>{};
    if (separateDirectories) {
      directories['/影视'] = <CloudFileEntry>[
        for (var season = 1; season <= 5; season++)
          _entry('collection-$season', '/影视/收藏$season', directory: true),
      ];
      for (var season = 1; season <= 5; season++) {
        final path = '/影视/收藏$season/怪奇物语';
        directories['/影视/收藏$season'] = <CloudFileEntry>[
          _entry('work-$season', path, directory: true),
        ];
        directories[path] = <CloudFileEntry>[
          _entry('season-$season', '$path/第$season季', directory: true),
        ];
        directories['$path/第$season季'] = <CloudFileEntry>[
          _entry('s${season}e1',
              '$path/第$season季/Stranger.Things.S0${season}E01.mkv'),
        ];
      }
    } else {
      directories['/影视'] = <CloudFileEntry>[
        _entry('work', '/影视/怪奇物语', directory: true),
      ];
      directories['/影视/怪奇物语'] = <CloudFileEntry>[
        for (var season = 1; season <= 5; season++)
          _entry('season-$season', '/影视/怪奇物语/第$season季', directory: true),
      ];
      for (var season = 1; season <= 5; season++) {
        final path = '/影视/怪奇物语/第$season季';
        directories[path] = <CloudFileEntry>[
          _entry('s${season}e1', '$path/Stranger.Things.S0${season}E01.mkv'),
        ];
      }
    }
    fixture.tree = const CloudMediaTreeResolver().resolve(
      sourceId: source.id,
      configuredRoots: source.rootPaths,
      directoryEntries: directories,
      minSizeBytes: 0,
    );
    expect(fixture.tree.works, isNotEmpty);
    final cache = CloudPosterCache(
      cacheRoot: fixture.root,
      downloader: (url) async {
        fixture.downloads.add(url);
        if (fixture.failDownload) throw const SocketException('海报请求失败');
        return imageBytes ?? utf8.encode(url);
      },
    );
    final items = <CloudMediaIndexItem>[];
    for (final work in fixture.tree.works) {
      final ownSeasons =
          work.seasons.map((season) => season.seasonNumber).toSet();
      final seasons = <TmdbSeasonMetadata>[];
      for (var season = 1; season <= 5; season++) {
        final url = ownSeasons.contains(season)
            ? '/old-$season.jpg'
            : '/summary-${work.root.id}-$season.jpg';
        final path = renderPosters
            ? File('assets/images/logo/logo_rounded.png').absolute.path
            : await cache.resolve(
                sourceId: source.id,
                stableId: '${work.workKey}|season:$season',
                url: 'https://image.tmdb.org/t/p/w500$url',
              );
        seasons.add(_season(season, url: url).copyWith(posterCachePath: path));
      }
      await fixture.repository.upsert(CloudWorkTmdbRecord.matched(
        sourceId: source.id,
        workKey: work.workKey,
        workRootId: work.root.id,
        workRootPath: work.root.remotePath,
        remoteName: work.remoteName,
        metadata: _metadata().copyWith(seasons: seasons),
        checkedAt: DateTime.utc(2026, 9, 1),
        tmdbMatchOrigin: TmdbMatchOrigin.manual,
        tmdbRuleVersion: currentTmdbRuleVersion,
      ));
      for (final season in work.seasons) {
        for (final episode in season.episodes) {
          items.add(CloudMediaIndexItem(
            sourceId: source.id,
            remoteId: episode.entry.id,
            remotePath: episode.entry.remotePath,
            name: episode.entry.name,
            workKey: work.workKey,
            workRootId: work.root.id,
            workRootPath: work.root.remotePath,
            size: episode.entry.size,
            modifiedAt: null,
            seriesName: work.displayTitle,
            seasonNumber: season.seasonNumber,
            episodeNumber: episode.episodeNumber,
            mediaType: CloudMediaType.episode,
          ));
        }
      }
    }
    await fixture.indexRepository.replaceSource(
      source.id,
      items,
      const <String, String>{},
      directories,
      source.rootPaths,
    );
    fixture.coordinator = CloudWorkTmdbCoordinator(
      repository: fixture.repository,
      legacyRepository: CloudResourceTmdbRepository(
          storage: MemoryCloudResourceTmdbStorage()),
      indexRepository: fixture.indexRepository,
      serviceFactory: (_) => CloudWorkTmdbService(
        repository: fixture.repository,
        indexRepository: fixture.indexRepository,
        client: fixture.client,
        posterCache: cache,
      ),
      apiKeyProvider: () => 'test-key',
    );
    await fixture.coordinator.loadAndSchedule(fixture.tree);
    final credentials = MemoryCloudCredentialStore();
    final sources = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    await sources.save(source);
    fixture.controller = CloudResourcesController(
      repository: sources,
      credentialStore: credentials,
      mediaIndexRepository: fixture.indexRepository,
      workTmdbRepository: fixture.repository,
      workTmdbCoordinator: fixture.coordinator,
      hiddenVideoRepository:
          CloudHiddenVideoRepository(storage: MemoryCloudHiddenVideoStorage()),
      mediaTagRepository:
          CloudMediaTagRepository(storage: MemoryCloudMediaTagStorage()),
      minRecognizedVideoSizeBytesProvider: () => 0,
    );
    await fixture.controller.ensureLoaded(startScan: false);
    await fixture.coordinator.loadAndSchedule(fixture.tree);
    fixture.downloads.clear();
    addTearDown(() async {
      fixture.controller.dispose();
      fixture.coordinator.dispose();
      await fixture.root.delete(recursive: true);
    });
    expect(fixture.controller.collection.groups, hasLength(5));
    return fixture;
  }
}

CloudFileEntry _entry(String id, String path, {bool directory = false}) =>
    CloudFileEntry(
      id: id,
      remotePath: path,
      name: path.split('/').last,
      size: directory ? 0 : 200,
      modifiedAt: null,
      isDirectory: directory,
    );

TmdbSeasonMetadata _season(int number, {String? url}) => TmdbSeasonMetadata(
      id: 100 + number,
      seasonNumber: number,
      name: '第 $number 季',
      episodeCount: 1,
      posterUrl: url ?? '/new-$number.jpg',
      episodes: <TmdbEpisodeMetadata>[
        TmdbEpisodeMetadata(
            id: 1000 + number, episodeNumber: 1, name: '第 $number 季首集'),
      ],
    );

TmdbMetadata _metadata({int id = 66732}) => TmdbMetadata(
      id: id,
      mediaType: TmdbMediaType.tv,
      title: '怪奇物语',
      overview: '原有整剧简介',
      posterUrl: '/show.jpg',
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 9, 1),
      matchConfidence: 1,
      seasons: <TmdbSeasonMetadata>[
        for (var season = 1; season <= 5; season++) _season(season)
      ],
    );

class _Client implements ITmdbClient, ITmdbClientCapabilities {
  final seasonCalls = <int>[];
  final failSeasons = <int>{};
  final started = Completer<void>();
  Completer<void>? pause;
  bool failDetails = false;

  @override
  Future<TmdbSeasonMetadata> seasonDetails(int id, int seasonNumber,
      {String language = 'zh-CN'}) async {
    seasonCalls.add(seasonNumber);
    if (!started.isCompleted) started.complete();
    await pause?.future;
    if (failSeasons.contains(seasonNumber)) throw StateError('季度请求失败');
    return _season(seasonNumber);
  }

  @override
  Future<TmdbMetadata> details(int id, TmdbMediaType mediaType,
      {String language = 'zh-CN'}) async {
    if (failDetails) throw StateError('剧目请求失败');
    return _metadata(id: id).copyWith(
        title: '新的整剧标题', overview: '新的整剧简介', posterUrl: '/new-show.jpg');
  }

  @override
  Future<List<TmdbMetadata>> search(String query, TmdbMediaType mediaType,
          {String language = 'zh-CN'}) async =>
      <TmdbMetadata>[_metadata()];

  @override
  Future<TmdbSearchPage> searchPage(String query, TmdbMediaType mediaType,
          {String language = 'zh-CN', required int page}) =>
      throw UnimplementedError();

  @override
  Future<List<String>> alternativeTitles(int id, TmdbMediaType mediaType,
          {String language = 'zh-CN'}) async =>
      <String>[];
}
