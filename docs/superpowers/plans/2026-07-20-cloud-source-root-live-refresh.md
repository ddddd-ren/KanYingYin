# 网盘来源目录变更实时刷新实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保存 OpenList 或夸克媒体根目录后，立即隐藏旧目录缓存、只扫描变化来源一次、同步刷新本地与网盘海报墙，并交付 2.1.23 签名 MSIX。

**Architecture:** 用纯 Dart 的 `CloudSourcePathScope` 统一路径边界和来源根选择比较；本地与网盘控制器在聚合前过滤缓存索引。`CloudSourceRootRefreshCoordinator` 以回调注入两个刷新入口和单一扫描入口，确保扫描前后都刷新视图且失败不回滚新配置；编辑页只负责检测变化、忙碌状态和错误提示。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、MobX、flutter_test、Windows Release、msix 3.18.0、PowerShell。

---

## 文件结构

- `lib/services/cloud/cloud_source_path_scope.dart`：规范网盘路径、判断严格根目录边界、比较 OpenList/夸克根选择。
- `lib/services/cloud/cloud_source_root_refresh_coordinator.dart`：顺序执行双视图过滤刷新、单次来源扫描和扫描后重载，聚合失败。
- `lib/pages/local/local_controller.dart`：加载网盘索引时按来源最新根目录过滤。
- `lib/pages/cloud/resources/cloud_resources_controller.dart`：过滤快照，并提供不会自动扫描的 `reloadSourcesAndSnapshot()`。
- `lib/pages/cloud/openlist_source_editor.dart`：根目录变化后触发刷新回调并展示更新状态。
- `lib/pages/cloud/quark/quark_source_editor.dart`：根目录或夸克远程 ID 变化后触发刷新回调并展示更新状态。
- `lib/pages/index_module.dart`：注册刷新协调器及其三个生产回调。
- `lib/pages/settings/settings_module.dart`：向两个来源编辑器注入统一刷新回调。
- `test/cloud_source_path_scope_test.dart`：覆盖规范化、`/A` 与 `/AB`、空根和夸克远程 ID。
- `test/local_controller_test.dart`：覆盖本地海报墙读取旧快照时立即隐藏旧根资源。
- `test/cloud_resources_controller_test.dart`：覆盖网盘海报墙过滤旧快照、空集合不回退和无扫描重载。
- `test/cloud_source_root_refresh_coordinator_test.dart`：覆盖调用顺序、单次扫描、失败后仍重载。
- `test/cloud_sources_ui_test.dart`、`test/quark_source_editor_test.dart`：覆盖编辑页变化检测、忙碌状态和错误提示。
- `test/navigation_config_test.dart`：锁定生产依赖注入和两个编辑路由使用同一协调器。
- `pubspec.yaml`、`lib/core/app_version.dart`：更新应用和 MSIX 版本。
- `README.md`、`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`lib/utils/version_history.dart`：更新普通用户可见文案。
- `test/version_consistency_test.dart`、`test/version_history_current_test.dart`、`test/identity_v2_zero_residue_test.dart`：锁定 2.1.23 版本契约。

### Task 1: 用纯函数测试锁定目录范围与变化语义

**Files:**
- Create: `test/cloud_source_path_scope_test.dart`
- Create: `lib/services/cloud/cloud_source_path_scope.dart`

- [ ] **Step 1: 写入路径范围失败测试**

创建测试，明确普通根目录、根路径、空根和格式归一化：

~~~dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_source_path_scope.dart';

void main() {
  group('CloudSourcePathScope', () {
    test('使用严格路径边界且空根不匹配任何缓存', () {
      expect(CloudSourcePathScope.normalizePath(r'A\\Season 01\\'), '/A/Season 01');
      expect(
        CloudSourcePathScope.containsPath(
          roots: const <String>['/A'],
          path: '/A/file.mkv',
        ),
        isTrue,
      );
      expect(
        CloudSourcePathScope.containsPath(
          roots: const <String>['/A'],
          path: '/AB/file.mkv',
        ),
        isFalse,
      );
      expect(
        CloudSourcePathScope.containsPath(
          roots: const <String>['/'],
          path: '/AB/file.mkv',
        ),
        isTrue,
      );
      expect(
        CloudSourcePathScope.containsPath(
          roots: const <String>[],
          path: '/A/file.mkv',
        ),
        isFalse,
      );
      expect(
        CloudSourcePathScope.containsPath(
          roots: const <String>['/'],
          path: '',
        ),
        isFalse,
      );
      expect(
        CloudSourcePathScope.containsPath(
          roots: const <String>[''],
          path: '/A/file.mkv',
        ),
        isFalse,
      );
    });

    test('OpenList 忽略根顺序与分隔符差异', () {
      const previous = CloudSource(
        id: 'openlist',
        type: CloudSourceType.openList,
        name: '家庭网盘',
        baseUrl: 'https://drive.example.com',
        rootPaths: <String>['/A/', r'\\B'],
      );
      const current = CloudSource(
        id: 'openlist',
        type: CloudSourceType.openList,
        name: '新名称',
        baseUrl: 'https://drive.example.com',
        rootPaths: <String>['/B', '/A', '/A'],
      );

      expect(
        CloudSourcePathScope.hasRootSelectionChanged(previous, current),
        isFalse,
      );
    });

    test('夸克同路径远程 ID 变化仍触发更新', () {
      const previous = CloudSource(
        id: 'quark',
        type: CloudSourceType.quark,
        name: '夸克网盘',
        baseUrl: 'https://pan.quark.cn',
        rootPaths: <String>['/影视'],
        rootRefs: <CloudRemoteRef>[
          CloudRemoteRef(id: 'old-fid', path: '/影视'),
        ],
      );
      const current = CloudSource(
        id: 'quark',
        type: CloudSourceType.quark,
        name: '夸克网盘',
        baseUrl: 'https://pan.quark.cn',
        rootPaths: <String>['/影视'],
        rootRefs: <CloudRemoteRef>[
          CloudRemoteRef(id: 'new-fid', path: '/影视'),
        ],
      );

      expect(
        CloudSourcePathScope.hasRootSelectionChanged(previous, current),
        isTrue,
      );
    });
  });
}
~~~

- [ ] **Step 2: 运行测试并确认缺少服务**

Run:

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/cloud_source_path_scope_test.dart
~~~

Expected: FAIL；`cloud_source_path_scope.dart` 不存在。

- [ ] **Step 3: 实现最小纯函数服务**

~~~dart
import 'package:kanyingyin/modules/cloud/cloud_source.dart';

abstract final class CloudSourcePathScope {
  static String normalizePath(String path) {
    var normalized = path.trim().replaceAll('\\', '/');
    normalized = normalized.replaceAll(RegExp(r'/+'), '/');
    if (normalized.isEmpty) return '/';
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static bool containsPath({
    required Iterable<String> roots,
    required String path,
  }) {
    if (path.trim().isEmpty) return false;
    final normalizedPath = normalizePath(path);
    final normalizedRoots = roots
        .where((root) => root.trim().isNotEmpty)
        .map(normalizePath)
        .toSet();
    if (normalizedRoots.isEmpty) return false;
    return normalizedRoots.any(
      (root) =>
          root == '/' ||
          normalizedPath == root ||
          normalizedPath.startsWith('$root/'),
    );
  }

  static bool containsSourcePath(CloudSource source, String path) =>
      containsPath(
        roots: source.remoteRoots.map((root) => root.path),
        path: path,
      );

  static bool hasRootSelectionChanged(
    CloudSource? previous,
    CloudSource current,
  ) {
    if (previous == null) return current.remoteRoots.isNotEmpty;
    if (previous.type != current.type) return true;
    return !_rootIdentities(previous).containsAll(_rootIdentities(current)) ||
        !_rootIdentities(current).containsAll(_rootIdentities(previous));
  }

  static Set<String> _rootIdentities(CloudSource source) => source.remoteRoots
      .map((root) {
        final path = normalizePath(root.path);
        if (source.type == CloudSourceType.openList) return path;
        final id = root.id.trim();
        return id.isEmpty ? path : '$id|$path';
      })
      .toSet();
}
~~~

- [ ] **Step 4: 运行、格式化并提交**

~~~powershell
D:/flutter/bin/dart.bat format lib/services/cloud/cloud_source_path_scope.dart test/cloud_source_path_scope_test.dart
D:/flutter/bin/flutter.bat test --no-pub test/cloud_source_path_scope_test.dart
git diff --check
git add -- lib/services/cloud/cloud_source_path_scope.dart test/cloud_source_path_scope_test.dart
git commit -m "统一网盘目录路径边界"
~~~

Expected: 测试 PASS，提交只包含路径范围服务和测试。

### Task 2: 本地媒体库在读取缓存时隐藏旧根资源

**Files:**
- Modify: `test/local_controller_test.dart`
- Modify: `lib/pages/local/local_controller.dart`

- [ ] **Step 1: 写入旧快照过滤回归测试**

~~~dart
test('网盘根目录变化后本地媒体库立即过滤旧缓存和播放目标', () async {
  const source = CloudSource(
    id: 'cloud-scope',
    type: CloudSourceType.openList,
    name: '家庭网盘',
    baseUrl: 'https://drive.example.com',
    rootPaths: <String>['/B'],
  );
  final sourceRepository = CloudSourceRepository(
    storage: MemoryCloudSourceStorage(),
    credentialStore: MemoryCloudCredentialStore(),
  );
  await sourceRepository.save(source);
  final indexRepository = CloudMediaIndexRepository(
    storage: MemoryCloudMediaIndexStorage(),
  );
  await indexRepository.replaceSource(
    source.id,
    <CloudMediaIndexItem>[
      _scopedEpisode(source.id, 'old-id', '/A/旧剧/S01E01.mkv', '旧剧'),
      _scopedEpisode(source.id, 'new-id', '/B/新剧/S01E01.mkv', '新剧'),
    ],
    const <String, String>{},
    const <String, List<CloudFileEntry>>{},
    const <String>['/A'],
  );
  final controller = LocalController(
    cloudSourceRepository: sourceRepository,
    cloudMediaIndexRepository: indexRepository,
  );

  await controller.reloadCloudLibraryIndex(throwOnFailure: true);

  expect(controller.cloudLibraryItems.map((item) => item.remoteId), <String>['new-id']);
  expect(
    controller.combinedMediaLibrary.series
        .expand((series) => series.episodes)
        .map((episode) => episode.remoteId),
    isNot(contains('old-id')),
  );
  expect(await indexRepository.getBySource(source.id), hasLength(2));
}

CloudMediaIndexItem _scopedEpisode(
  String sourceId,
  String remoteId,
  String remotePath,
  String seriesName,
) =>
    CloudMediaIndexItem(
      sourceId: sourceId,
      remoteId: remoteId,
      remotePath: remotePath,
      name: 'S01E01.mkv',
      workKey: '$sourceId|$seriesName',
      workRootId: seriesName,
      workRootPath: remotePath.substring(0, remotePath.lastIndexOf('/')),
      size: 1024,
      modifiedAt: DateTime(2026, 7, 20),
      seriesName: seriesName,
      seasonNumber: 1,
      episodeNumber: 1,
      mediaType: CloudMediaType.episode,
    );
~~~

- [ ] **Step 2: 运行测试并确认旧条目仍存在**

Run:

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/local_controller_test.dart --plain-name "网盘根目录变化后本地媒体库立即过滤旧缓存和播放目标"
~~~

Expected: FAIL；当前 `reloadCloudLibraryIndex()` 把 `/A` 与 `/B` 两条缓存都加入媒体库。

- [ ] **Step 3: 在聚合前按来源配置过滤**

在 `local_controller.dart` 导入 `cloud_source_path_scope.dart`，把循环改为：

~~~dart
for (final source in sources) {
  final sourceItems =
      await _cloudMediaIndexRepository.getBySource(source.id);
  items.addAll(
    sourceItems.where(
      (item) => CloudSourcePathScope.containsSourcePath(
        source,
        item.remotePath,
      ),
    ),
  );
}
~~~

- [ ] **Step 4: 运行相关测试并提交**

~~~powershell
D:/flutter/bin/dart.bat format lib/pages/local/local_controller.dart test/local_controller_test.dart
D:/flutter/bin/flutter.bat test --no-pub test/local_controller_test.dart test/cloud_library_integration_test.dart
git diff --check
git add -- lib/pages/local/local_controller.dart test/local_controller_test.dart
git commit -m "过滤本地媒体库旧网盘目录"
~~~

Expected: PASS；过滤只影响应用内索引可见性，不修改仓储快照。

### Task 3: 网盘海报墙增加无扫描重载并过滤旧快照

**Files:**
- Modify: `test/cloud_resources_controller_test.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`

- [ ] **Step 1: 写入无扫描快照过滤测试**

测试直接建立根目录为 `/B` 的来源和同时含 `/A`、`/B` 条目的旧快照，调用新入口，不配置可用云客户端：

~~~dart
test('无扫描重载按最新根目录过滤旧快照且不回退旧作品', () async {
  final credentials = MemoryCloudCredentialStore();
  final sourceRepository = CloudSourceRepository(
    storage: MemoryCloudSourceStorage(),
    credentialStore: credentials,
  );
  const source = CloudSource(
    id: 'scope-source',
    type: CloudSourceType.openList,
    name: '家庭网盘',
    baseUrl: 'https://drive.example.com',
    rootPaths: <String>['/B'],
  );
  await sourceRepository.save(source);
  final indexRepository = CloudMediaIndexRepository(
    storage: MemoryCloudMediaIndexStorage(),
  );
  await indexRepository.replaceSource(
    source.id,
    <CloudMediaIndexItem>[
      _scopedEpisode('scope-source', 'old-id', '/A/旧剧/S01E01.mkv', '旧剧'),
      _scopedEpisode('scope-source', 'new-id', '/B/新剧/S01E01.mkv', '新剧'),
    ],
    const <String, String>{},
    const <String, List<CloudFileEntry>>{},
    const <String>['/A'],
  );
  final controller = CloudResourcesController(
    repository: sourceRepository,
    credentialStore: credentials,
    mediaIndexRepository: indexRepository,
  );

  await controller.reloadSourcesAndSnapshot();

  expect(controller.entries.map((entry) => entry.id), <String>['new-id']);
  expect(
    controller.collection.groups
        .expand((group) => group.videos)
        .map((entry) => entry.id),
    isNot(contains('old-id')),
  );
  expect(controller.scanning, isFalse);
  controller.dispose();
}

CloudMediaIndexItem _scopedEpisode(
  String sourceId,
  String remoteId,
  String remotePath,
  String seriesName,
) =>
    CloudMediaIndexItem(
      sourceId: sourceId,
      remoteId: remoteId,
      remotePath: remotePath,
      name: 'S01E01.mkv',
      workKey: '$sourceId|$seriesName',
      workRootId: seriesName,
      workRootPath: remotePath.substring(0, remotePath.lastIndexOf('/')),
      size: 1024,
      modifiedAt: DateTime(2026, 7, 20),
      seriesName: seriesName,
      seasonNumber: 1,
      episodeNumber: 1,
      mediaType: CloudMediaType.episode,
    );
~~~

再增加空根测试：把来源 `rootPaths` 设为空、快照保留旧条目，断言 `entries`、`works` 和 `collection.groups` 全部为空。

- [ ] **Step 2: 运行测试并确认入口不存在**

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/cloud_resources_controller_test.dart --plain-name "无扫描重载按最新根目录过滤旧快照且不回退旧作品"
~~~

Expected: FAIL；`reloadSourcesAndSnapshot()` 尚未定义。

- [ ] **Step 3: 分离可选扫描的数据加载流程**

把现有 `load()` 与 `selectSource()` 的主体提取为带私有开关的实现：

~~~dart
Future<void> load() => _loadSources(startScan: true);

Future<void> reloadSourcesAndSnapshot() async {
  _scanToken?.cancel();
  await scanCompletion;
  await _loadSources(startScan: false);
}

Future<void> _loadSources({required bool startScan}) async {
  final generation = ++_generation;
  _scanToken?.cancel();
  loading = true;
  errorMessage = null;
  _notify();
  try {
    final loadedSources = (await _repository.getAll())
        .where((source) => source.enabled)
        .toList(growable: false);
    if (!_isCurrent(generation)) return;
    sources = loadedSources;
    final currentId = selectedSource?.id;
    final nextId = loadedSources.any((source) => source.id == currentId)
        ? currentId
        : loadedSources.firstOrNull?.id;
    await _selectSource(nextId, startScan: startScan);
  } on Object {
    sources = <CloudSource>[];
    selectedSource = null;
    currentDirectory = null;
    entries = <CloudFileEntry>[];
    _indexedItems.clear();
    _works = <CloudWorkIdentity>[];
    _mediaTree = null;
    loading = false;
    errorMessage = '网盘来源加载失败';
    _notify();
  }
}

Future<void> selectSource(String? sourceId) =>
    _selectSource(sourceId, startScan: true);

Future<void> _selectSource(
  String? sourceId, {
  required bool startScan,
}) async {
  final generation = ++_generation;
  _scanToken?.cancel();
  query = '';
  entries = <CloudFileEntry>[];
  _indexedItems.clear();
  _works = <CloudWorkIdentity>[];
  _mediaTree = null;
  currentDirectory = null;
  isVirtualRoot = false;
  errorMessage = null;
  selectedSource = sourceId == null
      ? null
      : sources.where((source) => source.id == sourceId).firstOrNull;
  final source = selectedSource;
  if (source == null) {
    loading = false;
    scanning = false;
    _notify();
    return;
  }
  if (source.remoteRoots.isEmpty) {
    loading = false;
    errorMessage = '该来源还没有配置媒体根目录';
    _notify();
    return;
  }
  loading = true;
  _notify();
  await _loadSnapshot(source, generation);
  if (!_isCurrent(generation)) return;
  loading = false;
  _notify();
  _scheduleTmdb(source, entries);
  if (startScan) {
    _startScan(source, generation);
  }
}
~~~

`reloadSourcesAndSnapshot()` 必须等待被取消的页面后台扫描真正结束，避免随后统一扫描命中 `CloudScanInProgressException`。

- [ ] **Step 4: 在写入集合前过滤索引条目**

~~~dart
final scopedItems = snapshot.items
    .where(
      (item) => CloudSourcePathScope.containsSourcePath(
        source,
        item.remotePath,
      ),
    )
    .toList(growable: false);
_indexedItems
  ..clear()
  ..addEntries(
    scopedItems.map(
      (item) => MapEntry(_resourceKeyForItem(item), item),
    ),
  );
entries = scopedItems
    .map(
      (item) => CloudFileEntry(
        id: item.remoteId,
        remotePath: item.remotePath,
        name: item.name,
        size: item.size,
        modifiedAt: item.modifiedAt,
        isDirectory: false,
      ),
    )
    .toList(growable: false);
~~~

- [ ] **Step 5: 运行相关控制器测试并提交**

~~~powershell
D:/flutter/bin/dart.bat format lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_resources_controller_test.dart
D:/flutter/bin/flutter.bat test --no-pub test/cloud_resources_controller_test.dart test/cloud_resources_flat_library_test.dart
git diff --check
git add -- lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_resources_controller_test.dart
git commit -m "实时过滤网盘海报墙旧缓存"
~~~

Expected: PASS；普通 `load()` 仍会自动扫描，`reloadSourcesAndSnapshot()` 只读取配置与快照。

### Task 4: 用协调器保证单次扫描和失败后的安全刷新

**Files:**
- Create: `test/cloud_source_root_refresh_coordinator_test.dart`
- Create: `lib/services/cloud/cloud_source_root_refresh_coordinator.dart`

- [ ] **Step 1: 写入顺序与失败行为测试**

~~~dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';
import 'package:kanyingyin/services/cloud/cloud_source_root_refresh_coordinator.dart';

void main() {
  test('按双刷新单次扫描双刷新的顺序更新来源', () async {
    final calls = <String>[];
    final coordinator = CloudSourceRootRefreshCoordinator(
      reloadLocalLibrary: () async => calls.add('local'),
      reloadCloudResources: () async => calls.add('cloud'),
      scanSource: (sourceId) async {
        calls.add('scan:$sourceId');
        return const CloudMediaScanResult(
          scanned: 1,
          skipped: 0,
          failures: 0,
          failedPaths: <String>[],
          cancelled: false,
        );
      },
    );

    await coordinator.refreshSource('source-a');

    expect(calls, <String>[
      'local',
      'cloud',
      'scan:source-a',
      'local',
      'cloud',
    ]);
  });

  test('扫描失败后仍执行两次后置重载并统一抛错', () async {
    final calls = <String>[];
    final coordinator = CloudSourceRootRefreshCoordinator(
      reloadLocalLibrary: () async => calls.add('local'),
      reloadCloudResources: () async => calls.add('cloud'),
      scanSource: (_) async {
        calls.add('scan');
        return const CloudMediaScanResult(
          scanned: 1,
          skipped: 0,
          failures: 1,
          failedPaths: <String>['/B'],
          cancelled: false,
        );
      },
    );

    await expectLater(
      coordinator.refreshSource('source-a'),
      throwsA(isA<CloudSourceRootRefreshException>()),
    );
    expect(calls, <String>['local', 'cloud', 'scan', 'local', 'cloud']);
  });
}
~~~

再增加前置本地刷新抛错测试，断言网盘前置刷新、扫描和两个后置刷新仍被调用，最终异常保留第一个原因。

- [ ] **Step 2: 运行测试并确认服务不存在**

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/cloud_source_root_refresh_coordinator_test.dart
~~~

Expected: FAIL；协调器和异常类型尚未定义。

- [ ] **Step 3: 实现协调器和结构化异常**

~~~dart
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';

typedef CloudLibraryReload = Future<void> Function();
typedef CloudSourceScan = Future<CloudMediaScanResult> Function(String sourceId);

final class CloudSourceRootRefreshException implements Exception {
  const CloudSourceRootRefreshException(this.cause);
  final Object cause;

  @override
  String toString() => '目录已保存，但媒体库更新失败：$cause';
}

final class CloudSourceRootRefreshCoordinator {
  const CloudSourceRootRefreshCoordinator({
    required CloudLibraryReload reloadLocalLibrary,
    required CloudLibraryReload reloadCloudResources,
    required CloudSourceScan scanSource,
  })  : _reloadLocalLibrary = reloadLocalLibrary,
        _reloadCloudResources = reloadCloudResources,
        _scanSource = scanSource;

  final CloudLibraryReload _reloadLocalLibrary;
  final CloudLibraryReload _reloadCloudResources;
  final CloudSourceScan _scanSource;

  Future<void> refreshSource(String sourceId) async {
    Object? firstError;

    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } on Object catch (error) {
        firstError ??= error;
      }
    }

    await attempt(_reloadLocalLibrary);
    await attempt(_reloadCloudResources);
    await attempt(() async {
      final result = await _scanSource(sourceId);
      if (result.cancelled || result.failures > 0) {
        throw StateError('网盘媒体扫描未完整完成');
      }
    });
    await attempt(_reloadLocalLibrary);
    await attempt(_reloadCloudResources);

    if (firstError != null) {
      throw CloudSourceRootRefreshException(firstError!);
    }
  }
}
~~~

- [ ] **Step 4: 运行、格式化并提交**

~~~powershell
D:/flutter/bin/dart.bat format lib/services/cloud/cloud_source_root_refresh_coordinator.dart test/cloud_source_root_refresh_coordinator_test.dart
D:/flutter/bin/flutter.bat test --no-pub test/cloud_source_root_refresh_coordinator_test.dart
git diff --check
git add -- lib/services/cloud/cloud_source_root_refresh_coordinator.dart test/cloud_source_root_refresh_coordinator_test.dart
git commit -m "协调网盘目录单次扫描刷新"
~~~

Expected: PASS；任一阶段失败都不会阻止后续安全重载，且一次保存只调用一次扫描。

### Task 5: 编辑页接入变化回调、忙碌提示和生产依赖

**Files:**
- Modify: `test/cloud_sources_ui_test.dart`
- Modify: `test/quark_source_editor_test.dart`
- Modify: `test/navigation_config_test.dart`
- Modify: `lib/pages/cloud/openlist_source_editor.dart`
- Modify: `lib/pages/cloud/quark/quark_source_editor.dart`
- Modify: `lib/pages/index_module.dart`
- Modify: `lib/pages/settings/settings_module.dart`

- [ ] **Step 1: 写入 OpenList 回调和忙碌测试**

在现有“选择并保存多个扫描目录”测试中传入回调并断言来源 ID 只记录一次。另建 Completer 测试：

~~~dart
final refreshStarted = Completer<void>();
final releaseRefresh = Completer<void>();
await tester.pumpWidget(MaterialApp(
  home: OpenListSourceEditorPage(
    source: source,
    controller: controller,
    onRootSelectionChanged: (sourceId) async {
      refreshStarted.complete();
      await releaseRefresh.future;
    },
  ),
));
await tester.pumpAndSettle();
await tester.tap(find.text('选择扫描目录'));
await tester.pumpAndSettle();
await tester.tap(find.byKey(const ValueKey<String>('select-/电影')));
await tester.tap(find.text('确定'));
await tester.pumpAndSettle();
await tester.tap(find.text('保存'));
await refreshStarted.future;
await tester.pump();
expect(find.text('正在更新媒体库'), findsOneWidget);
expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
releaseRefresh.complete();
await tester.pumpAndSettle();
~~~

增加目录不变测试，修改名称后保存，断言回调次数为 0：

~~~dart
var refreshCount = 0;
await tester.pumpWidget(MaterialApp(
  home: OpenListSourceEditorPage(
    source: source,
    controller: controller,
    onRootSelectionChanged: (_) async => refreshCount++,
  ),
));
await tester.enterText(
  find.widgetWithText(TextFormField, '名称'),
  '仅修改来源名称',
);
await tester.tap(find.text('保存'));
await tester.pumpAndSettle();
expect(refreshCount, 0);
expect((await repository.getById(source.id))?.name, '仅修改来源名称');
~~~

- [ ] **Step 2: 写入夸克远程 ID 变化测试和失败提示测试**

使用夸克假客户端让目录选择页返回 `CloudRemoteRef(id: 'new-fid', path: '/影视')`，初始来源为同路径 `old-fid`。保存后断言回调收到来源 ID 一次。让回调抛出 `CloudSourceRootRefreshException(StateError('scan failed'))`，断言：

~~~dart
expect(
  find.text('目录已保存，但媒体库更新失败，请稍后手动重试'),
  findsOneWidget,
);
expect((await repository.getById(source.id))?.rootRefs.single.id, 'new-fid');
~~~

- [ ] **Step 3: 运行编辑器测试并确认失败**

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/cloud_sources_ui_test.dart test/quark_source_editor_test.dart
~~~

Expected: FAIL；编辑器没有 `onRootSelectionChanged`，也没有独立媒体库更新状态。

- [ ] **Step 4: 为两个编辑器实现相同的保存状态机**

两个 Widget 增加：

~~~dart
final Future<void> Function(String sourceId)? onRootSelectionChanged;
~~~

State 增加：

~~~dart
bool _updatingLibrary = false;
bool get _busy => _controller.saving || _updatingLibrary;
~~~

OpenList 的 `_save()` 使用现有表单凭据并在持久化前计算变化：

~~~dart
final rootsChanged = CloudSourcePathScope.hasRootSelectionChanged(
  widget.source,
  source,
);
await _controller.save(
  source,
  credential:
      _usernameController.text.isEmpty && _passwordController.text.isEmpty
          ? null
          : _credential,
);
if (!mounted) return;
if (rootsChanged && widget.onRootSelectionChanged != null) {
  setState(() => _updatingLibrary = true);
  try {
    await widget.onRootSelectionChanged!(source.id);
  } on Object {
    if (!mounted) return;
    _showMessage('目录已保存，但媒体库更新失败，请稍后手动重试');
    return;
  } finally {
    if (mounted) setState(() => _updatingLibrary = false);
  }
}
if (mounted) Navigator.of(context).maybePop();
~~~

夸克的 `_save()` 保留 Cookie 的两项现有校验，随后使用同一状态机：

~~~dart
final rootsChanged = CloudSourcePathScope.hasRootSelectionChanged(
  widget.source,
  source,
);
await _controller.save(source, credential: _formCredential);
if (!mounted) return;
if (rootsChanged && widget.onRootSelectionChanged != null) {
  setState(() => _updatingLibrary = true);
  try {
    await widget.onRootSelectionChanged!(source.id);
  } on Object {
    if (!mounted) return;
    _showMessage('目录已保存，但媒体库更新失败，请稍后手动重试');
    return;
  } finally {
    if (mounted) setState(() => _updatingLibrary = false);
  }
}
if (mounted) Navigator.of(context).maybePop();
~~~

保存按钮和目录选择按钮使用 `_busy` 禁用；保存按钮文案为：

~~~dart
label: Text(_updatingLibrary ? '正在更新媒体库' : '保存'),
~~~

OpenList 增加与夸克一致的 `_showMessage` 私有方法。所有异步 UI 操作保留 `mounted` 检查。

- [ ] **Step 5: 注册协调器并注入两个编辑路由**

在 `IndexModule` 的控制器单例之后注册：

~~~dart
i.addSingleton<CloudSourceRootRefreshCoordinator>(
  () => CloudSourceRootRefreshCoordinator(
    reloadLocalLibrary: () =>
        Modular.get<LocalController>().reloadCloudLibraryIndex(
          throwOnFailure: true,
        ),
    reloadCloudResources: () =>
        Modular.get<CloudResourcesController>().reloadSourcesAndSnapshot(),
    scanSource: (sourceId) =>
        Modular.get<CloudLibraryController>().scanSource(sourceId),
  ),
);
~~~

在 `SettingsModule` 的 OpenList、夸克和兼容 OpenList 路由中统一注入：

~~~dart
onRootSelectionChanged:
    Modular.get<CloudSourceRootRefreshCoordinator>().refreshSource,
~~~

更新 `navigation_config_test.dart`，断言协调器单例注册、三个生产回调和两个编辑器路由均存在。

- [ ] **Step 6: 运行 UI、导航和集成测试并提交**

~~~powershell
D:/flutter/bin/dart.bat format lib/pages/cloud/openlist_source_editor.dart lib/pages/cloud/quark/quark_source_editor.dart lib/pages/index_module.dart lib/pages/settings/settings_module.dart test/cloud_sources_ui_test.dart test/quark_source_editor_test.dart test/navigation_config_test.dart
D:/flutter/bin/flutter.bat test --no-pub test/cloud_sources_ui_test.dart test/quark_source_editor_test.dart test/navigation_config_test.dart test/cloud_library_integration_test.dart
git diff --check
git add -- lib/pages/cloud/openlist_source_editor.dart lib/pages/cloud/quark/quark_source_editor.dart lib/pages/index_module.dart lib/pages/settings/settings_module.dart test/cloud_sources_ui_test.dart test/quark_source_editor_test.dart test/navigation_config_test.dart
git commit -m "保存网盘目录后实时刷新媒体库"
~~~

Expected: PASS；根目录变化触发一次协调刷新，仅改名称等字段不扫描，失败后配置仍保留。

### Task 6: 更新 2.1.23 版本契约与用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1: 先更新版本测试并确认失败**

把版本期望更新为：

~~~dart
const expectedVersion = '2.1.23';
const expectedBuildNumber = '20123';
~~~

新增版本历史测试：

~~~dart
test('二点一二十三说明网盘目录实时刷新和旧资源隐藏', () {
  final entries = versionHistoryForCurrent('2.1.23');
  expect(entries, hasLength(1));
  final changes = entries.single.changes.join('\n');
  expect(changes, contains('目录'));
  expect(changes, contains('实时'));
  expect(changes, contains('旧资源'));
  expect(changes, contains('不会修改网盘文件'));
  expect(entries.single.isPrerelease, isTrue);
});
~~~

Run:

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
~~~

Expected: FAIL；项目仍声明 2.1.22。

- [ ] **Step 2: 更新版本号和四处普通用户文案**

`pubspec.yaml`：

~~~yaml
version: 2.1.23+20123
msix_config:
  msix_version: 2.1.23.0
~~~

`AppVersion.current` 改为 `2.1.23`。README 当前版本、RELEASE_NOTES、UPDATE_DIALOG_COPY 和版本历史明确：

- 修改网盘媒体根目录后，旧目录资源会立即从本地与网盘海报墙隐藏。
- 看影音会自动扫描变化来源一次，并在完成后显示新目录资源，不需要重启应用。
- 更新失败时新目录配置仍保留，可从来源设置手动重试，旧资源不会重新出现。
- 已有 TMDB 标题、海报和匹配缓存继续保留；不会修改、删除或重命名网盘文件与本地视频。

- [ ] **Step 3: 运行版本与发布契约测试并提交**

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart test/release_config_contract_test.dart
git diff --check
git add -- pubspec.yaml README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/core/app_version.dart lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git commit -m "发布二点一二十三测试版"
~~~

Expected: PASS；所有应用版本、构建号、MSIX 版本和用户文案一致。

### Task 7: 全量验证、Windows Release 和签名 MSIX 交付

**Files:**
- Verify: entire repository
- Output: `build/windows/x64/runner/Release/kanyingyin.exe`
- Output: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `C:/Users/asus/Desktop/看影音-2.1.23.msix`

- [ ] **Step 1: 检查格式、差异和提交范围**

~~~powershell
D:/flutter/bin/dart.bat format lib test
git status --short
git diff --check
git log -12 --oneline
~~~

Expected: 没有无关用户文件、构建缓存或临时签名配置进入 Git。

- [ ] **Step 2: 运行全量测试与静态分析**

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub
D:/flutter/bin/flutter.bat analyze --no-pub
~~~

Expected: 所有测试 PASS；静态分析输出 `No issues found!`。

- [ ] **Step 3: 构建 Windows Release**

~~~powershell
D:/flutter/bin/flutter.bat build windows --release --no-pub
Get-Item -LiteralPath 'build/windows/x64/runner/Release/kanyingyin.exe','build/windows/x64/runner/Release/data/app.so' | Select-Object FullName,Length,LastWriteTime
~~~

Expected: Release 构建成功，两个核心产物时间均来自本轮。

- [ ] **Step 4: 使用本机证书生成签名 MSIX**

本机 `msix 3.18.0` 无法用 CLI 覆盖 YAML 的 `sign_msix: false`。仅在封装期间使用 `apply_patch` 临时改为 `true`，执行后立即使用 `apply_patch` 恢复 `false`。密码只在当前 PowerShell 内存中解密：

~~~powershell
$secure = Import-Clixml -LiteralPath "$env:USERPROFILE/.kanyingyin/signing/certificate-password.clixml"
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  D:/flutter/bin/dart.bat run msix:create --build-windows false --sign-msix true --certificate-path "$env:USERPROFILE/.kanyingyin/signing/certificate.pfx" --certificate-password $plainPassword
} finally {
  $plainPassword = $null
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
~~~

Expected: `kanyingyin.msix` 为本轮生成且带签名；Git 中的 `sign_msix` 最终仍为 `false`。

- [ ] **Step 5: 验证清单、签名、架构和 SHA-256**

把 MSIX 解包到新的随机临时目录，读取 `AppxManifest.xml` 并确认：

- Identity Name = `com.kanyingyin.player`
- Publisher = `CN=KanYingYin`
- Version = `2.1.23.0`
- ProcessorArchitecture = `x64`
- 包内存在 `AppxSignature.p7x`
- `Get-AuthenticodeSignature` 状态为 `Valid`

~~~powershell
Copy-Item -LiteralPath 'build/windows/x64/runner/Release/kanyingyin.msix' -Destination 'C:/Users/asus/Desktop/看影音-2.1.23.msix' -Force
Get-AuthenticodeSignature -LiteralPath 'C:/Users/asus/Desktop/看影音-2.1.23.msix'
Get-FileHash -Algorithm SHA256 -LiteralPath 'build/windows/x64/runner/Release/kanyingyin.msix'
Get-FileHash -Algorithm SHA256 -LiteralPath 'C:/Users/asus/Desktop/看影音-2.1.23.msix'
~~~

Expected: 源包和桌面包大小、SHA-256 一致，签名均为 `Valid`。

- [ ] **Step 6: 最终检查并提交必要修正**

~~~powershell
git status --short
git diff --check
git log -14 --oneline
~~~

只提交本轮相关源码、测试和文案。构建目录与 MSIX 不进入 Git；若验证没有产生源码变化，不创建空提交。

## 自检结果

- 规格覆盖：Task 1 覆盖严格路径边界、空根和夸克远程 ID；Tasks 2–3 覆盖两个海报墙的读取时过滤和旧播放目标消失；Task 4 覆盖单次扫描、调用顺序和失败后重载；Task 5 覆盖 OpenList/夸克保存交互、非目录修改不扫描和生产注入；Task 6 覆盖 2.1.23 版本文案；Task 7 覆盖全量质量门禁、Release、签名、清单、哈希和桌面交付。
- 占位符扫描：计划没有 TODO、TBD、未定义接口或“稍后实现”；每项代码修改均给出确定类型、方法、测试命令和预期结果。
- 类型一致性：路径服务统一为 `CloudSourcePathScope`；无扫描重载统一为 `reloadSourcesAndSnapshot()`；协调器统一为 `CloudSourceRootRefreshCoordinator.refreshSource(String)`；编辑回调统一为 `Future<void> Function(String)? onRootSelectionChanged`；版本统一为 `2.1.23+20123 / 2.1.23.0`。
