# 网盘剧集版本归并与固定海报尺寸 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重做网盘作品边界与版本识别，让同作品同季度的多版本文件正确归并、集数按唯一集号显示、待确认匹配入口可见，并让宽屏只增加海报列数而不放大卡片。

**Architecture:** `MediaNameAnalyzer` 负责把清晰度、码率、字幕和全季集数目录识别为结构目录并产出版本标签；`CloudMediaTreeResolver` 规范重叠配置根、从真实分集文件提取优先标题候选，同时继续为每个远程视频保留独立身份。集合层新增唯一集数并按季集与版本排序，表现层只消费这些强类型结果；TMDB、播放路径、远程 ID 和远程文件保持不变。

**Tech Stack:** Flutter 3.41.9、Dart、Material、Flutter Modular、MobX、Hive CE、flutter_test、TMDB、Windows MSIX。

---

## 文件结构

- `lib/modules/media/media_name_analysis.dart`：扩充 `MediaReleaseTags`，保存从目录继承的字幕版本标签。
- `lib/services/media_name_analyzer.dart`：识别组合版本目录和字幕标签，保证结构目录不进入剧名候选。
- `lib/services/cloud/cloud_media_tree_resolver.dart`：折叠重叠配置根、继承版本标签、优先采用分集文件共同标题。
- `lib/pages/cloud/resources/cloud_resource_collection.dart`：保留全部真实版本，计算唯一集数，并稳定排列同集版本。
- `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`：显示唯一集数与 `SxxExx · 版本` 标签。
- `lib/features/library/presentation/immersive_media_card.dart`：允许指定状态徽标响应点击，同时保持其他卡片行为不变。
- `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`：增加手动确认双入口并使用最大卡片宽度网格。
- `lib/pages/cloud/resources/cloud_resources_page.dart`：把手动确认统一路由到现有 TMDB 候选窗口。
- 对应 `test/*.dart`：以真实目录和 27 个文件场景覆盖回归。
- `pubspec.yaml`、`README.md`、`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`lib/utils/version_history.dart`、版本一致性测试：完成 2.1.21 交付。

### Task 1: 组合版本目录与字幕标签

**Files:**
- Modify: `lib/modules/media/media_name_analysis.dart`
- Modify: `lib/services/media_name_analyzer.dart`
- Test: `test/media_name_analyzer_test.dart`

- [ ] **Step 1: 写入失败测试**

在 `test/media_name_analyzer_test.dart` 增加表驱动测试，明确三种版本目录都透明，且字幕标签可序列化：

```dart
test('组合画质字幕和全季目录只产生版本标签', () {
  for (final (name, resolution, subtitle) in <(String, String?, String?)>[
    ('4K 高码率', '4K', null),
    ('【全9集】【1080P】【内封简繁英】', '1080p', '内封简繁英'),
    ('【全9集】【1080P】【内嵌中字】', '1080p', '内嵌中字'),
  ]) {
    final analysis = analyzer.analyze(name, isDirectory: true);
    expect(analyzer.isTransparentDirectoryName(name), isTrue);
    expect(analysis.titleCandidates, isEmpty);
    expect(analysis.releaseTags.resolution, resolution);
    expect(analysis.releaseTags.subtitles, subtitle == null ? isEmpty : <String>[subtitle]);
  }
});

test('字幕版本标签支持 JSON 往返', () {
  const tags = MediaReleaseTags(subtitles: <String>['内封简繁英']);
  expect(MediaReleaseTags.fromJson(tags.toJson()), tags);
});
```

- [ ] **Step 2: 验证测试按预期失败**

Run: `D:\flutter\bin\flutter.bat test test\media_name_analyzer_test.dart --no-pub`

Expected: FAIL，提示 `MediaReleaseTags` 没有 `subtitles`，且组合目录不是透明目录。

- [ ] **Step 3: 最小实现结构目录和字幕标签**

在 `MediaReleaseTags` 的构造、JSON、`copyWith`、相等与哈希中完整加入：

```dart
final List<String> subtitles;
```

在 `MediaNameAnalyzer` 中加入字幕提取，并让透明目录先剥离所有成对括号、`全\d+集`、清晰度、码率和字幕词后判断剩余内容是否为空。`analyze` 对透明目录返回 `MediaNodeRole.version` 和空标题候选：

```dart
final transparentDirectory =
    isDirectory && isTransparentDirectoryName(baseName);
final role = transparentDirectory
    ? MediaNodeRole.version
    : versionMatch != null
        ? MediaNodeRole.version
        : episodeNumber != null
            ? MediaNodeRole.episode
            : seasonNumber != null
                ? MediaNodeRole.season
                : normalized.isEmpty
                    ? MediaNodeRole.unknown
                    : MediaNodeRole.work;
```

字幕规范值保留用户能区分的 `内封简繁英`、`内嵌中字`，不把它们加入作品标题。

- [ ] **Step 4: 运行单元测试**

Run: `D:\flutter\bin\flutter.bat test test\media_name_analyzer_test.dart --no-pub`

Expected: PASS。

- [ ] **Step 5: 提交识别规则**

```powershell
git add lib/modules/media/media_name_analysis.dart lib/services/media_name_analyzer.dart test/media_name_analyzer_test.dart
git commit -m "扩展网盘版本目录识别"
```

### Task 2: 折叠重叠媒体根并优先真实文件标题

**Files:**
- Modify: `lib/services/cloud/cloud_media_tree_resolver.dart`
- Test: `test/cloud_media_tree_resolver_test.dart`

- [ ] **Step 1: 写入《弥留之国的爱丽丝》重叠根失败测试**

在已有真实多季度夹具基础上，把作品根、第一季、第二季和第三季目录同时传入 `configuredRoots`，断言：

```dart
expect(tree.works, hasLength(1));
expect(tree.works.single.seasons.map((season) => season.seasonNumber), <int>[1, 2, 3]);
expect(tree.works.single.seasons.last.remoteDirectories, hasLength(2));
```

- [ ] **Step 2: 写入《回魂计》27 文件失败测试**

构造 `/来自：分享/H-回-云鬼-计 【台剧】` 下三个版本目录，每目录 9 个 `The.Resurrected.S01Exx...mkv`，断言：

```dart
expect(tree.works, hasLength(1));
final work = tree.works.single;
expect(work.titleCandidates.first, 'The Resurrected');
expect(work.seasons, hasLength(1));
expect(work.seasons.single.episodes, hasLength(27));
expect(work.seasons.single.episodes.map((item) => item.episodeNumber).toSet(), hasLength(9));
expect(work.seasons.single.episodes.where((item) => item.episodeNumber == 1), hasLength(3));
expect(work.seasons.single.episodes.map((item) => item.entry.id).toSet(), hasLength(27));
```

- [ ] **Step 3: 验证两项测试失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_media_tree_resolver_test.dart --no-pub`

Expected: FAIL，重叠子根产生额外作品，`4K 高码率` 成为作品身份或 `The Resurrected` 不是第一候选。

- [ ] **Step 4: 规范配置根**

在 `resolve` 调用发现逻辑前规范并去重路径，只保留不被其他根完整包含的最上层根：

```dart
final roots = configuredRoots
    .map(CloudSeriesIdentityResolver.normalizeRemotePath)
    .toSet()
    .toList()
  ..sort((first, second) => first.length.compareTo(second.length));
final canonicalRoots = <String>[];
for (final root in roots) {
  final nested = canonicalRoots.any(
    (parent) => root == parent || root.startsWith('$parent/'),
  );
  if (!nested) canonicalRoots.add(root);
}
for (final root in canonicalRoots) {
  context.discoverConfiguredRoot(root);
}
```

- [ ] **Step 5: 继承版本标签并优先文件标题**

在 `_mergeReleaseTags` 合并 `subtitles`；在 `_workTitleCandidates` 中先加入从分集文件解析到的非空稳定别名，再加入目录候选。保留 `_addUnique` 防止同名重复；不能添加《回魂计》作品专用字符串。

- [ ] **Step 6: 运行媒体树与索引测试**

Run: `D:\flutter\bin\flutter.bat test test\cloud_media_tree_resolver_test.dart test\cloud_media_indexer_test.dart --no-pub`

Expected: PASS；每个远程 ID、路径仍一对一写入索引。

- [ ] **Step 7: 提交作品边界实现**

```powershell
git add lib/services/cloud/cloud_media_tree_resolver.dart test/cloud_media_tree_resolver_test.dart
git commit -m "归并重叠网盘媒体根"
```

### Task 3: TMDB 优先搜索共同文件标题

**Files:**
- Modify: `lib/services/cloud/cloud_work_tmdb_service.dart`
- Test: `test/cloud_work_tmdb_service_test.dart`

- [ ] **Step 1: 写入搜索顺序失败测试**

建立目录标题为 `H-回-云鬼-计 【台剧】`、`titleCandidates` 为 `['The Resurrected', 'H-回-云鬼-计 台剧']` 的作品，配置假客户端仅对英文标题返回电视剧候选：

```dart
final candidates = await service.searchCandidates(work);
expect(client.queries.first, 'The Resurrected');
expect(client.searchedTypes.first, TmdbMediaType.tv);
expect(candidates.single.title, '回魂计');
```

- [ ] **Step 2: 验证测试失败或锁定现有行为**

Run: `D:\flutter\bin\flutter.bat test test\cloud_work_tmdb_service_test.dart --no-pub`

Expected: 若服务仍重排目录标题则 FAIL；若已严格遵循 `titleCandidates`，测试 PASS 并作为回归锁定，不添加多余代码。

- [ ] **Step 3: 保持候选顺序且去重**

若测试失败，调整搜索词构造为：手动 `scrapeTitle` 优先，其后按 `work.titleCandidates` 原顺序加入，使用大小写不敏感集合去重，媒体类型继续固定为 `TmdbMediaType.tv`。

- [ ] **Step 4: 运行 TMDB 服务测试**

Run: `D:\flutter\bin\flutter.bat test test\cloud_work_tmdb_service_test.dart --no-pub`

Expected: PASS，且断网、无结果测试行为不变。

- [ ] **Step 5: 提交搜索候选回归**

```powershell
git add lib/services/cloud/cloud_work_tmdb_service.dart test/cloud_work_tmdb_service_test.dart
git commit -m "优先使用分集文件标题刮削"
```

### Task 4: 唯一集数与多版本选集

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resource_collection.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_card_view_data.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`
- Test: `test/cloud_resource_collection_test.dart`
- Test: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 写入 9 集 27 文件集合失败测试**

复用三个目录的 27 个索引项，断言：

```dart
final group = collection.groups.single;
expect(group.uniqueEpisodeCount, 9);
expect(group.videos, hasLength(27));
expect(group.videos.take(3).map((video) => video.name), <String>[
  '回魂计 S01E01 [4K 高码率].mkv',
  '回魂计 S01E01 [1080p 内封简繁英].mkv',
  '回魂计 S01E01 [1080p 内嵌中字].mkv',
]);
expect(group.videos.map((video) => video.id).toSet(), hasLength(27));
```

- [ ] **Step 2: 验证集合测试失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_collection_test.dart --no-pub`

Expected: FAIL，当前没有 `uniqueEpisodeCount`，字幕版本标签也未进入显示名。

- [ ] **Step 3: 实现唯一集数和稳定版本排序**

给 `CloudResourceSeasonGroup` 与 `CloudResourceMediaGroup` 增加必填或默认的 `uniqueEpisodeCount`；作品集合使用：

```dart
final uniqueEpisodeCount = seasonItems
    .map((item) => item.episodeNumber)
    .whereType<int>()
    .toSet()
    .length;
```

`_virtualEntries` 先按季度、集号排序，再按版本目录优先级与路径稳定排序；`_releaseSummary` 纳入 `tags.subtitles`。当标签为空且同集重复时继续使用 `版本 1/2/3`，任何真实条目都不得被删除。

- [ ] **Step 4: 让卡片和选集显示唯一集数及版本标签**

卡片详情和副标题使用 `group.uniqueEpisodeCount`；选集顶部、季度标题也使用唯一集数。每行左侧标签由集号和方括号内版本摘要组合成：

```dart
final variant = _variantLabel(video.name);
final label = variant == null ? episodeLabel : '$episodeLabel · $variant';
```

标题仍保留应用内虚拟文件名，点击后返回原始 `CloudFileEntry` 的 ID 和路径。

- [ ] **Step 5: 运行集合和页面测试**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_collection_test.dart test\cloud_resources_page_test.dart --no-pub`

Expected: PASS；季度卡为 9 集，选集存在 27 个可点击真实文件且同集版本相邻。

- [ ] **Step 6: 提交集合与选集实现**

```powershell
git add lib/pages/cloud/resources/cloud_resource_collection.dart lib/pages/cloud/resources/cloud_resource_card_view_data.dart lib/pages/cloud/resources/cloud_resource_episode_sheet.dart test/cloud_resource_collection_test.dart test/cloud_resources_page_test.dart
git commit -m "按唯一集号展示网盘多版本"
```

### Task 5: 待确认状态双入口

**Files:**
- Modify: `lib/features/library/presentation/immersive_media_card.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Test: `test/library_presentation_components_test.dart`
- Test: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 写入菜单和徽标入口失败测试**

构造 `CloudWorkTmdbStatus.conflict` 卡片，分别操作右上角菜单和“需要确认”徽标：

```dart
await tester.tap(find.byTooltip('资源操作'));
expect(find.text('手动确认匹配'), findsOneWidget);
await tester.tap(find.text('手动确认匹配'));
expect(find.byKey(const ValueKey<String>('cloud-tmdb-match-dialog')), findsOneWidget);
```

重新泵入页面后点击带键 `cloud-manual-match-badge` 的“需要确认”标签，也断言出现同一个窗口；关闭窗口后断言协调器没有写入任何选择结果。

- [ ] **Step 2: 验证 UI 测试失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart --plain-name "待确认卡片提供菜单和状态标签双入口" --no-pub`

Expected: FAIL，当前菜单没有“手动确认匹配”，徽标被 `IgnorePointer` 包裹。

- [ ] **Step 3: 让指定徽标可点击**

为 `ImmersiveMediaCardBadge` 增加可选 `VoidCallback? onTap` 和 `Key? key`。卡片 overlay 只在全部徽标不可交互时使用 `IgnorePointer`；可交互徽标使用透明 `Material` + `InkWell`，其他卡片的动画时长 160ms、`Curves.easeOut`、层级与点击行为保持原样。

- [ ] **Step 4: 统一手动确认动作**

`CloudResourcePosterWall` 增加 `onManualMatch` 回调；仅 `group.workRecord?.status == CloudWorkTmdbStatus.conflict` 时：

```dart
PopupMenuItem(
  value: _ResourceAction.manualMatch,
  child: const Text('手动确认匹配'),
)
```

同时把“需要确认”徽标的 `onTap` 指向相同回调并设置 `ValueKey('cloud-manual-match-badge')`。页面实现 `_manualMatchEntry`，调用 `_openTmdbDialog(group, rematch: true)`；候选窗口继续用现有 draft 预填标题、类型、年份和季度信息，取消时直接返回，不写索引。

- [ ] **Step 5: 运行共享卡片与网盘页面测试**

Run: `D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart test\cloud_resources_page_test.dart --no-pub`

Expected: PASS；普通 TMDB 刮削、重新匹配、媒体详情与卡片点击仍可用。

- [ ] **Step 6: 提交手动确认入口**

```powershell
git add lib/features/library/presentation/immersive_media_card.dart lib/pages/cloud/resources/cloud_resource_poster_wall.dart lib/pages/cloud/resources/cloud_resources_page.dart test/library_presentation_components_test.dart test/cloud_resources_page_test.dart
git commit -m "增加待确认资源匹配入口"
```

### Task 6: 固定海报尺寸的自适应网格

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Test: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 将固定二三四列测试改为尺寸上限测试**

分别在 620、920、1320、1920 像素宽度泵入海报墙，读取 `SliverGridDelegateWithMaxCrossAxisExtent`，断言：

```dart
expect(delegate.maxCrossAxisExtent, 300);
expect(delegate.crossAxisSpacing, 12);
expect(delegate.mainAxisSpacing, 12);
expect(delegate.childAspectRatio, 0.68);
```

同时从渲染尺寸断言宽屏卡片宽度不超过 300 像素、1920 宽比 1320 宽产生更多列，620 宽页面没有横向溢出异常。

- [ ] **Step 2: 验证网格测试失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart --plain-name "网盘资源网格保持海报尺寸并随宽度增加列数" --no-pub`

Expected: FAIL，当前委托为 `SliverGridDelegateWithFixedCrossAxisCount`。

- [ ] **Step 3: 使用最大横轴尺寸委托**

删除 2/3/4 列阈值和动态 `mainAxisExtent`，改为：

```dart
gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 300,
  mainAxisSpacing: 12,
  crossAxisSpacing: 12,
  childAspectRatio: 0.68,
),
```

保留 12 像素页面边距、纵向 `GridView`、海报比例、圆角、遮罩和交互。

- [ ] **Step 4: 运行页面测试**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart --no-pub`

Expected: PASS，无横向 overflow；普通窗口卡片尺寸与现状接近，最大化后列数增加。

- [ ] **Step 5: 提交网格布局**

```powershell
git add lib/pages/cloud/resources/cloud_resource_poster_wall.dart test/cloud_resources_page_test.dart
git commit -m "固定宽屏网盘海报尺寸"
```

### Task 7: 集成回归与索引刷新

**Files:**
- Modify: `lib/services/cloud/cloud_media_indexer.dart`（仅当识别版本号需要递增）
- Test: `test/cloud_media_indexer_test.dart`
- Test: `test/cloud_library_integration_test.dart`
- Test: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1: 增加索引刷新契约测试**

锁定新规则会让旧索引重新识别，同时播放身份不变：

```dart
expect(result.items, hasLength(27));
expect(result.items.map((item) => item.remoteId).toSet(), hasLength(27));
expect(result.items.map((item) => item.remotePath).toSet(), hasLength(27));
expect(result.items.map((item) => item.episodeNumber).toSet(), hasLength(9));
```

- [ ] **Step 2: 验证测试失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_media_indexer_test.dart test\cloud_library_integration_test.dart test\cloud_resources_controller_test.dart --no-pub`

Expected: 新索引版本断言先 FAIL；其他扫描、缓存回退和播放身份测试继续 PASS。

- [ ] **Step 3: 递增识别版本**

把媒体索引识别版本从 4 递增为 5，使已经缓存了错误作品边界或版本目录标题的来源在下次刷新时重新识别。不得清除成功目录缓存，也不得调用远程改名、移动或删除。

- [ ] **Step 4: 运行网盘专项回归**

Run: `D:\flutter\bin\flutter.bat test test\cloud_media_name_parser_test.dart test\cloud_media_tree_resolver_test.dart test\cloud_media_indexer_test.dart test\cloud_resource_collection_test.dart test\cloud_work_tmdb_service_test.dart test\cloud_resources_page_test.dart --no-pub`

Expected: PASS。

- [ ] **Step 5: 提交索引迁移**

```powershell
git add lib/services/cloud/cloud_media_indexer.dart test/cloud_media_indexer_test.dart test/cloud_library_integration_test.dart test/cloud_resources_controller_test.dart
git commit -m "刷新网盘媒体识别索引"
```

### Task 8: 2.1.21 版本文案与一致性

**Files:**
- Modify: `pubspec.yaml`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 先更新版本契约测试**

把当前期望版本改为：

```dart
const expectedVersion = '2.1.21';
```

版本历史测试断言最新条目包含“多版本”“唯一集数”“手动确认”和“海报尺寸”。

- [ ] **Step 2: 验证版本测试失败**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart --no-pub`

Expected: FAIL，当前项目仍为 2.1.20。

- [ ] **Step 3: 更新版本与普通用户文案**

将 `pubspec.yaml` 更新为：

```yaml
version: 2.1.21+20121
msix_config:
  msix_version: 2.1.21.0
```

四处发布文案保持一致，说明：同季多版本合并为一张卡、9 个唯一集号仍保留 27 个可播放文件、重叠媒体根不再产生重复季度、《回魂计》可由分集英文名正确刮削、待确认有双入口、最大化只增加海报列数、不会改动网盘文件和播放路径。README 同步描述规则，但不声称联网始终成功。

- [ ] **Step 4: 运行版本与文案测试**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart test\release_config_contract_test.dart --no-pub`

Expected: PASS。

- [ ] **Step 5: 提交版本文案**

```powershell
git add pubspec.yaml README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart
git commit -m "发布二点一二十一测试版"
```

### Task 9: 全量验证、Windows Release 与 MSIX 交付

**Files:**
- Verify: entire repository
- Output: `build/windows/x64/runner/Release/kanyingyin.exe`
- Output: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.21.msix`

- [ ] **Step 1: 格式化并检查差异**

Run: `D:\flutter\bin\dart.bat format lib test`

Run: `git status --short`

Run: `git diff --check`

Expected: 仅本轮相关文件变化，无空白错误，不修改用户原有文件。

- [ ] **Step 2: 全量测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub`

Expected: 全部测试 PASS；记录准确测试数量。

- [ ] **Step 3: 静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`。

- [ ] **Step 4: Windows Release 构建**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: `build\windows\x64\runner\Release\kanyingyin.exe` 存在且构建成功。

- [ ] **Step 5: 按项目打包 skill 生成签名 MSIX**

读取并遵循 `C:\Users\asus\.codex\skills\flutter-windows-msix-packaging\SKILL.md`。使用 `%USERPROFILE%\.kanyingyin\signing\certificate.pfx` 与 DPAPI 加密密码，在内存中解密密码并运行项目规定的 `msix:create`；不得把密码写入文件或输出。生成后保持 `pubspec.yaml` 的 `sign_msix: false` 仓库契约。

Expected: `build\windows\x64\runner\Release\kanyingyin.msix` 为新生成的签名包。

- [ ] **Step 6: 验证清单、签名并复制桌面**

解包读取 `AppxManifest.xml`，确认 Identity Name 为 `com.kanyingyin.player`、Version 为 `2.1.21.0`、ProcessorArchitecture 为 `x64`。执行：

```powershell
Get-AuthenticodeSignature -LiteralPath 'build\windows\x64\runner\Release\kanyingyin.msix'
Copy-Item -LiteralPath 'build\windows\x64\runner\Release\kanyingyin.msix' -Destination 'C:\Users\asus\Desktop\看影音-2.1.21.msix' -Force
Get-AuthenticodeSignature -LiteralPath 'C:\Users\asus\Desktop\看影音-2.1.21.msix'
Get-FileHash -Algorithm SHA256 -LiteralPath 'C:\Users\asus\Desktop\看影音-2.1.21.msix'
```

Expected: 源包与桌面包签名均为 `Valid`，SHA-256 一致。

- [ ] **Step 7: 最终检查并提交交付状态**

Run: `git status --short`

Run: `git log --oneline -10`

Expected: 功能、测试、版本文案均已提交；如打包产生应忽略的构建文件，不纳入提交。若最终验证引起格式或测试快照调整，只暂存本轮相关文件并提交：

```powershell
git add <本轮验证后实际修改的相关文件>
git commit -m "完成二点一二十一交付验证"
```

## 自检结果

- 规格覆盖：Task 1 覆盖组合版本目录；Tasks 2–3 覆盖父子根、《回魂计》文件标题和 TMDB 候选；Task 4 覆盖 9 个唯一集号、27 个真实文件及版本排序；Task 5 覆盖手动确认菜单和状态标签；Task 6 覆盖固定海报尺寸；Task 7 覆盖索引刷新与远程数据安全；Tasks 8–9 覆盖版本、文案、全量验证、Release、签名 MSIX 和桌面交付。
- 占位符扫描：计划不含未定义的 TBD、TODO 或“稍后实现”；所有代码步骤给出精确字段、调用点、命令和预期结果。
- 类型一致性：字幕字段统一为 `MediaReleaseTags.subtitles`，唯一集数字段统一为 `CloudResourceMediaGroup.uniqueEpisodeCount`，手动确认回调统一为 `onManualMatch`，版本统一为 `2.1.21+20121` / `2.1.21.0`。
