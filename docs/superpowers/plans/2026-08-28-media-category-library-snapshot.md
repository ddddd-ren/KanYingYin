# Media category library snapshot implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让电影、动漫和电视剧分类页只展示本地媒体库与网盘媒体库已经生成的成品作品，不再自行读取原始索引并重新归并。

**Architecture:** 本地侧复用 `LocalController.localMediaLibrary`。网盘侧由 `CloudResourcesController` 从持久化索引生成与网盘媒体库相同的 `CloudResourceCollection`，再通过一对一适配器输出 `MediaLibrarySeries`；分类运行时只合并两个成品快照。分类刷新只重读快照，不启动本地扫描、网盘扫描或 TMDB 请求。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、MobX、ChangeNotifier、flutter_test

---

## 文件职责

- Create: `lib/pages/cloud/resources/cloud_resource_media_library_adapter.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `lib/app/bindings/cloud_bindings.dart`
- Modify: `lib/features/library/application/media_category_runtime.dart`
- Modify: `lib/features/library/media_category_module.dart`
- Modify: `lib/features/library/presentation/media_category_page.dart`
- Create: `test/cloud_resource_media_library_adapter_test.dart`
- Modify: `test/cloud_resources_controller_test.dart`
- Replace: `test/media_category_hidden_video_state_test.dart` with `test/media_category_runtime_test.dart`
- Modify: `test/media_category_page_test.dart`

计划不修改 `LocalController`、索引器、TMDB 服务、数据库格式、版本号或发布文案。

### Task 1: 将网盘媒体库成品组转换为统一作品

**Files:**

- Create: `lib/pages/cloud/resources/cloud_resource_media_library_adapter.dart`
- Create: `test/cloud_resource_media_library_adapter_test.dart`

- [ ] **Step 1: 编写失败测试，固定一对一转换契约**

构造两个 `CloudMediaIndexItem`，先交给 `CloudResourceCollectionGrouper` 生成一个季度成品组，再断言适配后的作品保持同一个 `stableKey`、展示标题、海报、剧集顺序、字幕引用和远程身份。

```dart
test('网盘成品组转换后保留作品和剧集身份', () {
  final source = _source('quark', '夸克网盘');
  final items = <CloudMediaIndexItem>[
    _episode(source.id, 'e1', '/剧/S01E01.mkv', episode: 1),
    _episode(source.id, 'e2', '/剧/S01E02.mkv', episode: 2),
  ];
  final record = _matchedWorkRecord(source.id, items.first.workKey!);
  final collection = CloudResourceCollectionGrouper().group(
    items: items,
    recordsByWorkKey: <String, CloudWorkTmdbRecord>{
      record.workKey: record,
    },
    query: '',
  );

  final series = const CloudResourceMediaLibraryAdapter().convert(
    source: source,
    collection: collection,
    indexedItems: items,
  );

  expect(series, hasLength(1));
  expect(series.single.key, collection.groups.single.stableKey);
  expect(series.single.title, collection.groups.single.displayName);
  expect(series.single.mediaType, TmdbMediaType.tv);
  expect(series.single.genres, contains('动画'));
  expect(series.single.tmdbPosterUrl, '/season-1.jpg');
  expect(series.single.episodes.map((item) => item.remoteId), <String>[
    'e1',
    'e2',
  ]);
  expect(series.single.episodes.first.subtitleRemoteRefs, isNotEmpty);
  expect(
    series.single.episodes.first.name,
    collection.groups.single.videos.first.name,
  );
});
```

再增加电影多版本测试，确认版本名称和顺序与 `CloudResourceMediaGroup.videos` 完全一致。

- [ ] **Step 2: 运行测试并确认失败**

Run:

```powershell
D:/flutter/bin/flutter.bat test test/cloud_resource_media_library_adapter_test.dart
```

Expected: FAIL，提示 `CloudResourceMediaLibraryAdapter` 不存在。

- [ ] **Step 3: 实现纯转换器**

创建以下公开 API：

```dart
class CloudResourceMediaLibraryAdapter {
  const CloudResourceMediaLibraryAdapter();

  List<MediaLibrarySeries> convert({
    required CloudSource source,
    required CloudResourceCollection collection,
    required Iterable<CloudMediaIndexItem> indexedItems,
  });
}
```

转换规则如下：

- `MediaLibrarySeries.key` 使用 `group.stableKey`
- `seriesKey` 使用 `group.workKey`
- `title` 使用 `group.displayName`
- 来源字段使用传入的 `CloudSource`
- 媒体类型依次使用作品 TMDB、旧资源 TMDB、`group.isSeries`
- 类型标签依次使用作品 TMDB、旧资源 TMDB、索引项 `tmdbGenres`
- 季度海报优先于作品海报
- 剧集按 `group.videos` 当前顺序转换，不再次排序
- 剧集名称使用 `CloudFileEntry.name`，不再次解析
- 字幕、远程身份、季集号和发布标签从对应索引项复制
- 找不到索引项时使用 `CloudFileEntry` 的远程身份，字幕列表为空

关键转换代码：

```dart
return MediaLibrarySeries(
  key: group.stableKey,
  seriesKey: group.workKey,
  title: group.displayName,
  sourceKind: MediaSourceKind.cloud,
  sourceId: source.id,
  sourceName: source.name,
  isAvailable: source.enabled,
  mediaType: metadata?.mediaType ??
      legacy?.mediaType ??
      (group.isSeries ? TmdbMediaType.tv : TmdbMediaType.movie),
  genres: List<String>.unmodifiable(genres),
  tmdbTitle: metadata?.title ?? legacy?.title ?? firstItem?.tmdbTitle,
  tmdbOverview:
      metadata?.overview ?? legacy?.overview ?? firstItem?.tmdbOverview,
  tmdbRating: metadata?.rating ?? legacy?.rating ?? firstItem?.tmdbRating,
  tmdbReleaseDate: metadata?.releaseDate ?? legacy?.releaseDate,
  tmdbPosterUrl: posterUrl,
  posterCachePath: posterCachePath,
  episodes: group.videos.map((video) {
    final item = indexedByRemoteId[video.id];
    return MediaLibraryEpisode.cloud(
      stableId: video.id,
      name: video.name,
      sourceId: source.id,
      sourceName: source.name,
      isAvailable: source.enabled,
      remoteId: video.id,
      remotePath: video.remotePath,
      tmdbTitle: metadata?.title ?? legacy?.title ?? item?.tmdbTitle,
      tmdbOriginalTitle: metadata?.originalTitle ??
          legacy?.originalTitle ??
          item?.tmdbOriginalTitle,
      tmdbOverview:
          metadata?.overview ?? legacy?.overview ?? item?.tmdbOverview,
      tmdbRating: metadata?.rating ?? legacy?.rating ?? item?.tmdbRating,
      tmdbPosterUrl: posterUrl ?? item?.tmdbPosterUrl,
      tmdbBackdropUrl: metadata?.backdropUrl ??
          legacy?.backdropUrl ??
          item?.tmdbBackdropUrl,
      posterCachePath: posterCachePath ?? item?.posterCachePath,
      size: video.size,
      modifiedAt: video.modifiedAt,
      seasonNumber: video.seasonNumber ?? item?.seasonNumber,
      episodeNumber: video.episodeNumber ?? item?.episodeNumber,
      subtitleRemotePaths: item?.subtitlePaths ?? const <String>[],
      subtitleRemoteRefs: item?.subtitleRefs ?? const <CloudRemoteRef>[],
      releaseTags: video.releaseTags,
    );
  }).toList(growable: false),
);
```

- [ ] **Step 4: 运行适配器测试**

Run:

```powershell
D:/flutter/bin/flutter.bat test test/cloud_resource_media_library_adapter_test.dart
```

Expected: PASS。

### Task 2: 让网盘控制器输出全来源只读成品快照

**Files:**

- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `lib/app/bindings/cloud_bindings.dart`
- Modify: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1: 编写失败测试，证明快照不扫描来源**

使用两个启用来源和内存索引创建控制器，不调用 `load()` 或 `refresh()`，直接读取分类快照：

```dart
test('分类快照读取全部启用来源且不访问网盘客户端', () async {
  final fixture = await _Fixture.create(
    sources: <CloudSource>[
      _source('source-a', '夸克网盘'),
      _source('source-b', 'OpenList'),
    ],
    clients: <String, _FakeCloudClient>{
      'source-a': _FakeCloudClient(),
      'source-b': _FakeCloudClient(),
    },
    indexedItems: <CloudMediaIndexItem>[
      _scopedCloudEpisode('source-a', 'a1', '/影视/A/S01E01.mkv', '作品 A'),
      _scopedCloudEpisode('source-b', 'b1', '/影视/B/S01E01.mkv', '作品 B'),
    ],
  );

  await fixture.controller.reloadMediaLibrarySnapshot();

  expect(
    fixture.controller.mediaLibrarySnapshot.series
        .map((series) => series.sourceId)
        .toSet(),
    <String>{'source-a', 'source-b'},
  );
  expect(fixture.clients['source-a']!.listed, isEmpty);
  expect(fixture.clients['source-b']!.listed, isEmpty);
});
```

增加以下测试：

- 隐藏记录在分组前过滤
- 一个来源读取失败时保留该来源上次成功结果
- 来源被禁用或删除后清除对应结果和筛选项
- 当前网盘页 `collection.groups` 与成品快照的 `key`、标题和远程 ID 相同

- [ ] **Step 2: 运行目标测试并确认失败**

Run:

```powershell
D:/flutter/bin/flutter.bat test test/cloud_resources_controller_test.dart --plain-name "分类快照"
```

Expected: FAIL，提示快照 API 不存在。

- [ ] **Step 3: 注入现有作品记录仓储并增加快照状态**

构造函数增加可选参数，现有测试夹具无需全部修改：

```dart
CloudWorkTmdbRepository? workTmdbRepository,
CloudResourceMediaLibraryAdapter? mediaLibraryAdapter,
```

增加字段和只读 getter：

```dart
final CloudWorkTmdbRepository? _workTmdbRepository;
final CloudResourceMediaLibraryAdapter _mediaLibraryAdapter;
final Map<String, List<MediaLibrarySeries>> _mediaLibrarySeriesBySource =
    <String, List<MediaLibrarySeries>>{};
List<CloudSource> _mediaLibrarySources = const <CloudSource>[];

CloudMediaLibrary get mediaLibrarySnapshot {
  return CloudMediaLibrary(
    series: <MediaLibrarySeries>[
      for (final source in _mediaLibrarySources)
        ...?_mediaLibrarySeriesBySource[source.id],
    ],
    filters: <MediaLibrarySourceFilter>[
      const MediaLibrarySourceFilter('all', '全部', null),
      for (final source in _mediaLibrarySources)
        MediaLibrarySourceFilter(
          source.id,
          source.name,
          MediaSourceKind.cloud,
        ),
    ],
  );
}
```

在 `cloud_bindings.dart` 传入现有仓储：

```dart
workTmdbRepository: Modular.get<CloudWorkTmdbRepository>(),
```

- [ ] **Step 4: 实现无扫描的全来源刷新**

`reloadMediaLibrarySnapshot()` 只读取来源、索引、隐藏记录和作品记录仓储。每个来源执行以下顺序：

1. `CloudMediaIndexRepository.snapshot`
2. `CloudSourcePathScope.containsSourcePath`
3. 隐藏记录过滤
4. `CloudMediaTreeResolver.resolve`
5. `CloudResourceCollectionGrouper.group`
6. Task 1 的一对一转换器

方法骨架：

```dart
Future<void> reloadMediaLibrarySnapshot() async {
  final enabledSources = (await _repository.getAll())
      .where((source) => source.enabled)
      .toList(growable: false);
  final records = await _workTmdbRepository?.getAll() ??
      workTmdbRecords.values.toList(growable: false);
  final nextIds = enabledSources.map((source) => source.id).toSet();
  _mediaLibrarySources = enabledSources;

  for (final source in enabledSources) {
    try {
      final snapshot = await _mediaIndexRepository.snapshot(source.id);
      final hidden = await _hiddenVideoRepository.getBySource(source.id);
      final items = snapshot.items.where((item) {
        final inScope = CloudSourcePathScope.containsSourcePath(
          source,
          item.remotePath,
        );
        final isHidden = hidden.any((record) => record.matches(
              sourceId: item.sourceId,
              remoteId: item.remoteId,
              remotePath: item.remotePath,
            ));
        return inScope && !isHidden;
      }).toList(growable: false);
      final tree = _mediaTreeResolver.resolve(
        sourceId: source.id,
        configuredRoots:
            source.remoteRoots.map((root) => root.path).toList(growable: false),
        directoryEntries: snapshot.directoryEntries,
        minSizeBytes: _minRecognizedVideoSizeBytesProvider(),
      );
      final sourceRecords = <String, CloudWorkTmdbRecord>{
        for (final record in records)
          if (record.sourceId == source.id) record.workKey: record,
      };
      final collection = _collectionGrouper.group(
        items: items,
        works: tree.works,
        recordsByWorkKey: sourceRecords,
        query: '',
      );
      _mediaLibrarySeriesBySource[source.id] =
          _mediaLibraryAdapter.convert(
        source: source,
        collection: collection,
        indexedItems: items,
      );
    } on Object catch (error, stackTrace) {
      AppLogger().w(
        'CloudResourcesController: failed to load media library snapshot '
        'sourceId=${source.id}',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
  _mediaLibrarySeriesBySource.removeWhere(
    (sourceId, _) => !nextIds.contains(sourceId),
  );
  _notify();
}
```

异常分支不清除已存在的来源结果。首次失败时该来源保持空结果。

该方法不得修改 `sources`、`selectedSource`、`entries`、查询条件或目录范围。分类刷新不能改变网盘媒体库页面的当前状态。

- [ ] **Step 5: 同步当前网盘页的成品变化**

抽取同步 helper，使用 `_indexedItems`、`_works`、隐藏记录和 `workTmdbRecords` 更新当前来源。以下路径成功后调用：

- `_loadSnapshot`
- `_handleTmdbChange`
- `hideVideos`
- `restoreHiddenVideo`
- `restoreAllHiddenVideos`

helper 不读取当前 `query`、`selectedGenres` 或 `currentDirectoryScope`，避免把界面临时筛选写进分类快照。

- [ ] **Step 6: 统一分类页隐藏操作**

增加 `hideMediaLibraryEpisodes(Iterable<MediaLibraryEpisode>)`。它按来源合并现有 `CloudHiddenVideo`，调用同一个 `_hiddenVideoRepository.replaceSource`，然后重读成品快照。

```dart
Future<void> hideMediaLibraryEpisodes(
  Iterable<MediaLibraryEpisode> episodes,
) async {
  final bySource = <String, List<MediaLibraryEpisode>>{};
  for (final episode in episodes) {
    if (episode.sourceKind != MediaSourceKind.cloud ||
        episode.remoteId == null ||
        episode.remotePath == null) {
      throw ArgumentError.value(episode, 'episodes', '隐藏项必须是有效的网盘视频');
    }
    bySource.putIfAbsent(episode.sourceId, () => []).add(episode);
  }
  for (final entry in bySource.entries) {
    final records = <String, CloudHiddenVideo>{
      for (final record in await _hiddenVideoRepository.getBySource(entry.key))
        record.identityKey: record,
    };
    for (final episode in entry.value) {
      final record = CloudHiddenVideo(
        sourceId: entry.key,
        remoteId: episode.remoteId!,
        remotePath: normalizeCloudHiddenVideoPath(episode.remotePath!),
        fileName: episode.name,
      );
      records[record.identityKey] = record;
    }
    await _hiddenVideoRepository.replaceSource(
      entry.key,
      records.values.toList(growable: false),
    );
  }
  await reloadMediaLibrarySnapshot();
}
```

- [ ] **Step 7: 运行网盘回归测试**

Run:

```powershell
D:/flutter/bin/flutter.bat test test/cloud_resources_controller_test.dart
D:/flutter/bin/flutter.bat test test/cloud_resources_custom_tags_test.dart
D:/flutter/bin/flutter.bat test test/cloud_resources_page_test.dart
```

Expected: PASS。

### Task 3: 分类运行时只合并两个成品快照

**Files:**

- Modify: `lib/features/library/application/media_category_runtime.dart`
- Modify: `lib/features/library/media_category_module.dart`
- Replace: `test/media_category_hidden_video_state_test.dart` with `test/media_category_runtime_test.dart`

- [ ] **Step 1: 编写失败测试**

为运行时注入固定网盘成品快照，断言初始化只刷新一次快照，并把本地作品与网盘作品按原 `key` 合并。隐藏测试断言只调用注入的网盘隐藏回调；provider 内容变化后，`runtime.library` 立即读取新结果。

```dart
test('分类运行时合并本地和网盘成品快照', () async {
  var cloudLoads = 0;
  final runtime = MediaCategoryRuntime(
    localController: localController,
    videoController: videoController,
    refreshCloudLibrary: () async {
      cloudLoads++;
    },
    cloudLibraryProvider: () => cloudLibrary,
    hideCloudEpisodes: (_) async {},
    settings: settings,
    navigateToPlayer: () async {},
  );

  await runtime.initialize();

  expect(cloudLoads, 1);
  expect(runtime.library.series.map((item) => item.key), <String>[
    localSeries.key,
    cloudSeries.key,
  ]);
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```powershell
D:/flutter/bin/flutter.bat test test/media_category_runtime_test.dart
```

Expected: FAIL，提示 `refreshCloudLibrary` 或 `cloudLibraryProvider` 不存在。

- [ ] **Step 3: 删除第二套聚合职责并合并成品快照**

删除以下依赖和状态：

- `CloudWorkTmdbRepository`
- `ICloudHiddenVideoRepository`
- `_workRecords`
- `MediaCategoryHiddenVideoState`
- `CloudMediaLibraryAggregator().build`

增加以下 API：

```dart
typedef MediaCategoryCloudLibraryRefresh = Future<void> Function();
typedef MediaCategoryCloudLibraryProvider = CloudMediaLibrary Function();
typedef MediaCategoryCloudHideAction = Future<void> Function(
  Iterable<MediaLibraryEpisode> episodes,
);
```

初始化和 getter 改为：

```dart
Future<void> initialize() async {
  _localController.reloadLocalLibraryIndex();
  await _refreshCloudLibrary();
}

CloudMediaLibrary get library {
  final local = _localController.localMediaLibrary;
  final cloud = _cloudLibraryProvider();
  return CloudMediaLibrary(
    series: <MediaLibrarySeries>[
      ...local.series,
      ...cloud.series,
    ],
    filters: <MediaLibrarySourceFilter>[
      const MediaLibrarySourceFilter('all', '全部', null),
      const MediaLibrarySourceFilter(
        'local',
        '本地',
        MediaSourceKind.local,
      ),
      ...cloud.filters.where((item) => item.id != 'all'),
    ],
  );
}
```

`hideEpisodes` 只调用 `_hideCloudEpisodes`。网盘控制器完成仓储写入和快照刷新后，provider 会返回新结果。播放逻辑保持不变。

- [ ] **Step 4: 更新模块接线**

模块获取同一个 `CloudResourcesController` 单例：

```dart
final cloudController = Modular.get<CloudResourcesController>();
final runtime = MediaCategoryRuntime(
  localController: Modular.get<LocalController>(),
  videoController: Modular.get<LocalVideoController>(),
  refreshCloudLibrary: cloudController.reloadMediaLibrarySnapshot,
  cloudLibraryProvider: () => cloudController.mediaLibrarySnapshot,
  hideCloudEpisodes: cloudController.hideMediaLibraryEpisodes,
  settings: Modular.get<TypedSettings>(),
  navigateToPlayer: () async {
    await Modular.to.pushNamed('/video/');
  },
);
```

删除模块中作品记录仓储和隐藏仓储对分类运行时的注入。

- [ ] **Step 5: 运行分类运行时与查询测试**

Run:

```powershell
D:/flutter/bin/flutter.bat test test/media_category_runtime_test.dart
D:/flutter/bin/flutter.bat test test/media_library_query_test.dart
```

Expected: PASS。

### Task 4: 让已打开的分类页响应网盘快照通知

**Files:**

- Modify: `lib/features/library/presentation/media_category_page.dart`
- Modify: `lib/features/library/media_category_module.dart`
- Modify: `test/media_category_page_test.dart`

- [ ] **Step 1: 编写失败 Widget 测试**

```dart
testWidgets('网盘成品快照通知后分类页更新', (tester) async {
  final notifier = ChangeNotifier();
  var library = _library(<MediaLibrarySeries>[]);
  await tester.pumpWidget(MaterialApp(
    home: MediaCategoryPage(
      category: MediaLibraryCategory.movie,
      initialize: () async {},
      libraryProvider: () => library,
      libraryListenable: notifier,
      onPlayEpisode: (_, __) async {},
      observeLibrary: false,
    ),
  ));
  await tester.pumpAndSettle();

  library = _library(<MediaLibrarySeries>[_movie('新增电影')]);
  notifier.notifyListeners();
  await tester.pump();

  expect(find.text('新增电影'), findsOneWidget);
});
```

- [ ] **Step 2: 运行测试并确认失败**

Run:

```powershell
D:/flutter/bin/flutter.bat test test/media_category_page_test.dart --plain-name "网盘成品快照通知后分类页更新"
```

Expected: FAIL，提示 `libraryListenable` 不存在。

- [ ] **Step 3: 添加可选 Listenable 监听**

为 `MediaCategoryPage` 增加 `final Listenable? libraryListenable`。在 `build` 中使用 `ListenableBuilder` 包裹现有 `Observer`：

```dart
@override
Widget build(BuildContext context) {
  Widget content() => widget.observeLibrary
      ? Observer(builder: (_) => _buildContent())
      : _buildContent();
  final listenable = widget.libraryListenable;
  final body = listenable == null
      ? content()
      : ListenableBuilder(
          listenable: listenable,
          builder: (_, __) => content(),
        );
  return Scaffold(body: SafeArea(child: body));
}
```

模块传入 `libraryListenable: cloudController`。没有监听器的现有测试保持原行为。

- [ ] **Step 4: 运行分类页测试**

Run:

```powershell
D:/flutter/bin/flutter.bat test test/media_category_page_test.dart
```

Expected: PASS，且没有布局溢出或异步残留异常。

### Task 5: 对抗式审查与完整验证

**Files:**

- Review only: 本计划涉及的业务文件和测试文件

- [ ] **Step 1: 确认分类路径不再引用原始聚合器**

Run:

```powershell
rg -n "CloudMediaLibraryAggregator|localLibraryItems|cloudLibraryItems|CloudWorkTmdbRepository|MediaCategoryHiddenVideoState" lib/features/library
```

Expected: 分类运行时和模块无匹配。

- [ ] **Step 2: 确认刷新路径没有扫描和 TMDB 调用**

核对 `reloadMediaLibrarySnapshot` 调用图。该方法不得调用：

- `CloudMediaIndexer.scan`
- `CloudProviderRegistry.createClient`
- `CloudWorkTmdbCoordinator.loadAndSchedule`
- `TmdbClient`
- `LocalController.refreshLocalLibraryIndex`

- [ ] **Step 3: 运行定向测试**

Run:

```powershell
D:/flutter/bin/flutter.bat test test/cloud_resource_media_library_adapter_test.dart
D:/flutter/bin/flutter.bat test test/cloud_resources_controller_test.dart
D:/flutter/bin/flutter.bat test test/media_category_runtime_test.dart
D:/flutter/bin/flutter.bat test test/media_category_page_test.dart
D:/flutter/bin/flutter.bat test test/media_library_query_test.dart
```

Expected: 全部 PASS。

- [ ] **Step 4: 运行完整质量门槛**

Run:

```powershell
D:/flutter/bin/flutter.bat test
D:/flutter/bin/flutter.bat analyze
D:/flutter/bin/flutter.bat build windows --release
```

Expected:

- `flutter test` 全部通过
- `flutter analyze` 无 error
- Windows Release 构建成功

- [ ] **Step 5: 检查工作区边界**

Run:

```powershell
git diff --check
git status --short
git diff -- lib/features/library lib/pages/cloud/resources lib/app/bindings/cloud_bindings.dart test/cloud_resource_media_library_adapter_test.dart test/cloud_resources_controller_test.dart test/media_category_runtime_test.dart test/media_category_page_test.dart
```

Expected: 无空白错误，只包含本轮目标文件。保留工作区已有的版本、历史页、播放器、索引同步和发布文件修改。

本计划不执行 `git commit`。版本更新、Inno Setup 安装程序和桌面复制属于实现与完整验证通过后的独立交付阶段。
