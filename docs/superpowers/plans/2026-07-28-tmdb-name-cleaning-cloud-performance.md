# TMDB 名称清理与网盘资源性能优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 发布 `2.1.66` 测试版，统一清理本地与网盘 TMDB 搜索词，并消除网盘资源页和手动 TMDB 刮削触发的重复全量计算。

**Architecture:** 新建无状态 `TmdbResourceNameCleaner`，由本地刮削策略和网盘名称解析器共同调用。网盘控制器惰性缓存目录树与海报集合，TMDB 协调器使用资料修订号区分“加载状态变化”和“资料变化”，使状态通知不再使海报集合失效。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Test、ChangeNotifier、PowerShell、MSIX

---

## 文件职责

- `lib/services/tmdb/tmdb_resource_name_cleaner.dart`：维护 TMDB 搜索词中的媒体扩展名和发布标签清理规则
- `lib/services/cloud/cloud_media_name_parser.dart`：保留网盘季集识别，调用统一清洗器生成搜索词
- `lib/services/tmdb/tmdb_scrape_policy.dart`：保留本地搜索计划和类型判断，调用统一清洗器生成查询词
- `lib/services/cloud/cloud_resource_tmdb_coordinator.dart`：维护资源级 TMDB 资料修订号
- `lib/services/cloud/cloud_work_tmdb_coordinator.dart`：维护作品级 TMDB 资料修订号
- `lib/pages/cloud/resources/cloud_resources_controller.dart`：缓存目录树和海报集合，按依赖变化失效
- `test/tmdb_resource_name_cleaner_test.dart`：覆盖发布标签、扩展名和合法标题边界
- `test/cloud_media_name_parser_test.dart`、`test/tmdb_scrape_policy_test.dart`：验证本地和网盘查询词契约
- `test/cloud_resources_derived_cache_test.dart`：用 500 个索引项验证缓存次数和失效边界
- 版本与发布文件：记录 `2.1.66` 测试版并保留 `1.0.2` 正式版历史

### Task 1: 统一 TMDB 资源名称清理

**Files:**

- Create: `lib/services/tmdb/tmdb_resource_name_cleaner.dart`
- Create: `test/tmdb_resource_name_cleaner_test.dart`
- Modify: `lib/services/cloud/cloud_media_name_parser.dart`
- Modify: `lib/services/tmdb/tmdb_scrape_policy.dart`
- Modify: `test/cloud_media_name_parser_test.dart`
- Modify: `test/tmdb_scrape_policy_test.dart`

- [ ] **Step 1: 写统一清洗器失败测试**

创建 `test/tmdb_resource_name_cleaner_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/tmdb/tmdb_resource_name_cleaner.dart';

void main() {
  const cleaner = TmdbResourceNameCleaner();

  test('清除常见视频片源编码 HDR 和音频标签', () {
    final cases = <String, String>{
      '电影.2160p.WEB-DL.DV.HDR10+.x265.TrueHD.7.1.Atmos.mkv': '电影',
      '电影 1080p BluRay VC-1 DTS-HD MA 5.1.m2ts': '电影',
      '电影_720p_WEBRip_VP9_Opus.webm': '电影',
      '电影.DVDRip.XviD.AC3.avi': '电影',
      '电影 4K REMUX H.265 EAC3 DD+ DDP5.1.mkv': '电影',
      '电影 8K UHD AV1 HLG SDR LPCM PCM Vorbis ALAC.mkv': '电影',
    };

    for (final entry in cases.entries) {
      expect(cleaner.clean(entry.key), entry.value, reason: entry.key);
    }
  });

  test('只清除名称末尾的已知视频和音频扩展名', () {
    for (final name in <String>['电影.mp4', '电影.mkv', '电影.mka', '电影.flac']) {
      expect(cleaner.clean(name), '电影', reason: name);
    }
    expect(cleaner.clean('REC.unknown'), 'REC unknown');
  });

  test('保留正式括号标题数字标题和未知发布文字', () {
    expect(cleaner.clean('[REC] (2007).mkv'), '[REC] (2007)');
    expect(cleaner.clean('1923.mkv'), '1923');
    expect(cleaner.clean('The 100.mkv'), 'The 100');
    expect(cleaner.clean('作品【导演收藏】.mkv'), '作品【导演收藏】');
  });
}
```

- [ ] **Step 2: 运行测试并确认因文件不存在而失败**

Run: `D:\flutter\bin\flutter.bat test test\tmdb_resource_name_cleaner_test.dart`

Expected: FAIL，提示找不到 `tmdb_resource_name_cleaner.dart` 或 `TmdbResourceNameCleaner`。

- [ ] **Step 3: 实现无状态清洗器**

创建 `lib/services/tmdb/tmdb_resource_name_cleaner.dart`，实现以下公开接口和边界规则：

```dart
class TmdbResourceNameCleaner {
  const TmdbResourceNameCleaner();

  static final RegExp _knownExtensionPattern = RegExp(
    r'\.(?:mp4|mkv|avi|mov|wmv|flv|webm|m4v|ts|m2ts|mts|mpg|mpeg|vob|rm|rmvb|3gp|asf|ogv|f4v|divx|mp3|flac|wav|aac|m4a|ogg|opus|wma|ape|alac|ac3|eac3|dts|mka|aiff|aif|amr|tak|tta|wv|dsf|dff)$',
    caseSensitive: false,
  );
  static final RegExp _releaseTokenPattern = RegExp(
    r'(?<![A-Za-z0-9])(?:'
    r'x26[45]|h[ ._-]*26[45]|avc|hevc|av1|vp9|vc[ ._-]*1|mpeg[ ._-]*2|xvid|divx|'
    r'web[ ._-]*dl|webrip|blu[ ._-]*ray|bdrip|remux|hdtv|dvdrip|bd|'
    r'2160p|1440p|1080[pi]|720p|480p|4k|8k|uhd|'
    r'dolby[ ._-]*vision|hdr(?:10\+?)?|dv|hlg|sdr|'
    r'dts(?:[ ._-]*hd(?:[ ._-]*ma)?)?(?:[ ._-]*(?:2\.0|5\.1|7\.1))?|'
    r'(?:true[ ._-]*hd|eac[ ._-]*3|ac[ ._-]*3|ddp|dd\+?|aac|flac|lpcm|pcm|opus|vorbis|wma|ape|alac)'
    r'(?:[ ._-]*(?:2\.0|5\.1|7\.1))?|atmos'
    r')(?![A-Za-z0-9])',
    caseSensitive: false,
  );
  static final RegExp _bracketPattern = RegExp(r'\[([^\]]+)\]|【([^】]+)】');

  String clean(String value) {
    var result = value.trim().replaceFirst(_knownExtensionPattern, '');
    result = result.replaceAllMapped(_bracketPattern, (match) {
      final content = match.group(1) ?? match.group(2) ?? '';
      return _releaseTokenPattern.hasMatch(content) ? ' ' : match.group(0)!;
    });
    return result
        .replaceAll(_releaseTokenPattern, ' ')
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'^[\s&+,\-–—:：]+|[\s&+,\-–—:：]+$'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
```

- [ ] **Step 4: 运行清洗器测试并修正单个正则边界**

Run: `D:\flutter\bin\flutter.bat test test\tmdb_resource_name_cleaner_test.dart`

Expected: PASS。若失败，只调整导致该用例失败的边界，不增加未知尾缀猜测。

- [ ] **Step 5: 写本地与网盘一致性失败测试**

在 `test/cloud_media_name_parser_test.dart` 增加：

```dart
test('完整发布标签不会进入网盘 TMDB 搜索词', () {
  final draft = parser.parse(
    originalName:
        '流浪地球2.2160p.REMUX.DV.HDR10+.H.265.TrueHD.7.1.Atmos.mkv',
    isDirectory: false,
  );

  expect(draft.searchTitle, '流浪地球2');
});
```

在 `test/tmdb_scrape_policy_test.dart` 增加：

```dart
test('本地搜索计划清除与网盘相同的完整发布标签', () {
  const subject = TmdbScrapeSubject(
    stableKey: 'movie-release-name',
    titleCandidates: <String>[
      '流浪地球2.2160p.REMUX.DV.HDR10+.H.265.TrueHD.7.1.Atmos.mkv',
    ],
    mediaEvidence: TmdbMediaEvidence.movie,
  );

  final plan = policy.build(subject, const TmdbScrapeOptions.defaults());

  expect(plan.queries, <String>['流浪地球2']);
});
```

- [ ] **Step 6: 运行两个契约测试并确认旧规则失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_media_name_parser_test.dart test\tmdb_scrape_policy_test.dart`

Expected: FAIL，实际搜索词仍含 `REMUX`、`TrueHD` 或其他新增标签。

- [ ] **Step 7: 接入统一清洗器并删除重复发布标签正则**

在两个调用方添加依赖字段：

```dart
const CloudMediaNameParser({
  TmdbResourceNameCleaner cleaner = const TmdbResourceNameCleaner(),
}) : _cleaner = cleaner;

final TmdbResourceNameCleaner _cleaner;
```

```dart
const TmdbScrapePolicy({
  TmdbResourceNameCleaner cleaner = const TmdbResourceNameCleaner(),
}) : _cleaner = cleaner;

final TmdbResourceNameCleaner _cleaner;
```

让两个 `_cleanTitle` 先调用 `_cleaner.clean(value)`，随后只处理各自的季集、年份、全集和空白规则。删除两处 `_releaseTokenPattern` 及其方括号替换逻辑，保留现有空结果回退。

网盘解析器使用以下方法体：

```dart
String _cleanTitle(String value) {
  return _cleaner
      .clean(value)
      .replaceAll(_seasonEpisodePattern, ' ')
      .replaceAll(_chineseSeasonPattern, ' ')
      .replaceAll(_chineseNamedSeasonPattern, ' ')
      .replaceAll(_englishSeasonPattern, ' ')
      .replaceAll(_chineseEpisodePattern, ' ')
      .replaceAll(RegExp(r'[（(](?:19|20)\d{2}[)）]'), ' ')
      .replaceAll(RegExp(r'全\s*\d+\s*集|全集|完结'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
```

本地刮削策略使用以下方法体：

```dart
String _cleanTitle(String value) {
  return _cleaner
      .clean(value)
      .replaceAll(_seasonEpisodePattern, ' ')
      .replaceAll(_chineseSeasonPattern, ' ')
      .replaceAll(_englishSeasonPattern, ' ')
      .replaceAll(_chineseEpisodePattern, ' ')
      .replaceAll(_yearPattern, ' ')
      .replaceAll(RegExp(r'[（(]\s*[)）]'), ' ')
      .replaceAll(RegExp(r'全\s*\d+\s*集|全集|完结'), ' ')
      .replaceAll(RegExp(r'\s+-\s+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
```

- [ ] **Step 8: 运行名称解析相关测试**

Run: `D:\flutter\bin\flutter.bat test test\tmdb_resource_name_cleaner_test.dart test\cloud_media_name_parser_test.dart test\tmdb_scrape_policy_test.dart test\media_name_analyzer_test.dart`

Expected: PASS，`[REC]`、年份、季集号和现有发布名用例均不回退。

- [ ] **Step 9: 提交名称清理改动**

```powershell
git add -- lib/services/tmdb/tmdb_resource_name_cleaner.dart lib/services/cloud/cloud_media_name_parser.dart lib/services/tmdb/tmdb_scrape_policy.dart test/tmdb_resource_name_cleaner_test.dart test/cloud_media_name_parser_test.dart test/tmdb_scrape_policy_test.dart
git diff --cached --check
git commit -m "统一 TMDB 资源名称清理"
```

### Task 2: 缓存网盘目录树和海报集合

**Files:**

- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Create: `test/cloud_resources_derived_cache_test.dart`

- [ ] **Step 1: 写 500 个资源的确定性缓存失败测试**

创建 `test/cloud_resources_derived_cache_test.dart`。测试使用内存来源和索引仓库、500 个 `CloudMediaIndexItem`、计数目录树构建器和计数分组器：

```dart
test('几百个资源只构建一次目录树并复用海报集合', () async {
  var treeBuildCount = 0;
  final grouper = _CountingCollectionGrouper();
  final fixture = await _createCacheFixture(
    itemCount: 500,
    collectionGrouper: grouper,
    directoryScopeTreeBuilder: ({required rootPaths, required mediaPaths}) {
      treeBuildCount++;
      return CloudDirectoryScopeTree.build(
        rootPaths: rootPaths,
        mediaPaths: mediaPaths,
      );
    },
  );

  final first = fixture.controller.collection;
  final second = fixture.controller.collection;

  expect(first.groups, hasLength(500));
  expect(identical(first, second), isTrue);
  expect(treeBuildCount, 1);
  expect(grouper.calls, 1);
  fixture.controller.dispose();
});
```

计数分组器完整覆盖父类签名：

```dart
class _CountingCollectionGrouper extends CloudResourceCollectionGrouper {
  int calls = 0;

  @override
  CloudResourceCollection group({
    String? sourceId,
    List<CloudFileEntry> entries = const <CloudFileEntry>[],
    Map<String, CloudResourceTmdbRecord> records =
        const <String, CloudResourceTmdbRecord>{},
    int minSizeBytes = 0,
    List<CloudMediaIndexItem> items = const <CloudMediaIndexItem>[],
    List<CloudWorkIdentity> works = const <CloudWorkIdentity>[],
    Map<String, CloudWorkTmdbRecord> recordsByWorkKey =
        const <String, CloudWorkTmdbRecord>{},
    required String query,
  }) {
    calls++;
    return super.group(
      sourceId: sourceId,
      entries: entries,
      records: records,
      minSizeBytes: minSizeBytes,
      items: items,
      works: works,
      recordsByWorkKey: recordsByWorkKey,
      query: query,
    );
  }
}
```

- [ ] **Step 2: 运行缓存测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_derived_cache_test.dart`

Expected: FAIL，控制器尚无 `directoryScopeTreeBuilder` 参数，或重复读取返回不同集合实例。

- [ ] **Step 3: 增加目录树构建依赖和两个惰性缓存**

在控制器文件增加强类型构建器：

```dart
typedef CloudDirectoryScopeTreeBuilder = CloudDirectoryScopeTree Function({
  required Iterable<String> rootPaths,
  required Iterable<String> mediaPaths,
});

CloudDirectoryScopeTree _buildDirectoryScopeTree({
  required Iterable<String> rootPaths,
  required Iterable<String> mediaPaths,
}) =>
    CloudDirectoryScopeTree.build(
      rootPaths: rootPaths,
      mediaPaths: mediaPaths,
    );
```

构造函数增加可选 `directoryScopeTreeBuilder`，并保存以下字段：

```dart
final CloudDirectoryScopeTreeBuilder _directoryScopeTreeBuilder;
CloudDirectoryScopeTree? _directoryScopeTreeCache;
CloudResourceCollection? _collectionCache;

CloudDirectoryScopeTree get _directoryScopeTree =>
    _directoryScopeTreeCache ??= _directoryScopeTreeBuilder(
      rootPaths: selectedSource?.remoteRoots.map((root) => root.path) ??
          const <String>[],
      mediaPaths: _indexedItems.values.map((item) => item.remotePath),
    );
```

把 `collection` 改为先返回 `_collectionCache`，首次计算后保存结果。`visibleIndexedItems` 和 `visibleEntries` 在循环前各捕获一次 `final scopeTree = _directoryScopeTree`。

增加两个失效方法：

```dart
void _invalidateCollection() {
  _collectionCache = null;
}

void _invalidateDirectoryScopeTree() {
  _directoryScopeTreeCache = null;
  _invalidateCollection();
}
```

- [ ] **Step 4: 在控制器数据变化点失效缓存**

在以下赋值完成后调用 `_invalidateDirectoryScopeTree()`：选择或清空来源、载入或恢复索引快照。只涉及目录范围、搜索词、隐藏记录或展示资料时调用 `_invalidateCollection()`。

具体调用点包括：`hideVideos`、`restoreHiddenVideo`、`restoreAllHiddenVideos`、`reloadSourcesAndSnapshot` 的失败恢复、`_loadSources` 失败、`_selectSource` 清空状态、`_loadSnapshot`、`selectDirectoryScope`、`navigateDirectoryScopeUp`、`clearDirectoryScope` 和 `setQuery`。

各类赋值保持以下顺序，确保监听器读取不到旧缓存：

```dart
_hiddenVideos = next;
_invalidateCollection();
_notify();

query = value;
_invalidateCollection();
_notify();

_indexedItems
  ..clear()
  ..addEntries(scopedItems.map((item) => MapEntry(_resourceKeyForItem(item), item)));
_invalidateDirectoryScopeTree();
```

- [ ] **Step 5: 运行缓存测试和现有控制器测试**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_derived_cache_test.dart test\cloud_resources_controller_test.dart`

Expected: PASS；目录切换、隐藏恢复和搜索仍立即更新海报集合。

- [ ] **Step 6: 提交基础缓存改动**

```powershell
git add -- lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_resources_derived_cache_test.dart
git diff --cached --check
git commit -m "缓存网盘资源派生结果"
```

### Task 3: 区分 TMDB 加载状态和资料变化

**Files:**

- Modify: `lib/services/cloud/cloud_resource_tmdb_coordinator.dart`
- Modify: `lib/services/cloud/cloud_work_tmdb_coordinator.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `test/cloud_resources_derived_cache_test.dart`
- Modify: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1: 写 TMDB 状态通知不使缓存失效的失败测试**

在派生缓存测试中加入可主动通知的协调器。`emitStatusChange` 不修改 `recordsRevision`，`replaceRecord` 递增修订号：

```dart
class _CacheTmdbCoordinator extends CloudResourceTmdbCoordinator {
  _CacheTmdbCoordinator()
      : super(
          repository: CloudResourceTmdbRepository(
            storage: MemoryCloudResourceTmdbStorage(),
          ),
          serviceFactory: (_) => throw UnimplementedError(),
          apiKeyProvider: () => '',
        );

  int _testRevision = 0;

  @override
  int get recordsRevision => _testRevision;

  void emitStatusChange() => notifyListeners();

  void emitRecordChange() {
    _testRevision++;
    notifyListeners();
  }

  @override
  Future<void> loadAndSchedule(CloudResourceDirectoryContext context) async {}
}
```

测试断言：

```dart
final first = fixture.controller.collection;
coordinator.emitStatusChange();
expect(identical(fixture.controller.collection, first), isTrue);
expect(grouper.calls, 1);

coordinator.emitRecordChange();
expect(identical(fixture.controller.collection, first), isFalse);
expect(grouper.calls, 2);
```

- [ ] **Step 2: 运行状态通知测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_derived_cache_test.dart`

Expected: FAIL，协调器尚无 `recordsRevision`，或状态通知仍使集合失效。

- [ ] **Step 3: 为两个 TMDB 协调器增加资料修订号**

两个协调器都增加只读修订号：

```dart
int _recordsRevision = 0;
int get recordsRevision => _recordsRevision;

void _markRecordsChanged() {
  _recordsRevision++;
}
```

每次 `_records` 被清空重载、新增、替换或批量传播后调用 `_markRecordsChanged()`。仅修改 `_scrapingKeys`、`_scrapingWorkKeys`、完成数量和总数量时不递增。资料变化和加载状态可以在同一次 `notifyListeners()` 中发布。

- [ ] **Step 4: 控制器按修订号决定是否使集合失效**

构造时记录两个协调器的初始修订号，并把监听器从 `_notify` 改为 `_handleTmdbChange`：

```dart
int _resourceTmdbRecordsRevision = 0;
int _workTmdbRecordsRevision = 0;

void _handleTmdbChange() {
  final resourceRevision = _tmdbCoordinator?.recordsRevision ?? 0;
  final workRevision = _workTmdbCoordinator?.recordsRevision ?? 0;
  if (resourceRevision != _resourceTmdbRecordsRevision ||
      workRevision != _workTmdbRecordsRevision) {
    _resourceTmdbRecordsRevision = resourceRevision;
    _workTmdbRecordsRevision = workRevision;
    _invalidateCollection();
  }
  _notify();
}
```

`dispose` 使用同一回调移除监听器。更新测试中的 `_RecordingWorkTmdbCoordinator`，其测试记录发生变化时同步递增覆盖的 `recordsRevision`。

- [ ] **Step 5: 运行手动刮削和缓存回归测试**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_derived_cache_test.dart test\cloud_resources_controller_test.dart test\cloud_resources_page_test.dart test\cloud_resource_tmdb_coordinator_test.dart test\cloud_work_tmdb_coordinator_test.dart`

Expected: PASS；手动搜索开始和结束只改变目标卡片加载状态，应用候选后海报资料立即更新。

- [ ] **Step 6: 提交 TMDB 通知优化**

```powershell
git add -- lib/services/cloud/cloud_resource_tmdb_coordinator.dart lib/services/cloud/cloud_work_tmdb_coordinator.dart lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_resources_derived_cache_test.dart test/cloud_resources_controller_test.dart
git diff --cached --check
git commit -m "避免 TMDB 状态通知重复分组"
```

### Task 4: 更新 2.1.66 测试版

**Files:**

- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1: 先把版本测试期望改为测试版并确认失败**

将当前版本期望改为：

```dart
const expectedVersion = '2.1.66';
const expectedBuildNumber = '20166';
```

`version_consistency_test.dart` 断言当前文案包含“测试版”，当前历史包含 `isPrerelease: true`，并要求用户文案包含“TMDB 搜索词”“网盘资源页”“手动刮削”“不会修改”。`identity_v2_zero_residue_test.dart` 的当前版本期望改为 `2.1.66`。`version_history_current_test.dart` 新增 `2.1.66` 测试版条目断言，并保留 `1.0.2` 正式版测试。

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart test\identity_v2_zero_residue_test.dart`

Expected: FAIL，项目配置仍为 `1.0.2`，且没有 `2.1.66` 历史。

- [ ] **Step 2: 更新版本配置**

将版本配置改为：

```yaml
version: 2.1.66+20166

msix_config:
  msix_version: 2.1.66.0
```

把 `AppVersion.current` 和 README 当前版本改为 `2.1.66`。

- [ ] **Step 3: 写普通用户可读的测试版文案**

在发布说明、更新弹窗和版本历史使用一致核心文案：

```text
标题：看影音 2.1.66 测试版

- 扩充本地与网盘 TMDB 名称清理规则，常见视频编码、片源、HDR、音频编码和声道信息不再干扰影片搜索。
- 优化几百个资源的网盘媒体库载入，进入网盘资源页时不再反复重建目录和海报集合。
- 优化网盘手动 TMDB 刮削，搜索和应用候选时不再因加载状态反复整理全部资源。
- 本次更新只调整看影音内部的名称识别和展示缓存，不会修改或删除本地与网盘原始文件；TMDB 不可用时扫描和播放仍可使用。
```

在 `version_history.dart` 的 `1.0.2` 正式版之后插入 `2.1.66`，设置 `isPrerelease: true`。保留所有既有正式版和测试版历史。

- [ ] **Step 4: 运行版本测试**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart test\identity_v2_zero_residue_test.dart`

Expected: PASS，当前版本为 `2.1.66+20166`，MSIX 为 `2.1.66.0`，`1.0.2` 正式版历史仍存在。

- [ ] **Step 5: 提交测试版元数据**

```powershell
git add -- pubspec.yaml lib/core/app_version.dart README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git diff --cached --check
git commit -m "发布二点一六十六测试版"
```

### Task 5: 全量验收和 MSIX 交付

**Files:**

- Verify: all tracked project files
- Generate: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.66.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.66-异机安装包.zip`

- [ ] **Step 1: 格式化本轮 Dart 文件并检查差异**

Run: `D:\flutter\bin\dart.bat format lib\services\tmdb\tmdb_resource_name_cleaner.dart lib\services\cloud\cloud_media_name_parser.dart lib\services\tmdb\tmdb_scrape_policy.dart lib\services\cloud\cloud_resource_tmdb_coordinator.dart lib\services\cloud\cloud_work_tmdb_coordinator.dart lib\pages\cloud\resources\cloud_resources_controller.dart test\tmdb_resource_name_cleaner_test.dart test\cloud_media_name_parser_test.dart test\tmdb_scrape_policy_test.dart test\cloud_resources_derived_cache_test.dart test\cloud_resources_controller_test.dart test\version_consistency_test.dart test\version_history_current_test.dart test\identity_v2_zero_residue_test.dart`

Run: `git diff --check`

Expected: 格式化成功，差异中没有空白错误。

- [ ] **Step 2: 运行全量测试**

Run: `D:\flutter\bin\flutter.bat test`

Expected: PASS，退出码为 0。

- [ ] **Step 3: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze`

Expected: `No issues found!`，退出码为 0。

- [ ] **Step 4: 生成签名 Windows Release 和 MSIX**

确认看影音进程已退出后运行：

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/windows/build_signed_release.ps1`

Expected: Windows Release 构建成功，MSIX 创建、签名和验证成功；桌面生成 `看影音-2.1.66.msix` 与异机安装包 ZIP。

- [ ] **Step 5: 复核安装包清单、签名和桌面文件**

使用 PowerShell 读取 MSIX 中的 `AppxManifest.xml`，确认：

```text
Identity Name=com.kanyingyin.player
Identity Version=2.1.66.0
ProcessorArchitecture=x64
AuthenticodeSignature=Valid
```

计算构建目录和桌面 MSIX 的 SHA-256，两个哈希必须相同。再次运行 `Get-AppxPackage -Name com.kanyingyin.player`；如果未执行安装，明确记录系统仍安装 `2.1.65.0`。

- [ ] **Step 6: 检查提交和工作区状态**

```powershell
git status --short
git log -6 --oneline
```

Expected: 工作区干净，提交历史包含设计、名称清理、缓存、TMDB 通知优化和 `2.1.66` 测试版提交。
