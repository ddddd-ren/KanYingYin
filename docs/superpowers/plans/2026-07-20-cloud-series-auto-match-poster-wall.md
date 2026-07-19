# 网盘系列自动匹配与海报墙实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. The user explicitly forbids subagents. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 手动确认一个网盘分集后，让同目录同剧分集立即及后续自动继承，并把当前目录改为遵守网盘识别大小设置的作品海报墙。

**Architecture:** 新增精确系列身份、持久化系列规则和无网络传播服务。协调器先应用规则再执行 TMDB 搜索，索引器在扫描时复用规则。页面通过纯分组组件把文件夹导航与电影、剧集作品分开，并用现有视频大小设置统一过滤所有识别链路。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、Material 3、Hive 设置存储、flutter_test、Windows Release、MSIX

---

## 文件职责

新增文件：

- `lib/modules/cloud/cloud_series_match_rule.dart`：系列身份、规则和 JSON 模型
- `lib/repositories/cloud_series_match_rule_repository.dart`：规则持久化、覆盖、来源删除和恢复
- `lib/services/cloud/cloud_series_identity_resolver.dart`：从视频路径和大小生成精确系列身份
- `lib/services/cloud/cloud_series_match_service.dart`：学习手动选择、批量传播、后续规则应用和索引同步
- `lib/pages/cloud/resources/cloud_resource_collection.dart`：当前目录文件夹与作品分组的纯模型和算法
- `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`：文件夹导航与作品海报墙
- `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`：剧集选集列表
- `test/cloud_series_match_rule_repository_test.dart`
- `test/cloud_series_identity_resolver_test.dart`
- `test/cloud_series_match_service_test.dart`
- `test/cloud_resource_collection_test.dart`

修改文件：

- `lib/utils/storage.dart`：新增系列规则设置键
- `lib/repositories/cloud_resource_tmdb_repository.dart`：增加原子批量写入
- `lib/services/cloud/cloud_resource_tmdb_service.dart`：目标携带文件大小
- `lib/services/cloud/cloud_resource_tmdb_search.dart`：选择结果携带传播摘要
- `lib/services/cloud/cloud_resource_tmdb_coordinator.dart`：手动学习和规则优先匹配
- `lib/services/cloud/cloud_resource_auto_organizer.dart`：统一应用网盘视频大小阈值
- `lib/services/cloud/cloud_media_indexer.dart`：扫描结果继承系列规则
- `lib/pages/cloud/resources/cloud_resources_controller.dart`：提供作品集合、传播上下文和规则优先批量整理
- `lib/pages/cloud/resources/cloud_resources_grid.dart`：删除旧单文件网格，由作品海报墙替代
- `lib/pages/cloud/resources/cloud_resources_page.dart`：文件夹导航、海报墙、选集和传播反馈
- `lib/providers/cloud_library_controller.dart`：删除来源时删除并可回滚系列规则
- `lib/pages/index_module.dart`：注册和注入规则仓库、传播服务及大小设置
- 相关现有测试：控制器、协调器、扫描器、页面、来源删除、模块依赖和版本测试

## Task 1：系列身份与规则持久化

**Files:**
- Create: `lib/modules/cloud/cloud_series_match_rule.dart`
- Create: `lib/services/cloud/cloud_series_identity_resolver.dart`
- Create: `lib/repositories/cloud_series_match_rule_repository.dart`
- Modify: `lib/utils/storage.dart`
- Test: `test/cloud_series_identity_resolver_test.dart`
- Test: `test/cloud_series_match_rule_repository_test.dart`

- [ ] **Step 1：写系列身份失败测试**

测试使用截图中的名称，并验证目录、来源、阈值和电影边界：

```dart
final resolver = CloudSeriesIdentityResolver();
final first = resolver.resolve(
  sourceId: 'quark',
  remotePath: '/剧集/The.Resurrected.S01E01.2160p.NF.WEB-DL.mkv',
  size: 4 * 1024 * 1024 * 1024,
  minSizeBytes: 1024 * 1024,
);
final second = resolver.resolve(
  sourceId: 'quark',
  remotePath: '/剧集/The.Resurrected.S01E02.1080p.WEB-DL.mkv',
  size: 2 * 1024 * 1024 * 1024,
  minSizeBytes: 1024 * 1024,
);
expect(first?.stableKey, second?.stableKey);
expect(first?.seasonNumber, 1);
expect(first?.episodeNumber, 1);
expect(first?.normalizedSeriesName, 'the resurrected');
expect(
  resolver.resolve(
    sourceId: 'quark',
    remotePath: '/剧集/样片.S01E03.mkv',
    size: 1024 * 1024,
    minSizeBytes: 1024 * 1024,
  ),
  isNull,
);
```

另外断言不同父目录、不同来源和不同剧名的 `stableKey` 不同；`Movie.2026.mkv` 返回 `null`。

- [ ] **Step 2：运行测试确认类型不存在**

Run: `D:\flutter\bin\flutter.bat test test\cloud_series_identity_resolver_test.dart`

Expected: FAIL，提示 `CloudSeriesIdentityResolver` 不存在。

- [ ] **Step 3：实现精确系列身份**

公开接口固定为：

```dart
@immutable
class CloudSeriesEpisodeIdentity {
  const CloudSeriesEpisodeIdentity({
    required this.sourceId,
    required this.parentPath,
    required this.seriesName,
    required this.normalizedSeriesName,
    required this.seasonNumber,
    required this.episodeNumber,
  });

  final String sourceId;
  final String parentPath;
  final String seriesName;
  final String normalizedSeriesName;
  final int? seasonNumber;
  final int episodeNumber;

  String get stableKey =>
      '$sourceId|$parentPath|$normalizedSeriesName';
}

class CloudSeriesIdentityResolver {
  CloudSeriesIdentityResolver({LocalEpisodeParser? episodeParser})
      : _episodeParser = episodeParser ?? LocalEpisodeParser();

  final LocalEpisodeParser _episodeParser;

  CloudSeriesEpisodeIdentity? resolve({
    required String sourceId,
    required String remotePath,
    required int size,
    required int minSizeBytes,
  });
}
```

`resolve` 先规范化 POSIX 路径，再调用 `LocalVideoFileTypes.isRecognizedVideo` 和 `LocalEpisodeParser.parse`。没有有效集号时返回 `null`。标准剧名把点和下划线替换为空格，折叠空白并转小写。

- [ ] **Step 4：写规则仓库失败测试**

```dart
final storage = MemoryCloudSeriesMatchRuleStorage();
final repository = CloudSeriesMatchRuleRepository(storage: storage);
final original = CloudSeriesMatchRule(
  sourceId: 'quark',
  parentPath: '/剧集',
  normalizedSeriesName: 'the resurrected',
  metadata: metadata,
  posterCachePath: 'poster.jpg',
  updatedAt: DateTime.utc(2026, 7, 20),
);
await repository.upsert(original);
expect(await repository.get(original.stableKey), original);
await repository.upsert(
  original.copyWith(updatedAt: DateTime.utc(2026, 7, 21)),
);
expect((await repository.get(original.stableKey))?.updatedAt,
    DateTime.utc(2026, 7, 21));
final removed = await repository.removeSource('quark');
expect(removed, hasLength(1));
await repository.replaceSource('quark', removed);
expect(await repository.getBySource('quark'), hasLength(1));
```

- [ ] **Step 5：实现规则模型、存储和仓库**

在 `SettingBoxKey` 增加：

```dart
cloudSeriesMatchRules = 'cloudSeriesMatchRules',
```

规则模型使用 `TmdbMetadata.toJson` 和 `TmdbMetadata.fromJson` 保存完整元数据，并实现值相等、`hashCode` 和只更新 `updatedAt` 的 `copyWith`。仓库接口固定为：

```dart
Future<CloudSeriesMatchRule?> get(String stableKey);
Future<List<CloudSeriesMatchRule>> getBySource(String sourceId);
Future<void> upsert(CloudSeriesMatchRule rule);
Future<List<CloudSeriesMatchRule>> removeSource(String sourceId);
Future<void> replaceSource(
  String sourceId,
  List<CloudSeriesMatchRule> rules,
);
```

使用按 `synchronizationIdentity` 共享的 `Lock`，防止并发覆盖。

- [ ] **Step 6：格式化并运行两组测试**

Run: `D:\flutter\bin\dart.bat format lib\modules\cloud\cloud_series_match_rule.dart lib\services\cloud\cloud_series_identity_resolver.dart lib\repositories\cloud_series_match_rule_repository.dart test\cloud_series_identity_resolver_test.dart test\cloud_series_match_rule_repository_test.dart`

Run: `D:\flutter\bin\flutter.bat test test\cloud_series_identity_resolver_test.dart test\cloud_series_match_rule_repository_test.dart`

Expected: PASS。

- [ ] **Step 7：提交系列身份和仓库**

```powershell
git add -- lib/modules/cloud/cloud_series_match_rule.dart lib/services/cloud/cloud_series_identity_resolver.dart lib/repositories/cloud_series_match_rule_repository.dart lib/utils/storage.dart test/cloud_series_identity_resolver_test.dart test/cloud_series_match_rule_repository_test.dart
git commit -m "feat(cloud): 保存同目录系列匹配规则"
```

## Task 2：原子传播服务

**Files:**
- Create: `lib/services/cloud/cloud_series_match_service.dart`
- Modify: `lib/repositories/cloud_resource_tmdb_repository.dart`
- Modify: `lib/services/cloud/cloud_resource_tmdb_service.dart`
- Test: `test/cloud_series_match_service_test.dart`
- Modify: `test/cloud_resource_tmdb_repository_test.dart`

- [ ] **Step 1：写原子批量记录失败测试**

```dart
await repository.upsertAll(<CloudResourceTmdbRecord>[first, second]);
expect(await repository.get(first.stableKey), first);
expect(await repository.get(second.stableKey), second);
```

使用会在 `write` 抛错的存储，断言原始快照不产生单条新增记录。

- [ ] **Step 2：运行测试确认 `upsertAll` 不存在**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_tmdb_repository_test.dart`

Expected: FAIL，提示 `upsertAll` 未定义。

- [ ] **Step 3：实现单锁单写的 `upsertAll`**

```dart
Future<void> upsertAll(Iterable<CloudResourceTmdbRecord> updates) {
  return _mutationLock.synchronized(() async {
    final records = await _getAll();
    final byKey = <String, CloudResourceTmdbRecord>{
      for (final record in records) record.stableKey: record,
      for (final record in updates) record.stableKey: record,
    };
    await _write(byKey.values.toList(growable: false));
  });
}
```

- [ ] **Step 4：写传播服务失败测试**

测试一次手动选择传播到 `S01E02` 和 `S01E03`，但保留已有匹配和自定义标题：

```dart
final result = await service.learnAndPropagate(
  anchor: firstTarget,
  anchorRecord: selectedRecord,
  candidates: <CloudResourceTmdbTarget>[
    firstTarget,
    secondTarget,
    thirdTarget,
    alreadyMatchedTarget,
    customTitleTarget,
  ],
  existingRecords: existingRecords,
  language: 'zh-CN',
);
expect(result.eligible, isTrue);
expect(result.ruleSaved, isTrue);
expect(result.records.map((record) => record.remoteId),
    <String>['episode-2', 'episode-3']);
expect(result.indexSyncFailures, 0);
expect(tmdbClientCalls, 0);
```

再写 `applyRule` 测试，预置近期 `unmatched` 记录并断言仍生成 `matched` 记录。

- [ ] **Step 5：运行传播测试确认服务不存在**

Run: `D:\flutter\bin\flutter.bat test test\cloud_series_match_service_test.dart`

Expected: FAIL，提示 `CloudSeriesMatchService` 不存在。

- [ ] **Step 6：实现传播服务和强类型结果**

公开类型固定为：

```dart
class CloudSeriesPropagationResult {
  const CloudSeriesPropagationResult({
    required this.eligible,
    required this.ruleSaved,
    required this.records,
    required this.indexSyncFailures,
    required this.pendingIndexSyncTargets,
  });

  final bool eligible;
  final bool ruleSaved;
  final List<CloudResourceTmdbRecord> records;
  final int indexSyncFailures;
  final List<CloudResourceTmdbTarget> pendingIndexSyncTargets;
}

class CloudSeriesRuleApplication {
  const CloudSeriesRuleApplication({
    required this.record,
    required this.metadata,
    required this.indexSynced,
  });

  final CloudResourceTmdbRecord record;
  final TmdbMetadata metadata;
  final bool indexSynced;
}
```

服务构造参数为规则仓库、资源记录仓库、媒体索引仓库、身份解析器、阈值提供者和时钟。公开方法固定为：

```dart
Future<CloudSeriesPropagationResult> learnAndPropagate({
  required CloudResourceTmdbTarget anchor,
  required CloudResourceTmdbRecord anchorRecord,
  required List<CloudResourceTmdbTarget> candidates,
  required Map<String, CloudResourceTmdbRecord> existingRecords,
  required String language,
});

Future<CloudSeriesRuleApplication?> applyRule({
  required CloudResourceTmdbTarget target,
  CloudResourceTmdbRecord? existingRecord,
});

Future<bool> syncRecordToIndex({
  required CloudResourceTmdbTarget target,
  required CloudResourceTmdbRecord record,
});
```

`learnAndPropagate` 仅接受 `anchorRecord.mediaType == TmdbMediaType.tv`。它先尝试保存规则，再按身份精确筛选兄弟目标；匹配状态为 `matched` 或 `customTitle` 非空的目标不进入批量写入。规则保存异常只令 `ruleSaved` 为 `false`，不阻止当前传播。

`applyRule` 在已有自定义标题或匹配时返回 `null`。命中规则后写入匹配记录，并用精确远程路径调用 `CloudMediaIndexRepository.updateMatching`。索引异常设置 `indexSynced = false`，记录仍保留。`learnAndPropagate` 同时返回失败目标，协调器可在下次加载时调用 `syncRecordToIndex` 离线重试。

在 `CloudResourceTmdbTarget` 增加可空 `size` 字段。页面和扫描器创建独立视频目标时必须传入真实大小；目录目标保持 `null`。

- [ ] **Step 7：运行传播、仓库和 TMDB 服务回归**

Run: `D:\flutter\bin\flutter.bat test test\cloud_series_match_service_test.dart test\cloud_resource_tmdb_repository_test.dart test\cloud_resource_tmdb_service_test.dart`

Expected: PASS。

- [ ] **Step 8：提交传播服务**

```powershell
git add -- lib/services/cloud/cloud_series_match_service.dart lib/repositories/cloud_resource_tmdb_repository.dart lib/services/cloud/cloud_resource_tmdb_service.dart test/cloud_series_match_service_test.dart test/cloud_resource_tmdb_repository_test.dart test/cloud_resource_tmdb_service_test.dart
git commit -m "feat(cloud): 传播手动确认的系列元数据"
```

## Task 3：协调器学习规则并反馈传播结果

**Files:**
- Modify: `lib/services/cloud/cloud_resource_tmdb_search.dart`
- Modify: `lib/services/cloud/cloud_resource_tmdb_coordinator.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `test/cloud_resource_tmdb_coordinator_test.dart`
- Modify: `test/cloud_resources_controller_test.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1：写手动匹配传播失败测试**

在控制器测试中加载同目录四集，手动选择第一集：

```dart
final outcome = await fixture.controller.applyTmdbCandidate(
  firstEpisode,
  candidate,
  options: const TmdbScrapeOptions.defaults(),
);
expect(outcome.seriesPropagation.eligible, isTrue);
expect(outcome.seriesPropagation.propagatedCount, 3);
expect(coordinator.propagationCandidates.map((target) => target.remote.id),
    <String>['episode-1', 'episode-2', 'episode-3', 'episode-4']);
expect(coordinator.propagationCandidates.every((target) => target.size != null),
    isTrue);
```

页面测试断言成功提示为 `已保存“回魂计”，并自动匹配同目录 3 个分集`。

- [ ] **Step 2：运行三组测试确认传播摘要不存在**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_tmdb_coordinator_test.dart test\cloud_resources_controller_test.dart test\cloud_resources_page_test.dart`

Expected: FAIL，提示 `seriesPropagation` 不存在。

- [ ] **Step 3：扩展选择结果并串联传播**

新增默认摘要，保持旧调用兼容：

```dart
class CloudSeriesPropagationSummary {
  const CloudSeriesPropagationSummary({
    required this.eligible,
    required this.ruleSaved,
    required this.propagatedCount,
    required this.indexSyncFailures,
  });

  const CloudSeriesPropagationSummary.none()
      : eligible = false,
        ruleSaved = true,
        propagatedCount = 0,
        indexSyncFailures = 0;

  final bool eligible;
  final bool ruleSaved;
  final int propagatedCount;
  final int indexSyncFailures;
}
```

`CloudResourceTmdbSelectionOutcome` 增加：

```dart
final CloudSeriesPropagationSummary seriesPropagation;
```

构造函数提供默认值 `const CloudSeriesPropagationSummary.none()`。

协调器注入 `CloudSeriesMatchService? seriesMatchService`。`selectPrepared` 和 `select` 增加可选参数：

```dart
List<CloudResourceTmdbTarget> propagationCandidates =
    const <CloudResourceTmdbTarget>[],
```

TMDB 选择成功后调用 `learnAndPropagate`，把返回记录写入 `_records`，把 `pendingIndexSyncTargets` 写入 `_pendingIndexSyncTargets`，然后返回带摘要的新 outcome。

- [ ] **Step 4：控制器传入完整目录而非搜索结果**

`tmdbTargetFor` 写入 `size: entry.isDirectory ? null : entry.size`。`applyTmdbCandidate` 改为 `async`，把 `entries` 中所有独立视频转换为候选后传给协调器。不要使用 `visibleEntries`，搜索过滤不能改变传播范围。

- [ ] **Step 5：页面显示传播结果**

在 `_openTmdbDialog` 成功分支中优先处理传播摘要：

```dart
final propagation = outcome.seriesPropagation;
if (propagation.eligible && !propagation.ruleSaved) {
  _showMessage(
    '已保存“$title”，并匹配 ${propagation.propagatedCount} 个分集，'
    '但自动继承规则保存失败',
  );
} else if (propagation.propagatedCount > 0) {
  _showMessage(
    '已保存“$title”，并自动匹配同目录 '
    '${propagation.propagatedCount} 个分集',
  );
}
```

索引失败数量追加到提示末尾，不覆盖规则保存提示。

- [ ] **Step 6：运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_tmdb_coordinator_test.dart test\cloud_resources_controller_test.dart test\cloud_resources_page_test.dart`

Expected: PASS。

```powershell
git add -- lib/services/cloud/cloud_resource_tmdb_search.dart lib/services/cloud/cloud_resource_tmdb_coordinator.dart lib/pages/cloud/resources/cloud_resources_controller.dart lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_resource_tmdb_coordinator_test.dart test/cloud_resources_controller_test.dart test/cloud_resources_page_test.dart
git commit -m "feat(cloud): 手动匹配后关联同目录分集"
```

## Task 4：后续资源规则优先继承

**Files:**
- Modify: `lib/services/cloud/cloud_resource_tmdb_coordinator.dart`
- Modify: `lib/services/cloud/cloud_resource_auto_organizer.dart`
- Modify: `lib/services/cloud/cloud_media_indexer.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `test/cloud_resource_tmdb_coordinator_test.dart`
- Modify: `test/cloud_resource_auto_organizer_test.dart`
- Modify: `test/cloud_media_indexer_test.dart`
- Modify: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1：写规则优先于缓存和 TMDB 的失败测试**

协调器测试预置规则和近期 `unmatched`：

```dart
await coordinator.loadAndSchedule(context);
expect(coordinator.records[target.stableKey]?.status,
    CloudResourceTmdbStatus.matched);
expect(tmdbService.matchCalls, 0);
```

控制器自动整理测试断言规则继承计入 `matched`，并且 coordinator 的 TMDB `scrape` 未调用。

- [ ] **Step 2：运行测试确认规则仍在缓存后执行**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_tmdb_coordinator_test.dart test\cloud_resources_controller_test.dart`

Expected: FAIL，近期 `unmatched` 仍被跳过或发生 TMDB 调用。

- [ ] **Step 3：在协调器中先应用规则**

新增公开方法：

```dart
Future<CloudSeriesRuleApplication?> applySeriesRule(
  CloudResourceTmdbTarget target,
) async;
```

`loadAndSchedule` 加载记录后，先用传播服务重试 `_pendingIndexSyncTargets`，再对当前上下文独立视频调用 `applySeriesRule`，之后才检查 API Key 和 `_targetsToSchedule`。`scrape` 也先调用该方法，命中时返回带 `selected` 的 outcome，然后才调用 `_requiredApiKey`。规则应用和索引重试不依赖 API Key。

自动批量整理在判断已匹配和七天缓存前调用 `applySeriesRule`。命中数量计入 `matched`，进度计入已完成目标。

- [ ] **Step 4：写自动整理大小阈值失败测试**

```dart
final result = await CloudResourceAutoOrganizer(
  minRecognizedVideoSizeBytesProvider: () => 100,
).discover(source: source, client: client);
expect(result.candidates.map((target) => target.remote.id),
    <String>['large-video']);
expect(result.candidates.single.size, 101);
```

目录只有小视频时不得成为作品候选；普通子目录仍继续遍历。

- [ ] **Step 5：实现自动整理统一阈值**

`CloudResourceAutoOrganizer` 增加：

```dart
final int Function()? minRecognizedVideoSizeBytesProvider;
```

每次 `discover` 只读取一次阈值。所有视频判断改用：

```dart
LocalVideoFileTypes.isRecognizedVideo(
  entry.name,
  size: entry.size,
  minSizeBytes: minSizeBytes,
)
```

独立视频目标写入 `size: video.size`。

- [ ] **Step 6：写媒体索引继承失败测试**

向规则仓库保存 `The Resurrected`，扫描包含新 `S01E05` 的来源：

```dart
final result = await indexer.scan(source: source, client: client);
final item = (await indexRepository.getBySource(source.id)).single;
expect(item.tmdbId, 42);
expect(item.tmdbTitle, '回魂计');
```

- [ ] **Step 7：扫描建索引前应用规则**

`CloudMediaIndexer` 注入可空 `CloudSeriesMatchRuleRepository` 和 `CloudSeriesIdentityResolver`。完成视频条目构造后一次读取来源规则，按系列键查找并调用 `item.replaceTmdb`。匹配使用当前扫描已经读取的 `minSizeBytes`，不发起网络请求。

- [ ] **Step 8：运行四组测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_tmdb_coordinator_test.dart test\cloud_resource_auto_organizer_test.dart test\cloud_media_indexer_test.dart test\cloud_resources_controller_test.dart`

Expected: PASS。

```powershell
git add -- lib/services/cloud/cloud_resource_tmdb_coordinator.dart lib/services/cloud/cloud_resource_auto_organizer.dart lib/services/cloud/cloud_media_indexer.dart lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_resource_tmdb_coordinator_test.dart test/cloud_resource_auto_organizer_test.dart test/cloud_media_indexer_test.dart test/cloud_resources_controller_test.dart
git commit -m "feat(cloud): 后续分集优先继承已确认规则"
```

## Task 5：当前目录作品分组与大小过滤

**Files:**
- Create: `lib/pages/cloud/resources/cloud_resource_collection.dart`
- Create: `test/cloud_resource_collection_test.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1：写作品分组失败测试**

测试数据包含文件夹、四个同剧分集、另一个剧集、电影、字幕、图片和三个阈值边界视频：

```dart
final collection = CloudResourceCollectionGrouper().group(
  sourceId: 'quark',
  entries: entries,
  records: records,
  minSizeBytes: 100,
  query: '',
);
expect(collection.folders.map((entry) => entry.name), <String>['子目录']);
expect(collection.groups, hasLength(3));
final series = collection.groups.firstWhere((group) => group.isSeries);
expect(series.videos.map((video) => video.name), <String>[
  'Show.S01E01.mkv',
  'Show.S01E02.mkv',
  'Show.S02E01.mkv',
]);
final visibleNames = collection.groups
    .expand((group) => group.videos)
    .map((video) => video.name);
expect(visibleNames, isNot(contains('Show.ass')));
expect(visibleNames, isNot(contains('sample.mkv')));
```

`sample.mkv` 大小等于 100，必须隐藏；大小 101 的电影必须显示。

- [ ] **Step 2：运行测试确认分组器不存在**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_collection_test.dart`

Expected: FAIL，提示 `CloudResourceCollectionGrouper` 不存在。

- [ ] **Step 3：实现纯分组模型**

公开类型固定为：

```dart
class CloudResourceCollection {
  const CloudResourceCollection({
    required this.folders,
    required this.groups,
  });
  final List<CloudFileEntry> folders;
  final List<CloudResourceMediaGroup> groups;
}

class CloudResourceMediaGroup {
  const CloudResourceMediaGroup({
    required this.stableKey,
    required this.seriesName,
    required this.isSeries,
    required this.videos,
    required this.record,
  });
  final String stableKey;
  final String seriesName;
  final bool isSeries;
  final List<CloudFileEntry> videos;
  final CloudResourceTmdbRecord? record;
  CloudFileEntry get anchor => videos.first;
}
```

`group` 先保留目录，再用 `isRecognizedVideo` 过滤媒体。集数视频按系列身份键归组，非集数视频按资源 `stableKey` 独立成组。记录优先级为自定义标题、已匹配、无记录。组排序使用有效标题，组内排序使用季号、集号和文件名。

查询同时匹配文件夹名、有效标题、标准剧名和组内文件名。

- [ ] **Step 4：控制器暴露动态作品集合**

构造函数增加：

```dart
int Function()? minRecognizedVideoSizeBytesProvider,
CloudResourceCollectionGrouper? collectionGrouper,
CloudResourceAutoOrganizer? autoOrganizer,
```

新增 getter：

```dart
CloudResourceCollection get collection => _collectionGrouper.group(
  sourceId: selectedSource?.id ?? '',
  entries: entries,
  records: tmdbRecords,
  minSizeBytes: _minRecognizedVideoSizeBytesProvider(),
  query: query,
);
```

`tmdbEntriesForCurrentDirectory` 对独立视频使用相同阈值。字幕继续保留在原始 `entries`，播放匹配不读取 `collection`。

- [ ] **Step 5：运行分组和控制器测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_collection_test.dart test\cloud_resources_controller_test.dart`

Expected: PASS。

```powershell
git add -- lib/pages/cloud/resources/cloud_resource_collection.dart lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_resource_collection_test.dart test/cloud_resources_controller_test.dart
git commit -m "feat(cloud): 按识别规则生成网盘作品集合"
```

## Task 6：文件夹导航、作品海报墙和选集

**Files:**
- Create: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Create: `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Delete: `lib/pages/cloud/resources/cloud_resources_grid.dart`
- Modify: `test/cloud_resources_page_test.dart`
- Modify: `test/cloud_library_integration_test.dart`

- [ ] **Step 1：写海报墙失败测试**

页面加载一个文件夹、三集同剧、一个电影、字幕和低于阈值的视频，断言：

```dart
expect(find.byKey(const ValueKey<String>('cloud-folder-navigation')),
    findsOneWidget);
expect(find.text('子目录'), findsOneWidget);
expect(find.byType(ImmersiveMediaCard), findsNWidgets(2));
expect(find.text('Show.S01E02.mkv'), findsNothing);
expect(find.text('字幕.ass'), findsNothing);
expect(find.text('样片.mkv'), findsNothing);
expect(find.text('3 集'), findsOneWidget);
```

点击剧集海报后断言选集列表按 `S01E01`、`S01E02`、`S02E01` 排序；点击第二集后 `CloudPlaybackTarget.remoteId` 等于第二集真实 ID，字幕引用保持正确。

- [ ] **Step 2：运行页面测试确认仍显示单文件卡片**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart`

Expected: FAIL，仍找到三张分集卡片或找不到文件夹导航键。

- [ ] **Step 3：实现文件夹导航组件**

`CloudResourcePosterWall` 接收 `CloudResourceCollection`。当 `folders` 非空时，先渲染键为 `cloud-folder-navigation` 的 `Wrap`，每个 `ActionChip` 显示文件夹图标和名称，并调用 `onOpenDirectory`。

文件夹不计入海报网格列数。没有作品但有文件夹时仍显示导航；两者都为空时显示 `当前目录没有符合识别条件的视频或文件夹`。

- [ ] **Step 4：实现作品海报卡**

海报网格沿用当前 2、3、4 列断点和 `0.68` 海报比例。每个组只创建一个 `ImmersiveMediaCard`：

```dart
ImmersiveMediaCard(
  cover: poster,
  title: group.record?.effectiveTitle ?? group.seriesName,
  subtitle: group.isSeries ? '${group.videos.length} 集' : group.anchor.name,
  details: details,
  badges: badges,
  loading: group.videos.any(
    (video) => scrapingKeys.contains(resourceKey(video)),
  ),
  overlayMode: ImmersiveMediaCardOverlayMode.always,
  trailing: menu,
  onTap: () => onOpenGroup(group),
);
```

海报缓存和网络地址取 `group.record`。作品菜单把修改剧名、刮削和重新匹配回调传给 `group.anchor`。

- [ ] **Step 5：实现选集列表和播放**

`showCloudResourceEpisodeSheet` 返回选择的 `CloudFileEntry?`。列表项显示季集标签、原文件名、大小和字幕徽标。页面处理组点击：电影单文件直接 `_play`，剧集或多视频组打开选集 sheet，再把选择结果传给现有 `_play`。

- [ ] **Step 6：运行页面、媒体库和播放回归**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart test\cloud_library_integration_test.dart test\cloud_playback_resolver_test.dart test\quark_drive_client_test.dart`

Expected: PASS。

- [ ] **Step 7：提交海报墙**

```powershell
git add -- lib/pages/cloud/resources/cloud_resource_poster_wall.dart lib/pages/cloud/resources/cloud_resource_episode_sheet.dart lib/pages/cloud/resources/cloud_resources_page.dart lib/pages/cloud/resources/cloud_resources_grid.dart test/cloud_resources_page_test.dart test/cloud_library_integration_test.dart
git commit -m "feat(cloud): 将网盘目录改为作品海报墙"
```

## Task 7：来源删除、依赖注入和端到端回归

**Files:**
- Modify: `lib/providers/cloud_library_controller.dart`
- Modify: `lib/pages/index_module.dart`
- Modify: `test/cloud_library_controller_test.dart`
- Modify: `test/navigation_config_test.dart`
- Modify: `test/cloud_library_integration_test.dart`

- [ ] **Step 1：写来源删除规则清理和回滚失败测试**

使用内存规则仓库预置当前来源和另一来源的规则。成功删除后只保留另一来源：

```dart
await controller.delete('source-a');
expect(await ruleRepository.getBySource('source-a'), isEmpty);
expect(await ruleRepository.getBySource('source-b'), hasLength(1));
```

模拟来源仓库删除失败，断言媒体索引、资源 TMDB 记录和系列规则全部恢复。

- [ ] **Step 2：运行删除测试确认规则没有清理**

Run: `D:\flutter\bin\flutter.bat test test\cloud_library_controller_test.dart`

Expected: FAIL，规则仓库没有调用。

- [ ] **Step 3：为删除事务加入规则快照**

`CloudLibraryController` 注入 `CloudSeriesMatchRuleRepository?`。删除前保存 `removedSeriesRules`，调用 `removeSource`。后续任一步失败时调用 `replaceSource` 恢复。错误文案区分规则恢复失败，但不得声称远程文件被删除。

- [ ] **Step 4：完成 IndexModule 注入**

注册单例：

```dart
i.addSingleton<CloudSeriesMatchRuleRepository>(
  CloudSeriesMatchRuleRepository.new,
);
i.addSingleton<CloudSeriesMatchService>(() => CloudSeriesMatchService(
  ruleRepository: Modular.get<CloudSeriesMatchRuleRepository>(),
  recordRepository: Modular.get<CloudResourceTmdbRepository>(),
  indexRepository: Modular.get<CloudMediaIndexRepository>(),
  minRecognizedVideoSizeBytesProvider: () =>
      Modular.get<MediaRecognitionSettings>().cloudMinSizeBytes,
));
```

将同一个规则仓库注入 `CloudMediaIndexer` 和 `CloudLibraryController`，将传播服务注入协调器。`CloudResourcesController` 注入阈值提供者和使用同一阈值提供者的 `CloudResourceAutoOrganizer`。

- [ ] **Step 5：运行架构、模块和删除回归**

Run: `D:\flutter\bin\flutter.bat test test\cloud_library_controller_test.dart test\navigation_config_test.dart test\architecture_dependency_test.dart test\cloud_library_integration_test.dart`

Expected: PASS。

- [ ] **Step 6：提交清理与注入**

```powershell
git add -- lib/providers/cloud_library_controller.dart lib/pages/index_module.dart test/cloud_library_controller_test.dart test/navigation_config_test.dart test/cloud_library_integration_test.dart
git commit -m "feat(cloud): 接入系列规则生命周期"
```

## Task 8：更新 2.1.15 版本与用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1：先更新版本测试期望并确认失败**

将当前版本期望改为 `2.1.15+20115`、MSIX `2.1.15.0`、应用版本 `2.1.15`。

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart test\version_history_current_test.dart`

Expected: FAIL，当前文件仍为 2.1.14。

- [ ] **Step 2：同步版本与面向用户的说明**

更新文案必须包含：

- 手动匹配一集后，同目录同剧分集立即和后续自动继承
- 网盘资源按作品合并为海报墙并提供选集
- 非视频和不超过网盘识别大小的视频不显示、不刮削
- 不修改网盘文件、目录或播放路径

- [ ] **Step 3：运行版本测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart test\version_history_current_test.dart`

Expected: PASS。

```powershell
git add -- pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md test/version_consistency_test.dart test/identity_v2_zero_residue_test.dart test/version_history_current_test.dart
git commit -m "chore(release): 更新看影音 2.1.15 文案"
```

## Task 9：完整验证、Windows Release 和 MSIX 交付

**Files:**
- Verify only; do not stage generated build artifacts

- [ ] **Step 1：格式和差异检查**

Run: `D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test`

Run: `git diff --check`

Expected: 两条命令退出码均为 0。

- [ ] **Step 2：完整测试**

Run: `D:\flutter\bin\flutter.bat test`

Expected: 所有测试通过，0 失败。

- [ ] **Step 3：静态分析**

Run: `D:\flutter\bin\flutter.bat analyze`

Expected: `No issues found!`

- [ ] **Step 4：构建新的 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: `Built build\windows\x64\runner\Release\kanyingyin.exe`。

核对 `kanyingyin.exe` 和 `data\app.so` 来自本次源码构建，不交付旧产物。

- [ ] **Step 5：生成并签名 MSIX**

Run: `D:\flutter\bin\cache\dart-sdk\bin\dart.exe run msix:create --build-windows false`

使用证书 `CN=KanYingYin` 和本机私钥签名 `build\windows\x64\runner\Release\kanyingyin.msix`。使用 SignTool `/pa /v` 验证 0 错误、0 警告。

- [ ] **Step 6：验证清单和桌面文件**

从 `AppxManifest.xml` 核对：

- Identity：`com.kanyingyin.player`
- Publisher：`CN=KanYingYin`
- Version：`2.1.15.0`
- Architecture：`x64`

复制为 `C:\Users\asus\Desktop\看影音-2.1.15.msix`，比较构建包和桌面包 SHA-256，必须一致。

- [ ] **Step 7：最终 Git 审计**

Run: `git status --short`

Run: `git diff --check`

Expected: 只保留用户原有的 `.learnings/ERRORS.md` 和 `.learnings/LEARNINGS.md` 修改；所有本轮源码、测试、版本和文档均已提交。

## 实施约束

- 全程使用测试驱动开发，每个生产行为先看到对应测试按预期失败
- 不使用子智能体
- 不修改远程网盘文件、目录、远程 ID 或播放路径
- TMDB 不可用、没有 API Key 或断网时，规则继承、目录浏览和播放仍可用
- 同系列规则只按来源、父目录和标准剧名精确命中
- 已匹配记录和自定义剧名永不被传播覆盖
- 低于或等于网盘识别大小的视频不显示、不刮削、不传播
- 字幕不显示，但播放字幕关联继续使用原始目录条目
- 每个任务只暂存列出的相关文件，不提交 `.learnings` 修改
