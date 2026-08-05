# 网易爆米花刮削对标优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提升看影音对本地文件名、中文/英文别名、年份和季集信息的召回与自动匹配准确率，使本地、网盘作品和网盘资源得到一致且更完整的 TMDB 元数据。

**Architecture:** 复用现有的 TmdbScrapeSubject、TmdbScrapePolicy、TmdbScrapeEngine、TmdbMetadataMergePolicy 和 TmdbPosterPolicy。在共享 TMDB 层增加分页候选、替代标题、语言补充、逐集详情和请求缓存；本地与网盘只负责构造主题、保存记录和映射实际可播放文件，不各自维护评分规则。现有自动/手动来源、规则版本和冲突保护继续生效，新的匹配规则从版本 3 升到版本 4。

**Tech Stack:** Flutter 3.41.9、Dart、Dio、TMDB v3 API、Hive/现有仓库模型、flutter_test、PowerShell、网易爆米花 bmh-cli（仅用于对标采样）。

---

## 当前差距与不可变边界

- lib/services/tmdb/tmdb_matcher.dart 目前主要依赖标题完全/包含匹配、年份和媒体类型固定加分；没有别名、token 相似度、分页候选、季集证据和可解释评分信号。
- lib/services/tmdb/tmdb_client.dart 当前只取 /search/movie、/search/tv 的第一页；TmdbMetadata 只有季度级资料，没有剧集名称、播出日期和资源映射。
- lib/services/cloud/cloud_tmdb_metadata_service.dart 仍有直接 search -> choose 路径，可能和使用 TmdbScrapeEngine 的其他入口产生不同候选。
- lib/services/cloud/cloud_resource_tmdb_service.dart 有资源级短期搜索缓存，但不是共享缓存；多个入口同时刮削同一作品时仍可能重复请求。
- currentTmdbRuleVersion 为 3，LocalMediaIndexItem、CloudWorkTmdbRecord 和 CloudResourceTmdbRecord 已支持 TmdbMatchOrigin 与规则版本，必须保留旧 JSON 兼容和手动结果保护。
- 网易爆米花的搜索接口跨多个媒体源、支持模糊关键词和分页；其本地协议、AES 校验和服务端实现不属于看影音的可复用依赖，方案不复制这些协议。
- 不改变原始视频、字幕、网盘远程路径或播放 ID；TMDB 无 Key、断网、限流或详情失败时，扫描、已保存资料浏览和播放继续可用。

## 评分与验收目标

以不少于 30 条脱敏样本建立基线，样本包含电影、单季剧、多季剧、中文译名、英文原名、括号年份、纯数字集号、发布规格和同名歧义。实施完成后满足：

1. 自动匹配精确率不低于 98%，任何类型冲突或同名同年电影/电视剧不得自动确认。
2. Top-3 候选召回率不低于 95%，且相对基线自动召回率提高至少 15 个百分点；不能通过降低自动阈值换取召回。
3. 同一应用进程内相同查询的并发请求合并为一次；缓存命中搜索 P95 小于 100 ms，冷查询最多读取 3 页/类型并受并发上限约束。
4. 已存在的实际季度在 TMDB 有资料时，逐集标题和播出日期覆盖率达到 100%；缺失详情时回退 SxxExx 与原始文件名。
5. 全量 flutter test、flutter analyze 和 Windows Release 构建通过；本计划不自动改版本、不安装 MSIX。

### Task 1: 建立爆米花对标样本与可重复基线

**Files:**
- Create: test/fixtures/tmdb_scrape_corpus.dart
- Create: test/tmdb_scrape_benchmark_test.dart
- Create: docs/tmdb-scrape-benchmark.md

- [x] **Step 1: 固定样本结构和初始案例**

在 test/fixtures/tmdb_scrape_corpus.dart 定义 TmdbScrapeCorpusCase：

~~~dart
class TmdbScrapeCorpusCase {
  const TmdbScrapeCorpusCase({
    required this.name,
    required this.titleCandidates,
    required this.expectedType,
    required this.expectedIdentity,
    this.year,
    this.seasonNumbers = const <int>{},
    this.episodeNumbers = const <int>{},
    this.expectedAutoMatch = true,
  });

  final String name;
  final List<String> titleCandidates;
  final TmdbMediaType expectedType;
  final String expectedIdentity;
  final int? year;
  final Set<int> seasonNumbers;
  final Set<int> episodeNumbers;
  final bool expectedAutoMatch;
}
~~~

初始案例固定为：流浪地球2.2160p WEB-DL HEVC DDP 5.1.mkv、三体 S01E01 2160p WEB-DL、Isekai Nonbiri Nouka 2、H-回-元异-计【台剧】 (2025) 4K 全6集 完结、同名作品 2020；再补充至少 25 条覆盖括号年份、中文/英文别名、日文罗马字、OVA/特别篇、纯数字集号、两位数集号、多季度、同名不同年、同名不同类型和发布组误导词的样本。候选使用固定的 TmdbMetadata 假对象；expectedIdentity 使用稳定测试标识，避免单元测试依赖实时 TMDB ID。

- [x] **Step 2: 写基线测试并记录结果**

benchmark 测试调用现有 TmdbScrapeEngine，输出 case、expected、actual、auto、candidateCount、requestCount 以及 Top-1/Top-3 统计：

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/tmdb_scrape_benchmark_test.dart -r expanded
~~~

将日期、提交号和汇总数字写入 docs/tmdb-scrape-benchmark.md，不写入 API Key、Cookie、Token、远程路径或个人媒体源 ID。

- [x] **Step 3: 采集爆米花对标结果**

仅对脱敏关键词运行 CLI，先确认状态：

~~~powershell
C:/Users/asus/AppData/Local/BaoMiHua/netease-baomihua-player/bin/bmh-cli.exe --json doctor
C:/Users/asus/AppData/Local/BaoMiHua/netease-baomihua-player/bin/bmh-cli.exe --json search --keyword "流浪地球2" --page 1 --page-size 20 --types "2,3"
~~~

只摘录标题、年份、媒体类型、排序位置和公开 tmdb_id；emby、jellyfin、fnos、zspace 结果的 media_id 不当作 TMDB ID。文档不记录爆米花本地 HTTP/AES 细节。

- [x] **Step 4: 提交基线**

~~~powershell
git add test/fixtures/tmdb_scrape_corpus.dart test/tmdb_scrape_benchmark_test.dart docs/tmdb-scrape-benchmark.md
git commit -m "建立TMDB刮削对标基线"
~~~

### Task 2: 扩展 TMDB 候选、别名和逐集数据模型

**Files:**
- Create: lib/services/tmdb/tmdb_client_capabilities.dart
- Modify: lib/modules/local/tmdb_metadata.dart
- Modify: lib/modules/cloud/cloud_resource_tmdb_record.dart
- Modify: lib/services/tmdb/tmdb_client.dart
- Modify: test/tmdb_client_test.dart
- Modify: test/cloud_resource_tmdb_record_test.dart
- Create: test/tmdb_metadata_serialization_test.dart

- [x] **Step 1: 写失败测试**

覆盖 searchPage 第 2 页、alternativeTitles、seasonDetails 和旧 JSON 兼容：

~~~dart
final page = await client.searchPage(
  'Avatar',
  TmdbMediaType.movie,
  page: 2,
);
expect(page.page, 2);
expect(page.totalPages, 3);
expect(page.results.single.popularity, 12.5);

final aliases = await client.alternativeTitles(42, TmdbMediaType.tv);
expect(aliases, contains('The Three-Body Problem'));

final season = await client.seasonDetails(42, 1, language: 'zh-CN');
expect(season.episodes.single.name, '第一个故事');
expect(season.episodes.single.episodeNumber, 1);
~~~

TmdbMetadata.fromJson 读取旧 JSON 时新增列表必须为空，toJson 再读回保持相等。

- [x] **Step 2: 运行测试确认新接口不存在**

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/tmdb_client_test.dart test/tmdb_metadata_serialization_test.dart
~~~

- [x] **Step 3: 增加可选能力接口，避免破坏现有 fake**

tmdb_client_capabilities.dart 定义：

~~~dart
abstract interface class ITmdbClientCapabilities {
  Future<TmdbSearchPage> searchPage(
    String query,
    TmdbMediaType mediaType, {
    required String language,
    required int page,
  });

  Future<List<String>> alternativeTitles(
    int id,
    TmdbMediaType mediaType, {
    required String language,
  });

  Future<TmdbSeasonMetadata> seasonDetails(
    int id,
    int seasonNumber, {
    required String language,
  });
}

class TmdbSearchPage {
  const TmdbSearchPage({
    required this.page,
    required this.totalPages,
    required this.results,
  });

  final int page;
  final int totalPages;
  final List<TmdbMetadata> results;
}
~~~

TmdbClient 同时实现 ITmdbClient 和 ITmdbClientCapabilities；旧 ITmdbClient.search 保持原签名并只读取第一页。能力不存在时引擎回退到旧搜索，现有测试 fake 不需要新增成员。

- [x] **Step 4: 扩展元数据并解析官方响应**

TmdbSeasonMetadata 增加 episodes；TmdbMetadata 增加 aliases、popularity、voteCount。新增字段完整实现 fromJson、toJson、copyWith、==、hashCode。TmdbClient 解析 search 的 popularity/vote_count、alternative_titles 的 titles[].title、season endpoint 的 episodes；中文详情缺字段时沿用英文补充逻辑，别名与逐集名称按非空值合并。CloudResourceTmdbRecord 的 matched 工厂、fromJson、toJson、相等比较和复制方法同步保存 aliases、popularity、voteCount，否则资源重启后会丢失别名评分证据。

~~~dart
class TmdbEpisodeMetadata {
  const TmdbEpisodeMetadata({
    required this.id,
    required this.episodeNumber,
    required this.name,
    this.overview,
    this.airDate,
    this.stillUrl,
    this.rating,
  });

  final int id;
  final int episodeNumber;
  final String name;
  final String? overview;
  final String? airDate;
  final String? stillUrl;
  final double? rating;
}
~~~

- [x] **Step 5: 运行回归并提交**

~~~powershell
D:/flutter/bin/dart.bat format --output=none --set-exit-if-changed lib/modules/local/tmdb_metadata.dart lib/services/tmdb/tmdb_client.dart lib/services/tmdb/tmdb_client_capabilities.dart test/tmdb_client_test.dart test/tmdb_metadata_serialization_test.dart
D:/flutter/bin/flutter.bat test --no-pub test/tmdb_client_test.dart test/tmdb_metadata_serialization_test.dart
git add lib/modules/local/tmdb_metadata.dart lib/services/tmdb/tmdb_client.dart lib/services/tmdb/tmdb_client_capabilities.dart test/tmdb_client_test.dart test/tmdb_metadata_serialization_test.dart
git commit -m "扩展TMDB别名分页与逐集资料"
~~~

预期：全部 PASS，旧 JSON、端点回退、Bearer/API Key 行为不变。

### Task 3: 重做候选召回、评分和自动确认边界

**Files:**
- Modify: lib/services/tmdb/tmdb_scrape_options.dart
- Modify: lib/services/tmdb/tmdb_scrape_policy.dart
- Modify: lib/services/tmdb/tmdb_scrape_engine.dart
- Modify: lib/services/tmdb/tmdb_matcher.dart
- Modify: lib/services/tmdb/tmdb_scrape_subject.dart
- Modify: lib/pages/tmdb_match_dialog.dart
- Modify: test/tmdb_matcher_test.dart
- Modify: test/tmdb_scrape_policy_test.dart
- Modify: test/tmdb_scrape_engine_test.dart
- Modify: test/tmdb_match_dialog_test.dart
- Modify: test/tmdb_scrape_benchmark_test.dart

- [ ] **Step 1: 写失败测试锁定别名优先和保守确认**

覆盖“别名命中优先于同名但年份错误”“同名同年电影/电视剧无类型证据时不自动确认”“第 2 页候选去重”。构造的 TmdbRankedCandidate 断言 aliasMatched、titleSimilarity 和 shouldAutoMatch；网络异常继续抛出，不伪装成空候选。

~~~dart
final aliasCandidate = TmdbMetadata(
  id: 1,
  mediaType: TmdbMediaType.tv,
  title: '三体',
  aliases: const <String>['The Three-Body Problem'],
  releaseDate: '2023-01-01',
  language: 'zh-CN',
  matchedAt: DateTime(2026),
  matchConfidence: 0,
);
final ranked = const TmdbMatcher().rank(
  queryTitle: 'The Three Body Problem',
  queryYear: 2023,
  expectedTypes: <TmdbMediaType>{TmdbMediaType.tv},
  candidates: <TmdbMetadata>[aliasCandidate],
);
expect(ranked.best?.metadata.id, 1);
expect(ranked.best?.aliasMatched, isTrue);
expect(ranked.best?.titleSimilarity, greaterThanOrEqualTo(0.78));
expect(ranked.shouldAutoMatch, isTrue);
~~~

- [ ] **Step 2: 运行评分、策略和引擎测试**

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/tmdb_matcher_test.dart test/tmdb_scrape_policy_test.dart test/tmdb_scrape_engine_test.dart
~~~

预期：新增信号测试先失败，旧同名、年份和类型测试仍可编译并给出明确失败。

- [ ] **Step 3: 扩展搜索计划和分页召回**

TmdbScrapeOptions 增加并持久化 maximumSearchPages（默认 3）和 maximumAliasCandidates（默认 20），fromMap/toMap/copyWith 全部覆盖。TmdbScrapePolicy 按“手动搜索词、清洗主标题、其他标题候选”输出去重查询。TmdbScrapeEngine 对每个媒体类型读取第 1 页到 min(totalPages, maximumSearchPages) 页，按 mediaType.name:id 去重；能力不存在时调用旧 search 一次。初始候选只为前 20 个补充 alternativeTitles，别名失败不丢主结果，最多 4 个并发。

- [ ] **Step 4: 实现可解释且保守的评分器**

TmdbRankedCandidate 增加 aliasMatched、titleSimilarity、seasonEvidenceMatched、matchReason。评分固定为：主/原始标题完全相等 0.62，别名完全相等 0.58；token Jaccard、包含关系和 CJK 连续片段最多 0.28；年份相同 +0.16、相差一年 +0.08、相差两年以上 -0.12；类型匹配 +0.14、冲突 -0.50；季集证据与电视剧候选 +0.08；popularity 只在同分时最多微调 0.02。结果限制在 0..1。

自动确认必须满足类型匹配、标题/别名完全匹配或相似度至少 0.78、总分阈值和领先 margin；auto 模式同时有电影/电视剧且没有季集证据时不得凭同名同年自动确认。matchReason 用固定中文片段拼接，供对话框和 benchmark 使用。

- [ ] **Step 5: 更新候选对话框**

候选卡保留现有标题/年份/类型信号，增加别名匹配、季集证据和 matchReason；不改搜索、单选、手动应用、取消行为。补充 tmdb_match_dialog_test.dart 的理由可见和空理由不渲染测试。

- [ ] **Step 6: 运行 benchmark 和回归并提交**

~~~powershell
D:/flutter/bin/dart.bat format --output=none --set-exit-if-changed lib/services/tmdb/tmdb_scrape_options.dart lib/services/tmdb/tmdb_scrape_policy.dart lib/services/tmdb/tmdb_scrape_engine.dart lib/services/tmdb/tmdb_matcher.dart lib/services/tmdb/tmdb_scrape_subject.dart lib/pages/tmdb_match_dialog.dart test/tmdb_matcher_test.dart test/tmdb_scrape_policy_test.dart test/tmdb_scrape_engine_test.dart test/tmdb_match_dialog_test.dart
D:/flutter/bin/flutter.bat test --no-pub test/tmdb_matcher_test.dart test/tmdb_scrape_policy_test.dart test/tmdb_scrape_engine_test.dart test/tmdb_match_dialog_test.dart test/tmdb_scrape_benchmark_test.dart
git add lib/services/tmdb/tmdb_scrape_options.dart lib/services/tmdb/tmdb_scrape_policy.dart lib/services/tmdb/tmdb_scrape_engine.dart lib/services/tmdb/tmdb_matcher.dart lib/services/tmdb/tmdb_scrape_subject.dart lib/pages/tmdb_match_dialog.dart test/tmdb_matcher_test.dart test/tmdb_scrape_policy_test.dart test/tmdb_scrape_engine_test.dart test/tmdb_match_dialog_test.dart test/tmdb_scrape_benchmark_test.dart
git commit -m "优化TMDB候选召回与保守匹配"
~~~

预期：测试全部 PASS，benchmark 达到开头的精确率、召回率和请求数量目标。

### Task 4: 补齐季度和逐集元数据并映射可播放集

**Files:**
- Create: lib/services/tmdb/tmdb_episode_title_resolver.dart
- Modify: lib/services/tmdb/tmdb_scrape_engine.dart
- Modify: lib/services/tmdb/tmdb_metadata_merge_policy.dart
- Modify: lib/modules/local/tmdb_metadata.dart
- Modify: lib/services/cloud/cloud_media_library.dart
- Modify: lib/pages/cloud/resources/cloud_resource_collection.dart
- Modify: lib/services/cloud/cloud_work_tmdb_service.dart
- Modify: lib/services/cloud/cloud_resource_tmdb_service.dart
- Modify: test/tmdb_metadata_policy_test.dart
- Modify: test/cloud_library_integration_test.dart
- Modify: test/cloud_work_tmdb_service_test.dart
- Modify: test/cloud_resource_tmdb_service_test.dart

- [ ] **Step 1: 写逐集合并和回退测试**

有 TMDB 集名时，固定断言：

~~~dart
expect(
  const TmdbEpisodeTitleResolver().resolve(
    seriesTitle: '三体',
    seasonNumber: 1,
    episodeNumber: 1,
    episodeName: '第一集',
    originalFileName: '01.mkv',
  ),
  '三体 S01E01 第一集',
);
~~~

无集名回退为三体 S01E01；无季号为作品名 Exx；全缺失为原始文件名。多个版本只替换展示标题，版本标签、原始文件名、字幕关联和远程播放引用不变。合并按 seasonNumber/episodeNumber 去重并保留已缓存图片。

- [ ] **Step 2: 运行失败测试确认逐集字段不存在**

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/tmdb_metadata_policy_test.dart test/cloud_library_integration_test.dart test/cloud_work_tmdb_service_test.dart test/cloud_resource_tmdb_service_test.dart
~~~

- [ ] **Step 3: 只抓取实际存在季度详情并合并**

在 TmdbScrapeEngine 或独立 TmdbDetailsHydrator 增加 hydrateSeasons：只对主题实际存在且大于 0 的季度调用 ITmdbClientCapabilities.seasonDetails，最多 4 个并发；失败季度保留摘要。电影不发季度请求，电视剧无实际季度证据时不发逐集请求。语言回退沿用 zh-CN 到 en-US 策略，逐集字段按非空值合并。TmdbMetadataMergePolicy 在覆盖开关、锁定字段、季度海报和旧 JSON 下保持原行为，episodes 只能补全，不能清空手动资料。

- [ ] **Step 4: 映射展示而不改播放身份**

TmdbEpisodeTitleResolver.resolve 的固定规则为：有 TMDB 集名返回 作品名 SxxExx 集名，没有返回作品名 SxxExx，没有季号返回作品名 Exx，全部缺失返回原始文件名。修改 CloudMediaLibraryAggregator 和 CloudResourceCollection 只在构造展示模型时调用解析器；LocalMediaIndexItem.path、CloudFileEntry.remotePath、remoteId、字幕路径和播放请求对象不变。

- [ ] **Step 5: 运行逐集、聚合和播放回归并提交**

~~~powershell
D:/flutter/bin/dart.bat format --output=none --set-exit-if-changed lib/modules/local/tmdb_metadata.dart lib/services/tmdb/tmdb_episode_title_resolver.dart lib/services/tmdb/tmdb_metadata_merge_policy.dart lib/services/tmdb/tmdb_scrape_engine.dart lib/services/cloud/cloud_media_library.dart lib/pages/cloud/resources/cloud_resource_collection.dart
D:/flutter/bin/flutter.bat test --no-pub test/tmdb_metadata_policy_test.dart test/cloud_library_integration_test.dart test/cloud_work_tmdb_service_test.dart test/cloud_resource_tmdb_service_test.dart test/cloud_playback_resolver_test.dart test/local_playback_request_builder_test.dart
git add lib/modules/local/tmdb_metadata.dart lib/services/tmdb/tmdb_episode_title_resolver.dart lib/services/tmdb/tmdb_metadata_merge_policy.dart lib/services/tmdb/tmdb_scrape_engine.dart lib/services/cloud/cloud_media_library.dart lib/pages/cloud/resources/cloud_resource_collection.dart lib/services/cloud/cloud_work_tmdb_service.dart lib/services/cloud/cloud_resource_tmdb_service.dart test/tmdb_metadata_policy_test.dart test/cloud_library_integration_test.dart test/cloud_work_tmdb_service_test.dart test/cloud_resource_tmdb_service_test.dart
git commit -m "补齐TMDB逐集资料与展示映射"
~~~

预期：所有测试 PASS；真实播放请求仍使用原路径/ID，UI 仅多出 TMDB 集名。

### Task 5: 统一三条业务路径并收敛旧入口

**Files:**
- Modify: lib/services/tmdb/local_tmdb_scrape_service.dart
- Modify: lib/services/cloud/cloud_work_tmdb_service.dart
- Modify: lib/services/cloud/cloud_resource_tmdb_service.dart
- Modify: lib/services/cloud/cloud_tmdb_metadata_service.dart
- Modify: lib/pages/local/local_controller.dart
- Modify: lib/app/bindings/cloud_bindings.dart
- Create: test/tmdb_local_cloud_contract_test.dart
- Modify: test/local_tmdb_integration_test.dart
- Modify: test/cloud_work_tmdb_service_test.dart
- Modify: test/cloud_resource_tmdb_service_test.dart
- Modify: test/cloud_library_integration_test.dart

- [ ] **Step 1: 写本地、网盘作品、网盘资源同输入契约测试**

同一组 titleCandidates/year/seasonNumbers/episodeNumbers 分别通过 LocalTmdbSubjectBuilder、CloudTmdbSubjectBuilder.forWork 和 forResource 构造主题，断言 TmdbSearchPlan.queries、year、mediaTypes、候选去重、自动结论和 matchReason 相同。额外断言自定义标题优先、手动记录不被自动覆盖、不同 TMDB ID 进入 pending/conflict 并保留旧资料。

~~~dart
final plans = <TmdbSearchPlan>[
  const LocalTmdbSubjectBuilder().build(
    seriesName: '三体 S01E01 2160p',
    items: localItems,
  ),
  const CloudTmdbSubjectBuilder().forWork(work, record: workRecord),
  const CloudTmdbSubjectBuilder().forResource(target, record: resourceRecord),
].map((subject) {
  return const TmdbScrapePolicy().build(
    subject,
    const TmdbScrapeOptions.defaults(),
  );
}).toList(growable: false);
for (final plan in plans.skip(1)) {
  expect(plan.queries, plans.first.queries);
  expect(plan.year, plans.first.year);
  expect(plan.mediaTypes, plans.first.mediaTypes);
}
~~~

- [ ] **Step 2: 运行契约测试确认旧入口差异**

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/tmdb_local_cloud_contract_test.dart test/local_tmdb_integration_test.dart test/cloud_work_tmdb_service_test.dart test/cloud_resource_tmdb_service_test.dart test/cloud_library_integration_test.dart
~~~

预期：CloudTmdbMetadataService 的直接 search -> choose 路径在新别名/分页案例上与共享引擎不同，契约测试先失败。

- [ ] **Step 3: 让旧服务成为共享引擎兼容门面**

删除 CloudTmdbMetadataService.match/searchCandidates 内部直接调用 ITmdbClient.search 与 TmdbMatcher.choose 的逻辑，改为用 sourceId、seriesName 和当前索引的季集证据构造 TmdbScrapeSubject，再调用同一个 TmdbScrapeEngine；保留 CloudTmdbMatchOutcome、select 签名和仓库更新行为。LocalTmdbScrapeService、CloudWorkTmdbService、CloudResourceTmdbService 都通过注入的共享引擎/能力接口执行搜索，不重新实现候选排序。

LocalController._cloudTmdbService 和 cloud_bindings.dart 使用同一 TmdbClientFactory 与 TmdbScrapeCache；同一 API Key 下本地和网盘请求共享缓存实例，不在日志中输出 Key。currentTmdbRuleVersion 从 3 改为 4，协调器只迁移版本低于 4 且来源为 automatic/legacyUnknown 的记录；manual、自定义标题、字段锁定和 conflict 保持原样。自动迁移只有在新旧 mediaType:id 相同才写回，否则标记待确认并保留旧元数据。

- [ ] **Step 4: 更新兼容测试并提交**

~~~powershell
D:/flutter/bin/dart.bat format --output=none --set-exit-if-changed lib/services/tmdb/local_tmdb_scrape_service.dart lib/services/tmdb/tmdb_scrape_engine.dart lib/services/tmdb/tmdb_scrape_policy.dart lib/services/tmdb/tmdb_scrape_subject.dart lib/services/cloud/cloud_work_tmdb_service.dart lib/services/cloud/cloud_resource_tmdb_service.dart lib/services/cloud/cloud_tmdb_metadata_service.dart lib/pages/local/local_controller.dart lib/app/bindings/cloud_bindings.dart test/tmdb_local_cloud_contract_test.dart
D:/flutter/bin/flutter.bat test --no-pub test/tmdb_local_cloud_contract_test.dart test/local_tmdb_integration_test.dart test/cloud_work_tmdb_service_test.dart test/cloud_resource_tmdb_service_test.dart test/cloud_library_integration_test.dart test/cloud_resource_tmdb_coordinator_test.dart test/cloud_work_tmdb_coordinator_test.dart
git add lib/services/tmdb/local_tmdb_scrape_service.dart lib/services/tmdb/tmdb_scrape_engine.dart lib/services/tmdb/tmdb_scrape_policy.dart lib/services/tmdb/tmdb_scrape_subject.dart lib/services/cloud/cloud_work_tmdb_service.dart lib/services/cloud/cloud_resource_tmdb_service.dart lib/services/cloud/cloud_tmdb_metadata_service.dart lib/pages/local/local_controller.dart lib/app/bindings/cloud_bindings.dart test/tmdb_local_cloud_contract_test.dart test/local_tmdb_integration_test.dart test/cloud_work_tmdb_service_test.dart test/cloud_resource_tmdb_service_test.dart test/cloud_library_integration_test.dart test/cloud_resource_tmdb_coordinator_test.dart test/cloud_work_tmdb_coordinator_test.dart
git commit -m "统一本地与网盘TMDB刮削入口"
~~~

预期：三条路径对同一输入返回相同排序；本地、网盘作品和资源的手动选择、冲突保护、季度海报和索引同步全部 PASS。

### Task 6: 建立共享请求缓存与并发控制

**Files:**
- Create: lib/services/tmdb/tmdb_scrape_cache.dart
- Modify: lib/services/tmdb/tmdb_scrape_engine.dart
- Modify: lib/services/tmdb/tmdb_client.dart
- Modify: lib/services/cloud/cloud_resource_tmdb_service.dart
- Modify: lib/app/bindings/cloud_bindings.dart
- Modify: lib/pages/local/local_controller.dart
- Create: test/tmdb_scrape_cache_test.dart
- Modify: test/cloud_resource_tmdb_service_test.dart
- Modify: test/cloud_work_tmdb_service_test.dart

- [ ] **Step 1: 写缓存命中、过期、并发合并和错误隔离测试**

~~~dart
final cache = TmdbScrapeCache(
  now: () => clock,
  searchTtl: const Duration(minutes: 10),
  detailsTtl: const Duration(hours: 24),
  maximumEntries: 100,
);
final first = cache.getOrLoad<List<TmdbMetadata>>(
  'search|tv|zh-CN|三体',
  loader,
);
final second = cache.getOrLoad<List<TmdbMetadata>>(
  'search|tv|zh-CN|三体',
  loader,
);
expect(
  await Future.wait(<Future<List<TmdbMetadata>>>[first, second]),
  hasLength(2),
);
expect(loadCount, 1);
~~~

同一键失败后允许下一次重试；不同语言、媒体类型、页码、API Key 客户端不得共享错误结果。缓存值只存 TMDB 响应对象，不存 API Key、Bearer Token、Cookie、远程路径或原始视频内容。

- [ ] **Step 2: 运行缓存测试确认共享缓存不存在**

~~~powershell
D:/flutter/bin/flutter.bat test --no-pub test/tmdb_scrape_cache_test.dart
~~~

- [ ] **Step 3: 实现 TTL、LRU 和 in-flight 去重**

TmdbScrapeCache 提供：

~~~dart
class TmdbScrapeCache {
  TmdbScrapeCache({
    this.searchTtl = const Duration(minutes: 10),
    this.detailsTtl = const Duration(hours: 24),
    this.aliasTtl = const Duration(days: 30),
    this.maximumEntries = 100,
    DateTime Function()? now,
  });

  Future<T> getOrLoad<T>(String key, Future<T> Function() loader);
  void clear();
}
~~~

使用 LinkedHashMap 实现 LRU，使用 Map<String, Future<Object?>> 保存进行中的请求；只缓存成功值，超过 maximumEntries 从最旧项淘汰。TmdbScrapeEngine、详情补充和季集详情均通过该缓存；删除 CloudResourceTmdbService 的私有 _searchCache。

- [ ] **Step 4: 接入组合根并控制并发**

在 cloud_bindings.dart 和 local_controller.dart 创建按 API Key 客户端实例绑定的共享缓存；Future.wait 通过固定 poolSize = 4 的并发闸门限制别名和季度请求。网络异常沿用 TmdbEndpointPolicy 的官方端点回退；401/403/429 不重复重试，缓存命中旧的已保存元数据不受影响。

- [ ] **Step 5: 运行性能回归并提交**

~~~powershell
D:/flutter/bin/dart.bat format --output=none --set-exit-if-changed lib/services/tmdb/tmdb_scrape_cache.dart lib/services/tmdb/tmdb_scrape_engine.dart lib/services/tmdb/tmdb_client.dart lib/services/cloud/cloud_resource_tmdb_service.dart lib/app/bindings/cloud_bindings.dart lib/pages/local/local_controller.dart test/tmdb_scrape_cache_test.dart
D:/flutter/bin/flutter.bat test --no-pub test/tmdb_scrape_cache_test.dart test/cloud_resource_tmdb_service_test.dart test/cloud_work_tmdb_service_test.dart test/local_tmdb_integration_test.dart
git add lib/services/tmdb/tmdb_scrape_cache.dart lib/services/tmdb/tmdb_scrape_engine.dart lib/services/tmdb/tmdb_client.dart lib/services/cloud/cloud_resource_tmdb_service.dart lib/app/bindings/cloud_bindings.dart lib/pages/local/local_controller.dart test/tmdb_scrape_cache_test.dart test/cloud_resource_tmdb_service_test.dart test/cloud_work_tmdb_service_test.dart
git commit -m "合并TMDB请求缓存与并发控制"
~~~

预期：同一查询并发只产生一次 fake client 调用，资源服务原有过期重搜测试改为验证共享缓存，全部 PASS。

### Task 7: 明确零配置方案边界并完善用户可见说明

**Files:**
- Create: docs/tmdb-zero-config-options.md
- Modify: lib/pages/settings/tmdb_settings.dart
- Modify: README.md
- Modify: test/tmdb_settings_language_test.dart
- Create: test/tmdb_zero_config_copy_test.dart

- [ ] **Step 1: 固定本期默认方案**

本期继续使用用户自己的 TMDB API Key，不在公共安装包内置 Key，不抓取或复用爆米花本地 HTTP/AES 协议。设置页显示 Key 只保存在看影音专属安全存储；无 Key 时可扫描、浏览和播放，只有发起 TMDB 请求时提示配置。docs/tmdb-zero-config-options.md 记录两条后续路线：

1. 官方/自建 TMDB 代理：客户端调用看影音定义的 HTTPS API，服务端负责 Key、限流和缓存；需要独立部署、隐私政策和运维成本。
2. 继续用户自带 Key：无服务端成本、隐私边界清晰，但首次配置多一步。

默认选择路线 2；只有另立服务端项目并完成安全评审后才切换路线 1。文档不出现爆米花的本地端口、AES 密钥或逆向协议细节。

- [ ] **Step 2: 写文案回归测试**

tmdb_zero_config_copy_test.dart 断言设置页和 README 同时包含“公共安装包不内置 TMDB Key”“没有 Key 或断网时本地扫描和播放仍可用”“不会修改原始视频/字幕”三条说明。

~~~dart
final readme = File('README.md').readAsStringSync(encoding: utf8);
expect(readme, contains('公共安装包不内置 TMDB Key'));
expect(readme, contains('没有 Key 或断网时，本地扫描和播放仍可用'));
expect(readme, contains('不会修改或删除原始视频、字幕'));
~~~

- [ ] **Step 3: 更新设置页并运行 UI 测试**

保留现有 Key 校验、语言、地区和阈值控件；只增加零配置说明和失败状态文案，不改变保存、测试连接和代理恢复行为。

~~~powershell
D:/flutter/bin/dart.bat format --output=none --set-exit-if-changed lib/pages/settings/tmdb_settings.dart test/tmdb_settings_language_test.dart test/tmdb_zero_config_copy_test.dart
D:/flutter/bin/flutter.bat test --no-pub test/tmdb_settings_language_test.dart test/tmdb_zero_config_copy_test.dart
~~~

预期：设置页现有语言和保存测试、零配置文案测试全部 PASS。

- [ ] **Step 4: 提交边界和文案**

~~~powershell
git add docs/tmdb-zero-config-options.md lib/pages/settings/tmdb_settings.dart README.md test/tmdb_settings_language_test.dart test/tmdb_zero_config_copy_test.dart
git commit -m "明确TMDB零配置边界与用户说明"
~~~

### Task 8: 全量质量门禁与交付前检查

**Files:**
- Modify: docs/tmdb-scrape-benchmark.md
- Modify: RELEASE_NOTES.md（仅在用户明确批准版本交付时）
- Modify: lib/utils/version_history.dart（仅在用户明确批准版本交付时）

- [ ] **Step 1: 运行格式、测试、分析和 Release 构建**

~~~powershell
D:/flutter/bin/dart.bat format --output=none --set-exit-if-changed .
D:/flutter/bin/flutter.bat test --no-pub
D:/flutter/bin/flutter.bat analyze --no-pub
D:/flutter/bin/flutter.bat build windows --release --no-pub
~~~

预期：四条命令 exit code 均为 0；测试数量、分析结果、构建目录和 benchmark 汇总写入 docs/tmdb-scrape-benchmark.md。

- [ ] **Step 2: 做离线与数据保护回归**

用无 API Key 的测试容器运行本地扫描和播放请求构建测试；用断网 fake client 运行已保存 TMDB 资料浏览测试。确认 diff 中没有视频、字幕、Cookie、Token、API Key、MSIX、ZIP、构建缓存或桌面交付物：

~~~powershell
git status --short
git diff --stat
git diff --check
rg -n -i "api[_ -]?key|bearer|cookie|token|password|msix|zip" lib test docs
~~~

rg 只允许命中测试样例、文档说明或现有安全代码；任何真实凭据命中都必须在提交前移除。

- [ ] **Step 3: 重新执行对标采样并验收阈值**

再次运行 test/tmdb_scrape_benchmark_test.dart，把新旧自动精确率、Top-3 召回率、P95 缓存命中耗时、平均冷查询请求数和逐集覆盖率追加到 benchmark 文档。只有达到本文目标才标记计划完成；未达到时保留为待确认候选，不通过降低阈值“修复”统计结果。

- [ ] **Step 4: 版本交付另行执行**

本计划默认不改变 pubspec.yaml、msix_config.msix_version、安装包和已安装版本。若用户批准交付版本，必须另按项目发布门禁执行：先运行 Get-AppxPackage -Name com.kanyingyin.player 记录已安装版本，再同步版本号、更新 RELEASE_NOTES.md 与 lib/utils/version_history.dart，生成并签名 MSIX、核对清单版本、复制 看影音-版本号.msix 到桌面，并在安装动作后再次查询已安装版本。

- [ ] **Step 5: 检查本轮 Git 状态并提交代码**

~~~powershell
git status --short
git diff --stat
git diff --check
git add docs/tmdb-scrape-benchmark.md
git commit -m "完成网易爆米花对标的TMDB刮削优化"
~~~

提交前必须保留用户已有的 test/library_genre_backfill_service_test.dart 改动，不得将无关工作区改动加入提交。
