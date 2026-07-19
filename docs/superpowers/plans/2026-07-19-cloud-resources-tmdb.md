# 网盘资源 TMDB 刮削实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为网盘资源页增加文件夹和根目录独立视频的 TMDB 自动刮削、手动重新匹配、海报展示与云媒体索引同步。

**Architecture:** 新增资源级 TMDB 记录与仓库，以 `sourceId + remoteId + normalizedRemotePath` 持久化缓存。`CloudResourceTmdbService` 负责搜索、选择、海报缓存和可确认的云索引同步，`CloudResourceTmdbCoordinator` 负责 Key 门禁、正/负缓存和最多 2 并发自动调度。

**Tech Stack:** Flutter 3.41.9、Flutter Modular、Hive 现有设置箱、`ITmdbClient`、`TmdbMatcher`、`CloudPosterCache`、`CloudMediaIndexRepository`、flutter_test、MSIX 3.18.0。

---

## 文件结构

- Create `lib/modules/cloud/cloud_resource_tmdb_record.dart`：强类型资源元数据与稳定键。
- Create `lib/repositories/cloud_resource_tmdb_repository.dart`：Hive/内存存储、原子 upsert 和按来源删除。
- Create `lib/services/cloud/cloud_resource_tmdb_service.dart`：查询名、匹配、详情、海报和云索引同步。
- Create `lib/services/cloud/cloud_resource_tmdb_coordinator.dart`：自动调度、负缓存、进度与代次。
- Modify `lib/pages/cloud/resources/cloud_resources_controller.dart`：接收 TMDB 协调器，暴露记录和刮削状态。
- Modify `lib/pages/cloud/resources/cloud_resources_grid.dart`：海报、中文标题、评分、进度和操作菜单。
- Modify `lib/pages/cloud/resources/cloud_resources_page.dart`：系列头部、批量刮削、手动候选和重新匹配。
- Modify `lib/providers/cloud_library_controller.dart`：来源删除同步清理资源 TMDB 记录。
- Modify `lib/utils/storage.dart` 与 `lib/pages/index_module.dart`：存储键和生产依赖。
- Create tests: `test/cloud_resource_tmdb_record_test.dart`、`test/cloud_resource_tmdb_repository_test.dart`、`test/cloud_resource_tmdb_service_test.dart`、`test/cloud_resource_tmdb_coordinator_test.dart`；modify `test/cloud_resources_controller_test.dart`、`test/cloud_resources_page_test.dart`、`test/cloud_source_cleanup_test.dart`。

### Task 1: 强类型 TMDB 记录与存储

**Files:**
- Create: `lib/modules/cloud/cloud_resource_tmdb_record.dart`
- Create: `lib/repositories/cloud_resource_tmdb_repository.dart`
- Modify: `lib/utils/storage.dart`
- Test: `test/cloud_resource_tmdb_record_test.dart`
- Test: `test/cloud_resource_tmdb_repository_test.dart`

- [ ] **Step 1: 先写模型红灯测试**

```dart
test('资源 TMDB 记录稳定键和 JSON 往返保留公开元数据', () {
  final record = CloudResourceTmdbRecord.matched(
    sourceId: 'quark-source',
    remoteId: 'folder-fid',
    remotePath: '/影视/流浪地球',
    displayName: '流浪地球',
    resourceKind: CloudResourceKind.directory,
    metadata: metadata,
    posterCachePath: r'C:\cache\poster.jpg',
    checkedAt: DateTime.utc(2026, 7, 19),
  );
  expect(record.stableKey, 'quark-source|folder-fid|/影视/流浪地球');
  expect(CloudResourceTmdbRecord.fromJson(record.toJson()), record);
  final serialized = record.toJson().toString().toLowerCase();
  for (final secret in ['cookie', 'authorization', 'playback', 'stoken']) {
    expect(serialized, isNot(contains(secret)));
  }
});
```

- [ ] **Step 2: 运行红灯**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_tmdb_record_test.dart`

Expected: FAIL，模型不存在。

- [ ] **Step 3: 实现模型与枚举**

```dart
enum CloudResourceKind { directory, standaloneVideo }
enum CloudResourceTmdbStatus { unchecked, matched, unmatched, failed }

class CloudResourceTmdbRecord {
  const CloudResourceTmdbRecord({
    required this.sourceId,
    required this.remoteId,
    required this.remotePath,
    required this.displayName,
    required this.resourceKind,
    required this.status,
    required this.checkedAt,
    this.tmdbId,
    this.mediaType,
    this.title,
    this.originalTitle,
    this.overview,
    this.rating,
    this.posterUrl,
    this.backdropUrl,
    this.posterCachePath,
  });

  String get stableKey => cloudResourceTmdbKey(
        sourceId: sourceId,
        remoteId: remoteId,
        remotePath: remotePath,
      );
}
```

`cloudResourceTmdbKey()` 将 `\` 转为 `/`，合并重复分隔符，保留根路径。实现 `matched`、`unmatched`、`failed` 命名构造、`toJson/fromJson`、`==` 和 `hashCode`。

- [ ] **Step 4: 先写仓库红灯测试**

```dart
test('并发更新不丢记录且按来源删除', () async {
  final repository = CloudResourceTmdbRepository(
    storage: MemoryCloudResourceTmdbStorage(),
  );
  await Future.wait(<Future<void>>[
    repository.upsert(first),
    repository.upsert(second),
  ]);
  expect(await repository.getBySource('source-a'), hasLength(2));
  await repository.removeSource('source-a');
  expect(await repository.getBySource('source-a'), isEmpty);
});
```

- [ ] **Step 5: 运行红灯并实现仓库**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_tmdb_repository_test.dart`

Expected: FAIL，仓库不存在。

```dart
abstract interface class CloudResourceTmdbStorage {
  Object get synchronizationIdentity;
  Future<List<Map<String, Object?>>> read();
  Future<void> write(List<Map<String, Object?>> records);
}

class CloudResourceTmdbRepository {
  Future<CloudResourceTmdbRecord?> get(String stableKey);
  Future<List<CloudResourceTmdbRecord>> getBySource(String sourceId);
  Future<void> upsert(CloudResourceTmdbRecord record);
  Future<void> removeSource(String sourceId);
}
```

Hive 存储使用新 `SettingBoxKey.cloudResourceTmdbRecords`，写操作使用按 `synchronizationIdentity` 共享的 `synchronized.Lock`。

- [ ] **Step 6: 运行绿灯并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_tmdb_record_test.dart test\cloud_resource_tmdb_repository_test.dart`

Expected: PASS。

```powershell
git add lib/modules/cloud/cloud_resource_tmdb_record.dart lib/repositories/cloud_resource_tmdb_repository.dart lib/utils/storage.dart test/cloud_resource_tmdb_record_test.dart test/cloud_resource_tmdb_repository_test.dart
git commit -m '功能：持久化网盘资源 TMDB 信息'
```

### Task 2: 查询、匹配、海报与云索引同步

**Files:**
- Create: `lib/services/cloud/cloud_resource_tmdb_service.dart`
- Test: `test/cloud_resource_tmdb_service_test.dart`

- [ ] **Step 1: 先写查询名与自动匹配红灯测试**

```dart
test('文件夹查询名移除编码和完结标记但保留年份', () {
  expect(
    CloudResourceTmdbService.queryName(
      'H-回-元异-计【台剧】 (2025) 4K 全6集 完结',
      isDirectory: true,
    ),
    'H-回-元异-计 (2025)',
  );
});

test('自动匹配保存详情、海报并同步文件夹子树索引', () async {
  final outcome = await service.match(resource, options: options);
  expect(outcome.selected?.id, 42);
  expect((await resourceRepository.get(resource.stableKey))?.title, '中文片名');
  expect(indexRepository.updatedPaths, everyElement(startsWith('/影视/流浪地球/')));
});
```

- [ ] **Step 2: 运行红灯**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_tmdb_service_test.dart`

Expected: FAIL，服务不存在。

- [ ] **Step 3: 实现服务**

```dart
class CloudResourceTmdbOutcome {
  const CloudResourceTmdbOutcome({required this.candidates, this.selected});
  final List<TmdbMetadata> candidates;
  final CloudResourceTmdbRecord? selected;
}

class CloudResourceTmdbService {
  Future<CloudResourceTmdbOutcome> match(
    CloudResourceTmdbTarget target, {
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  });

  Future<CloudResourceTmdbOutcome> searchCandidates(
    CloudResourceTmdbTarget target, {
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  });

  Future<CloudResourceTmdbRecord> select(
    CloudResourceTmdbTarget target,
    TmdbMetadata candidate, {
    TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
  });
}
```

`CloudResourceTmdbTarget` 包含来源、`CloudRemoteRef`、展示名和 `CloudResourceKind`。`auto` 模式下文件夹先搜索电视，独立视频先搜索电影；首类型无候选时查询另一类型。选择后缓存海报并调用 `CloudMediaIndexRepository.updateMatching()`：文件夹只匹配其规范化路径子树，独立视频只匹配精确路径。

- [ ] **Step 4: 先写未匹配与手动选择测试**

```dart
test('无候选保存未匹配而不破坏云索引', () async {
  final outcome = await service.match(resource);
  expect(outcome.candidates, isEmpty);
  expect((await repository.get(resource.stableKey))?.status,
      CloudResourceTmdbStatus.unmatched);
  expect(indexRepository.updateCount, 0);
});

test('手动选择保存用户候选', () async {
  final record = await service.select(resource, candidate);
  expect(record.tmdbId, candidate.id);
  expect(record.title, '手动选择标题');
});
```

- [ ] **Step 5: 运行全部服务测试并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_tmdb_service_test.dart`

Expected: PASS。

```powershell
git add lib/services/cloud/cloud_resource_tmdb_service.dart test/cloud_resource_tmdb_service_test.dart
git commit -m '功能：实现网盘资源 TMDB 匹配'
```

### Task 3: 自动刮削调度与目录集成

**Files:**
- Create: `lib/services/cloud/cloud_resource_tmdb_coordinator.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `lib/pages/index_module.dart`
- Test: `test/cloud_resource_tmdb_coordinator_test.dart`
- Test: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1: 先写缓存、Key 和并发红灯测试**

```dart
test('TMDB Key 缺失时只读缓存不发请求', () async {
  await coordinator.loadAndSchedule(context, apiKey: '');
  expect(service.matchCalls, 0);
  expect(coordinator.records[matched.stableKey], matched);
});

test('未匹配七天内不重试且失败可重试', () async {
  await coordinator.loadAndSchedule(context, now: DateTime.utc(2026, 7, 19));
  expect(service.requestedKeys, contains(failed.stableKey));
  expect(service.requestedKeys, isNot(contains(recentUnmatched.stableKey)));
});

test('自动请求并发不超过二', () async {
  await coordinator.loadAndSchedule(context);
  expect(service.maximumConcurrentCalls, 2);
});
```

- [ ] **Step 2: 运行红灯并实现协调器**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_tmdb_coordinator_test.dart`

Expected: FAIL，协调器不存在。

```dart
class CloudResourceDirectoryContext {
  const CloudResourceDirectoryContext({
    required this.source,
    required this.directory,
    required this.entries,
    required this.isConfiguredRoot,
  });
}

class CloudResourceTmdbCoordinator extends ChangeNotifier {
  Map<String, CloudResourceTmdbRecord> get records;
  Set<String> get scrapingKeys;
  Future<void> loadAndSchedule(CloudResourceDirectoryContext context);
  Future<CloudResourceTmdbOutcome> scrape(CloudResourceTmdbTarget target);
  Future<CloudResourceTmdbOutcome> rematch(CloudResourceTmdbTarget target);
  Future<CloudResourceTmdbRecord> select(
      CloudResourceTmdbTarget target, TmdbMetadata candidate);
}
```

调度队列用两个 worker 消费；文件夹始终入队，视频只在 `isConfiguredRoot` 时入队。已匹配且名称未变直接读缓存，`unmatched.checkedAt + 7 days > now` 跳过，`failed` 允许重试。

- [ ] **Step 3: 先写控制器集成红灯测试**

```dart
test('根目录调度文件夹和独立视频，子目录只调度文件夹', () async {
  await controller.load();
  expect(coordinator.lastContext!.isConfiguredRoot, isTrue);
  expect(coordinator.lastContext!.entries, contains(video));
  await controller.openDirectory(childRef);
  expect(coordinator.lastContext!.isConfiguredRoot, isFalse);
});
```

- [ ] **Step 4: 接入控制器与生产依赖**

`CloudResourcesController` 增加可选 `CloudResourceTmdbCoordinator`，目录加载成功后构造 context，且只在当前代次仍有效时交付。控制器转发协调器通知，页面不直接管理并发队列。

`IndexModule` 注入共享仓库、云媒体索引、TMDB Key/刮削选项 provider、`TmdbClient` 工厂和海报缓存工厂。

- [ ] **Step 5: 运行绿灯并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_tmdb_coordinator_test.dart test\cloud_resources_controller_test.dart`

Expected: PASS。

```powershell
git add lib/services/cloud/cloud_resource_tmdb_coordinator.dart lib/pages/cloud/resources/cloud_resources_controller.dart lib/pages/index_module.dart test/cloud_resource_tmdb_coordinator_test.dart test/cloud_resources_controller_test.dart
git commit -m '功能：自动刮削网盘资源'
```

### Task 4: 海报卡片、系列头部与手动匹配

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_grid.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 先写元数据展示红灯测试**

```dart
testWidgets('卡片显示海报、中文标题、评分和原文件名', (tester) async {
  await tester.pumpWidget(pageWithRecord(matched));
  await tester.pumpAndSettle();
  expect(find.byKey(ValueKey('tmdb-poster-${matched.stableKey}')), findsOneWidget);
  expect(find.text('中文片名'), findsOneWidget);
  expect(find.textContaining('8.7 ★'), findsOneWidget);
  expect(find.text(resource.name), findsOneWidget);
});

testWidgets('进入已匹配文件夹显示系列头部', (tester) async {
  await tester.pumpWidget(pageInsideMatchedDirectory(matched));
  expect(find.text(matched.overview!), findsOneWidget);
  expect(find.byKey(const ValueKey('cloud-series-header')), findsOneWidget);
});
```

- [ ] **Step 2: 运行红灯并实现展示**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart`

Expected: FAIL，网格尚未接收 TMDB 记录。

`CloudResourcesGrid` 增加 `records`、`scrapingKeys`、`onScrape`、`onRematch`。海报优先使用存在的 `posterCachePath`，再用 `TmdbMatchSheet.imageUrl(record.posterUrl)`，失败回退文件夹/视频图标。

- [ ] **Step 3: 先写手动候选红灯测试**

```dart
testWidgets('重新匹配显示候选并保存所选结果', (tester) async {
  await tester.tap(find.byTooltip('资源操作'));
  await tester.tap(find.text('重新匹配'));
  await tester.pumpAndSettle();
  expect(find.text('选择 TMDB 匹配'), findsOneWidget);
  await tester.tap(find.text('候选片名'));
  await tester.pumpAndSettle();
  expect(coordinator.selectedCandidate?.id, 42);
});
```

- [ ] **Step 4: 实现手动刮削和批量入口**

卡片菜单提供 `TMDB 刮削` 和 `重新匹配`。普通刮削允许自动选中；无自动选中且有候选时打开 `TmdbMatchSheet`。重新匹配先打开 `TmdbScrapeOptionsSheet`，再展示候选。工具栏增加“刮削当前目录”，依次调用协调器且显示进度。

- [ ] **Step 5: 运行绿灯并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart`

Expected: PASS。

```powershell
git add lib/pages/cloud/resources/cloud_resources_grid.dart lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_resources_page_test.dart
git commit -m '界面：展示并重新匹配网盘 TMDB 信息'
```

### Task 5: 来源删除清理与故障隔离

**Files:**
- Modify: `lib/providers/cloud_library_controller.dart`
- Modify: `test/cloud_source_cleanup_test.dart`
- Modify: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1: 先写来源删除红灯测试**

```dart
test('删除来源清理资源 TMDB 记录且不删除远程文件', () async {
  await controller.delete('quark-source');
  expect(await tmdbRepository.getBySource('quark-source'), isEmpty);
  expect(fakeCloudClient.deleteCalls, 0);
});
```

- [ ] **Step 2: 运行红灯并接入清理**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_source_cleanup_test.dart`

Expected: FAIL，删除流程尚未清理新仓库。

`CloudLibraryController` 增加可注入 `CloudResourceTmdbRepository`。删除时在远程凭据删除前清理记录；若随后来源删除失败，使用删除前快照恢复记录，与现有媒体索引回滚对齐。

- [ ] **Step 3: 先写 TMDB 故障隔离测试**

```dart
test('TMDB 失败不改写目录错误且视频仍可播放', () async {
  await controller.load();
  tmdbCoordinator.failPending();
  expect(controller.errorMessage, isNull);
  expect(controller.visibleEntries, contains(video));
});
```

- [ ] **Step 4: 运行绿灯并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_source_cleanup_test.dart test\cloud_resources_controller_test.dart test\cloud_playback_resolver_test.dart`

Expected: PASS。

```powershell
git add lib/providers/cloud_library_controller.dart test/cloud_source_cleanup_test.dart test/cloud_resources_controller_test.dart
git commit -m '修复：安全清理网盘 TMDB 缓存'
```

### Task 6: 全量回归、版本与签名 MSIX

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `README.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1: 版本前全量门禁**

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: 格式无变化，全量测试通过，静态分析无问题。

- [ ] **Step 2: 版本更新为 2.1.6**

```yaml
version: 2.1.6+20106
msix_version: 2.1.6.0
```

发布文案面向普通用户说明：网盘文件夹和独立视频可自动刮削；卡片显示海报、中文标题和评分；支持手动重新匹配；TMDB 不可用时不影响网盘浏览和播放。

- [ ] **Step 3: 版本后重跑完整门禁与 Release**

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: 全部退出码为 0，`kanyingyin.exe` 与 `data/app.so` 为本轮新产物。

- [ ] **Step 4: 生成签名 MSIX 并验证**

使用 `apply_patch` 临时将 `sign_msix` 改为 `true`，用 `%USERPROFILE%\.kanyingyin\signing\certificate.pfx` 与 DPAPI 密码生成包，然后用 `apply_patch` 恢复 `false`。验证：

```text
Identity Name: com.kanyingyin.player
Identity Version: 2.1.6.0
Architecture: x64
Authenticode Status: Valid
AppxSignature.p7x: 存在
Desktop: C:\Users\asus\Desktop\看影音-2.1.6.msix
```

计算桌面包 SHA-256，并确认复制后签名仍为 `Valid`。

- [ ] **Step 5: 检查差异并提交发布**

```powershell
git status --short
git diff --check
git add README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart test/identity_v2_zero_residue_test.dart test/version_consistency_test.dart test/version_history_current_test.dart
git commit -m '发布：交付网盘 TMDB 刮削 2.1.6'
```

`.learnings/ERRORS.md` 和 `.learnings/LEARNINGS.md` 全程保持未暂存、未提交。
