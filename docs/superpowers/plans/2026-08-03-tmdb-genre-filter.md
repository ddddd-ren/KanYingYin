# TMDB 类型标签筛选与刮削名称清理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Windows 版已有本地和个人网盘媒体补齐 TMDB 类型并提供可组合的多选筛选，同时安全清理截图中的发布规格词。

**Architecture:** 以 `TmdbMetadata.genres` 作为类型数据的权威来源，网盘平铺索引保存其投影供统一媒体库快速读取。纯 Dart 查询组件负责筛选，独立补齐服务负责去重请求和仓储更新，`LocalController` 只暴露状态与命令，现有媒体库面板负责交互。

**Tech Stack:** Flutter 3.41.9、Dart、MobX、Flutter Modular、Dio、flutter_test、PowerShell、MSIX。

**Platform Scope:** 只构建、打包和验收 Windows x64 MSIX。不构建 APK/AAB，不启动 Android 模拟器，不连接 Android 设备，不执行 Android 安装或实机测试。共享的 Dart/Flutter 单元与组件测试仍执行，用于验证跨平台媒体库公共逻辑。

---

## 文件结构

- 修改 `lib/modules/local/tmdb_metadata.dart`：新增不可变类型列表及 JSON、复制支持。
- 修改 `lib/services/tmdb/tmdb_client.dart`：解析和合并 TMDB 类型。
- 修改 `lib/services/tmdb/tmdb_metadata_merge_policy.dart`：刮削合并时保留新类型。
- 修改 `lib/modules/cloud/cloud_media_index_item.dart`：保存网盘索引的 TMDB 类型投影。
- 修改 `lib/repositories/cloud_media_index_repository.dart`：兼容读写 `tmdbGenres`。
- 修改 `lib/services/cloud/cloud_tmdb_metadata_service.dart`：新刮削结果同步类型。
- 修改 `lib/services/cloud/cloud_media_library.dart`：系列聚合类型。
- 新建 `lib/features/library/application/media_library_query.dart`：来源、关键词、类型的纯查询规则。
- 新建 `lib/features/library/application/library_genre_backfill_service.dart`：已有资源的后台增量补齐。
- 修改 `lib/pages/local/local_controller.dart` 与生成文件：触发补齐并暴露进度、失败和重试状态。
- 修改 `lib/pages/local/library_sheet.dart`：类型多选菜单、清除、进度和重试入口。
- 修改 `lib/services/tmdb/tmdb_resource_name_cleaner.dart`：安全识别新增发布片段。
- 修改版本、发布说明和版本契约测试：发布 Windows `2.1.104` 测试版。

### Task 1: 扩展 TMDB 类型领域模型和客户端解析

**Files:**
- Modify: `lib/modules/local/tmdb_metadata.dart`
- Modify: `lib/services/tmdb/tmdb_client.dart`
- Modify: `lib/services/tmdb/tmdb_metadata_merge_policy.dart`
- Test: `test/local_media_index_tmdb_test.dart`
- Test: `test/tmdb_client_test.dart`
- Test: `test/tmdb_metadata_policy_test.dart`

- [ ] **Step 1: 写入领域模型和客户端失败测试**

在 `local_media_index_tmdb_test.dart` 的往返测试中加入：

```dart
genres: const <String>['动作', '科幻'],
// JSON 往返后
expect(restored.tmdb?.genres, const <String>['动作', '科幻']);
expect(
  TmdbMetadata.fromJson(<String, dynamic>{
    ...item.tmdb!.toJson(),
    'genres': <Object?>['动作', '', '动作', 42, ' 科幻 '],
  }).genres,
  const <String>['动作', '科幻'],
);
```

在 `tmdb_client_test.dart` 的详情响应中加入 `genres`，并断言：

```dart
'genres': <Map<String, Object?>>[
  <String, Object?>{'id': 16, 'name': '动画'},
  <String, Object?>{'id': 878, 'name': '科幻'},
  <String, Object?>{'id': 999, 'name': '动画'},
],
// 请求完成后
expect(metadata.genres, const <String>['动画', '科幻']);
```

在 `tmdb_metadata_policy_test.dart` 增加：

```dart
test('合并元数据时始终采用详情返回的类型', () {
  final existing = _metadata(title: '旧标题', genres: const ['剧情']);
  final fetched = _metadata(title: '新标题', genres: const ['动画', '科幻']);
  final merged = mergePolicy.merge(
    existing: existing,
    fetched: fetched,
    options: const TmdbScrapeOptions.defaults(),
    locks: const TmdbFieldLocks(title: true, overview: true, poster: true),
    matchConfidence: 0.9,
  );
  expect(merged.genres, const <String>['动画', '科幻']);
});
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\local_media_index_tmdb_test.dart test\tmdb_client_test.dart test\tmdb_metadata_policy_test.dart
```

Expected: FAIL，错误明确指出 `genres` 命名参数或 getter 不存在。

- [ ] **Step 3: 最小实现类型模型、解析和合并**

在 `TmdbMetadata` 中加入不可变字段和规范化函数：

```dart
final List<String> genres;

const TmdbMetadata({
  required this.id,
  required this.mediaType,
  required this.title,
  required this.language,
  required this.matchedAt,
  required this.matchConfidence,
  this.originalTitle,
  this.overview,
  this.releaseDate,
  this.rating,
  this.posterUrl,
  this.backdropUrl,
  this.genres = const <String>[],
  this.seasons = const <TmdbSeasonMetadata>[],
});

static List<String> _genresFromJson(Object? value) {
  if (value is! List) return const <String>[];
  final result = <String>[];
  for (final item in value.whereType<String>()) {
    final genre = item.trim();
    if (genre.isNotEmpty && !result.contains(genre)) result.add(genre);
  }
  return List<String>.unmodifiable(result);
}
```

`fromJson`、`toJson` 和 `copyWith` 分别使用：

```dart
genres: _genresFromJson(json['genres']),
if (genres.isNotEmpty) 'genres': genres,
genres: genres ?? this.genres,
```

在 `TmdbClient._fromJson` 中解析：

```dart
genres: _genreNames(json['genres']),
```

并新增：

```dart
List<String> _genreNames(Object? value) {
  if (value is! List) return const <String>[];
  final result = <String>[];
  for (final raw in value.whereType<Map<Object?, Object?>>()) {
    final name = _asString(raw['name']);
    if (name != null && !result.contains(name)) result.add(name);
  }
  return List<String>.unmodifiable(result);
}
```

中英文详情合并与 `TmdbMetadataMergePolicy.merge` 都传入：

```dart
genres: primary.genres.isNotEmpty ? primary.genres : fallback.genres,
// merge policy
genres: fetched.genres,
```

- [ ] **Step 4: 运行目标测试并确认 GREEN**

Run: 与 Step 2 相同。

Expected: PASS，0 failures。

- [ ] **Step 5: 提交领域模型改动**

```powershell
git add lib/modules/local/tmdb_metadata.dart lib/services/tmdb/tmdb_client.dart lib/services/tmdb/tmdb_metadata_merge_policy.dart test/local_media_index_tmdb_test.dart test/tmdb_client_test.dart test/tmdb_metadata_policy_test.dart
git commit -m "功能：保存TMDB类型信息"
```

### Task 2: 将类型投影到网盘索引和统一媒体库

**Files:**
- Modify: `lib/modules/cloud/cloud_media_index_item.dart`
- Modify: `lib/repositories/cloud_media_index_repository.dart`
- Modify: `lib/services/cloud/cloud_tmdb_metadata_service.dart`
- Modify: `lib/services/cloud/cloud_media_library.dart`
- Test: `test/cloud_library_integration_test.dart`
- Test: `test/cloud_media_index_repository_test.dart`

- [ ] **Step 1: 写入网盘持久化和系列聚合失败测试**

在仓储测试构造带类型的条目并往返：

```dart
final enriched = item.replaceTmdb(
  tmdbId: 42,
  tmdbTitle: '中文片名',
  tmdbGenres: const <String>['动画', '科幻'],
);
await repository.replaceSource('openlist', <CloudMediaIndexItem>[enriched], {}, {}, ['/']);
expect(
  (await repository.getBySource('openlist')).single.tmdbGenres,
  const <String>['动画', '科幻'],
);
```

在 `cloud_library_integration_test.dart` 增加：

```dart
test('本地和网盘系列聚合稳定去重的 TMDB 类型', () {
  final localWithGenres = local.copyWith(
    tmdb: local.tmdb?.copyWith(genres: const ['剧情', '科幻']),
  );
  final cloudWithGenres = openList.replaceTmdb(
    tmdbId: 42,
    tmdbTitle: '中文片名',
    tmdbGenres: const ['动画', '科幻', '动画'],
  );
  final library = const CloudMediaLibraryAggregator().build(
    localItems: [localWithGenres],
    cloudItems: [cloudWithGenres],
    cloudSources: sources,
  );
  expect(library.series.firstWhere((e) => e.sourceId == 'local').genres,
      const ['剧情', '科幻']);
  expect(library.series.firstWhere((e) => e.sourceId == 'openlist').genres,
      const ['动画', '科幻']);
});
```

- [ ] **Step 2: 运行测试并确认 RED**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_index_repository_test.dart test\cloud_library_integration_test.dart
```

Expected: FAIL，`tmdbGenres` 和 `MediaLibrarySeries.genres` 尚不存在。

- [ ] **Step 3: 最小实现网盘类型投影**

在 `CloudMediaIndexItem` 构造函数、字段、`copyWith`、`replaceTmdb` 中加入：

```dart
this.tmdbGenres = const <String>[],
final List<String> tmdbGenres;
List<String>? tmdbGenres,
tmdbGenres: tmdbGenres ?? this.tmdbGenres,
```

仓储读写加入：

```dart
tmdbGenres: json['tmdbGenres'] is List
    ? (json['tmdbGenres'] as List).whereType<String>().toList(growable: false)
    : const <String>[],
if (item.tmdbGenres.isNotEmpty) 'tmdbGenres': item.tmdbGenres,
```

`CloudTmdbMetadataService.select` 调用 `replaceTmdb` 时加入：

```dart
tmdbGenres: metadata.genres,
```

`MediaLibrarySeries` 加入不可变 `genres`；本地从系列集数的 `item.tmdb?.genres` 合并，网盘从 `items.expand((item) => item.tmdbGenres)` 合并。使用同一私有函数：

```dart
List<String> _uniqueGenres(Iterable<String> values) {
  final result = <String>[];
  for (final value in values) {
    final genre = value.trim();
    if (genre.isNotEmpty && !result.contains(genre)) result.add(genre);
  }
  return List<String>.unmodifiable(result);
}
```

- [ ] **Step 4: 运行目标测试并确认 GREEN**

Run: 与 Step 2 相同。

Expected: PASS，旧索引缺少 `tmdbGenres` 时仍能读取。

- [ ] **Step 5: 提交索引和聚合改动**

```powershell
git add lib/modules/cloud/cloud_media_index_item.dart lib/repositories/cloud_media_index_repository.dart lib/services/cloud/cloud_tmdb_metadata_service.dart lib/services/cloud/cloud_media_library.dart test/cloud_media_index_repository_test.dart test/cloud_library_integration_test.dart
git commit -m "功能：聚合本地与网盘类型标签"
```

### Task 3: 新增可组合的媒体库类型查询

**Files:**
- Create: `lib/features/library/application/media_library_query.dart`
- Create: `test/media_library_query_test.dart`

- [ ] **Step 1: 写入查询规则失败测试**

创建测试，使用最小 `MediaLibrarySeries` 固件覆盖：

```dart
test('多个类型任一匹配并与来源关键词同时满足', () {
  final result = const MediaLibraryQuery().apply(
    series: <MediaLibrarySeries>[
      _series('local', '星际动画', const ['动画', '科幻']),
      _series('openlist', '太空纪录片', const ['纪录片']),
      _series('openlist', '科幻电影', const ['科幻']),
    ],
    sourceId: 'openlist',
    keyword: '片',
    selectedGenres: const <String>{'动画', '科幻'},
  );
  expect(result.map((item) => item.title), const ['科幻电影']);
});

test('可用类型按中文名称排序且切换来源移除失效选择', () {
  final query = const MediaLibraryQuery();
  final available = query.availableGenres(
    <MediaLibrarySeries>[
      _series('local', 'A', const ['科幻', '动画']),
      _series('openlist', 'B', const ['纪录片']),
    ],
    sourceId: 'local',
  );
  expect(available, const ['动画', '科幻']);
  expect(query.retainAvailableGenres(const {'科幻', '纪录片'}, available),
      const <String>{'科幻'});
});
```

- [ ] **Step 2: 运行并确认 RED**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\media_library_query_test.dart
```

Expected: FAIL，导入文件或 `MediaLibraryQuery` 不存在。

- [ ] **Step 3: 实现纯查询组件**

```dart
class MediaLibraryQuery {
  const MediaLibraryQuery();

  List<MediaLibrarySeries> apply({
    required Iterable<MediaLibrarySeries> series,
    String sourceId = 'all',
    String keyword = '',
    Set<String> selectedGenres = const <String>{},
  }) {
    final query = keyword.trim().toLowerCase();
    return series.where((item) {
      if (sourceId != 'all' && item.sourceId != sourceId) return false;
      if (query.isNotEmpty && !item.title.toLowerCase().contains(query)) {
        return false;
      }
      if (selectedGenres.isNotEmpty &&
          !item.genres.any(selectedGenres.contains)) return false;
      return true;
    }).toList(growable: false);
  }

  List<String> availableGenres(Iterable<MediaLibrarySeries> series,
      {String sourceId = 'all'}) {
    final values = <String>{};
    for (final item in series) {
      if (sourceId == 'all' || item.sourceId == sourceId) {
        values.addAll(item.genres);
      }
    }
    return values.toList(growable: false)..sort();
  }

  Set<String> retainAvailableGenres(
          Set<String> selected, Iterable<String> available) =>
      selected.intersection(available.toSet());
}
```

- [ ] **Step 4: 运行测试并确认 GREEN**

Run: 与 Step 2 相同。

Expected: PASS。

- [ ] **Step 5: 提交查询组件**

```powershell
git add lib/features/library/application/media_library_query.dart test/media_library_query_test.dart
git commit -m "功能：新增媒体库类型查询"
```

### Task 4: 为已有资源实现后台类型补齐服务

**Files:**
- Create: `lib/features/library/application/library_genre_backfill_service.dart`
- Create: `test/library_genre_backfill_service_test.dart`
- Modify: `lib/repositories/local_media_index_repository.dart` only if the existing interface needs no-op test exposure; prefer existing `updateItems`.

- [ ] **Step 1: 写入去重、持久化和失败隔离测试**

```dart
test('同一 TMDB 作品只请求一次并更新本地与网盘条目', () async {
  final client = _FakeTmdbClient(<String, TmdbMetadata>{
    'tv:42': _metadata(42, TmdbMediaType.tv, const ['动画']),
  });
  final result = await LibraryGenreBackfillService(
    localRepository: localRepository,
    cloudRepository: cloudRepository,
    clientFactory: (_) => client,
  ).backfill(
    apiKey: 'key',
    localItems: <LocalMediaIndexItem>[localA, localB],
    cloudItems: <CloudMediaIndexItem>[cloudA],
  );
  expect(client.detailKeys, const ['tv:42']);
  expect(result.updatedWorks, 1);
  expect(result.failedWorks, 0);
  expect(localRepository.getAll().every((item) => item.tmdb!.genres.contains('动画')), isTrue);
  expect((await cloudRepository.getBySource('openlist')).single.tmdbGenres,
      const ['动画']);
});

test('无 Key 直接返回且单项失败不阻止其他作品', () async {
  final noKey = await service.backfill(
    apiKey: '',
    localItems: [localA],
    cloudItems: const [],
  );
  expect(noKey.updatedWorks, 0);
  expect(noKey.failedWorks, 0);
  client.throwKeys.add('movie:7');
  final result = await service.backfill(
    apiKey: 'key',
    localItems: [movie7, tv42],
    cloudItems: const [],
  );
  expect(result.updatedWorks, 1);
  expect(result.failedWorks, 1);
});
```

- [ ] **Step 2: 运行并确认 RED**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\library_genre_backfill_service_test.dart
```

Expected: FAIL，补齐服务和结果类型不存在。

- [ ] **Step 3: 实现补齐服务的最小公开接口**

```dart
typedef TmdbClientFactory = ITmdbClient Function(String apiKey);

class LibraryGenreBackfillResult {
  const LibraryGenreBackfillResult({
    required this.updatedWorks,
    required this.failedWorks,
  });
  final int updatedWorks;
  final int failedWorks;
}

class LibraryGenreBackfillService {
  const LibraryGenreBackfillService({
    required ILocalMediaIndexRepository localRepository,
    required CloudMediaIndexRepository cloudRepository,
    required TmdbClientFactory clientFactory,
  }) : _localRepository = localRepository,
       _cloudRepository = cloudRepository,
       _clientFactory = clientFactory;

  final ILocalMediaIndexRepository _localRepository;
  final CloudMediaIndexRepository _cloudRepository;
  final TmdbClientFactory _clientFactory;

  Future<LibraryGenreBackfillResult> backfill({
    required String apiKey,
    required List<LocalMediaIndexItem> localItems,
    required List<CloudMediaIndexItem> cloudItems,
    void Function(int current, int total)? onProgress,
  }) async {
    if (apiKey.trim().isEmpty) {
      return const LibraryGenreBackfillResult(updatedWorks: 0, failedWorks: 0);
    }
    final targets = <(TmdbMediaType, int), _GenreTargets>{};
    for (var index = 0; index < localItems.length; index++) {
      final metadata = localItems[index].tmdb;
      if (metadata == null ||
          metadata.id <= 0 ||
          metadata.genres.isNotEmpty ||
          localItems[index].scrapeStatus != TmdbScrapeStatus.matched) {
        continue;
      }
      targets
          .putIfAbsent(
            (metadata.mediaType, metadata.id),
            _GenreTargets.new,
          )
          .localIndexes
          .add(index);
    }
    for (final item in cloudItems) {
      final key = _cloudKey(item);
      if (key == null || item.tmdbGenres.isNotEmpty) continue;
      targets.putIfAbsent(key, _GenreTargets.new).cloudItems.add(item);
    }
    if (targets.isEmpty) {
      return const LibraryGenreBackfillResult(updatedWorks: 0, failedWorks: 0);
    }

    final client = _clientFactory(apiKey.trim());
    final updatedLocalItems = localItems.toList(growable: false);
    var localChanged = false;
    var updatedWorks = 0;
    var failedWorks = 0;
    var current = 0;
    for (final entry in targets.entries) {
      try {
        final details = await client.details(
          entry.key.$2,
          entry.key.$1,
          language: 'zh-CN',
        );
        if (details.genres.isEmpty) continue;
        for (final index in entry.value.localIndexes) {
          final item = updatedLocalItems[index];
          updatedLocalItems[index] = item.copyWith(
            tmdb: item.tmdb!.copyWith(genres: details.genres),
          );
          localChanged = true;
        }
        for (final cloudItem in entry.value.cloudItems) {
          await _cloudRepository.updateMatching(
            cloudItem.sourceId,
            (item) => _cloudKey(item) == entry.key,
            (item) => item.copyWith(tmdbGenres: details.genres),
          );
        }
        updatedWorks++;
      } on Object {
        failedWorks++;
      } finally {
        current++;
        onProgress?.call(current, targets.length);
      }
    }
    if (localChanged) await _localRepository.updateItems(updatedLocalItems);
    return LibraryGenreBackfillResult(
      updatedWorks: updatedWorks,
      failedWorks: failedWorks,
    );
  }

  (TmdbMediaType, int)? _cloudKey(CloudMediaIndexItem item) {
    final id = item.tmdbId;
    if (id == null || id <= 0) return null;
    final type = switch (item.mediaType) {
      CloudMediaType.movie => TmdbMediaType.movie,
      CloudMediaType.series ||
      CloudMediaType.episode ||
      CloudMediaType.special =>
        TmdbMediaType.tv,
      CloudMediaType.unknown => null,
    };
    return type == null ? null : (type, id);
  }
}

class _GenreTargets {
  final List<int> localIndexes = <int>[];
  final List<CloudMediaIndexItem> cloudItems = <CloudMediaIndexItem>[];
}
```

实现时将 `CloudMediaType.movie` 映射到 `TmdbMediaType.movie`，将 `series`、`episode`、`special` 映射到 `tv`，`unknown` 不自动请求。先批量更新内存中的本地列表并调用一次 `updateItems`；网盘按 `sourceId + tmdbId + mediaType` 使用 `updateMatching`，只替换 `tmdbGenres`，不触碰其他字段。

- [ ] **Step 4: 运行测试并确认 GREEN**

Run: 与 Step 2 相同。

Expected: PASS，重复作品只产生一次详情请求，部分失败仍更新成功作品。

- [ ] **Step 5: 提交补齐服务**

```powershell
git add lib/features/library/application/library_genre_backfill_service.dart test/library_genre_backfill_service_test.dart
git commit -m "功能：后台补齐已有资源类型"
```

### Task 5: 接入控制器状态和自动/手动触发

**Files:**
- Modify: `lib/pages/local/local_controller.dart`
- Modify generated: `lib/pages/local/local_controller.g.dart`
- Test: `test/local_controller_test.dart`

- [ ] **Step 1: 写入控制器失败测试**

```dart
test('加载索引后后台补齐类型并支持失败重试', () async {
  final completer = Completer<TmdbMetadata>();
  final controller = LocalController(
    mediaIndexRepository: localRepository,
    cloudMediaIndexRepository: cloudRepository,
    tmdbApiKeyProvider: TmdbApiKeyProvider(userKeyReader: () => 'key'),
    genreBackfillService: fakeService,
  );
  final refresh = controller.refreshLibraryGenres();
  await Future<void>.delayed(Duration.zero);
  expect(controller.isRefreshingLibraryGenres, isTrue);
  completer.complete(metadataWithGenres);
  await refresh;
  expect(controller.isRefreshingLibraryGenres, isFalse);
  expect(controller.libraryGenreRefreshProgress, contains('已更新'));
});
```

同时断言 `init()` 使用 `unawaited` 触发补齐，媒体库初始化不会等待详情请求完成。

- [ ] **Step 2: 运行并确认 RED**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\local_controller_test.dart
```

Expected: FAIL，构造参数、状态或刷新方法不存在。

- [ ] **Step 3: 接入控制器**

构造函数注入可选 `LibraryGenreBackfillService`，默认复用现有仓储和 `TmdbClient`。增加：

```dart
@observable
bool isRefreshingLibraryGenres = false;

@observable
String libraryGenreRefreshProgress = '';

@observable
String? libraryGenreRefreshError;

@action
Future<LibraryGenreBackfillResult> refreshLibraryGenres() async {
  if (isRefreshingLibraryGenres) {
    return const LibraryGenreBackfillResult(updatedWorks: 0, failedWorks: 0);
  }
  isRefreshingLibraryGenres = true;
  libraryGenreRefreshError = null;
  try {
    final result = await _genreBackfillService.backfill(
      apiKey: _tmdbApiKey,
      localItems: localLibraryItems.toList(growable: false),
      cloudItems: cloudLibraryItems.toList(growable: false),
      onProgress: (current, total) => runInAction(() {
        libraryGenreRefreshProgress = '正在补齐类型 $current/$total';
      }),
    );
    _reloadLocalLibraryIndexSafe();
    await reloadCloudLibraryIndex();
    libraryGenreRefreshProgress = '已更新 ${result.updatedWorks} 个作品类型';
    if (result.failedWorks > 0) {
      libraryGenreRefreshError = '${result.failedWorks} 个作品暂时无法更新';
    }
    return result;
  } finally {
    isRefreshingLibraryGenres = false;
  }
}
```

增加一个不阻塞 `init()` 的顺序助手，确保网盘索引已加载后才统一补齐：

```dart
Future<void> _reloadCloudAndBackfillGenres() async {
  await reloadCloudLibraryIndex();
  await refreshLibraryGenres();
}
```

将 `init()` 中原来的 `unawaited(reloadCloudLibraryIndex())` 替换为 `unawaited(_reloadCloudAndBackfillGenres())`。无 Key 或无候选时服务立即返回，不影响界面。用项目现有 build_runner 命令更新 MobX 生成文件。

- [ ] **Step 4: 生成 MobX 文件并运行测试**

```powershell
D:\flutter\bin\dart.bat run build_runner build --delete-conflicting-outputs
D:\flutter\bin\flutter.bat test --no-pub test\local_controller_test.dart test\cloud_library_integration_test.dart
```

Expected: build_runner exit 0；测试 PASS。

- [ ] **Step 5: 提交控制器接入**

```powershell
git add lib/pages/local/local_controller.dart lib/pages/local/local_controller.g.dart test/local_controller_test.dart
git commit -m "功能：接入类型补齐状态"
```

### Task 6: 增加类型多选筛选界面

**Files:**
- Modify: `lib/pages/local/library_sheet.dart`
- Test: `test/cloud_library_integration_test.dart`

- [ ] **Step 1: 写入组件失败测试**

```dart
testWidgets('类型菜单支持多选任一匹配和清除', (tester) async {
  final controller = _controllerWithGenreSeries();
  await tester.pumpWidget(_librarySheet(controller));
  await tester.tap(find.byTooltip('筛选 TMDB 类型'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('动画'));
  await tester.tap(find.byTooltip('筛选 TMDB 类型'));
  await tester.tap(find.text('科幻'));
  await tester.pumpAndSettle();
  expect(find.text('类型 2'), findsOneWidget);
  expect(find.text('动画作品'), findsOneWidget);
  expect(find.text('科幻作品'), findsOneWidget);
  expect(find.text('纪录片作品'), findsNothing);
  await tester.tap(find.byTooltip('筛选 TMDB 类型'));
  await tester.tap(find.text('清除'));
  await tester.pumpAndSettle();
  expect(find.text('纪录片作品'), findsOneWidget);
});

testWidgets('补齐失败时保留轻量重试入口', (tester) async {
  controller.libraryGenreRefreshError = '1 个作品暂时无法更新';
  await tester.pumpWidget(_librarySheet(controller));
  expect(find.text('1 个作品暂时无法更新'), findsOneWidget);
  expect(find.byTooltip('刷新类型标签'), findsOneWidget);
});
```

- [ ] **Step 2: 运行并确认 RED**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\cloud_library_integration_test.dart
```

Expected: FAIL，找不到类型筛选按钮或数量文本。

- [ ] **Step 3: 实现紧凑类型菜单并改用查询组件**

状态增加：

```dart
final Set<String> _selectedGenres = <String>{};
final MediaLibraryQuery _libraryQuery = const MediaLibraryQuery();
```

来源变化时执行：

```dart
final available = _libraryQuery.availableGenres(
  library.series,
  sourceId: value,
);
setState(() {
  widget.controller.selectLibrarySource(value);
  _selectedGenres
    ..clear()
    ..addAll(_libraryQuery.retainAvailableGenres(_selectedGenres, available));
});
```

类型入口使用 `PopupMenuButton<String>`，每个选项用 `CheckedPopupMenuItem`，点击后切换集合；首项 `clear` 清空。按钮 tooltip 为“筛选 TMDB 类型”，文本为：

```dart
Text(_selectedGenres.isEmpty ? '类型' : '类型 ${_selectedGenres.length}')
```

列表结果统一由 `MediaLibraryQuery.apply` 计算，再分别映射为本地和网盘现有 tile；本地排序继续使用 `_filtered` 的原排序规则。补齐中显示小尺寸 `CircularProgressIndicator` 和进度文本，失败时显示汇总文本及 tooltip 为“刷新类型标签”的刷新图标按钮。

- [ ] **Step 4: 运行组件与查询测试并确认 GREEN**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\media_library_query_test.dart test\cloud_library_integration_test.dart
```

Expected: PASS，类型为空时不显示空菜单，来源切换会清理失效选择。

- [ ] **Step 5: 提交界面改动**

```powershell
git add lib/pages/local/library_sheet.dart test/cloud_library_integration_test.dart
git commit -m "功能：增加TMDB类型多选筛选"
```

### Task 7: 安全清理截图中的发布词

**Files:**
- Modify: `lib/services/tmdb/tmdb_resource_name_cleaner.dart`
- Test: `test/tmdb_resource_name_cleaner_test.dart`
- Test: `test/tmdb_scrape_policy_test.dart`

- [ ] **Step 1: 写入截图样例和防误删失败测试**

```dart
test('清除新增 REMUX 发布片段但保留正常短片名', () {
  const suffixes = <String>[
    'REMUX -HD MA TrueHD 7 1',
    'PROPER US REMUX -HD MA TrueHD 7 1',
    'UHD REMUX TrueHD7 1-DreamHD',
    'V4 UHD REMUX TrueHD7 1 Multi Audio-D',
    'V3 UHD REMUX DoVi TrueHD7 1 14Audio',
  ];
  for (final suffix in suffixes) {
    expect(cleaner.clean('流浪地球 $suffix.mkv'), '流浪地球', reason: suffix);
  }
  expect(cleaner.clean('Us (2019).mkv'), 'Us (2019)');
  expect(cleaner.clean('V字仇杀队.mkv'), 'V字仇杀队');
});
```

在 `tmdb_scrape_policy_test.dart` 使用最长样例断言查询词为 `流浪地球`。

- [ ] **Step 2: 运行并确认 RED**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\tmdb_resource_name_cleaner_test.dart test\tmdb_scrape_policy_test.dart
```

Expected: FAIL，查询词残留 `HD MA`、`DoVi`、`Multi Audio`、`14Audio` 或 `V3/V4`。

- [ ] **Step 3: 实现上下文限定的发布片段清理**

扩展已知规格 token：

```dart
r'dovi|hd[ ._-]*ma|multi[ ._-]*audio|\d{1,2}[ ._-]*audio|'
```

新增只匹配尾部发布片段的模式，避免全局删除 `US` 与版本词：

```dart
static final RegExp _releaseContextSuffixPattern = RegExp(
  r'(?:(?<![A-Za-z0-9])v\d{1,2}(?![A-Za-z0-9])[ ._-]*)?'
  r'(?:(?:proper|us|uhd|remux|dovi|hd[ ._-]*ma|true[ ._-]*hd|'
  r'multi[ ._-]*audio|\d{1,2}[ ._-]*audio|[ ._-])+)$',
  caseSensitive: false,
);
```

先由既有 release token 清除长规格，再对剩余尾部使用上下文模式；不得把 `us` 加入全局 `_releaseTokenPattern`。保持 `DreamHD` 只按已知发布组尾缀清理。

- [ ] **Step 4: 运行测试并确认 GREEN**

Run: 与 Step 2 相同。

Expected: PASS，所有截图样例得到干净标题，`Us` 与中文正式片名保持不变。

- [ ] **Step 5: 提交清理规则**

```powershell
git add lib/services/tmdb/tmdb_resource_name_cleaner.dart test/tmdb_resource_name_cleaner_test.dart test/tmdb_scrape_policy_test.dart
git commit -m "优化：清理REMUX发布规格词"
```

### Task 8: 更新 2.1.104 测试版元数据和用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`
- Modify: version and release contract tests under `test/`

- [ ] **Step 1: 先更新版本契约测试为 RED**

将当前 Windows 测试版本期望统一为：

```dart
const expectedVersion = '2.1.104';
const expectedBuildNumber = '20104';
const expectedMsixVersion = '2.1.104.0';
```

版本历史测试断言普通用户文案至少包含：

```dart
expect(changes, contains('媒体库新增 TMDB 类型标签筛选，可同时选择多个类型，并与来源和名称搜索一起使用'));
expect(changes, contains('已有本地和网盘资源会在后台补齐类型信息，断网或 TMDB 不可用时不影响浏览和播放'));
expect(changes, contains('改进复杂 REMUX 文件名的 TMDB 匹配，减少画质、音轨和发布组信息干扰'));
```

- [ ] **Step 2: 运行版本测试并确认 RED**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart test\version_history_current_test.dart test\release_config_contract_test.dart
```

Expected: FAIL，当前版本仍为 `1.0.5`。

- [ ] **Step 3: 更新版本和普通用户文案**

统一修改：

```yaml
version: 2.1.104+20104
msix_config:
  msix_version: 2.1.104.0
```

`AppVersion.current` 设为 `2.1.104`。`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md` 和 `VersionHistory` 新增日期 `2026-08-03` 的 Windows 测试版条目，使用 Step 1 的三条用户文案，并明确不会修改或删除本地及网盘原始文件。Android 正式版版本号和 Android 更新内容保持不变。

- [ ] **Step 4: 运行版本测试并确认 GREEN**

Run: 与 Step 2 相同。

Expected: PASS。

- [ ] **Step 5: 提交版本文案**

```powershell
git add pubspec.yaml lib/core/app_version.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/release_config_contract_test.dart
git commit -m "发布：准备2.1.104类型筛选测试版"
```

### Task 9: 完整验证、MSIX 交付与最终提交检查

**Files:**
- Verify all changed files
- Generated artifact: desktop `看影音-2.1.104.msix`

本任务不执行任何 Android 构建、打包、安装、模拟器或实机命令。

- [ ] **Step 1: 检查差异和 UTF-8 内容**

```powershell
chcp 65001 > $null
$OutputEncoding = [System.Text.UTF8Encoding]::new()
git status --short
git diff --check
git log -9 --oneline
```

Expected: 只有本轮相关提交和文件，无空白错误、无意外未跟踪文件。

- [ ] **Step 2: 运行完整测试**

```powershell
D:\flutter\bin\flutter.bat test --no-pub
```

Expected: exit 0，0 failures。

- [ ] **Step 3: 运行静态分析**

```powershell
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: `No issues found!`。

- [ ] **Step 4: 构建 Windows Release**

```powershell
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: exit 0，`build\windows\x64\runner\Release\kanyingyin.exe` 新鲜生成。

- [ ] **Step 5: 使用仓库脚本生成签名 MSIX**

先按 `flutter-windows-msix-packaging` 技能检查仓库脚本参数，再执行实际脚本。预期命令形态：

```powershell
powershell -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1
```

Expected: exit 0，生成签名的 `2.1.104.0` x64 MSIX，并复制到当前用户桌面为 `看影音-2.1.104.msix`。

- [ ] **Step 6: 独立核验包身份、版本、签名和哈希**

解包读取 `AppxManifest.xml`，核对：

```text
Identity Name=com.kanyingyin.player
Identity Version=2.1.104.0
ProcessorArchitecture=x64
```

用 `signtool verify /pa` 验证签名；分别计算构建产物和桌面副本 SHA-256，预期完全一致。再次执行 `Get-AppxPackage -Name com.kanyingyin.player`，记录已安装版本仍为 `2.1.103.0`，除非用户明确要求安装。

- [ ] **Step 7: 最终工作区和提交检查**

```powershell
git status --short
git log -10 --oneline --decorate
```

Expected: 工作区干净；所有本轮改动已提交；未推送、未自动安装新包。
