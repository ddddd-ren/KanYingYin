# 网盘资源 TMDB 渐进式匹配 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为网盘资源单项刮削增加可编辑的结构化识别、严格排序候选和安全确认弹窗，同时保持批量刮削自动化及夸克原文件不变。

**Architecture:** 名称解析、候选评分、TMDB 搜索和界面状态分别放在独立强类型组件中。`CloudResourceTmdbService` 继续负责 TMDB 与持久化，Coordinator/Controller 只编排状态，`CloudResourcesPage` 通过新的对话框收集用户输入和选择。旧公开方法保留为兼容适配层，避免本地媒体库和现有网盘测试被一次性破坏。

**Tech Stack:** Flutter 3.41.9、Dart、Material、Flutter Modular、MobX、Dio、Hive、flutter_test、msix。

**Execution constraint:** 用户明确禁止子智能体；实施时必须选择 `superpowers:executing-plans` 在当前会话内执行。

---

## 文件结构

- Create: `lib/services/cloud/cloud_media_name_parser.dart` — 解析原名称并生成只读 `TmdbMatchDraft`。
- Create: `lib/services/cloud/cloud_resource_tmdb_search.dart` — 定义搜索请求、搜索结果和选择结果。
- Create: `lib/pages/cloud/resources/cloud_tmdb_match_dialog.dart` — 管理单项准备、搜索、候选选择和保存界面。
- Create: `test/cloud_media_name_parser_test.dart` — 覆盖标题、年份、季集和发布标签解析。
- Create: `test/cloud_tmdb_match_dialog_test.dart` — 独立验证弹窗状态和响应式布局。
- Modify: `lib/services/tmdb/tmdb_matcher.dart` — 在现有严格评分上增加候选信号和稳定排序。
- Modify: `lib/services/cloud/cloud_resource_tmdb_service.dart` — 增加显式搜索、双类型查询、LRU 缓存和安全选择结果。
- Modify: `lib/services/cloud/cloud_resource_tmdb_coordinator.dart` — 编排准备搜索、选择结果和待同步重试。
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart` — 暴露页面需要的强类型方法。
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart` — 接入单项弹窗并增强批量汇总。
- Modify: `test/tmdb_matcher_test.dart` — 覆盖排序、类型、年份和领先幅度。
- Modify: `test/cloud_resource_tmdb_service_test.dart` — 覆盖双类型、缓存和部分成功。
- Modify: `test/cloud_resource_tmdb_coordinator_test.dart` — 覆盖最后请求结果和索引重试。
- Modify: `test/cloud_resources_controller_test.dart` — 覆盖草稿与请求透传。
- Modify: `test/cloud_resources_page_test.dart` — 覆盖入口、候选确认、批量不弹窗和四类汇总。
- Modify: `pubspec.yaml`、`RELEASE_NOTES.md`、`lib/utils/version_history.dart` — 发布 2.1.11。

### Task 1: 结构化解析网盘媒体名称

**Files:**
- Create: `lib/services/cloud/cloud_media_name_parser.dart`
- Create: `test/cloud_media_name_parser_test.dart`
- Modify: `lib/services/cloud/cloud_resource_tmdb_service.dart`

- [ ] **Step 1: 写出 Alice 单集和发布标签的失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_media_name_parser.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

void main() {
  const parser = CloudMediaNameParser();

  test('单集名称识别标题、季号、集号和电视剧类型', () {
    final draft = parser.parse(
      originalName: 'Alice in Borderland S01E01.mkv',
      isDirectory: false,
    );

    expect(draft.originalName, 'Alice in Borderland S01E01.mkv');
    expect(draft.searchTitle, 'Alice in Borderland');
    expect(draft.mediaTypeMode, TmdbMediaTypeMode.tv);
    expect(draft.seasonNumber, 1);
    expect(draft.episodeNumber, 1);
    expect(draft.year, isNull);
  });

  test('发布标签被清理且括号年份被结构化', () {
    final draft = parser.parse(
      originalName: '弥留之国的爱丽丝 (2020) 2160p WEB-DL x265 HDR 全8集',
      isDirectory: true,
    );

    expect(draft.searchTitle, '弥留之国的爱丽丝');
    expect(draft.year, 2020);
  });

  test('自定义剧名优先但季集仍从原名称识别', () {
    final draft = parser.parse(
      originalName: 'Alice.in.Borderland.S02E03.1080p.mkv',
      isDirectory: false,
      preferredTitle: '弥留之国的爱丽丝',
    );

    expect(draft.searchTitle, '弥留之国的爱丽丝');
    expect(draft.seasonNumber, 2);
    expect(draft.episodeNumber, 3);
  });
}
```

- [ ] **Step 2: 运行解析器测试并确认因类型不存在而失败**

Run: `D:\flutter\bin\flutter.bat test test/cloud_media_name_parser_test.dart`

Expected: FAIL，提示找不到 `cloud_media_name_parser.dart` 或 `CloudMediaNameParser`。

- [ ] **Step 3: 实现不可变草稿和最小解析器**

```dart
import 'package:flutter/foundation.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

@immutable
class TmdbMatchDraft {
  const TmdbMatchDraft({
    required this.originalName,
    required this.searchTitle,
    required this.mediaTypeMode,
    this.year,
    this.seasonNumber,
    this.episodeNumber,
  });

  final String originalName;
  final String searchTitle;
  final TmdbMediaTypeMode mediaTypeMode;
  final int? year;
  final int? seasonNumber;
  final int? episodeNumber;
}

class CloudMediaNameParser {
  const CloudMediaNameParser();

  TmdbMatchDraft parse({
    required String originalName,
    required bool isDirectory,
    String? preferredTitle,
  }) {
    final source = isDirectory
        ? originalName.trim()
        : originalName.replaceFirst(RegExp(r'\.[^.\\/]+$'), '').trim();
    final episode = RegExp(
      r'\bS(\d{1,2})E(\d{1,3})\b',
      caseSensitive: false,
    ).firstMatch(source);
    final yearMatch = RegExp(
      r'(?:^|[\s._(（])((?:19|20)\d{2})(?=$|[\s._)）])',
    ).firstMatch(source);
    final titleSource = preferredTitle?.trim().isNotEmpty == true
        ? preferredTitle!.trim()
        : source;
    final title = _cleanTitle(titleSource);
    return TmdbMatchDraft(
      originalName: originalName,
      searchTitle: title.isEmpty ? source : title,
      mediaTypeMode:
          episode == null ? TmdbMediaTypeMode.auto : TmdbMediaTypeMode.tv,
      year: yearMatch == null ? null : int.parse(yearMatch.group(1)!),
      seasonNumber:
          episode == null ? null : int.parse(episode.group(1)!),
      episodeNumber:
          episode == null ? null : int.parse(episode.group(2)!),
    );
  }

  String _cleanTitle(String value) {
    return value
        .replaceAll(RegExp(r'\bS\d{1,2}E\d{1,3}\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'[（(](?:19|20)\d{2}[)）]'), ' ')
        .replaceAll(
          RegExp(
            r'\b(?:2160p|1080p|720p|4k|8k|uhd|hdr10?|bluray|web-?dl|x26[45]|h26[45])\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'全\s*\d+\s*集|全集|完结'), ' ')
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
```

- [ ] **Step 4: 增加季目录、普通括号标题、字幕组和未知名称测试并收紧清理规则**

```dart
test('只删除已知发布标签并保留正式括号标题', () {
  final rec = parser.parse(originalName: '[REC] (2007).mkv', isDirectory: false);
  final release = parser.parse(
    originalName: '作品【字幕组】[WEB-DL] 1080p.mkv',
    isDirectory: false,
  );

  expect(rec.searchTitle, '[REC]');
  expect(rec.year, 2007);
  expect(release.searchTitle, '作品');
});

test('未知名称不猜测结构字段', () {
  final draft = parser.parse(originalName: 'Untitled Video.mkv', isDirectory: false);

  expect(draft.searchTitle, 'Untitled Video');
  expect(draft.year, isNull);
  expect(draft.seasonNumber, isNull);
  expect(draft.episodeNumber, isNull);
});
```

实现只删除内容命中 `字幕组|字幕|中字|WEB-DL|BluRay|x264|x265` 的 `[]` 或 `【】` 块，不无条件删除所有括号内容。

- [ ] **Step 5: 让旧 `queryName` 委托新解析器并运行相关测试**

Run: `D:\flutter\bin\flutter.bat test test/cloud_media_name_parser_test.dart test/cloud_resource_tmdb_service_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交解析器**

```powershell
git add -- lib/services/cloud/cloud_media_name_parser.dart lib/services/cloud/cloud_resource_tmdb_service.dart test/cloud_media_name_parser_test.dart test/cloud_resource_tmdb_service_test.dart
git commit -m "功能：解析网盘媒体名称"
```

### Task 2: 扩展严格匹配器为稳定候选排序

**Files:**
- Modify: `lib/services/tmdb/tmdb_matcher.dart`
- Modify: `test/tmdb_matcher_test.dart`

- [ ] **Step 1: 写出候选信号、稳定排序和自动双类型的失败测试**

```dart
test('候选按严格分数排序并暴露匹配信号', () {
  final result = matcher.rank(
    queryTitle: 'Alice in Borderland',
    queryYear: 2020,
    expectedTypes: const {TmdbMediaType.tv},
    candidates: <TmdbMetadata>[
      metadata(2, 'Alice', TmdbMediaType.tv, '2020-01-01'),
      metadata(1, 'Alice in Borderland', TmdbMediaType.tv, '2020-12-10'),
    ],
  );

  expect(result.candidates.first.metadata.id, 1);
  expect(result.candidates.first.titleMatched, isTrue);
  expect(result.candidates.first.yearMatched, isTrue);
  expect(result.candidates.first.typeMatched, isTrue);
  expect(result.shouldAutoMatch, isTrue);
});

test('自动类型允许电影和电视剧统一评分', () {
  final result = matcher.rank(
    queryTitle: '同名作品',
    expectedTypes: const {TmdbMediaType.movie, TmdbMediaType.tv},
    candidates: <TmdbMetadata>[
      metadata(1, '同名作品', TmdbMediaType.movie, '2020-01-01'),
      metadata(2, '同名作品', TmdbMediaType.tv, '2020-01-01'),
    ],
  );

  expect(result.candidates.map((item) => item.metadata.id), <int>[1, 2]);
  expect(result.shouldAutoMatch, isFalse);
});
```

- [ ] **Step 2: 运行匹配器测试并确认 `rank` 不存在**

Run: `D:\flutter\bin\flutter.bat test test/tmdb_matcher_test.dart`

Expected: FAIL，提示 `rank` 未定义。

- [ ] **Step 3: 增加候选类型和 `rank`，让 `choose` 复用它**

```dart
class TmdbRankedCandidate {
  const TmdbRankedCandidate({
    required this.metadata,
    required this.score,
    required this.titleMatched,
    required this.yearMatched,
    required this.typeMatched,
  });

  final TmdbMetadata metadata;
  final double score;
  final bool titleMatched;
  final bool yearMatched;
  final bool typeMatched;
}

class TmdbRankedResult {
  const TmdbRankedResult({
    required this.candidates,
    required this.shouldAutoMatch,
  });

  final List<TmdbRankedCandidate> candidates;
  final bool shouldAutoMatch;

  TmdbRankedCandidate? get best => candidates.firstOrNull;
}
```

`rank` 必须保留输入索引作为同分排序第二键；`shouldAutoMatch` 只在首项达到最低分、类型正确且与第二名差值达到 `minimumLead` 时为真。`choose` 返回首项元数据和分数，不复制评分公式。

- [ ] **Step 4: 运行匹配器测试**

Run: `D:\flutter\bin\flutter.bat test test/tmdb_matcher_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交匹配器扩展**

```powershell
git add -- lib/services/tmdb/tmdb_matcher.dart test/tmdb_matcher_test.dart
git commit -m "功能：排序 TMDB 匹配候选"
```

### Task 3: 增加显式搜索请求、双类型查询和 LRU 缓存

**Files:**
- Create: `lib/services/cloud/cloud_resource_tmdb_search.dart`
- Modify: `lib/services/cloud/cloud_resource_tmdb_service.dart`
- Modify: `test/cloud_resource_tmdb_service_test.dart`

- [ ] **Step 1: 定义搜索与选择结果类型**

```dart
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

class CloudResourceTmdbSearchRequest {
  const CloudResourceTmdbSearchRequest({
    required this.queryTitle,
    required this.mediaTypeMode,
    required this.options,
    this.queryYear,
  });

  final String queryTitle;
  final TmdbMediaTypeMode mediaTypeMode;
  final TmdbScrapeOptions options;
  final int? queryYear;
}

class CloudResourceTmdbSearchOutcome {
  const CloudResourceTmdbSearchOutcome({required this.ranked});
  final TmdbRankedResult ranked;
}

class CloudResourceTmdbSelectionOutcome {
  const CloudResourceTmdbSelectionOutcome({
    required this.record,
    required this.posterCached,
    required this.indexSynced,
  });

  final CloudResourceTmdbRecord record;
  final bool posterCached;
  final bool indexSynced;
}
```

- [ ] **Step 2: 写出自动类型查询两个端点和缓存重评分的失败测试**

测试使用可变 `now`，连续相同查询只调用每个 TMDB 类型一次；改变年份后命中候选缓存但排序结果重新计算；推进 11 分钟后重新请求。再循环 51 个不同查询，断言最早一项被淘汰。

- [ ] **Step 3: 运行服务测试并确认新 API 不存在**

Run: `D:\flutter\bin\flutter.bat test test/cloud_resource_tmdb_service_test.dart`

Expected: FAIL，提示 `CloudResourceTmdbSearchRequest` 或 `searchPrepared` 未定义。

- [ ] **Step 4: 实现 `searchPrepared` 和有界 LRU**

`CloudResourceTmdbService` 新增：

```dart
Future<CloudResourceTmdbSearchOutcome> searchPrepared(
  CloudResourceTmdbTarget target,
  CloudResourceTmdbSearchRequest request,
)
```

方法先验证 `queryTitle.trim().isNotEmpty`，按 `mediaTypeMode` 决定一个或两个端点，合并候选后调用 `TmdbMatcher.rank`。缓存使用 `LinkedHashMap<String, _CachedSearch>`，命中时先移除再插入表示最近使用；每次读取检查 10 分钟 TTL；插入后从头移除直到不超过 50 项。缓存项只保存 `List<TmdbMetadata>` 和创建时间。

- [ ] **Step 5: 让现有自动 `match` 和 `searchCandidates` 通过适配请求复用新方法**

自动请求使用解析后的标题与年份；`TmdbScrapeOptions.mediaTypeMode` 原样进入请求。`match` 只在 `ranked.shouldAutoMatch` 为真时调用选择路径；无候选仍保存 7 天负缓存，手动 `searchPrepared` 不保存未匹配记录。

- [ ] **Step 6: 运行解析、匹配和服务测试**

Run: `D:\flutter\bin\flutter.bat test test/cloud_media_name_parser_test.dart test/tmdb_matcher_test.dart test/cloud_resource_tmdb_service_test.dart`

Expected: PASS。

- [ ] **Step 7: 提交搜索服务**

```powershell
git add -- lib/services/cloud/cloud_resource_tmdb_search.dart lib/services/cloud/cloud_resource_tmdb_service.dart test/cloud_resource_tmdb_service_test.dart
git commit -m "功能：增强网盘 TMDB 搜索"
```

### Task 4: 选择候选时容忍图片和索引部分失败

**Files:**
- Modify: `lib/services/cloud/cloud_resource_tmdb_service.dart`
- Modify: `test/cloud_resource_tmdb_service_test.dart`

- [ ] **Step 1: 写出海报失败仍保存和索引失败可识别的失败测试**

分别注入抛错的 `CloudPosterCache` 下载器和抛错的媒体索引存储。断言 `selectWithOutcome` 返回已保存记录；海报失败时 `posterCached == false`，索引失败时 `indexSynced == false`，旧的 `select` 仍返回记录。

- [ ] **Step 2: 运行目标测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test/cloud_resource_tmdb_service_test.dart --plain-name "海报缓存失败仍保存文字元数据"`

Expected: FAIL，提示 `selectWithOutcome` 未定义或异常未被隔离。

- [ ] **Step 3: 实现 `selectWithOutcome` 和兼容适配层**

```dart
Future<CloudResourceTmdbRecord> select(
  CloudResourceTmdbTarget target,
  TmdbMetadata candidate, {
  TmdbScrapeOptions options = const TmdbScrapeOptions.defaults(),
}) async {
  return (await selectWithOutcome(target, candidate, options: options)).record;
}
```

`selectWithOutcome` 必须先取得详情；图片缓存异常只将 `posterCached` 设为 `false`；资源记录保存失败继续抛出；索引同步异常只将 `indexSynced` 设为 `false`。不得把 API Key、Cookie 或 URL 写入错误文本。

- [ ] **Step 4: 增加幂等 `syncRecordToIndex`**

从已匹配 `CloudResourceTmdbRecord` 重建索引所需字段，并复用 `_syncIndex`。记录不是 `matched` 或缺少 TMDB ID/媒体类型/标题时直接返回 `false`，不得请求 TMDB。

- [ ] **Step 5: 运行服务全文件测试**

Run: `D:\flutter\bin\flutter.bat test test/cloud_resource_tmdb_service_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交安全选择路径**

```powershell
git add -- lib/services/cloud/cloud_resource_tmdb_service.dart test/cloud_resource_tmdb_service_test.dart
git commit -m "修复：保留部分成功的 TMDB 匹配"
```

### Task 5: 贯通 Coordinator 与 Controller 强类型 API

**Files:**
- Modify: `lib/services/cloud/cloud_resource_tmdb_coordinator.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `test/cloud_resource_tmdb_coordinator_test.dart`
- Modify: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1: 写出草稿优先级、显式请求透传和待同步重试测试**

断言 Controller 使用记录的 `customTitle` 生成草稿；显式搜索词、类型和年份原样传到 Coordinator；`selectPrepared` 返回 `indexSynced == false` 时记录稳定键，下一次 `loadAndSchedule` 调用 `syncRecordToIndex`，成功后移除待同步键。

- [ ] **Step 2: 运行两个测试文件并确认新方法缺失**

Run: `D:\flutter\bin\flutter.bat test test/cloud_resource_tmdb_coordinator_test.dart test/cloud_resources_controller_test.dart`

Expected: FAIL，提示 `tmdbDraftFor`、`searchTmdb` 或 `selectPrepared` 未定义。

- [ ] **Step 3: 在 Coordinator 增加强类型方法**

```dart
Future<CloudResourceTmdbSearchOutcome> searchPrepared(
  CloudResourceTmdbTarget target,
  CloudResourceTmdbSearchRequest request,
)

Future<CloudResourceTmdbSelectionOutcome> selectPrepared(
  CloudResourceTmdbTarget target,
  TmdbRankedCandidate candidate, {
  required TmdbScrapeOptions options,
})
```

两者继续经过 `_requiredApiKey` 和 `_tracked`。选择结果中的记录立即更新 `_records`；索引未同步时把稳定键和目标加入内存待同步表。`loadAndSchedule` 加载记录后，先对当前目录可定位的待同步项重试一次，再执行自动刮削。

- [ ] **Step 4: 在 Controller 增加页面 API**

```dart
TmdbMatchDraft tmdbDraftFor(CloudFileEntry entry)

Future<CloudResourceTmdbSearchOutcome> searchTmdb(
  CloudFileEntry entry,
  CloudResourceTmdbSearchRequest request,
)

Future<CloudResourceTmdbSelectionOutcome> applyTmdbCandidate(
  CloudFileEntry entry,
  TmdbRankedCandidate candidate, {
  required TmdbScrapeOptions options,
})
```

`tmdbDraftFor` 使用 `tmdbRecordFor(entry)?.effectiveTitle` 作为首选搜索标题，但只有存在自定义标题或已匹配标题时才传入；原始季集始终来自 `entry.name`。

- [ ] **Step 5: 保留旧 `rematchTmdb` 和 `selectTmdbCandidate` 兼容行为**

旧方法继续供其他页面和测试使用，内部可委托新方法，但公开返回类型不得改变。

- [ ] **Step 6: 运行 Coordinator、Controller 和服务测试**

Run: `D:\flutter\bin\flutter.bat test test/cloud_resource_tmdb_service_test.dart test/cloud_resource_tmdb_coordinator_test.dart test/cloud_resources_controller_test.dart`

Expected: PASS。

- [ ] **Step 7: 提交编排层**

```powershell
git add -- lib/services/cloud/cloud_resource_tmdb_coordinator.dart lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_resource_tmdb_coordinator_test.dart test/cloud_resources_controller_test.dart
git commit -m "功能：贯通网盘 TMDB 匹配流程"
```

### Task 6: 实现居中双栏匹配弹窗

**Files:**
- Create: `lib/pages/cloud/resources/cloud_tmdb_match_dialog.dart`
- Create: `test/cloud_tmdb_match_dialog_test.dart`

- [ ] **Step 1: 写出初始字段、候选选择和取消不保存的失败 Widget 测试**

测试构造 `TmdbMatchDraft`，注入记录请求的 `onSearch` 和 `onApply` 回调。断言原文件名、搜索词、电视剧、2020、第 1 季、第 1 集和安全提示可见；修改搜索词后按 Enter 发送请求；未选候选时“应用匹配”禁用；选择候选后保存一次；关闭不调用保存。

- [ ] **Step 2: 运行弹窗测试并确认 Widget 不存在**

Run: `D:\flutter\bin\flutter.bat test test/cloud_tmdb_match_dialog_test.dart`

Expected: FAIL，提示找不到 `CloudTmdbMatchDialog`。

- [ ] **Step 3: 创建有状态弹窗和回调接口**

```dart
typedef CloudTmdbSearchCallback = Future<CloudResourceTmdbSearchOutcome>
    Function(CloudResourceTmdbSearchRequest request);
typedef CloudTmdbApplyCallback = Future<CloudResourceTmdbSelectionOutcome>
    Function(TmdbRankedCandidate candidate, TmdbScrapeOptions options);

class CloudTmdbMatchDialog extends StatefulWidget {
  const CloudTmdbMatchDialog({
    super.key,
    required this.title,
    required this.draft,
    required this.initialOptions,
    required this.onSearch,
    required this.onApply,
  });

  final String title;
  final TmdbMatchDraft draft;
  final TmdbScrapeOptions initialOptions;
  final CloudTmdbSearchCallback onSearch;
  final CloudTmdbApplyCallback onApply;
}
```

State 持有文本控制器、类型、选项、候选、选中项、加载/保存标志、错误文本和 `_requestGeneration`。搜索完成前后比较代次；`dispose` 释放控制器；异步回调后先检查 `mounted`。

- [ ] **Step 4: 构建响应式双栏与候选卡片**

使用 `Dialog`、`ConstrainedBox(maxWidth: 960, maxHeight: 720)` 和 `LayoutBuilder`。宽度小于 720 时用 `Column`，否则用 `Row`。候选卡片复用 `TmdbMatchSheet.imageUrl`，展示中文标题、原始标题、年份、类型、评分和匹配信号。最高分且 `ranked.shouldAutoMatch` 为真时显示“推荐”。

- [ ] **Step 5: 增加验证、键盘和竞态测试**

空搜索词与非四位年份不调用搜索；Enter 搜索；Esc 关闭；两次搜索倒序完成时只显示第二次结果；搜索或保存期间按钮不可重复触发；海报或索引部分失败显示准确提示。

- [ ] **Step 6: 运行弹窗测试**

Run: `D:\flutter\bin\flutter.bat test test/cloud_tmdb_match_dialog_test.dart`

Expected: PASS。

- [ ] **Step 7: 提交弹窗**

```powershell
git add -- lib/pages/cloud/resources/cloud_tmdb_match_dialog.dart test/cloud_tmdb_match_dialog_test.dart
git commit -m "功能：新增网盘 TMDB 匹配弹窗"
```

### Task 7: 接入单项入口并增强批量汇总

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 改写单项页面测试为准备弹窗流程**

从资源菜单分别点击“TMDB 刮削”和“重新匹配”，断言两者都出现 `cloud-tmdb-match-dialog`；搜索后出现候选；选择并应用后 Fake Coordinator 收到正确候选；原文件名仍显示。删除旧的“先打开选项底部表、再打开候选底部表”期望。

- [ ] **Step 2: 运行页面目标测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test/cloud_resources_page_test.dart --plain-name "重新匹配显示可编辑搜索词与候选并保存"`

Expected: FAIL，因为页面仍打开两个 BottomSheet。

- [ ] **Step 3: 用共享 `_openTmdbDialog` 替换两个旧流程**

```dart
Future<void> _openTmdbDialog(
  CloudFileEntry entry, {
  required bool rematch,
}) async {
  final draft = _controller.tmdbDraftFor(entry);
  await showDialog<void>(
    context: context,
    builder: (context) => CloudTmdbMatchDialog(
      title: rematch ? '重新匹配 TMDB' : 'TMDB 刮削',
      draft: draft,
      initialOptions: _controller.tmdbScrapeOptions,
      onSearch: (request) => _controller.searchTmdb(entry, request),
      onApply: (candidate, options) => _controller.applyTmdbCandidate(
        entry,
        candidate,
        options: options,
      ),
    ),
  );
}
```

`_scrapeEntry` 和 `_rematchEntry` 只负责调用此方法。页面不再为单项操作直接调用旧 `TmdbScrapeOptionsSheet` 或 `TmdbMatchSheet`。

- [ ] **Step 4: 写出批量四类汇总且不弹窗的失败测试**

Fake Coordinator 按四个资源依次返回：已选择、存在候选但未自动选择、空候选、抛出异常。点击“刮削当前目录”后断言没有 `CloudTmdbMatchDialog`，其他资源继续处理，SnackBar 显示“成功 1 项，待确认 1 项，无结果 1 项，失败 1 项”。

- [ ] **Step 5: 实现批量分类计数**

循环中：`selected != null` 计成功；`candidates.isNotEmpty` 计待确认；空候选计无结果；异常计失败。保持最大并发和现有进度显示不变，不在批量路径调用 `showDialog`。

- [ ] **Step 6: 运行网盘页面、集成和字幕回归测试**

Run: `D:\flutter\bin\flutter.bat test test/cloud_resources_page_test.dart test/cloud_library_integration_test.dart test/cloud_media_indexer_test.dart`

Expected: PASS。

- [ ] **Step 7: 提交页面接入**

```powershell
git add -- lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_resources_page_test.dart
git commit -m "功能：接入网盘 TMDB 渐进式匹配"
```

### Task 8: 版本、全量验证和 Windows MSIX 交付

**Files:**
- Modify: `pubspec.yaml`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: 更新版本和用户发布说明**

将 `pubspec.yaml` 的 `version` 更新为 `2.1.11+20111`，并将 `msix_config.msix_version` 更新为 `2.1.11.0`。发布说明使用普通用户能理解的文案：单项刮削可先修改搜索词和类型、候选信息更完整、批量歧义不再误匹配、网盘原文件不会改变。

- [ ] **Step 2: 格式化本轮 Dart 文件并检查 diff**

Run: `D:\flutter\bin\dart.bat format lib/services/cloud/cloud_media_name_parser.dart lib/services/cloud/cloud_resource_tmdb_search.dart lib/services/tmdb/tmdb_matcher.dart lib/services/cloud/cloud_resource_tmdb_service.dart lib/services/cloud/cloud_resource_tmdb_coordinator.dart lib/pages/cloud/resources/cloud_resources_controller.dart lib/pages/cloud/resources/cloud_tmdb_match_dialog.dart lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_media_name_parser_test.dart test/tmdb_matcher_test.dart test/cloud_resource_tmdb_service_test.dart test/cloud_resource_tmdb_coordinator_test.dart test/cloud_resources_controller_test.dart test/cloud_tmdb_match_dialog_test.dart test/cloud_resources_page_test.dart`

Expected: 命令退出码 0。

- [ ] **Step 3: 运行完整测试**

Run: `D:\flutter\bin\flutter.bat test`

Expected: 全部测试通过，无失败或跳过的新增关键测试。

- [ ] **Step 4: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze`

Expected: `No issues found!`。

- [ ] **Step 5: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release`

Expected: 生成 `build\windows\x64\runner\Release\kanyingyin.exe`，命令退出码 0。

- [ ] **Step 6: 按项目 MSIX skill 生成签名安装包**

执行 `flutter-windows-msix-packaging` skill 指定的预检、清理旧 staging、打包和签名步骤。不得手工复用旧 Release 目录或旧清单。

Expected: 新 MSIX 清单 `Identity Version="2.1.11.0"`，签名状态为 `Valid`。

- [ ] **Step 7: 复制桌面安装包并计算 SHA-256**

目标必须是 `C:\Users\asus\Desktop\看影音-2.1.11.msix`。验证文件存在、清单版本正确、签名有效，并记录 `Get-FileHash -Algorithm SHA256` 输出。

- [ ] **Step 8: 检查只包含本轮文件并提交发布**

Run: `git status --short` 和 `git diff --check`。

只暂存本轮代码、测试、版本和发布文档；不得暂存 `.learnings/ERRORS.md`、`.learnings/LEARNINGS.md` 或 `.superpowers/`。

```powershell
git add -- pubspec.yaml RELEASE_NOTES.md lib/utils/version_history.dart
git commit -m "发布：交付网盘 TMDB 渐进式匹配 2.1.11"
```

- [ ] **Step 9: 最终验收记录**

交付说明必须包含：测试总数、`flutter analyze` 结果、Windows Release 路径、桌面 MSIX 路径、清单版本、签名状态、SHA-256、相关提交，以及未提交的用户原有 `.learnings` 修改。
