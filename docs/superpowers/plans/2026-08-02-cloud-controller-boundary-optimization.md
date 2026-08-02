# 网盘资源控制器边界优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将来源快照、扫描事务和隐藏记录持久化从 `CloudResourcesController` 提取为独立协调器，保持四种网盘、TMDB、目录范围和播放行为不变。

**Architecture:** Controller 继续作为 ChangeNotifier 页面门面；Snapshot/Scan/Hidden Coordinator 返回不可变结果并通过进度事件沟通。现有 `CloudMediaIndexer`、TMDB Coordinator、自动整理器和分组器继续复用，生产实例统一在 `cloud_bindings.dart` 组合。

**Tech Stack:** Flutter 3.41.9、Dart、ChangeNotifier、Flutter Modular、Hive CE、OpenList/夸克/百度/迅雷服务、flutter_test。

---

## 文件结构

- Create: `lib/features/cloud/application/cloud_resource_snapshot_coordinator.dart`
- Create: `lib/features/cloud/application/cloud_resource_scan_coordinator.dart`
- Create: `lib/features/cloud/application/cloud_hidden_video_coordinator.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `lib/app/bindings/cloud_bindings.dart`
- Modify: `test/architecture_dependency_test.dart`
- Create: 三个 Coordinator 单元测试。

### Task 1: 提取隐藏记录事务

**Files:**
- Create: `lib/features/cloud/application/cloud_hidden_video_coordinator.dart`
- Create: `test/cloud_hidden_video_coordinator_test.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart:333-388,1071-1105`

- [ ] **Step 1: 写入失败测试，证明写入失败不改变快照**

```dart
test('隐藏记录写入失败时保留原快照', () async {
  final original = [_hidden('old')];
  final coordinator = CloudHiddenVideoCoordinator(
    repository: _ThrowingHiddenRepository(original),
  );
  await expectLater(
    coordinator.hide(
      sourceId: 'source',
      current: original,
      videos: [_entry('new')],
    ),
    throwsStateError,
  );
  expect(original.map((item) => item.remoteId), ['old']);
});

test('恢复全部记录只提交仓储成功后的空快照', () async {
  final repository = _MemoryHiddenRepository([_hidden('a'), _hidden('b')]);
  final result = await CloudHiddenVideoCoordinator(repository: repository)
      .restoreAll(sourceId: 'source', current: await repository.getBySource('source'));
  expect(result, isEmpty);
  expect(await repository.getBySource('source'), isEmpty);
});
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_hidden_video_coordinator_test.dart`

Expected: FAIL，提示 Coordinator 未定义。

- [ ] **Step 3: 实现事务式隐藏、恢复和全部恢复**

```dart
final class CloudHiddenVideoCoordinator {
  const CloudHiddenVideoCoordinator({
    required ICloudHiddenVideoRepository repository,
  }) : _repository = repository;

  final ICloudHiddenVideoRepository _repository;

  Future<List<CloudHiddenVideo>> hide({
    required String sourceId,
    required List<CloudHiddenVideo> current,
    required Iterable<CloudFileEntry> videos,
  }) async {
    final next = <String, CloudHiddenVideo>{
      for (final item in current) item.identityKey: item,
    };
    for (final video in videos) {
      final record = CloudHiddenVideo.fromEntry(sourceId: sourceId, entry: video);
      next[record.identityKey] = record;
    }
    final snapshot = List<CloudHiddenVideo>.unmodifiable(next.values);
    await _repository.replaceSource(sourceId, snapshot);
    return snapshot;
  }

  Future<List<CloudHiddenVideo>> restore({
    required String sourceId,
    required List<CloudHiddenVideo> current,
    required CloudHiddenVideo record,
  }) async {
    final snapshot = current
        .where((item) => item.identityKey != record.identityKey)
        .toList(growable: false);
    await _repository.replaceSource(sourceId, snapshot);
    return List<CloudHiddenVideo>.unmodifiable(snapshot);
  }

  Future<List<CloudHiddenVideo>> restoreAll({
    required String sourceId,
    required List<CloudHiddenVideo> current,
  }) async {
    if (current.isEmpty) return const <CloudHiddenVideo>[];
    await _repository.clearSource(sourceId);
    return const <CloudHiddenVideo>[];
  }
}
```

- [ ] **Step 4: Controller 委托并仅在成功后替换 `_hiddenVideos`**

```dart
final next = await _hiddenVideoCoordinator.hide(
  sourceId: source.id,
  current: _hiddenVideos,
  videos: videos,
);
_hiddenVideos = next;
_invalidateCollection();
_notify();
```

- [ ] **Step 5: 运行隐藏记录回归并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_hidden_video_coordinator_test.dart test/cloud_hidden_video_repository_test.dart test/cloud_resources_controller_test.dart`

Expected: PASS。

```powershell
git add lib/features/cloud/application/cloud_hidden_video_coordinator.dart lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_hidden_video_coordinator_test.dart test/cloud_resources_controller_test.dart
git commit -m "重构：提取网盘隐藏记录协调器"
```

### Task 2: 提取来源与索引快照

**Files:**
- Create: `lib/features/cloud/application/cloud_resource_snapshot_coordinator.dart`
- Create: `test/cloud_resource_snapshot_coordinator_test.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart:389-585`

- [ ] **Step 1: 写入失败测试，覆盖首选来源、根目录过滤和旧请求失效**

```dart
test('优先选择指定可用来源并过滤旧根目录索引', () async {
  final slow = Completer<List<CloudSource>>();
  final coordinator = CloudResourceSnapshotCoordinator(
    sourceRepository: _QueuedSourceRepository([slow.future, Future.value([_source('b')])]),
    mediaIndexRepository: _IndexRepository([
      _item(sourceId: 'b', path: '/新根/A.mp4'),
      _item(sourceId: 'b', path: '/旧根/B.mp4'),
    ]),
    hiddenRepository: _MemoryHiddenRepository(const []),
  );
  final old = coordinator.load(preferredSourceId: 'a');
  final current = await coordinator.load(preferredSourceId: 'b');
  slow.complete([_source('a')]);
  expect(await old, isNull);
  expect(current?.selectedSource?.id, 'b');
  expect(current?.indexedItems.values.map((item) => item.remotePath), ['/新根/A.mp4']);
});
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_resource_snapshot_coordinator_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现 generation 与不可变快照**

```dart
final class CloudResourceSnapshot {
  const CloudResourceSnapshot({
    required this.sources,
    required this.selectedSource,
    required this.indexedItems,
    required this.hiddenVideos,
  });
  final List<CloudSource> sources;
  final CloudSource? selectedSource;
  final Map<String, CloudMediaIndexItem> indexedItems;
  final List<CloudHiddenVideo> hiddenVideos;
}

final class CloudResourceSnapshotCoordinator {
  CloudResourceSnapshotCoordinator({
    required CloudSourceRepository sourceRepository,
    required CloudMediaIndexRepository mediaIndexRepository,
    required ICloudHiddenVideoRepository hiddenRepository,
  })  : _sources = sourceRepository,
        _index = mediaIndexRepository,
        _hidden = hiddenRepository;

  final CloudSourceRepository _sources;
  final CloudMediaIndexRepository _index;
  final ICloudHiddenVideoRepository _hidden;
  int _generation = 0;

  void invalidate() => _generation++;

  Future<CloudResourceSnapshot?> load({
    String? preferredSourceId,
    String? currentSourceId,
  }) async {
    final generation = ++_generation;
    final sources = (await _sources.getAll())
        .where((source) => source.enabled)
        .toList(growable: false);
    final selected = _selectSource(sources, preferredSourceId, currentSourceId);
    final items = selected == null
        ? const <CloudMediaIndexItem>[]
        : await _index.getBySource(selected.id);
    final filtered = <String, CloudMediaIndexItem>{
      for (final item in items)
        if (CloudSourcePathScope.containsSourcePath(selected!, item.remotePath))
          item.id: item,
    };
    final hidden = selected == null
        ? const <CloudHiddenVideo>[]
        : await _hidden.getBySource(selected.id);
    if (generation != _generation) return null;
    return CloudResourceSnapshot(
      sources: List<CloudSource>.unmodifiable(sources),
      selectedSource: selected,
      indexedItems: Map<String, CloudMediaIndexItem>.unmodifiable(filtered),
      hiddenVideos: List<CloudHiddenVideo>.unmodifiable(hidden),
    );
  }
}
```

`_selectSource` 顺序固定为：有效的 `preferredSourceId`、仍有效的 `currentSourceId`、第一个启用来源、`null`。

- [ ] **Step 4: Controller 用单一 `_applySnapshot` 提交状态**

```dart
void _applySnapshot(CloudResourceSnapshot snapshot) {
  sources = snapshot.sources;
  selectedSource = snapshot.selectedSource;
  _indexedItems
    ..clear()
    ..addAll(snapshot.indexedItems);
  _hiddenVideos = snapshot.hiddenVideos;
  _invalidateDirectoryScopeTree();
  _invalidateCollection();
  _reconcileDirectoryScope();
}
```

- [ ] **Step 5: 运行来源快照回归并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_resource_snapshot_coordinator_test.dart test/cloud_resources_controller_test.dart test/cloud_resources_derived_cache_test.dart`

Expected: PASS。

```powershell
git add lib/features/cloud/application/cloud_resource_snapshot_coordinator.dart lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_resource_snapshot_coordinator_test.dart test/cloud_resources_controller_test.dart
git commit -m "重构：提取网盘资源快照协调器"
```

### Task 3: 提取扫描事务和进度

**Files:**
- Create: `lib/features/cloud/application/cloud_resource_scan_coordinator.dart`
- Create: `test/cloud_resource_scan_coordinator_test.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart:586-649,922-1039`

- [ ] **Step 1: 写入失败测试，覆盖取消、异常和 dispose 后结果**

```dart
test('取消扫描后清理活动状态且不返回提交结果', () async {
  final token = CloudScanCancellationToken();
  final coordinator = CloudResourceScanCoordinator(
    indexer: _BlockingIndexer(),
    clientFactory: (_) => _FakeCloudDriveClient(),
  );
  final pending = coordinator.scan(source: _source('a'), token: token);
  token.cancel();
  final result = await pending;
  expect(result.cancelled, isTrue);
  expect(coordinator.isScanning, isFalse);
});

test('同一协调器拒绝并行扫描', () async {
  final coordinator = CloudResourceScanCoordinator(
    indexer: _BlockingIndexer(),
    clientFactory: (_) => _FakeCloudDriveClient(),
  );
  final first = coordinator.scan(source: _source('a'));
  await expectLater(coordinator.scan(source: _source('a')), throwsStateError);
  await coordinator.cancel();
  await first;
});
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_resource_scan_coordinator_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现扫描事务结果和 `finally` 清理**

```dart
final class CloudResourceScanSummary {
  const CloudResourceScanSummary({
    required this.cancelled,
    required this.scannedDirectories,
  });
  final bool cancelled;
  final int scannedDirectories;
}

final class CloudResourceScanCoordinator {
  CloudResourceScanCoordinator({
    required CloudMediaIndexer indexer,
    required CloudDriveClient Function(CloudSource source) clientFactory,
  })  : _indexer = indexer,
        _clientFactory = clientFactory;
  final CloudMediaIndexer _indexer;
  final CloudDriveClient Function(CloudSource source) _clientFactory;
  Future<CloudResourceScanSummary>? _active;
  CloudScanCancellationToken? _token;

  bool get isScanning => _active != null;
  Future<void> cancel() async {
    _token?.cancel();
    final active = _active;
    if (active != null) await active;
  }

  Future<CloudResourceScanSummary> scan({
    required CloudSource source,
    CloudScanCancellationToken? token,
    void Function(CloudMediaIndexProgress progress)? onProgress,
  }) {
    if (_active != null) throw StateError('网盘来源正在扫描');
    _token = token ?? CloudScanCancellationToken();
    final future = _run(source, _token!, onProgress);
    _active = future;
    return future.whenComplete(() {
      _active = null;
      _token = null;
    });
  }

  Future<CloudResourceScanSummary> _run(
    CloudSource source,
    CloudScanCancellationToken token,
    void Function(CloudMediaScanProgress progress)? onProgress,
  ) async {
    final client = _clientFactory(source);
    try {
      final result = await _indexer.scan(
        source: source,
        client: client,
        cancellationToken: token,
        onProgress: onProgress,
      );
      return CloudResourceScanSummary(
        cancelled: result.cancelled,
        scannedDirectories: result.scanned,
      );
    } finally {
      await client.close();
    }
  }
}
```

- [ ] **Step 4: Controller 负责 busy/error 字段，Coordinator 负责事务**

```dart
scanning = true;
errorMessage = null;
try {
  final result = await _scanCoordinator.scan(
    source: source,
    token: _scanToken,
    onProgress: _applyScanProgress,
  );
  if (!_isCurrent(generation) || result.cancelled) return;
  final snapshot = await _snapshotCoordinator.load(currentSourceId: source.id);
  if (snapshot != null && _isCurrent(generation)) _applySnapshot(snapshot);
} finally {
  if (_isCurrent(generation)) {
    scanning = false;
    currentScanPath = null;
    _notify();
  }
}
```

- [ ] **Step 5: 运行扫描和自动整理回归并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_resource_scan_coordinator_test.dart test/cloud_resources_controller_test.dart test/cloud_media_indexer_test.dart test/cloud_resources_flat_library_test.dart`

Expected: PASS。

```powershell
git add lib/features/cloud/application/cloud_resource_scan_coordinator.dart lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_resource_scan_coordinator_test.dart test/cloud_resources_controller_test.dart
git commit -m "重构：提取网盘资源扫描事务"
```

### Task 4: 组合依赖并锁定架构

**Files:**
- Modify: `lib/app/bindings/cloud_bindings.dart:27-122`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart:1-155`
- Modify: `test/architecture_dependency_test.dart`

- [ ] **Step 1: 添加失败架构测试**

```dart
test('CloudResourcesController 不构造已提取事务的底层实现', () {
  final controller = File(
    '${libDirectory.path}${Platform.pathSeparator}pages'
    '${Platform.pathSeparator}cloud${Platform.pathSeparator}resources'
    '${Platform.pathSeparator}cloud_resources_controller.dart',
  );
  final source = controller.readAsStringSync();
  for (final construction in const <String>[
    'CloudHiddenVideoRepository(',
    'CloudMediaIndexRepository(',
    'CloudMediaIndexer(',
    'CloudProviderRegistry(',
  ]) {
    expect(source, isNot(contains(construction)), reason: construction);
  }
  expect(source, isNot(contains('Modular.get<')));
});
```

- [ ] **Step 2: 运行架构测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/architecture_dependency_test.dart`

Expected: FAIL。

- [ ] **Step 3: 在 `cloud_bindings.dart` 注册三个 Coordinator 并改为 required 注入**

```dart
i.addSingleton<CloudHiddenVideoCoordinator>(() => CloudHiddenVideoCoordinator(
  repository: Modular.get<CloudHiddenVideoRepository>(),
));
i.addSingleton<CloudResourceSnapshotCoordinator>(() =>
    CloudResourceSnapshotCoordinator(
      sourceRepository: Modular.get<CloudSourceRepository>(),
      mediaIndexRepository: Modular.get<CloudMediaIndexRepository>(),
      hiddenRepository: Modular.get<CloudHiddenVideoRepository>(),
    ));
i.addSingleton<CloudResourceScanCoordinator>(() => CloudResourceScanCoordinator(
  indexer: Modular.get<CloudMediaIndexer>(),
  clientFactory: (source) => Modular.get<CloudProviderRegistry>().createClient(
    source,
    Modular.get<CloudCredentialStore>(),
  ),
));
```

- [ ] **Step 4: 运行网盘全域测试、分析并提交阶段二**

```powershell
D:\flutter\bin\dart.bat format lib/features/cloud/application lib/pages/cloud/resources/cloud_resources_controller.dart lib/app/bindings/cloud_bindings.dart test/cloud_*_test.dart test/architecture_dependency_test.dart
D:\flutter\bin\flutter.bat test --no-pub test/architecture_dependency_test.dart test/cloud_library_controller_test.dart test/cloud_resources_controller_test.dart test/cloud_media_indexer_test.dart test/cloud_library_integration_test.dart
D:\flutter\bin\flutter.bat analyze --no-pub
git add lib/features/cloud/application lib/pages/cloud/resources/cloud_resources_controller.dart lib/app/bindings/cloud_bindings.dart test
git commit -m "重构：完成网盘资源控制器边界优化"
```

Expected: 测试 PASS，analyze 为 `No issues found!`。
