# 网盘剧场版识别、海报缓存与播放防重 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将网盘正剧目录中的不同剧场版拆为独立电影作品、归并同一电影的发布版本、稳定复用海报缓存，并修复重复点击网盘影片导致播放页叠加和假死的问题，最终以 2.1.58 测试版交付。

**Architecture:** 继续使用 `CloudWorkIdentity` 作为 TMDB 与海报缓存的作品边界，但让媒体树为每个独立电影生成单独且稳定的电影 `workKey`，同片多版本共享该键，正剧季度继续使用原目录作品键。索引、作品级 TMDB 服务和海报缓存沿用现有链路；播放防重直接复用 `CloudPlaybackNavigationCoordinator`，放在夸克、百度和 OpenList 共用的 `CloudResourcesPage` 入口。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、MobX、media_kit、TMDB、flutter_test、PowerShell、Windows MSIX

---

## 文件职责

- `lib/modules/media/media_name_analysis.dart`：保存强类型电影内容提示。
- `lib/services/media_name_analyzer.dart`：识别剧场版、Movie、OVA、OAD、特别篇，并生成去除发布规格但保留作品名的候选。
- `lib/modules/cloud/cloud_media_tree.dart`：为电影作品携带稳定身份及每个真实文件的发布标签。
- `lib/services/cloud/cloud_media_tree_resolver.dart`：把正剧季度与独立电影拆成不同作品；同片版本归并，不同影片隔离。
- `lib/services/cloud/cloud_media_indexer.dart`：把电影作品键、显示标题、媒体类型和发布标签写入索引。
- `lib/pages/cloud/resources/cloud_resource_collection.dart`：一部电影生成一张卡，多版本生成可区分的版本名称。
- `lib/services/cloud/cloud_tmdb_subject_builder.dart`：多文件电影仍提供明确的电影 TMDB 证据。
- `lib/services/tmdb/tmdb_scrape_subject.dart`：提升规则版本，触发现有自动匹配重新计算。
- `lib/pages/cloud/resources/cloud_resources_page.dart`：统一控制播放解析和导航的单次进入。
- `test/media_name_analyzer_test.dart`、`test/cloud_media_tree_resolver_test.dart`、`test/cloud_media_indexer_test.dart`、`test/cloud_resource_collection_test.dart`、`test/cloud_work_tmdb_service_test.dart`、`test/cloud_resources_page_test.dart`：覆盖完整红绿回归链路。

### Task 1: 测试驱动电影内容提示和标题规范化

**Files:**
- Modify: `test/media_name_analyzer_test.dart`
- Modify: `lib/modules/media/media_name_analysis.dart`
- Modify: `lib/services/media_name_analyzer.dart`

- [ ] **Step 1: 写入失败测试**

在 `MediaNameAnalyzer` 测试中加入电影标记、发布规格清理和连续剧优先级：

```dart
test('剧场版和 OVA 提供电影内容提示并保留完整作品标题', () {
  final theatrical = analyzer.analyze(
    '中二病也要谈恋爱 剧场版 Take On Me 2160p BluRay H265.mkv',
    isDirectory: false,
  );
  final ova = analyzer.analyze('摇曳露营 OVA.mkv', isDirectory: false);

  expect(theatrical.contentHint, MediaContentHint.movie);
  expect(
    theatrical.titleCandidates,
    contains('中二病也要谈恋爱 剧场版 Take On Me'),
  );
  expect(theatrical.releaseTags.resolution, '2160p');
  expect(ova.contentHint, MediaContentHint.ova);
  expect(ova.titleCandidates, contains('摇曳露营 OVA'));
});

test('明确季集号优先于特别篇电影提示', () {
  final result = analyzer.analyze(
    '作品 S01E03 特别篇 1080p.mkv',
    isDirectory: false,
  );

  expect(result.role, MediaNodeRole.episode);
  expect(result.seasonNumber, 1);
  expect(result.episodeNumber, 3);
});

test('语言和字幕规格不改变电影标题身份', () {
  final mandarin = analyzer.analyze(
    '示例电影 2026 2160p 国语 内封简繁.mkv',
    isDirectory: false,
  );
  final japanese = analyzer.analyze(
    '示例电影 2026 1080p 日语 内嵌中字.mkv',
    isDirectory: false,
  );

  expect(mandarin.titleCandidates.first, '示例电影');
  expect(japanese.titleCandidates.first, '示例电影');
  expect(mandarin.releaseTags.audio, contains('国语'));
  expect(japanese.releaseTags.audio, contains('日语'));
});
```

- [ ] **Step 2: 运行测试确认红灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\media_name_analyzer_test.dart --reporter compact
```

Expected: FAIL，`MediaContentHint` 和 `contentHint` 尚不存在。

- [ ] **Step 3: 增加强类型提示并实现最小识别**

在 `media_name_analysis.dart` 增加：

```dart
enum MediaContentHint { movie, ova, oad, special, unknown }
```

为 `MediaNameAnalysis` 增加默认值：

```dart
this.contentHint = MediaContentHint.unknown,
```

在分析器中增加不包含具体作品名的通用标记：

```dart
static final RegExp _theatricalPattern = RegExp(
  r'剧场版|\bThe[\s._-]+Movie\b|\bMovie\b',
  caseSensitive: false,
  unicode: true,
);
static final RegExp _ovaPattern = RegExp(r'\bOVA\b', caseSensitive: false);
static final RegExp _oadPattern = RegExp(r'\bOAD\b', caseSensitive: false);
static final RegExp _specialPattern = RegExp(
  r'特别篇|特别版|Special',
  caseSensitive: false,
  unicode: true,
);
static final RegExp _languagePattern = RegExp(
  r'国语|国配|日语|粤语|英语|双语',
  caseSensitive: false,
  unicode: true,
);
```

`contentHint` 只提供内容证据，不覆盖已经识别出的季集号。把 `特别篇` 从 `_versionPattern` 中移出，电影标记保留在清理后的标题中；分辨率、片源、编码、年份、语言和字幕标签由通用规则移除。语言写入 `MediaReleaseTags.audio`，以便版本选择显示。

- [ ] **Step 4: 格式化并确认绿灯**

```powershell
D:\flutter\bin\dart.bat format lib\modules\media\media_name_analysis.dart lib\services\media_name_analyzer.dart test\media_name_analyzer_test.dart
D:\flutter\bin\flutter.bat test --no-pub test\media_name_analyzer_test.dart --reporter compact
```

Expected: PASS，既有数字标题、季集号和剪辑版测试继续通过。

- [ ] **Step 5: 提交识别器切片**

```powershell
git add lib/modules/media/media_name_analysis.dart lib/services/media_name_analyzer.dart test/media_name_analyzer_test.dart
git diff --cached --check
git commit -m "功能：识别网盘剧场版电影提示"
```

### Task 2: 测试驱动媒体树拆分电影作品并归并发布版本

**Files:**
- Modify: `test/cloud_media_tree_resolver_test.dart`
- Modify: `lib/modules/cloud/cloud_media_tree.dart`
- Modify: `lib/services/cloud/cloud_media_tree_resolver.dart`

- [ ] **Step 1: 写入真实目录结构失败测试**

使用一个正剧作品目录，同时放置季度、两个不同剧场版和同一剧场版的两个版本：

```dart
test('正剧目录中的不同剧场版拆分作品且同片版本归并', () {
  const root = '/动漫/示例作品';
  const season = '$root/第一季';
  const movies = '$root/剧场版';
  final tree = resolver.resolve(
    sourceId: 'quark-a',
    configuredRoots: const <String>[root],
    directoryEntries: <String, List<CloudFileEntry>>{
      root: <CloudFileEntry>[
        _dir('season', season, '第一季'),
        _dir('movies', movies, '剧场版'),
      ],
      season: <CloudFileEntry>[
        _video('e1', '$season/01.mkv', '01.mkv'),
        _video('e2', '$season/02.mkv', '02.mkv'),
      ],
      movies: <CloudFileEntry>[
        _video('a4k', '$movies/示例作品 剧场版 A 2160p.mkv',
            '示例作品 剧场版 A 2160p.mkv'),
        _video('a1080', '$movies/示例作品 剧场版 A 1080p.mkv',
            '示例作品 剧场版 A 1080p.mkv'),
        _video('b', '$movies/示例作品 剧场版 B.mkv',
            '示例作品 剧场版 B.mkv'),
      ],
    },
    minSizeBytes: 100,
  );

  expect(tree.works, hasLength(3));
  expect(tree.works.where((work) => work.seasons.isNotEmpty), hasLength(1));
  final moviesByTitle = <String, CloudWorkIdentity>{
    for (final work in tree.works.where((work) => work.seasons.isEmpty))
      work.displayTitle: work,
  };
  expect(moviesByTitle['示例作品 剧场版 A']!.standaloneVideos, hasLength(2));
  expect(moviesByTitle['示例作品 剧场版 B']!.standaloneVideos, hasLength(1));
  expect(moviesByTitle.values.map((work) => work.workKey).toSet(), hasLength(2));
});
```

另加矩阵断言：同名不同年份不合并；不同来源和不同根目录的键不同；纯数字连续集仍提升为第一季。

- [ ] **Step 2: 运行测试确认红灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_tree_resolver_test.dart --reporter compact
```

Expected: FAIL，现有实现把同一目录下全部独立视频放在一个 `standaloneVideos` 列表中。

- [ ] **Step 3: 给电影作品携带文件级发布标签**

为 `CloudWorkIdentity` 增加强类型只读映射：

```dart
this.standaloneReleaseTags = const <String, MediaReleaseTags>{},

final Map<String, MediaReleaseTags> standaloneReleaseTags;

MediaReleaseTags releaseTagsFor(CloudFileEntry entry) =>
    standaloneReleaseTags[entry.remotePath] ?? const MediaReleaseTags();
```

构造时使用 `Map.unmodifiable`，键统一为规范远程路径。

- [ ] **Step 4: 将独立视频按电影身份拆成作品**

在解析器中保留正剧 `workKeyFor(sourceId, root)`；将 `standaloneVideos` 交给新的私有分组函数。分组键只由同一根目录内的规范标题和年份组成：

```dart
String _movieIdentityKey(MediaNameAnalysis analysis, CloudFileEntry entry) {
  final title = (analysis.titleCandidates.isEmpty
          ? p.basenameWithoutExtension(entry.name)
          : analysis.titleCandidates.first)
      .trim()
      .toLowerCase();
  return '$title|${analysis.year ?? 0}';
}

String movieWorkKeyFor(
  String sourceId,
  CloudFileEntry root,
  String identityKey,
) {
  final boundary = root.id.trim().isEmpty
      ? CloudSeriesIdentityResolver.normalizeRemotePath(root.remotePath)
      : root.id.trim();
  final digest = sha256.convert(utf8.encode(identityKey)).toString();
  return '$sourceId|movie|$boundary|$digest';
}
```

先输出含季度的正剧作品，再为每个电影分组输出一个无季度 `CloudWorkIdentity`。同一分组内保留全部真实文件及发布标签；不同标题、不同年份、不同根或不同来源不共享键。无法提取标题时使用文件的稳定远程身份单独成组，不与其他未知文件合并。

- [ ] **Step 5: 确认绿灯并提交**

```powershell
D:\flutter\bin\dart.bat format lib\modules\cloud\cloud_media_tree.dart lib\services\cloud\cloud_media_tree_resolver.dart test\cloud_media_tree_resolver_test.dart
D:\flutter\bin\flutter.bat test --no-pub test\media_name_analyzer_test.dart test\cloud_media_tree_resolver_test.dart --reporter compact
git add lib/modules/cloud/cloud_media_tree.dart lib/services/cloud/cloud_media_tree_resolver.dart test/cloud_media_tree_resolver_test.dart
git diff --cached --check
git commit -m "功能：分离网盘正剧与剧场版作品"
```

### Task 3: 测试驱动电影索引和海报墙多版本展示

**Files:**
- Modify: `test/cloud_media_indexer_test.dart`
- Modify: `test/cloud_resource_collection_test.dart`
- Modify: `lib/modules/cloud/cloud_media_index_item.dart`
- Modify: `lib/services/cloud/cloud_media_indexer.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_collection.dart`

- [ ] **Step 1: 写入索引失败测试**

扫描 Task 2 的目录夹具并断言：

```dart
final movieA = snapshot.items
    .where((item) => item.seriesName == '示例作品 剧场版 A')
    .toList();
final movieB = snapshot.items
    .where((item) => item.seriesName == '示例作品 剧场版 B')
    .toList();

expect(movieA, hasLength(2));
expect(movieA.map((item) => item.workKey).toSet(), hasLength(1));
expect(movieA.every((item) => item.mediaType == CloudMediaType.movie), isTrue);
expect(movieA.map((item) => item.releaseTags.resolution).toSet(),
    <String?>{'2160p', '1080p'});
expect(movieB, hasLength(1));
expect(movieB.single.workKey, isNot(movieA.first.workKey));
```

将现有“OVA 和 Special 归入主系列特殊篇”测试收紧为：只有带明确季集号或季度目录证据的 OVA 保持剧集特别篇；没有季集证据的 OVA 作为独立电影作品。

- [ ] **Step 2: 写入集合分组失败测试**

```dart
final collection = CloudResourceCollectionGrouper().group(
  items: snapshot.items,
  works: tree.works,
  query: '',
);

final movieAGroup = collection.groups.singleWhere(
  (group) => group.displayName == '示例作品 剧场版 A',
);
expect(movieAGroup.isSeries, isFalse);
expect(movieAGroup.videos, hasLength(2));
expect(movieAGroup.videos.map((video) => video.variantLabel),
    containsAll(<String>['2160p', '1080p']));
expect(
  collection.groups.where((group) => !group.isSeries),
  hasLength(2),
);
```

- [ ] **Step 3: 运行目标测试确认红灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_indexer_test.dart test\cloud_resource_collection_test.dart --reporter compact
```

Expected: FAIL，电影发布标签未写入索引，且无集号的多文件不会生成版本标签。

- [ ] **Step 4: 写入电影身份和发布标签**

将识别版本从 5 提升为 6：

```dart
static const int currentRecognitionVersion = 6;
```

索引器对独立电影使用所属电影 `CloudWorkIdentity`：

```dart
final standaloneWork = standaloneWorksByPath[normalizedPath];
final standaloneTags = standaloneWork?.releaseTagsFor(entry) ??
    const MediaReleaseTags();
```

电影条目写入电影 `workKey`、电影 `displayTitle`、`CloudMediaType.movie` 和 `standaloneTags`。只有明确季集证据的条目写入 `episode` 或 `special`。

- [ ] **Step 5: 为电影多版本生成可区分名称**

扩展 `_virtualEntries`，当作品无季度且视频多于一个时也生成版本标签：

```dart
final needsMovieVariant = labelMovieVariants && sorted.length > 1;
if (episode == null && needsMovieVariant) {
  final index = movieVariantIndex++;
  final summary = _releaseSummary(item);
  variantLabel = summary.isEmpty ? '版本 $index' : summary;
  displayName = '$base [$variantLabel]$extension';
}
```

单文件电影维持直接播放；多版本电影由现有 `group.videos.length > 1` 行为打开选择弹层，不新增播放器协议。

- [ ] **Step 6: 确认绿灯并提交**

```powershell
D:\flutter\bin\dart.bat format lib\modules\cloud\cloud_media_index_item.dart lib\services\cloud\cloud_media_indexer.dart lib\pages\cloud\resources\cloud_resource_collection.dart test\cloud_media_indexer_test.dart test\cloud_resource_collection_test.dart
D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_indexer_test.dart test\cloud_resource_collection_test.dart test\cloud_resources_controller_test.dart --reporter compact
git add lib/modules/cloud/cloud_media_index_item.dart lib/services/cloud/cloud_media_indexer.dart lib/pages/cloud/resources/cloud_resource_collection.dart test/cloud_media_indexer_test.dart test/cloud_resource_collection_test.dart
git diff --cached --check
git commit -m "功能：归并剧场版多版本展示"
```

### Task 4: 测试驱动电影 TMDB 类型与稳定海报缓存

**Files:**
- Modify: `test/cloud_work_tmdb_service_test.dart`
- Modify: `test/cloud_work_tmdb_coordinator_test.dart`
- Modify: `test/cloud_library_integration_test.dart`
- Modify: `lib/services/cloud/cloud_tmdb_subject_builder.dart`
- Modify: `lib/services/tmdb/tmdb_scrape_subject.dart`

- [ ] **Step 1: 写入多版本电影 TMDB 失败测试**

构造一个包含两个 `standaloneVideos`、没有季度的电影作品：

```dart
final subject = const CloudTmdbSubjectBuilder().forWork(movieWork);
expect(subject.mediaEvidence, TmdbMediaEvidence.movie);
expect(subject.titleCandidates.first, '示例作品 剧场版 A');
```

服务测试使用同一 `workKey` 应用一次电影候选，断言两个索引条目都得到相同 TMDB ID，海报下载器只调用一次，`posterCachePath` 指向同一个存在的文件。

- [ ] **Step 2: 写入缓存稳定性回归测试**

```dart
final first = await service.select(
  movieWork,
  candidate,
  existingSeasons: const <int>{},
  options: options,
);
final rescanned = movieWorkWithSameIdentityButReorderedFiles;
final second = await service.select(
  rescanned,
  candidate,
  existingSeasons: const <int>{},
  options: options,
);

expect(second.record.workKey, first.record.workKey);
expect(second.record.posterCachePath, first.record.posterCachePath);
expect(downloadCalls, 1);
```

该测试验证稳定电影键与现有 `CloudPosterCache` 的 URL sidecar 协作，不修改缓存原子替换实现。

- [ ] **Step 3: 运行测试确认红灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\cloud_work_tmdb_service_test.dart test\cloud_work_tmdb_coordinator_test.dart test\cloud_library_integration_test.dart --reporter compact
```

Expected: FAIL，多文件无季度作品当前返回 `TmdbMediaEvidence.unknown`。

- [ ] **Step 4: 明确电影证据并提升 TMDB 规则版本**

将作品证据修改为：

```dart
mediaEvidence: seasons.isNotEmpty || episodes.isNotEmpty
    ? TmdbMediaEvidence.tv
    : work.standaloneVideos.isNotEmpty
        ? TmdbMediaEvidence.movie
        : TmdbMediaEvidence.unknown,
```

将规则版本从 1 提升为 2：

```dart
const int currentTmdbRuleVersion = 2;
```

已手动匹配和有自定义名称的记录继续受现有保护；未保护记录按新电影身份重新计算。海报仍使用 `work.workKey` 作为 `stableId`，相同 URL 命中已有缓存，URL 更新失败时沿用旧文件。

- [ ] **Step 5: 确认绿灯并提交**

```powershell
D:\flutter\bin\dart.bat format lib\services\cloud\cloud_tmdb_subject_builder.dart lib\services\tmdb\tmdb_scrape_subject.dart test\cloud_work_tmdb_service_test.dart test\cloud_work_tmdb_coordinator_test.dart test\cloud_library_integration_test.dart
D:\flutter\bin\flutter.bat test --no-pub test\cloud_work_tmdb_service_test.dart test\cloud_work_tmdb_coordinator_test.dart test\cloud_library_integration_test.dart test\tmdb_local_cloud_contract_test.dart --reporter compact
git add lib/services/cloud/cloud_tmdb_subject_builder.dart lib/services/tmdb/tmdb_scrape_subject.dart test/cloud_work_tmdb_service_test.dart test/cloud_work_tmdb_coordinator_test.dart test/cloud_library_integration_test.dart
git diff --cached --check
git commit -m "优化：稳定剧场版刮削与海报缓存"
```

### Task 5: 测试驱动网盘播放入口防重复导航

**Files:**
- Modify: `test/cloud_resources_page_test.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`

- [ ] **Step 1: 写入连续点击失败测试**

使用 `Completer<void>` 阻塞第一次回调，在完成前再次点击同一卡片：

```dart
testWidgets('播放请求进行中连续点击只进入一次', (tester) async {
  final release = Completer<void>();
  var calls = 0;
  await tester.pumpWidget(MaterialApp(
    home: CloudResourcesPage(
      controller: fixture.controller,
      onPlayRequest: (_) async {
        calls++;
        await release.future;
      },
    ),
  ));
  await tester.pumpAndSettle();

  final card = find.byType(ImmersiveMediaCard).first;
  await tester.tap(card);
  await tester.pump();
  await tester.tap(card);
  await tester.pump();

  expect(calls, 1);
  release.complete();
  await tester.pumpAndSettle();
});
```

再增加失败后可重试测试：第一次回调抛出异常，第二次点击能够产生第二次调用。页面销毁测试断言未完成请求完成后不触发后续页面状态更新。

- [ ] **Step 2: 运行页面测试确认红灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart --plain-name "播放请求进行中连续点击只进入一次" --reporter compact
```

Expected: FAIL，`calls` 为 2。

- [ ] **Step 3: 在共用入口接入导航协调器**

状态类增加：

```dart
final CloudPlaybackNavigationCoordinator _playbackNavigation =
    CloudPlaybackNavigationCoordinator();
```

`_play` 的第一条有效操作获取代次，并在所有异步边界检查：

```dart
final generation = _playbackNavigation.tryBegin();
if (generation == null) return;
try {
  // 构造请求并执行测试回调或真实解析。
  if (!mounted || !_playbackNavigation.isCurrent(generation)) return;
  await Modular.to.pushNamed('/video/');
} on Object catch (error, stackTrace) {
  // 沿用现有脱敏日志和用户提示。
} finally {
  _playbackNavigation.finish(generation);
}
```

`onPlayRequest` 与生产解析必须位于同一个协调边界。为协调器增加明确的失效接口，并在页面 `dispose` 中调用：

```dart
void invalidate() {
  _generation++;
  _busy = false;
}
```

生产导航必须 `await pushNamed`，使锁覆盖播放页整个生命周期；返回资源页后 `finally` 才释放。页面销毁后的旧请求因 `isCurrent` 为假而不能导航。

- [ ] **Step 4: 运行页面与播放协调测试确认绿灯**

```powershell
D:\flutter\bin\dart.bat format lib\pages\cloud\resources\cloud_resources_page.dart lib\services\cloud\cloud_playback_resolver.dart test\cloud_resources_page_test.dart
D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart test\cloud_playback_resolver_test.dart --reporter compact
```

Expected: PASS，连续点击只产生一次请求，失败后可以重试。

- [ ] **Step 5: 提交播放器修复**

```powershell
git add lib/pages/cloud/resources/cloud_resources_page.dart lib/services/cloud/cloud_playback_resolver.dart test/cloud_resources_page_test.dart test/cloud_playback_resolver_test.dart
git diff --cached --check
git commit -m "修复：避免网盘播放页重复进入"
```

### Task 6: 页面整体验收剧场版卡片与版本选择

**Files:**
- Modify: `test/cloud_resources_page_test.dart`
- Modify only if a failing test requires it: `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`
- Modify only if a failing test requires it: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`

- [ ] **Step 1: 写入端到端页面失败测试**

用控制器快照提供一季正剧、电影 A 的两个版本和电影 B 的一个版本，断言三张卡：

```dart
expect(find.text('示例作品 第 1 季'), findsOneWidget);
expect(find.text('示例作品 剧场版 A'), findsOneWidget);
expect(find.text('示例作品 剧场版 B'), findsOneWidget);
expect(find.byType(ImmersiveMediaCard), findsNWidgets(3));
```

点击电影 A 后断言版本弹层同时显示 `2160p` 和 `1080p`，选择 `1080p` 后生成的播放请求只含电影 A 的两个真实版本，不含正剧和电影 B。点击电影 B 直接生成单文件请求。

- [ ] **Step 2: 运行测试确认红灯或已有行为**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart --plain-name "剧场版独立成卡且同片版本可选择" --reporter compact
```

Expected: 在前序数据层尚未完全接通时 FAIL；若直接 PASS，保留该测试作为端到端证据，不做无必要的页面改动。

- [ ] **Step 3: 仅补足失败的展示边界**

复用现有电影多版本弹层，不新增第二套 UI。电影卡的集数文案不显示“集”，多版本时显示“2 个版本”；正剧卡继续显示唯一集数。版本选择项优先显示 `variantLabel`，没有发布标签时显示原文件名。

- [ ] **Step 4: 确认页面测试并提交**

```powershell
D:\flutter\bin\dart.bat format lib\pages\cloud\resources\cloud_resource_episode_sheet.dart lib\pages\cloud\resources\cloud_resource_poster_wall.dart test\cloud_resources_page_test.dart
D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart test\cloud_resource_collection_test.dart --reporter compact
git add lib/pages/cloud/resources/cloud_resource_episode_sheet.dart lib/pages/cloud/resources/cloud_resource_poster_wall.dart test/cloud_resources_page_test.dart
git diff --cached --check
git commit -m "优化：展示剧场版电影版本"
```

若两个生产文件均无改动，只提交测试文件，提交信息仍使用上述文案。

### Task 7: 更新 2.1.58 版本与用户文案

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

- [ ] **Step 1: 先更新版本测试并确认红灯**

```dart
const expectedVersion = '2.1.58';
const expectedBuildNumber = '20158';
```

用户文案测试断言包含“剧场版”“独立电影”“多版本”“海报缓存”“重复点击”“播放器”，并保留“不修改或删除网盘文件”的安全说明。

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart test\version_history_current_test.dart test\identity_v2_zero_residue_test.dart --reporter compact
```

Expected: FAIL，实际版本仍为 2.1.57。

- [ ] **Step 2: 更新版本和发布说明**

```yaml
version: 2.1.58+20158
msix_version: 2.1.58.0
```

在版本历史顶部加入面向普通用户的 2.1.58 测试版条目：不同剧场版独立识别和刮削，同一电影的多种清晰度或字幕版本合并到一张卡，海报缓存更稳定；修复连续点击网盘视频后播放器可能卡住的问题；夸克、百度和 OpenList 均生效；不会修改或删除网盘原始文件。

- [ ] **Step 3: 确认绿灯并提交**

```powershell
D:\flutter\bin\dart.bat format lib\core\app_version.dart lib\utils\version_history.dart test\version_consistency_test.dart test\version_history_current_test.dart test\identity_v2_zero_residue_test.dart
D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart test\version_history_current_test.dart test\identity_v2_zero_residue_test.dart --reporter compact
git add pubspec.yaml lib/core/app_version.dart README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git diff --cached --check
git commit -m "发布：准备二点一五十八测试版"
```

### Task 8: 完整验证和 MSIX 交付

**Files:**
- Verify: `build/windows/x64/runner/Release/kanyingyin.exe`
- Verify: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.58.msix`

- [ ] **Step 1: 检查工作树和关键差异**

```powershell
git status --short
git diff 58954d1..HEAD --stat
git diff --check
```

Expected: 只有本轮剧场版、海报、播放防重、测试、版本和文案相关改动，没有用户无关文件。

- [ ] **Step 2: 运行完整质量门禁**

```powershell
D:\flutter\bin\flutter.bat test --no-pub --reporter compact
D:\flutter\bin\flutter.bat analyze --no-pub
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: 测试 0 失败，分析输出 `No issues found!`，Release 构建 exit 0。

- [ ] **Step 3: 生成签名 MSIX**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1
```

Expected: 构建脚本成功，桌面生成 `看影音-2.1.58.msix`，签名验证 0 错误。

- [ ] **Step 4: 独立核验安装包**

读取 MSIX 内 `AppxManifest.xml`，确认：

```text
Identity Name="com.kanyingyin.player"
Publisher="CN=KanYingYin"
Version="2.1.58.0"
ProcessorArchitecture="x64"
```

使用 `Get-AuthenticodeSignature` 确认签名为 `Valid`，使用 `Get-FileHash -Algorithm SHA256` 记录桌面包哈希，并确认桌面包与构建产物哈希一致。

- [ ] **Step 5: 再次记录 Windows 已安装版本**

```powershell
Get-AppxPackage -Name com.kanyingyin.player |
  Select-Object Name, Version, InstallLocation
```

Expected: 若没有执行安装，明确记录仍为 2.1.57.0；若交付脚本或用户执行了安装，再记录 2.1.58.0。不得用 `pubspec.yaml` 推断已安装版本。

- [ ] **Step 6: 最终状态检查**

```powershell
git status --short
git log -8 --oneline
```

Expected: 工作树干净，所有实现、测试、版本与发布文案均已按任务提交；桌面安装包存在且版本、签名、哈希核验完成。
