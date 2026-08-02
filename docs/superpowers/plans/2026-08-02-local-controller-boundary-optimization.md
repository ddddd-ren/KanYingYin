# 本地媒体库控制器边界优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将目录导航、本地索引事务和本地/网盘目录加载从 `LocalController` 提取为可独立测试的应用协调器，同时保持页面 API、MobX 状态和媒体数据语义不变。

**Architecture:** `LocalController` 继续作为页面门面并负责提交 Observable 状态；三个 Coordinator 通过构造注入接收扫描器、Repository 和回调，返回不可变结果。生产依赖只在 `library_bindings.dart` 组合，Controller 不再创建或直接调用 Repository/具体 Service。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular 6、MobX、Hive CE、flutter_test。

---

## 文件结构

- Create: `lib/features/library/application/local_directory_navigation_coordinator.dart` — 目录导航、排序、最近目录和过期结果。
- Create: `lib/features/library/application/local_library_index_coordinator.dart` — 多来源索引、取消、进度和汇总。
- Create: `lib/features/library/application/local_library_catalog_coordinator.dart` — 本地/网盘索引快照和来源刷新。
- Modify: `lib/pages/local/local_controller.dart` — 保留状态与兼容 API，委托三个 Coordinator。
- Modify: `lib/app/bindings/library_bindings.dart` — 组合并注入生产依赖。
- Modify: `test/architecture_dependency_test.dart` — 锁定 Controller 依赖方向。
- Create: 三个对应的 Coordinator 单元测试。

### Task 1: 建立目录导航协调器

**Files:**
- Create: `lib/features/library/application/local_directory_navigation_coordinator.dart`
- Create: `test/local_directory_navigation_coordinator_test.dart`
- Modify: `test/local_controller_test.dart:61-390`

- [ ] **Step 1: 写入失败测试，覆盖过期导航和偏好保存失败降级**

```dart
test('慢目录结果不会覆盖后发导航', () async {
  final first = Completer<LocalScanResult>();
  final scanner = _QueuedScanner([first.future, Future.value(_scan('B'))]);
  final coordinator = LocalDirectoryNavigationCoordinator(
    scanner: scanner,
    preferences: _MemoryPreferences(),
    sourceRepository: _MemorySourceRepository(),
    pathExists: (_) => true,
  );

  final pendingA = coordinator.navigate(
    path: 'A',
    sortMode: LocalSortMode.name,
    ascending: true,
    recentDirectories: const [],
  );
  final resultB = await coordinator.navigate(
    path: 'B',
    sortMode: LocalSortMode.name,
    ascending: true,
    recentDirectories: const ['A'],
  );
  first.complete(_scan('A'));

  expect(await pendingA, isNull);
  expect(resultB?.path, 'B');
  expect(resultB?.recentDirectories, ['B', 'A']);
});

test('保存最近目录失败仍返回扫描结果', () async {
  final coordinator = LocalDirectoryNavigationCoordinator(
    scanner: _QueuedScanner([Future.value(_scan('A'))]),
    preferences: _ThrowingPreferences(),
    sourceRepository: _MemorySourceRepository(),
    pathExists: (_) => true,
  );
  final result = await coordinator.navigate(
    path: 'A',
    sortMode: LocalSortMode.name,
    ascending: true,
    recentDirectories: const [],
  );
  expect(result?.items, hasLength(1));
});
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_directory_navigation_coordinator_test.dart`

Expected: FAIL，提示 `LocalDirectoryNavigationCoordinator` 未定义。

- [ ] **Step 3: 实现强类型结果和代际控制**

```dart
typedef LocalPathExists = bool Function(String path);

final class LocalDirectoryNavigationResult {
  const LocalDirectoryNavigationResult({
    required this.path,
    required this.items,
    required this.skippedCount,
    required this.recentDirectories,
  });

  final String path;
  final List<LocalFileItem> items;
  final int skippedCount;
  final List<String> recentDirectories;
}

final class LocalDirectoryUnavailableException implements Exception {
  const LocalDirectoryUnavailableException(this.path);
  final String path;
}

final class LocalDirectoryNavigationCoordinator {
  LocalDirectoryNavigationCoordinator({
    required ILocalMediaScanner scanner,
    required ILocalLibraryPreferences preferences,
    required ILocalMediaSourceRepository sourceRepository,
    LocalPathExists? pathExists,
  })  : _scanner = scanner,
        _preferences = preferences,
        _sourceRepository = sourceRepository,
        _pathExists =
            pathExists ?? ((path) => Directory(path).existsSync());

  final ILocalMediaScanner _scanner;
  final ILocalLibraryPreferences _preferences;
  final ILocalMediaSourceRepository _sourceRepository;
  final LocalPathExists _pathExists;
  int _generation = 0;

  void invalidate() => _generation++;

  Future<LocalDirectoryNavigationResult?> navigate({
    required String path,
    required LocalSortMode sortMode,
    required bool ascending,
    required List<String> recentDirectories,
  }) async {
    if (!_pathExists(path)) throw LocalDirectoryUnavailableException(path);
    final generation = ++_generation;
    final recent = LocalLibraryPreferences.normalizeRecentDirectories(
      <String>[path, ...recentDirectories],
    );
    try {
      await _preferences.saveLastLocalDirectory(path);
      await _preferences.saveRecentDirectories(recent);
    } on Object catch (error, stackTrace) {
      AppLogger().w('目录偏好保存失败，继续扫描', error: error, stackTrace: stackTrace);
    }
    final scan = await _scanner.scan(
      path,
      sortMode: sortMode,
      ascending: ascending,
    );
    if (generation != _generation) return null;
    try {
      await _sourceRepository.updateScanSummary(
        path: path,
        fileCount: scan.items.length,
        videoCount: scan.items.where((item) => item.isVideo).length,
        directoryCount: scan.items.where((item) => item.isDirectory).length,
        skippedCount: scan.skippedCount,
      );
    } on Object catch (error, stackTrace) {
      AppLogger().w('目录扫描摘要保存失败', error: error, stackTrace: stackTrace);
    }
    return LocalDirectoryNavigationResult(
      path: path,
      items: List<LocalFileItem>.unmodifiable(scan.items),
      skippedCount: scan.skippedCount,
      recentDirectories: List<String>.unmodifiable(recent),
    );
  }
}
```

- [ ] **Step 4: 让 `LocalController.navigateTo/refresh/toggleSort` 委托 Coordinator**

```dart
final LocalDirectoryNavigationCoordinator _navigationCoordinator;

Future<void> navigateTo(String path) async {
  errorMessage = null;
  isLoading = true;
  currentPath = path;
  try {
    final result = await _navigationCoordinator.navigate(
      path: path,
      sortMode: LocalSortMode.fromValue(sortBy),
      ascending: sortAscending,
      recentDirectories: pathHistory,
    );
    if (result == null) return;
    items = ObservableList.of(_applySeriesTitleOverrides(result.items));
    pathHistory = ObservableList.of(result.recentDirectories);
  } on LocalDirectoryUnavailableException {
    errorMessage = '目录不存在: $path';
  } on Object catch (error) {
    errorMessage = '读取目录失败: $error';
  } finally {
    if (currentPath == path) isLoading = false;
  }
}
```

- [ ] **Step 5: 运行目录导航回归**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_directory_navigation_coordinator_test.dart test/local_controller_test.dart`

Expected: PASS，现有过期导航、排序、最近目录和保存失败测试继续通过。

- [ ] **Step 6: 提交**

```powershell
git add lib/features/library/application/local_directory_navigation_coordinator.dart lib/pages/local/local_controller.dart test/local_directory_navigation_coordinator_test.dart test/local_controller_test.dart
git commit -m "重构：提取本地目录导航协调器"
```

### Task 2: 提取本地媒体库索引事务

**Files:**
- Create: `lib/features/library/application/local_library_index_coordinator.dart`
- Create: `test/local_library_index_coordinator_test.dart`
- Modify: `lib/pages/local/local_controller.dart:47-58,829-980,1354-1372`

- [ ] **Step 1: 写入失败测试，覆盖多来源汇总、取消和 Android 文档来源**

```dart
test('按来源汇总索引结果并保存可访问来源摘要', () async {
  final repository = _RecordingSourceRepository();
  final coordinator = LocalLibraryIndexCoordinator(
    indexer: _LocationIndexer(<LocalMediaIndexResult>[
      _result('file', added: 1),
      _result('document', updated: 2),
    ]),
    sourceRepository: repository,
  );
  final result = await coordinator.run(
    sources: [_fileSource(), _documentSource()],
    isSourceAvailable: (_) => true,
    isCancelled: () => false,
  );
  expect(result.sources, 2);
  expect(result.added, 1);
  expect(result.updated, 2);
  expect(repository.updatedLocations, hasLength(2));
});

test('索引取消返回 cancelled 且不继续下一来源', () async {
  var cancelled = false;
  final indexer = _CallbackIndexer(onFirst: () => cancelled = true);
  final result = await LocalLibraryIndexCoordinator(
    indexer: indexer,
    sourceRepository: _RecordingSourceRepository(),
  ).run(
    sources: [_fileSource(), _secondFileSource()],
    isSourceAvailable: (_) => true,
    isCancelled: () => cancelled,
  );
  expect(result.cancelled, isTrue);
  expect(indexer.calls, 1);
});
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_library_index_coordinator_test.dart`

Expected: FAIL，提示协调器和结果类型未定义。

- [ ] **Step 3: 实现不可变汇总结果和来源循环**

```dart
final class LocalLibraryIndexSummary {
  const LocalLibraryIndexSummary({
    required this.sources,
    required this.total,
    required this.added,
    required this.updated,
    required this.reused,
    required this.removed,
    required this.skipped,
    required this.failures,
    required this.cancelled,
    required this.sourceAccessibility,
  });
  final int sources, total, added, updated, reused, removed, skipped;
  final List<LocalMediaIndexFailure> failures;
  final bool cancelled;
  final Map<String, bool> sourceAccessibility;
}

final class LocalLibraryIndexCoordinator {
  const LocalLibraryIndexCoordinator({
    required ILocalMediaIndexer indexer,
    required ILocalMediaSourceRepository sourceRepository,
  })  : _indexer = indexer,
        _sourceRepository = sourceRepository;

  final ILocalMediaIndexer _indexer;
  final ILocalMediaSourceRepository _sourceRepository;

  Future<LocalLibraryIndexSummary> run({
    required List<LocalMediaSource> sources,
    required bool Function(LocalMediaSource) isSourceAvailable,
    required bool Function() isCancelled,
    LocalMediaIndexProgressCallback? onProgress,
  }) async {
    final available = sources
        .where((source) => source.location.isDocument || isSourceAvailable(source))
        .toList(growable: false);
    var total = 0, added = 0, updated = 0, reused = 0, removed = 0, skipped = 0;
    var cancelled = false;
    final failures = <LocalMediaIndexFailure>[];
    final accessibility = <String, bool>{};
    for (final source in available) {
      if (isCancelled()) { cancelled = true; break; }
      final result = await _indexSource(source, isCancelled, onProgress);
      accessibility[source.id] = result.sourceAccessible;
      total += result.totalCount;
      added += result.addedCount;
      updated += result.updatedCount;
      reused += result.reusedCount;
      removed += result.removedCount;
      skipped += result.skippedCount;
      failures.addAll(result.failures);
      if (result.cancelled || isCancelled()) { cancelled = true; break; }
      if (result.sourceAccessible) {
        await _sourceRepository.updateScanSummaryForLocation(
          location: source.location,
          fileCount: result.totalCount,
          videoCount: result.totalCount,
          directoryCount: 0,
          skippedCount: result.skippedCount,
        );
      }
    }
    return LocalLibraryIndexSummary(
      sources: available.length,
      total: total,
      added: added,
      updated: updated,
      reused: reused,
      removed: removed,
      skipped: skipped,
      failures: List<String>.unmodifiable(failures),
      cancelled: cancelled,
      sourceAccessibility: Map<String, bool>.unmodifiable(accessibility),
    );
  }

  Future<LocalMediaIndexResult> _indexSource(
    LocalMediaSource source,
    LocalMediaIndexCancelChecker isCancelled,
    LocalMediaIndexProgressCallback? onProgress,
  ) {
    final locationIndexer = _indexer is ILocalMediaLocationIndexer
        ? _indexer as ILocalMediaLocationIndexer
        : null;
    if (locationIndexer != null) {
      return locationIndexer.indexSourceLocation(
        source.location,
        enrichMediaInfo: true,
        generateThumbnails: true,
        isCancelled: isCancelled,
        onProgress: onProgress,
      );
    }
    if (!source.location.isFile) {
      throw UnsupportedError('当前索引器不支持 Android 文档来源');
    }
    return _indexer.indexSource(
      source.path,
      enrichMediaInfo: true,
      generateThumbnails: true,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );
  }
}
```

- [ ] **Step 4: Controller 映射进度与兼容 Map 返回值**

```dart
final summary = await _indexCoordinator.run(
  sources: mediaSources,
  isSourceAvailable: _sourceCoordinator.isAvailable,
  isCancelled: () => cancelLibraryIndexRequested,
  onProgress: _applyLibraryIndexProgressEvent,
);
_sourceAccessibility.addAll(summary.sourceAccessibility);
libraryIndexFailures
  ..clear()
  ..addAll(summary.failures);
return <String, int>{
  'sources': summary.sources,
  'total': summary.total,
  'added': summary.added,
  'updated': summary.updated,
  'reused': summary.reused,
  'removed': summary.removed,
  'skipped': summary.skipped,
  'failed': summary.failures.length,
  'cancelled': summary.cancelled ? 1 : 0,
};
```

- [ ] **Step 5: 运行索引回归**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_library_index_coordinator_test.dart test/local_controller_test.dart test/local_media_indexer_test.dart test/android_local_media_scan_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交**

```powershell
git add lib/features/library/application/local_library_index_coordinator.dart lib/pages/local/local_controller.dart test/local_library_index_coordinator_test.dart test/local_controller_test.dart
git commit -m "重构：提取本地媒体库索引事务"
```

### Task 3: 提取本地与网盘目录快照

**Files:**
- Create: `lib/features/library/application/local_library_catalog_coordinator.dart`
- Create: `test/local_library_catalog_coordinator_test.dart`
- Modify: `lib/pages/local/local_controller.dart:727-826,1589-1598`

- [ ] **Step 1: 写入失败测试，证明失效网盘根缓存被过滤**

```dart
test('加载网盘快照时只保留当前来源根目录内索引', () async {
  final source = _cloudSource(remoteRoots: [const CloudRemoteRef(id: 'r', path: '/影视')]);
  final coordinator = LocalLibraryCatalogCoordinator(
    localIndexRepository: _LocalIndexRepository([_localItem()]),
    cloudSourceRepository: _CloudSourceRepository([source]),
    cloudIndexRepository: _CloudIndexRepository([
      _cloudItem('/影视/A.mp4'),
      _cloudItem('/旧目录/B.mp4'),
    ]),
  );
  final snapshot = await coordinator.load();
  expect(snapshot.localItems, hasLength(1));
  expect(snapshot.cloudItems.map((item) => item.remotePath), ['/影视/A.mp4']);
});
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_library_catalog_coordinator_test.dart`

Expected: FAIL，提示 `LocalLibraryCatalogCoordinator` 未定义。

- [ ] **Step 3: 实现快照加载和来源刷新**

```dart
final class LocalLibraryCatalogSnapshot {
  const LocalLibraryCatalogSnapshot({
    required this.localItems,
    required this.cloudItems,
    required this.cloudSources,
  });
  final List<LocalMediaIndexItem> localItems;
  final List<CloudMediaIndexItem> cloudItems;
  final List<CloudSource> cloudSources;
}

final class LocalLibraryCatalogCoordinator {
  const LocalLibraryCatalogCoordinator({
    required ILocalMediaIndexRepository localIndexRepository,
    required CloudSourceRepository cloudSourceRepository,
    required CloudMediaIndexRepository cloudIndexRepository,
    Future<void> Function(String sourceId)? scanCloudSource,
  })  : _local = localIndexRepository,
        _sources = cloudSourceRepository,
        _cloud = cloudIndexRepository,
        _scanCloudSource = scanCloudSource;

  final ILocalMediaIndexRepository _local;
  final CloudSourceRepository _sources;
  final CloudMediaIndexRepository _cloud;
  final Future<void> Function(String sourceId)? _scanCloudSource;

  Future<LocalLibraryCatalogSnapshot> load() async {
    final sources = await _sources.getAll();
    final cloudItems = <CloudMediaIndexItem>[];
    for (final source in sources) {
      final items = await _cloud.getBySource(source.id);
      cloudItems.addAll(items.where(
        (item) => CloudSourcePathScope.containsSourcePath(source, item.remotePath),
      ));
    }
    return LocalLibraryCatalogSnapshot(
      localItems: List<LocalMediaIndexItem>.unmodifiable(_local.getAll()),
      cloudItems: List<CloudMediaIndexItem>.unmodifiable(cloudItems),
      cloudSources: List<CloudSource>.unmodifiable(sources),
    );
  }

  Future<LocalLibraryCatalogSnapshot> refreshCloudSource(String sourceId) async {
    final scan = _scanCloudSource;
    if (scan == null) throw StateError('网盘来源扫描器尚未配置');
    await scan(sourceId);
    return load();
  }
}
```

- [ ] **Step 4: Controller 只提交快照和刷新 busy/error 状态**

用 `_applyCatalogSnapshot` 同时替换三个 Observable 集合；`reloadCloudLibraryIndex(throwOnFailure: true)` 继续向上传播异常，非严格路径只记录日志并保留旧快照。

```dart
void _applyCatalogSnapshot(LocalLibraryCatalogSnapshot snapshot) {
  localLibraryItems = ObservableList.of(snapshot.localItems);
  cloudLibraryItems
    ..clear()
    ..addAll(snapshot.cloudItems);
  cloudLibrarySources
    ..clear()
    ..addAll(snapshot.cloudSources);
}
```

- [ ] **Step 5: 运行目录聚合回归**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_library_catalog_coordinator_test.dart test/local_controller_test.dart test/cloud_library_integration_test.dart test/cloud_source_path_scope_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交**

```powershell
git add lib/features/library/application/local_library_catalog_coordinator.dart lib/pages/local/local_controller.dart test/local_library_catalog_coordinator_test.dart test/local_controller_test.dart
git commit -m "重构：提取媒体库目录快照协调器"
```

### Task 4: 收口依赖注入和架构门禁

**Files:**
- Modify: `lib/app/bindings/library_bindings.dart:32-134`
- Modify: `lib/pages/local/local_controller.dart:1-190`
- Modify: `test/architecture_dependency_test.dart`

- [ ] **Step 1: 先添加失败的依赖边界断言**

```dart
test('LocalController 不构造已提取事务的底层实现', () {
  final controller = File(
    '${libDirectory.path}${Platform.pathSeparator}pages'
    '${Platform.pathSeparator}local${Platform.pathSeparator}local_controller.dart',
  );
  final source = controller.readAsStringSync();
  for (final construction in const <String>[
    'LocalMediaScanner(',
    'LocalMediaIndexer(',
    'LocalMediaIndexRepository(',
    'LocalMediaSourceRepository(',
    'CloudMediaIndexRepository(',
    'CloudSourceRepository(',
  ]) {
    expect(source, isNot(contains(construction)), reason: construction);
  }
  expect(source, isNot(contains('Modular.get<')));
});
```

- [ ] **Step 2: 运行架构测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/architecture_dependency_test.dart`

Expected: FAIL，列出 `LocalController` 当前 Repository/Service 导入。

- [ ] **Step 3: 在绑定层创建并注入三个 Coordinator**

```dart
i.addSingleton<LocalDirectoryNavigationCoordinator>(() =>
    LocalDirectoryNavigationCoordinator(
      scanner: Modular.get<LocalMediaScanner>(),
      preferences: Modular.get<ILocalLibraryPreferences>(),
      sourceRepository: Modular.get<ILocalMediaSourceRepository>(),
    ));
i.addSingleton<LocalLibraryIndexCoordinator>(() =>
    LocalLibraryIndexCoordinator(
      indexer: Modular.get<ILocalMediaIndexer>(),
      sourceRepository: Modular.get<ILocalMediaSourceRepository>(),
    ));
i.addSingleton<LocalLibraryCatalogCoordinator>(() =>
    LocalLibraryCatalogCoordinator(
      localIndexRepository: Modular.get<ILocalMediaIndexRepository>(),
      cloudSourceRepository: Modular.get<CloudSourceRepository>(),
      cloudIndexRepository: Modular.get<CloudMediaIndexRepository>(),
      scanCloudSource: (id) => Modular.get<CloudLibraryController>().scanSource(id),
    ));
```

生产 `LocalController` 构造改为 required Coordinator；测试通过显式 fake 注入，不再由 Controller 构造默认 Repository/Service。

- [ ] **Step 4: 运行格式、架构和本地全域测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib/features/library/application lib/pages/local/local_controller.dart lib/app/bindings/library_bindings.dart test/local_*_test.dart test/architecture_dependency_test.dart
D:\flutter\bin\flutter.bat test --no-pub test/architecture_dependency_test.dart test/local_controller_test.dart test/local_media_indexer_test.dart test/local_media_scanner_test.dart test/cloud_library_integration_test.dart
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: 全部 PASS；analyze 输出 `No issues found!`。

- [ ] **Step 5: 提交阶段一**

```powershell
git add lib/features/library/application lib/pages/local/local_controller.dart lib/app/bindings/library_bindings.dart test
git commit -m "重构：完成本地媒体库控制器边界优化"
```
