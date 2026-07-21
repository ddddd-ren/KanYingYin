# 本地与网盘 TMDB 统一刮削 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让本地媒体库和所有网盘来源通过同一套标题清洗、类型判断、候选评分、字段合并、季度海报和安全迁移规则完成 TMDB 刮削。

**Architecture:** 新增无来源依赖的刮削主题、搜索规划、搜索引擎、元数据合并和海报选择策略；本地与网盘只负责把现有识别结果转换成共享主题，并通过各自仓库和图片存储提交结果。匹配记录持久化自动/手动来源与规则版本，旧记录只在同一 TMDB ID 时自动刷新，冲突时保留旧数据并要求确认。

**Tech Stack:** Flutter、Dart、Flutter Modular、MobX、Hive CE、Dio、TMDB API、flutter_test、PowerShell、MSIX、SignTool。

---

### Task 1: 共享刮削主题与搜索规划

**Files:**
- Create: `lib/services/tmdb/tmdb_scrape_subject.dart`
- Create: `lib/services/tmdb/tmdb_scrape_policy.dart`
- Create: `test/tmdb_scrape_policy_test.dart`

- [ ] **Step 1: 写入标题、年份和媒体类型规划失败测试**

测试以下真实规则：发布规格和季集标识被清理；手动标题优先且重复候选去重；显式电影/电视剧覆盖自动判断；自动模式有季集证据时只搜索电视剧，电影证据只搜索电影，未知时按电影、电视剧顺序同时搜索。

```dart
const subject = TmdbScrapeSubject(
  stableKey: 'same-work',
  titleCandidates: <String>[
    '三体 S01 2160p WEB-DL',
    '三体 第一季',
  ],
  year: 2023,
  seasonNumbers: <int>{1},
  episodeNumbers: <int>{1, 2},
  mediaEvidence: TmdbMediaEvidence.tv,
);
final plan = const TmdbScrapePolicy().build(
  subject,
  const TmdbScrapeOptions.defaults(),
);
expect(plan.queries, <String>['三体']);
expect(plan.year, 2023);
expect(plan.mediaTypes, <TmdbMediaType>[TmdbMediaType.tv]);
```

- [ ] **Step 2: 运行测试并确认共享类型不存在**

```powershell
D:\flutter\bin\flutter.bat test test\tmdb_scrape_policy_test.dart
```

预期：FAIL，找不到 `TmdbScrapeSubject` 或 `TmdbScrapePolicy`。

- [ ] **Step 3: 实现强类型主题与搜索计划**

`tmdb_scrape_subject.dart` 定义：

```dart
const int currentTmdbRuleVersion = 1;

enum TmdbMediaEvidence { movie, tv, unknown }
enum TmdbMatchOrigin { automatic, manual, legacyUnknown }

class TmdbFieldLocks {
  const TmdbFieldLocks({
    this.title = false,
    this.overview = false,
    this.poster = false,
  });
  final bool title;
  final bool overview;
  final bool poster;
}

class TmdbScrapeSubject {
  const TmdbScrapeSubject({
    required this.stableKey,
    required this.titleCandidates,
    this.year,
    this.seasonNumbers = const <int>{},
    this.episodeNumbers = const <int>{},
    this.mediaEvidence = TmdbMediaEvidence.unknown,
    this.existingMetadata,
    this.fieldLocks = const TmdbFieldLocks(),
    this.matchOrigin = TmdbMatchOrigin.legacyUnknown,
    this.ruleVersion = 0,
  });
  final String stableKey;
  final List<String> titleCandidates;
  final int? year;
  final Set<int> seasonNumbers;
  final Set<int> episodeNumbers;
  final TmdbMediaEvidence mediaEvidence;
  final TmdbMetadata? existingMetadata;
  final TmdbFieldLocks fieldLocks;
  final TmdbMatchOrigin matchOrigin;
  final int ruleVersion;
}
```

`TmdbScrapePolicy.build()` 返回不可变 `TmdbSearchPlan`。标题清洗覆盖 `SxxExxx`、中英文季度、年份括号、分辨率、编码、HDR、WEB-DL、BluRay、字幕与发布组方括号；规范化后按不区分大小写去重。媒体类型严格按已确认设计映射。

- [ ] **Step 4: 运行规划测试和现有选项测试**

```powershell
D:\flutter\bin\flutter.bat test test\tmdb_scrape_policy_test.dart test\tmdb_scrape_options_test.dart
```

预期：PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/services/tmdb/tmdb_scrape_subject.dart lib/services/tmdb/tmdb_scrape_policy.dart test/tmdb_scrape_policy_test.dart
git commit -m "统一TMDB搜索主题与规划"
```

### Task 2: 共享候选搜索与自动匹配引擎

**Files:**
- Create: `lib/services/tmdb/tmdb_scrape_engine.dart`
- Modify: `lib/services/tmdb/tmdb_matcher.dart`
- Modify: `lib/services/tmdb/tmdb_scraper.dart`
- Create: `test/tmdb_scrape_engine_test.dart`
- Modify: `test/tmdb_matcher_test.dart`
- Modify: `test/tmdb_scraper_test.dart`

- [ ] **Step 1: 写入多标题、多类型、去重和回退失败测试**

使用记录调用的 `ITmdbClient` 测试：第一个标题只有低分结果时继续第二个标题；电影与电视剧相同数字 ID 不互相去重；同类型同 ID 只保留一次；达到阈值时返回查询标题、稳定排序与自动候选；所有请求失败返回失败而不是未匹配。

```dart
final outcome = await TmdbScrapeEngine(
  client: fakeClient,
).search(subject, const TmdbScrapeOptions.defaults());
expect(fakeClient.queries, <String>['错误标题', '三体']);
expect(outcome.queryTitle, '三体');
expect(outcome.ranked.shouldAutoMatch, isTrue);
expect(outcome.ranked.best?.metadata.id, 42);
```

- [ ] **Step 2: 运行测试并确认引擎不存在**

```powershell
D:\flutter\bin\flutter.bat test test\tmdb_scrape_engine_test.dart
```

预期：FAIL，找不到 `TmdbScrapeEngine`。

- [ ] **Step 3: 实现搜索引擎和稳定匹配**

定义：

```dart
class TmdbScrapeSearchOutcome {
  const TmdbScrapeSearchOutcome({
    required this.queryTitle,
    required this.ranked,
  });
  final String? queryTitle;
  final TmdbRankedResult ranked;
}
```

引擎对规划中的每个标题搜索全部媒体类型，以 `mediaType.name:id` 去重，再调用 `TmdbMatcher.rank()`。当前标题达到自动阈值时立即返回；否则继续后续标题，并保留候选最高分更高的非空结果作为手动确认结果。网络异常向调用方抛出，空候选只在所有请求成功且确实为空时返回。

`TmdbMatcher` 的同分排序依次使用分数、标题完全匹配、年份匹配、媒体类型证据和原始稳定索引。`TmdbScraper` 改为单标题兼容门面，内部构造共享主题并调用引擎，保持现有公开返回类型。

- [ ] **Step 4: 运行共享引擎、评分器和旧刮削器测试**

```powershell
D:\flutter\bin\flutter.bat test test\tmdb_scrape_engine_test.dart test\tmdb_matcher_test.dart test\tmdb_scraper_test.dart
```

预期：PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/services/tmdb/tmdb_scrape_engine.dart lib/services/tmdb/tmdb_matcher.dart lib/services/tmdb/tmdb_scraper.dart test/tmdb_scrape_engine_test.dart test/tmdb_matcher_test.dart test/tmdb_scraper_test.dart
git commit -m "统一TMDB候选搜索与匹配"
```

### Task 3: 共享字段合并与季度海报策略

**Files:**
- Create: `lib/services/tmdb/tmdb_metadata_merge_policy.dart`
- Create: `lib/services/tmdb/tmdb_poster_policy.dart`
- Create: `test/tmdb_metadata_policy_test.dart`

- [ ] **Step 1: 写入字段锁定和海报选择失败测试**

测试标题、简介、海报锁定；所有 `overwrite*` 与 `fetch*` 选项；实际季度过滤；季度海报优先和作品海报回退。

```dart
final merged = const TmdbMetadataMergePolicy().merge(
  existing: oldMetadata,
  fetched: newMetadata,
  options: options,
  locks: const TmdbFieldLocks(title: true),
  matchConfidence: 0.92,
  existingSeasons: const <int>{2},
);
expect(merged.title, oldMetadata.title);
expect(merged.overview, newMetadata.overview);
expect(merged.seasons.map((item) => item.seasonNumber), <int>[2]);
expect(
  const TmdbPosterPolicy().select(merged, seasonNumber: 2),
  '/season-2.jpg',
);
```

- [ ] **Step 2: 运行测试并确认策略不存在**

```powershell
D:\flutter\bin\flutter.bat test test\tmdb_metadata_policy_test.dart
```

预期：FAIL，找不到合并或海报策略。

- [ ] **Step 3: 实现两个无副作用策略**

`TmdbMetadataMergePolicy.merge()` 按规格处理锁定、覆盖和抓取选项，更新评分、日期、语言、匹配时间及置信度。`existingSeasons` 非空时只保留实际季度并按季度号排序；为空时保留详情季度但不触发无关图片下载。

`TmdbPosterPolicy.select()` 在 `fetchPoster == false` 或海报锁定时返回现有图片策略结果；电视剧有当前季度海报时优先选择，否则回退总海报；电影只返回总海报。

- [ ] **Step 4: 运行策略测试和本地季度海报回归**

```powershell
D:\flutter\bin\flutter.bat test test\tmdb_metadata_policy_test.dart test\local_tmdb_integration_test.dart
```

预期：PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/services/tmdb/tmdb_metadata_merge_policy.dart lib/services/tmdb/tmdb_poster_policy.dart test/tmdb_metadata_policy_test.dart
git commit -m "统一TMDB字段与海报策略"
```

### Task 4: 持久化匹配来源与规则版本

**Files:**
- Modify: `lib/modules/local/local_media_index_item.dart`
- Modify: `lib/modules/cloud/cloud_resource_tmdb_record.dart`
- Modify: `lib/modules/cloud/cloud_work_tmdb_record.dart`
- Modify: `lib/modules/cloud/cloud_series_match_rule.dart`
- Modify: `test/local_media_index_tmdb_test.dart`
- Modify: `test/cloud_resource_tmdb_record_test.dart`
- Modify: `test/cloud_work_tmdb_record_test.dart`
- Modify: `test/cloud_series_match_rule_repository_test.dart`

- [ ] **Step 1: 写入 JSON 向后兼容失败测试**

新 JSON 必须往返保存 `tmdbMatchOrigin` 和 `tmdbRuleVersion`；旧 JSON 缺字段时读取为 `legacyUnknown` 与 `0`。本地 `copyWith`、网盘工厂和系列规则传播必须保留字段。

```dart
final legacy = LocalMediaIndexItem.fromJson(legacyJson);
expect(legacy.tmdbMatchOrigin, TmdbMatchOrigin.legacyUnknown);
expect(legacy.tmdbRuleVersion, 0);
final restored = LocalMediaIndexItem.fromJson(
  legacy.copyWith(
    tmdbMatchOrigin: TmdbMatchOrigin.manual,
    tmdbRuleVersion: currentTmdbRuleVersion,
  ).toJson(),
);
expect(restored.tmdbMatchOrigin, TmdbMatchOrigin.manual);
```

- [ ] **Step 2: 运行记录测试并确认字段不存在**

```powershell
D:\flutter\bin\flutter.bat test test\local_media_index_tmdb_test.dart test\cloud_resource_tmdb_record_test.dart test\cloud_work_tmdb_record_test.dart test\cloud_series_match_rule_repository_test.dart
```

预期：FAIL，找不到来源或规则版本字段。

- [ ] **Step 3: 增加兼容字段和工厂参数**

三个记录模型增加：

```dart
final TmdbMatchOrigin tmdbMatchOrigin;
final int tmdbRuleVersion;
```

普通构造器默认 `legacyUnknown / 0`，新 `matched` 工厂要求调用方显式传入来源与版本。JSON 只写有效枚举名和非负版本；非法值安全回退。手动学习的 `CloudSeriesMatchRule` 固定记录 `manual / currentTmdbRuleVersion`，应用规则生成的记录保持手动来源。

- [ ] **Step 4: 运行记录与仓库测试**

```powershell
D:\flutter\bin\flutter.bat test test\local_media_index_tmdb_test.dart test\cloud_resource_tmdb_record_test.dart test\cloud_work_tmdb_record_test.dart test\cloud_series_match_rule_repository_test.dart
```

预期：PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/modules/local/local_media_index_item.dart lib/modules/cloud/cloud_resource_tmdb_record.dart lib/modules/cloud/cloud_work_tmdb_record.dart lib/modules/cloud/cloud_series_match_rule.dart test/local_media_index_tmdb_test.dart test/cloud_resource_tmdb_record_test.dart test/cloud_work_tmdb_record_test.dart test/cloud_series_match_rule_repository_test.dart
git commit -m "记录TMDB匹配来源与规则版本"
```

### Task 5: 本地媒体库接入共享规则并安全迁移

**Files:**
- Create: `lib/services/tmdb/local_tmdb_subject_builder.dart`
- Modify: `lib/services/tmdb/local_tmdb_scrape_service.dart`
- Modify: `test/local_tmdb_integration_test.dart`
- Create: `test/local_tmdb_subject_builder_test.dart`

- [ ] **Step 1: 写入本地主题和迁移失败测试**

覆盖：本地系列生成与网盘等价的清洗前候选和季集证据；新自动匹配写入 `automatic / 1`；手动选择写入 `manual / 1`；旧记录同 ID 刷新；不同 ID 或低置信度保留旧元数据并设为 `pending`；锁定记录不自动迁移。

```dart
final result = await service.scrapeSeries(
  apiKey: 'key',
  seriesName: '三体 S01 2160p',
);
final item = index.getAll().single;
expect(result.status, TmdbScrapeStatus.matched);
expect(item.tmdbMatchOrigin, TmdbMatchOrigin.automatic);
expect(item.tmdbRuleVersion, currentTmdbRuleVersion);
```

- [ ] **Step 2: 运行本地测试并确认旧服务行为不满足迁移**

```powershell
D:\flutter\bin\flutter.bat test test\local_tmdb_subject_builder_test.dart test\local_tmdb_integration_test.dart
```

预期：FAIL，主题构建器不存在或记录未写入新字段。

- [ ] **Step 3: 接入共享引擎、合并和海报策略**

`LocalTmdbSubjectBuilder` 从同一 `seriesName` 的索引项生成标题候选、年份、实际季度/集号、媒体证据、现有元数据和字段锁定。

`LocalTmdbScrapeService` 删除私有 `_extractYear`、`_inferType`、`_resolveType`、`_mergeMetadata` 和 `_posterPathFor` 规则，改用共享策略。自动结果只在无旧数据或与旧记录 ID 相同时提交；冲突保留旧元数据、保存候选并返回 `pending`。`selectCandidate()` 始终记录手动来源。图片仍写入本地 `tmdb-poster.jpg`，下载失败不回滚元数据。

- [ ] **Step 4: 运行本地 TMDB、扫描和播放回归**

```powershell
D:\flutter\bin\flutter.bat test test\local_tmdb_subject_builder_test.dart test\local_tmdb_integration_test.dart test\local_controller_test.dart test\local_playback_request_builder_test.dart
```

预期：PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/services/tmdb/local_tmdb_subject_builder.dart lib/services/tmdb/local_tmdb_scrape_service.dart test/local_tmdb_subject_builder_test.dart test/local_tmdb_integration_test.dart
git commit -m "接入本地统一TMDB刮削"
```

### Task 6: 网盘作品与资源接入共享规则和一致性契约

**Files:**
- Create: `lib/services/cloud/cloud_tmdb_subject_builder.dart`
- Modify: `lib/services/cloud/cloud_work_tmdb_service.dart`
- Modify: `lib/services/cloud/cloud_resource_tmdb_service.dart`
- Modify: `lib/services/cloud/cloud_work_tmdb_coordinator.dart`
- Modify: `lib/services/cloud/cloud_resource_tmdb_coordinator.dart`
- Create: `test/tmdb_local_cloud_contract_test.dart`
- Modify: `test/cloud_work_tmdb_service_test.dart`
- Modify: `test/cloud_resource_tmdb_service_test.dart`
- Modify: `test/cloud_work_tmdb_coordinator_test.dart`
- Modify: `test/cloud_resource_tmdb_coordinator_test.dart`
- Modify: `test/cloud_library_integration_test.dart`

- [ ] **Step 1: 写入本地/网盘一致性契约和云迁移失败测试**

对电影、单季剧、多季剧、纯集号文件、年份目录和发布规格名称，分别通过本地与网盘主题构建器生成主题，再由共享策略断言搜索标题、年份、类型、候选顺序、自动结论、字段合并和季度海报完全一致。

云服务测试还要覆盖：自动和手动来源写入；版本 `0` 同 ID 刷新；不同 ID 进入 `conflict` 并保留旧元数据；已有系列规则不自动迁移；匹配版本 `1` 不在每次加载重复请求。

- [ ] **Step 2: 运行契约测试并确认云端仍使用私有规则**

```powershell
D:\flutter\bin\flutter.bat test test\tmdb_local_cloud_contract_test.dart test\cloud_work_tmdb_service_test.dart test\cloud_resource_tmdb_service_test.dart
```

预期：FAIL，云主题构建器不存在或两端计划不同。

- [ ] **Step 3: 接入网盘作品与资源服务**

`CloudTmdbSubjectBuilder` 为作品树和独立资源生成共享主题。`CloudWorkTmdbService` 与 `CloudResourceTmdbService` 删除私有标题清洗、媒体类型列表、循环搜索、字段替换和季度海报选择规则，统一调用共享引擎、合并策略与海报策略；仅保留云仓库事务和 `CloudPosterCache`。

资源状态枚举增加 `conflict`。协调器只调度版本低于 `currentTmdbRuleVersion` 的旧匹配记录；手动、自定义标题、系列规则和冲突记录不自动覆盖。迁移同 ID 后写版本 `1`，失败保留旧版本以便后续退避重试。

- [ ] **Step 4: 运行网盘契约、三种来源和播放回归**

```powershell
D:\flutter\bin\flutter.bat test test\tmdb_local_cloud_contract_test.dart test\cloud_work_tmdb_service_test.dart test\cloud_resource_tmdb_service_test.dart test\cloud_work_tmdb_coordinator_test.dart test\cloud_resource_tmdb_coordinator_test.dart test\cloud_library_integration_test.dart test\cloud_playback_resolver_test.dart
```

预期：PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/services/cloud/cloud_tmdb_subject_builder.dart lib/services/cloud/cloud_work_tmdb_service.dart lib/services/cloud/cloud_resource_tmdb_service.dart lib/services/cloud/cloud_work_tmdb_coordinator.dart lib/services/cloud/cloud_resource_tmdb_coordinator.dart lib/modules/cloud/cloud_resource_tmdb_record.dart test/tmdb_local_cloud_contract_test.dart test/cloud_work_tmdb_service_test.dart test/cloud_resource_tmdb_service_test.dart test/cloud_work_tmdb_coordinator_test.dart test/cloud_resource_tmdb_coordinator_test.dart test/cloud_library_integration_test.dart
git commit -m "接入网盘统一TMDB刮削"
```

### Task 7: 完整验收、签名版本与安装包交付

**Files:**
- Create: `tool/windows/build_signed_release.ps1`
- Create: `test/signed_release_packaging_test.dart`
- Modify: `pubspec.yaml`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 写入签名打包行为和新版本失败测试**

测试脚本必须读取当前用户保护的 PFX 密码、构建 Release、创建 MSIX、用 SignTool 签名、验证 `Valid`、核对清单并复制桌面；异机 ZIP 固定清单包含 MSIX、公钥证书、安装脚本、说明和 SHA-256，禁止包含 PFX、密码、TMDB Key 与临时 JSON。版本测试明确升级到 `2.1.32+20132` 与 `2.1.32.0`，并要求发布文案包含“本地与网盘 TMDB 规则统一”和数据保护说明。

- [ ] **Step 2: 运行签名和版本测试并确认缺少脚本或旧版本**

```powershell
D:\flutter\bin\flutter.bat test test\signed_release_packaging_test.dart test\version_consistency_test.dart test\version_history_current_test.dart
```

预期：FAIL，缺少签名发布脚本或版本仍为上一版。

- [ ] **Step 3: 实现公共签名发布脚本并更新版本文案**

`build_signed_release.ps1` 只读取 `certificate.pfx` 与 `certificate-password.clixml`，不要求私人 TMDB Key。脚本使用本轮 Release 产物创建 MSIX，以 SHA-256 签名并验证，导出公钥证书，复用 `tool/windows/installer` 生成固定清单异机 ZIP。`finally` 清零 BSTR 和明文密码并删除受限临时目录。

同步应用版本为 `2.1.32+20132`、MSIX 版本为 `2.1.32.0`，并更新弹窗、README 和版本历史；文案面向普通用户说明统一匹配、旧手动结果保护、断网继续可用和不会修改原始媒体。

- [ ] **Step 4: 运行完整质量门禁**

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed .
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

预期：全部 exit code 0。

- [ ] **Step 5: 生成签名 MSIX、验证并复制桌面**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1
```

预期：桌面生成 `看影音-2.1.32.msix` 和 `看影音-2.1.32-异机安装包.zip`；清单身份、发布者、版本和 x64 正确；`Get-AuthenticodeSignature` 为 `Valid`；桌面文件哈希与构建产物一致。

- [ ] **Step 6: 检查差异并提交交付版本**

```powershell
git status --short
git diff --check
git add tool/windows/build_signed_release.ps1 test/signed_release_packaging_test.dart pubspec.yaml README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/core/app_version.dart lib/utils/version_history.dart test/version_consistency_test.dart test/identity_v2_zero_residue_test.dart test/version_history_current_test.dart
git commit -m "发布统一TMDB刮削测试版"
```

提交不得包含 `.learnings/ERRORS.md`、`.learnings/LEARNINGS.md`、构建目录、MSIX、ZIP、PFX、证书密码或 TMDB Key。
