# TMDB 剧集手动匹配实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为本地视频和个人网盘剧集提供统一的逐视频 TMDB 集名匹配、保留原名和恢复自动识别能力，并保证重新扫描及进入播放器后仍显示正确集名。

**Architecture:** 新增不依赖具体媒体来源的剧集匹配领域模型、严格预匹配器和对话框；本地保存服务通过本地索引批量更新，网盘保存服务通过独立规则仓储持久化并刷新当前索引。扫描器在自动识别后应用网盘手动规则，所有播放入口继续使用既有 `TmdbEpisodeTitleResolver` 生成的最终展示标题。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、MobX、Hive、`flutter_test`、现有 TMDB 客户端与媒体索引仓储。

---

## 文件结构

- `lib/features/episode_matching/domain/manual_episode_match.dart`：共享资源项、赋值操作和批量校验。
- `lib/features/episode_matching/domain/manual_episode_pre_matcher.dart`：只接受结构化季集证据的严格预匹配。
- `lib/features/episode_matching/application/manual_episode_match_controller.dart`：加载 TMDB 电视剧详情/季度、维护编辑状态并生成保存结果。
- `lib/features/episode_matching/presentation/manual_episode_match_dialog.dart`：作品搜索后使用的季度与逐视频匹配界面。
- `lib/features/episode_matching/application/local_episode_match_service.dart`：本地索引快照、批量保存与失败恢复。
- `lib/features/episode_matching/application/cloud_episode_match_service.dart`：网盘规则保存、即时索引刷新与失败结果。
- `lib/modules/cloud/cloud_episode_match_rule.dart`：网盘逐视频规则的持久化模型。
- `lib/repositories/cloud_episode_match_rule_repository.dart`：Hive/内存规则仓储与批量原子替换。
- `lib/modules/local/local_media_index_item.dart`：提供可显式清空季号、集号的映射更新方法。
- `lib/modules/cloud/cloud_media_index_item.dart`：提供可显式清空或替换季集字段的映射更新方法。
- `lib/services/cloud/cloud_media_indexer.dart`：扫描完成后应用网盘逐视频规则。
- `lib/pages/local/local_controller.dart`、`lib/pages/local/local_page.dart`、`lib/pages/local/library_sheet.dart`：本地入口、保存和刷新。
- `lib/pages/cloud/resources/cloud_resources_controller.dart`、`cloud_resources_page.dart`、`cloud_resource_poster_wall.dart`：网盘入口、保存和刷新。
- `lib/services/local_playback_request_builder.dart`、`lib/services/local_series_grouper.dart`：把最终集名送入播放列表。

### Task 1: 共享匹配模型和严格预匹配

**Files:**
- Create: `lib/features/episode_matching/domain/manual_episode_match.dart`
- Create: `lib/features/episode_matching/domain/manual_episode_pre_matcher.dart`
- Test: `test/manual_episode_match_test.dart`
- Test: `test/manual_episode_pre_matcher_test.dart`

- [ ] **Step 1: 写失败测试，固定操作状态、重复集映射和严格证据边界**

```dart
test('允许多个资源映射同一集并拒绝不存在的资源或集号', () {
  final items = <ManualEpisodeMatchItem>[
    ManualEpisodeMatchItem(
      resourceId: 'a',
      originalName: 'Show.S01E01.mkv',
      automaticSeasonNumber: 1,
      automaticEpisodeNumber: 1,
    ),
    ManualEpisodeMatchItem(
      resourceId: 'b',
      originalName: 'Show.1080p.mkv',
    ),
  ];
  final assignments = <ManualEpisodeAssignment>[
    ManualEpisodeAssignment.mapped(resourceId: 'a', seasonNumber: 1, episodeNumber: 1),
    ManualEpisodeAssignment.mapped(resourceId: 'b', seasonNumber: 1, episodeNumber: 1),
  ];
  expect(
    validateManualEpisodeAssignments(
      items: items,
      assignments: assignments,
      validEpisodeNumbers: const <int>{1, 2},
    ),
    isEmpty,
  );
});

test('泛目录中的纯数字文件名不自动预匹配', () {
  final result = const ManualEpisodePreMatcher().match(
    originalName: '01.mkv',
    parentName: '电视剧',
    expectedSeriesName: '异世界悠闲农家',
  );
  expect(result, isNull);
});

test('季度目录与文件名季号冲突时不自动预匹配', () {
  final result = const ManualEpisodePreMatcher().match(
    originalName: 'Show.S01E03.mkv',
    parentName: 'Season 2',
    expectedSeriesName: 'Show',
  );
  expect(result, isNull);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/manual_episode_match_test.dart test/manual_episode_pre_matcher_test.dart`

Expected: FAIL，提示共享模型和预匹配器尚不存在。

- [ ] **Step 3: 实现强类型模型、校验和严格预匹配**

```dart
enum ManualEpisodeAssignmentMode { mapped, keepOriginal, restoreAutomatic }

final class ManualEpisodeMatchItem {
  const ManualEpisodeMatchItem({
    required this.resourceId,
    required this.originalName,
    this.parentName,
    this.existingSeasonNumber,
    this.existingEpisodeNumber,
    this.automaticSeasonNumber,
    this.automaticEpisodeNumber,
    this.manualOverride = false,
  });

  final String resourceId;
  final String originalName;
  final String? parentName;
  final int? existingSeasonNumber;
  final int? existingEpisodeNumber;
  final int? automaticSeasonNumber;
  final int? automaticEpisodeNumber;
  final bool manualOverride;
}

final class ManualEpisodeAssignment {
  const ManualEpisodeAssignment._({
    required this.resourceId,
    required this.mode,
    this.seasonNumber,
    this.episodeNumber,
  });

  factory ManualEpisodeAssignment.mapped({
    required String resourceId,
    required int seasonNumber,
    required int episodeNumber,
  }) => ManualEpisodeAssignment._(
        resourceId: resourceId,
        mode: ManualEpisodeAssignmentMode.mapped,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      );

  factory ManualEpisodeAssignment.keepOriginal(String resourceId) =>
      ManualEpisodeAssignment._(
        resourceId: resourceId,
        mode: ManualEpisodeAssignmentMode.keepOriginal,
      );

  factory ManualEpisodeAssignment.restoreAutomatic(String resourceId) =>
      ManualEpisodeAssignment._(
        resourceId: resourceId,
        mode: ManualEpisodeAssignmentMode.restoreAutomatic,
      );

  final String resourceId;
  final ManualEpisodeAssignmentMode mode;
  final int? seasonNumber;
  final int? episodeNumber;
}
```

`ManualEpisodePreMatcher.match()` 复用 `LocalEpisodeParser`/媒体名称分析结果，只在文件名或季度目录提供正整数季集号、作品名可确认且季号不冲突时返回 `({int seasonNumber, int episodeNumber})`；年份、`4K`、`8K`、码率和泛目录纯数字均返回 `null`。

- [ ] **Step 4: 运行测试确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/manual_episode_match_test.dart test/manual_episode_pre_matcher_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交共享领域逻辑**

```powershell
git add lib/features/episode_matching/domain/manual_episode_match.dart lib/features/episode_matching/domain/manual_episode_pre_matcher.dart test/manual_episode_match_test.dart test/manual_episode_pre_matcher_test.dart
git commit -m "实现剧集手动匹配领域逻辑"
```

### Task 2: 本地索引显式清空与批量保存

**Files:**
- Modify: `lib/modules/local/local_media_index_item.dart`
- Create: `lib/features/episode_matching/application/local_episode_match_service.dart`
- Test: `test/local_episode_match_service_test.dart`
- Test: `test/local_media_index_tmdb_test.dart`

- [ ] **Step 1: 写失败测试，覆盖映射、保留原名、恢复自动识别和失败回滚**

测试使用内存版 `ILocalMediaIndexRepository`，断言：`mapped` 写入季度/集号、TMDB 元数据、`TmdbMatchOrigin.manual` 和 `manualOverride=true`；`keepOriginal` 显式清空季集且保持 `manualOverride=true`；`restoreAutomatic` 清除手动覆盖并重新采用严格解析结果；仓储抛错后全部项目恢复保存前快照。

- [ ] **Step 2: 运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_episode_match_service_test.dart test/local_media_index_tmdb_test.dart`

Expected: FAIL，提示 `withEpisodeMapping` 和本地保存服务不存在。

- [ ] **Step 3: 增加显式可空更新并实现本地批量服务**

```dart
LocalMediaIndexItem withEpisodeMapping({
  required int? seasonNumber,
  required int? episodeNumber,
  required bool manualOverride,
  TmdbMetadata? tmdb,
  TmdbMatchOrigin? tmdbMatchOrigin,
}) {
  return LocalMediaIndexItem(
    location: location,
    name: name,
    parentLocation: parentLocation,
    sourceLocation: sourceLocation,
    size: size,
    modified: modified,
    seriesName: seriesName,
    indexedAt: indexedAt,
    cover: cover,
    subtitlePath: subtitlePath,
    durationMillis: durationMillis,
    videoWidth: videoWidth,
    videoHeight: videoHeight,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    episodeTitle: episodeTitle,
    releaseGroup: releaseGroup,
    resolution: resolution,
    source: source,
    codec: codec,
    tmdb: tmdb ?? this.tmdb,
    tmdbIdentity: tmdbIdentity,
    titleLocked: titleLocked,
    posterLocked: posterLocked,
    overviewLocked: overviewLocked,
    scrapeStatus: TmdbScrapeStatus.matched,
    tmdbMatchOrigin: tmdbMatchOrigin ?? this.tmdbMatchOrigin,
    tmdbRuleVersion: tmdbRuleVersion,
    manualOverride: manualOverride,
    pathFingerprint: pathFingerprint,
    derivedMetadataVersion: derivedMetadataVersion,
  );
}
```

`LocalEpisodeMatchService.save()` 先验证完整批次，建立 `Map<String, LocalMediaIndexItem>` 快照和更新集合，再只调用一次 `repository.updateItems(updates)`；失败时用快照再次 `updateItems` 并重新抛出原错误。

- [ ] **Step 4: 运行本地持久化测试确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_episode_match_service_test.dart test/local_media_index_tmdb_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交本地持久化**

```powershell
git add lib/modules/local/local_media_index_item.dart lib/features/episode_matching/application/local_episode_match_service.dart test/local_episode_match_service_test.dart test/local_media_index_tmdb_test.dart
git commit -m "支持本地剧集映射持久化"
```

### Task 3: 网盘逐视频规则仓储

**Files:**
- Create: `lib/modules/cloud/cloud_episode_match_rule.dart`
- Create: `lib/repositories/cloud_episode_match_rule_repository.dart`
- Modify: `lib/utils/storage.dart`
- Test: `test/cloud_episode_match_rule_repository_test.dart`

- [ ] **Step 1: 写失败测试，覆盖 JSON 往返、身份键、批量替换和删除**

```dart
test('远程 ID 或路径变化后规则不命中', () {
  final rule = CloudEpisodeMatchRule.mapped(
    sourceId: 'quark-1',
    remoteId: 'video-1',
    remotePath: '/Show/S01E01.mkv',
    tmdbId: 196285,
    seasonNumber: 1,
    episodeNumber: 1,
    updatedAt: DateTime.utc(2026, 8, 6),
  );
  expect(rule.matches(sourceId: 'quark-1', remoteId: 'video-2', remotePath: '/Show/S01E01.mkv'), isFalse);
  expect(rule.matches(sourceId: 'quark-1', remoteId: 'video-1', remotePath: '/Moved/S01E01.mkv'), isFalse);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_episode_match_rule_repository_test.dart`

Expected: FAIL，提示规则模型和仓储不存在。

- [ ] **Step 3: 实现规则模型和仓储**

`CloudEpisodeMatchRule` 包含 `sourceId`、`remoteId`、规范化 `remotePath`、`mode`、`tmdbId`、`seasonNumber`、`episodeNumber`、`updatedAt`；稳定键必须同时包含三个身份字段。仓储沿用 `CloudSeriesMatchRuleRepository` 的 `synchronized.Lock`、Hive/内存存储模式，并提供 `getBySource`、`replaceSourceItems`、`remove`。

```dart
enum CloudEpisodeMatchMode { mapped, keepOriginal }

String cloudEpisodeMatchRuleKey({
  required String sourceId,
  required String remoteId,
  required String remotePath,
}) => '${sourceId.trim()}|${remoteId.trim()}|${CloudSeriesIdentityResolver.normalizeRemotePath(remotePath)}';
```

在 `SettingBoxKey` 增加 `cloudEpisodeMatchRules`，不得复用系列自动继承规则键。

- [ ] **Step 4: 运行规则仓储测试确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_episode_match_rule_repository_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交网盘规则仓储**

```powershell
git add lib/modules/cloud/cloud_episode_match_rule.dart lib/repositories/cloud_episode_match_rule_repository.dart lib/utils/storage.dart test/cloud_episode_match_rule_repository_test.dart
git commit -m "新增网盘剧集匹配规则仓储"
```

### Task 4: 网盘扫描覆盖和即时索引刷新

**Files:**
- Modify: `lib/modules/cloud/cloud_media_index_item.dart`
- Modify: `lib/services/cloud/cloud_media_indexer.dart`
- Create: `lib/features/episode_matching/application/cloud_episode_match_service.dart`
- Test: `test/cloud_media_indexer_test.dart`
- Test: `test/cloud_episode_match_service_test.dart`

- [ ] **Step 1: 写失败测试，覆盖重新扫描、保留原名和索引刷新失败**

断言扫描器在自动解析完成后应用规则：`mapped` 覆盖季集并设为 `CloudMediaType.episode`，`keepOriginal` 清空季集并压制自动识别；远程身份不一致时保持扫描结果。保存服务先持久化规则，再批量更新当前索引；规则成功而索引失败时返回 `rulesSaved=true, indexSynced=false`。

- [ ] **Step 2: 运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_media_indexer_test.dart test/cloud_episode_match_service_test.dart`

Expected: FAIL，提示扫描器尚未加载规则，索引模型也不能显式清空季集。

- [ ] **Step 3: 实现网盘覆盖与保存服务**

为 `CloudMediaIndexItem` 增加 `withEpisodeMapping({required int? seasonNumber, required int? episodeNumber, required bool keepOriginal})`，完整保留远程路径、ID、字幕、TMDB 字段和播放身份。`CloudMediaIndexer` 构造函数接收 `CloudEpisodeMatchRuleRepository?`，每次扫描按来源读取一次规则并以稳定键查找。`CloudEpisodeMatchService.save()` 对 `restoreAutomatic` 删除规则并用严格解析器重建当前索引，对另外两种模式批量替换规则。

- [ ] **Step 4: 运行网盘测试确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_media_indexer_test.dart test/cloud_episode_match_service_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交网盘扫描与保存逻辑**

```powershell
git add lib/modules/cloud/cloud_media_index_item.dart lib/services/cloud/cloud_media_indexer.dart lib/features/episode_matching/application/cloud_episode_match_service.dart test/cloud_media_indexer_test.dart test/cloud_episode_match_service_test.dart
git commit -m "应用网盘剧集手动匹配规则"
```

### Task 5: TMDB 季度加载和共享匹配对话框

**Files:**
- Create: `lib/features/episode_matching/application/manual_episode_match_controller.dart`
- Create: `lib/features/episode_matching/presentation/manual_episode_match_dialog.dart`
- Test: `test/manual_episode_match_controller_test.dart`
- Test: `test/manual_episode_match_dialog_test.dart`

- [ ] **Step 1: 写失败测试，覆盖只接受电视剧、按需季度加载、编辑和取消**

测试断言：电影候选被拒绝；选择作品只加载电视剧详情；切换季度只请求该季度一次；空季度禁止完成；自动预选可逐项改为具体集、保留原名或恢复自动识别；取消不调用保存回调；保存期间按钮禁用且失败后页面保留。

- [ ] **Step 2: 运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/manual_episode_match_controller_test.dart test/manual_episode_match_dialog_test.dart`

Expected: FAIL，提示控制器和对话框不存在。

- [ ] **Step 3: 实现控制器和响应式对话框**

控制器接收 `TmdbClient`、`TmdbMetadata selectedSeries` 和资源列表；`selectSeason(int)` 调用 `client.seasonDetails(id, seasonNumber, language: selectedSeries.language)`，再把该季度合并回作品元数据。对话框顶部显示作品海报、标题和季度下拉框，主体为稳定高度的资源列表，每行使用 `DropdownButtonFormField` 选择 `第 N 集 名称`、`保留原名` 或 `恢复自动识别`；底部只有取消与完成命令按钮。

- [ ] **Step 4: 运行控制器和界面测试确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/manual_episode_match_controller_test.dart test/manual_episode_match_dialog_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交共享交互**

```powershell
git add lib/features/episode_matching/application/manual_episode_match_controller.dart lib/features/episode_matching/presentation/manual_episode_match_dialog.dart test/manual_episode_match_controller_test.dart test/manual_episode_match_dialog_test.dart
git commit -m "实现剧集手动匹配界面"
```

### Task 6: 接入本地与网盘菜单

**Files:**
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `lib/pages/local/local_page.dart`
- Modify: `lib/pages/local/library_sheet.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Test: `test/local_manual_episode_matching_test.dart`
- Test: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 写失败测试，固定两个入口和批量保存刷新行为**

本地系列与网盘剧集操作菜单都必须显示“匹配剧集”；本地入口传入系列全部索引项，网盘入口传入作品/季度组全部视频；完成后刷新各自集合，取消不写入；无 TMDB Key 时显示“请先在设置中填写 TMDB API Key”。

- [ ] **Step 2: 运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_manual_episode_matching_test.dart test/cloud_resources_page_test.dart`

Expected: FAIL，提示菜单入口或保存回调不存在。

- [ ] **Step 3: 接入共享搜索和匹配对话框**

本地控制器公开 `manualEpisodeItemsForPaths()` 与 `saveManualEpisodeAssignments()`；网盘控制器公开 `manualEpisodeItemsForGroup()` 与 `saveManualEpisodeAssignments()`。两个页面先复用 `TmdbMatchDialog` 搜索电视剧候选，再打开 `ManualEpisodeMatchDialog`；不得在选择候选时提前写入索引或规则。

- [ ] **Step 4: 运行入口测试确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_manual_episode_matching_test.dart test/cloud_resources_page_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交本地和网盘入口**

```powershell
git add lib/pages/local/local_controller.dart lib/pages/local/local_page.dart lib/pages/local/library_sheet.dart lib/pages/cloud/resources/cloud_resources_controller.dart lib/pages/cloud/resources/cloud_resources_page.dart lib/pages/cloud/resources/cloud_resource_poster_wall.dart test/local_manual_episode_matching_test.dart test/cloud_resources_page_test.dart
git commit -m "接入本地和网盘剧集匹配"
```

### Task 7: 贯通详情、历史和播放器集名

**Files:**
- Modify: `lib/services/local_playback_request_builder.dart`
- Modify: `lib/pages/local/local_page.dart`
- Modify: `lib/services/local_series_grouper.dart`
- Modify: `lib/pages/video/video_page.dart`（仅在现有 `Road.identifier` 来源仍缺标题时修改）
- Test: `test/local_playback_request_builder_test.dart`
- Test: `test/local_series_grouper_test.dart`
- Test: `test/cloud_resource_playback_request_test.dart`

- [ ] **Step 1: 写失败测试，固定最终展示标题进入 Road**

构造带 TMDB 第一季第一集名称的本地和网盘条目，断言播放请求中的标题与最终 `Road.identifier` 为 `作品 S01E01 集名`；无集名时回退原文件名。观看历史重新建立播放请求时使用相同标题。

- [ ] **Step 2: 运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_playback_request_builder_test.dart test/local_series_grouper_test.dart test/cloud_resource_playback_request_test.dart`

Expected: FAIL，本地入口仍使用去扩展名文件名。

- [ ] **Step 3: 传递现有最终标题，不重复拼接**

```dart
factory LocalPlaybackEntry.fromIndexItem(LocalMediaIndexItem item) {
  return LocalPlaybackEntry(
    location: item.location,
    parentLocation: item.parentLocation,
    name: item.name,
    title: item.displayTitle,
    subtitlePath: item.subtitlePath,
  );
}
```

`local_page.dart` 的 `_playbackTitle()` 返回 `item.displayTitle`；`LocalVideoGroup.playlistFilesForPlayback` 从已关联索引项取得 `displayTitle`，不能再次用文件名拼接。网盘保持 `CloudFileEntry.name -> CloudPlaybackTarget.title -> Road.identifier` 的现有链路。

- [ ] **Step 4: 运行播放链路测试确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_playback_request_builder_test.dart test/local_series_grouper_test.dart test/cloud_resource_playback_request_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交标题贯通修复**

```powershell
git add lib/services/local_playback_request_builder.dart lib/pages/local/local_page.dart lib/services/local_series_grouper.dart lib/pages/video/video_page.dart test/local_playback_request_builder_test.dart test/local_series_grouper_test.dart test/cloud_resource_playback_request_test.dart
git commit -m "统一播放列表剧集名称"
```

### Task 8: 完整验证和测试版交付

**Files:**
- Modify: `pubspec.yaml`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: 再次记录版本起点并升级下一测试版**

Run: `Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name,Version,InstallLocation`

Expected: 当前安装版为 `2.1.133.0`。把 Dart 版本改为 `2.1.134+20134`，MSIX 版本改为 `2.1.134.0`，更新普通用户可读的测试版说明，明确本地/网盘逐集匹配、重新扫描保持映射和不修改原文件。

- [ ] **Step 2: 运行全部质量门禁**

Run: `D:\flutter\bin\flutter.bat test --no-pub`

Expected: 全部 PASS。

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: 无 error。

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: 生成 `build\windows\x64\runner\Release\kanyingyin.exe`。

- [ ] **Step 3: 生成、签名并验证 MSIX**

关闭正在运行的看影音后使用仓库公共签名脚本；脚本会重新验证 Release 产物，执行 MSIX 封装、时间戳签名、`signtool verify /pa`、清单身份/版本检查、桌面复制和 SHA-256 一致性检查。

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1`

Expected: 桌面存在 `看影音-2.1.134.msix`，文件非空，哈希与源包一致。

- [ ] **Step 4: 检查工作区并只提交本轮文件**

Run: `git status --short`

Expected: 仍保留用户原有的 ` M test/library_genre_backfill_service_test.dart`，但它不在暂存区。

Run: `git diff --check`

Expected: 无输出。

逐项 `git add` 本计划涉及的代码、测试和版本文件，不得执行 `git add .`。

- [ ] **Step 5: 创建交付提交并核对**

```powershell
git commit -m "支持TMDB剧集手动匹配"
git status --short
git log -1 --oneline
```

Expected: 提交成功，工作区只剩用户原有测试改动；桌面测试包为 `C:\Users\asus\Desktop\看影音-2.1.134.msix`。
