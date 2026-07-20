# Local Season Poster Scraping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让本地电视剧按已识别季度下载并展示 TMDB 对应季海报，缺失时回退作品总海报。

**Architecture:** 保留现有本地索引、按目录去重和 `tmdb-poster.jpg` 缓存结构。只在 `LocalTmdbScrapeService` 中补齐季度元数据合并，并把海报地址选择收口为按媒体类型和 `seasonNumber` 决策的私有方法。

**Tech Stack:** Flutter 3.41.9、Dart、flutter_test、TMDB 强类型元数据、本地媒体索引仓库。

---

## 文件结构

- 修改 `lib/services/tmdb/local_tmdb_scrape_service.dart`：保存季度元数据并选择季度海报。
- 修改 `test/local_tmdb_integration_test.dart`：覆盖自动匹配、手动匹配、多季、回退和目录去重。

### Task 1: 保留 TMDB 季度元数据

**Files:**
- Modify: `test/local_tmdb_integration_test.dart`
- Modify: `lib/services/tmdb/local_tmdb_scrape_service.dart`

- [ ] **Step 1: 写入失败测试**

把 `_FakeClient.details` 返回值补充两条 `TmdbSeasonMetadata`，海报分别为 `/season-1.jpg` 和 `/season-2.jpg`，并在“匹配成功后更新同系列全部剧集”末尾增加：

```dart
expect(
  index.getAll().first.tmdb?.seasons.map((item) => item.seasonNumber),
  <int>[1, 2],
);
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_tmdb_integration_test.dart --plain-name "匹配成功后更新同系列全部剧集"`

Expected: FAIL，索引中的 `tmdb.seasons` 为空。

- [ ] **Step 3: 最小实现季度元数据合并**

在 `_mergeMetadata` 返回的 `TmdbMetadata` 中加入：

```dart
seasons: fetched.seasons,
```

- [ ] **Step 4: 运行测试并确认 GREEN**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_tmdb_integration_test.dart --plain-name "匹配成功后更新同系列全部剧集"`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/services/tmdb/local_tmdb_scrape_service.dart test/local_tmdb_integration_test.dart
git commit -m "保留本地剧集季度元数据"
```

### Task 2: 按季度选择并下载海报

**Files:**
- Modify: `test/local_tmdb_integration_test.dart`
- Modify: `lib/services/tmdb/local_tmdb_scrape_service.dart`

- [ ] **Step 1: 让测试索引项支持季度**

把 `_item` 增加命名参数并传入模型：

```dart
LocalMediaIndexItem _item(String name, {int? seasonNumber}) {
  return LocalMediaIndexItem(
    path: 'D:/Video/$name',
    name: name,
    parentPath: 'D:/Video',
    sourcePath: 'D:/Video',
    size: 100,
    modified: DateTime(2026),
    seriesName: '流浪地球',
    seasonNumber: seasonNumber,
    indexedAt: DateTime(2026),
  );
}
```

- [ ] **Step 2: 写入多季失败测试**

建立 `Season 1` 的两集和 `Season 2` 的一集，分别设置 `seasonNumber: 1`、`1`、`2`，以 `TmdbMediaType.tv` 刮削并捕获下载地址，断言：

```dart
expect(downloads.map((item) => item.url), <String>[
  'https://image.tmdb.org/t/p/w780/season-1.jpg',
  'https://image.tmdb.org/t/p/w780/season-2.jpg',
]);
expect(downloads.map((item) => item.path),
    everyElement(endsWith('tmdb-poster.jpg')));
```

- [ ] **Step 3: 运行多季测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_tmdb_integration_test.dart --plain-name "电视剧按季度下载对应 TMDB 海报且同目录只下载一次"`

Expected: FAIL，实际两次均为作品总海报 `/poster.jpg`。

- [ ] **Step 4: 实现海报选择方法**

在 `LocalTmdbScrapeService` 中增加：

```dart
String? _posterPathFor(LocalMediaIndexItem item) {
  final metadata = item.tmdb;
  if (metadata == null) return null;
  final seasonNumber = item.seasonNumber;
  if (metadata.mediaType == TmdbMediaType.tv && seasonNumber != null) {
    for (final season in metadata.seasons) {
      final poster = season.posterUrl?.trim() ?? '';
      if (season.seasonNumber == seasonNumber && poster.isNotEmpty) {
        return poster;
      }
    }
  }
  final fallback = metadata.posterUrl?.trim() ?? '';
  return fallback.isEmpty ? null : fallback;
}
```

在 `_downloadPosters` 的分组和下载循环中都使用 `_posterPathFor`，替代直接读取 `item.tmdb?.posterUrl`。同目录继续只下载一次。

- [ ] **Step 5: 运行多季测试并确认 GREEN**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_tmdb_integration_test.dart --plain-name "电视剧按季度下载对应 TMDB 海报且同目录只下载一次"`

Expected: PASS。

- [ ] **Step 6: 写入并运行回退测试**

建立一个 `seasonNumber: 3` 的目录和一个季度为空的目录，使用只包含第 1、2 季的假 TMDB 详情，断言两次下载均为：

```dart
'https://image.tmdb.org/t/p/w780/poster.jpg'
```

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_tmdb_integration_test.dart --plain-name "季度海报缺失或季度未识别时回退作品总海报"`

Expected: PASS；若失败，只修正 `_posterPathFor`。

- [ ] **Step 7: 提交**

```powershell
git add lib/services/tmdb/local_tmdb_scrape_service.dart test/local_tmdb_integration_test.dart
git commit -m "支持本地剧集分季海报"
```

### Task 3: 本地媒体回归

**Files:**
- Verify: `test/local_tmdb_integration_test.dart`
- Verify: `test/local_media_index_tmdb_test.dart`
- Verify: `test/local_series_grouper_test.dart`

- [ ] **Step 1: 运行相关测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/local_tmdb_integration_test.dart test/local_media_index_tmdb_test.dart test/local_series_grouper_test.dart`

Expected: 全部 PASS。

- [ ] **Step 2: 检查差异**

Run: `git diff --check`

Expected: 无空白错误，且不包含 `.learnings` 和百度播放文件。
