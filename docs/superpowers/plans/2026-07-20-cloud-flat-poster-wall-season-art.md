# 网盘全量海报墙与季度海报 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将网盘资源页改为缓存优先、后台递归刷新的全来源海报墙，并让多季度电视剧在选集页使用 TMDB 对应季度海报。

**Architecture:** `CloudResourcesController` 读取 `CloudMediaIndexRepository` 快照立即构建页面，再使用与 `CloudLibraryController` 共享的 `CloudMediaIndexer` 刷新全部根目录。作品分组层只接收视频并按 TMDB ID 或标准剧名跨目录聚合；季度信息随现有 TMDB 元数据、资源记录和系列规则持久化，选集页按季度渲染并从索引读取真实字幕引用。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、ChangeNotifier、Hive CE、Dio、Material 3、flutter_test、Windows Release、MSIX。

---

## 文件结构

### 新建

- `docs/superpowers/plans/2026-07-20-cloud-flat-poster-wall-season-art.md`：本实施计划。

### 修改

- `lib/modules/local/tmdb_metadata.dart`：增加强类型季度元数据，并让电视剧详情携带季度列表。
- `lib/services/tmdb/tmdb_client.dart`：解析 `/tv/{id}` 返回的 `seasons`，合并中文与英文降级结果。
- `lib/modules/cloud/cloud_resource_tmdb_record.dart`：持久化季度数据。
- `lib/modules/cloud/cloud_series_match_rule.dart`：让手动确认规则携带并比较季度数据。
- `lib/services/cloud/cloud_series_match_service.dart`：在传播和规则继承时保留季度信息。
- `lib/services/cloud/cloud_resource_tmdb_service.dart`：缓存主海报和实际季度海报，再保存完整记录。
- `lib/pages/cloud/resources/cloud_resources_controller.dart`：缓存优先加载索引、后台全根目录扫描、索引字幕查询和来源级 TMDB 调度。
- `lib/pages/cloud/resources/cloud_resource_collection.dart`：移除文件夹集合，按 TMDB ID/标准剧名跨目录聚合并生成季度组。
- `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`：只渲染媒体海报墙，不再渲染文件夹入口。
- `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`：按季度展示季度海报、季度信息和真实选集。
- `lib/pages/cloud/resources/cloud_resources_page.dart`：移除目录导航，显示来源级扫描状态，使用索引字幕引用播放。
- `lib/pages/index_module.dart`：注册共享 `CloudMediaIndexer` 并注入两个控制器。
- `pubspec.yaml`、`lib/core/app_version.dart`、`README.md`、`UPDATE_DIALOG_COPY.md`、`RELEASE_NOTES.md`、`lib/utils/version_history.dart`：更新到 2.1.16。
- `test/tmdb_client_test.dart`、`test/cloud_resource_tmdb_record_test.dart`、`test/cloud_resource_tmdb_service_test.dart`、`test/cloud_series_match_service_test.dart`：季度元数据、缓存和传播测试。
- `test/cloud_resources_controller_test.dart`、`test/cloud_resource_collection_test.dart`、`test/cloud_resources_page_test.dart`：缓存优先扫描、扁平聚合、季度 UI、字幕播放及无导航测试。
- `test/version_consistency_test.dart`、`test/version_history_current_test.dart`、`test/identity_v2_zero_residue_test.dart`：2.1.16 一致性测试。

## Task 1：TMDB 季度强类型模型与客户端解析

**Files:**
- Modify: `lib/modules/local/tmdb_metadata.dart`
- Modify: `lib/services/tmdb/tmdb_client.dart`
- Test: `test/tmdb_client_test.dart`

- [ ] **Step 1：先写季度解析失败测试**

在 `test/tmdb_client_test.dart` 增加电视剧详情响应，明确验证季度号、集数、简介和海报：

```dart
test('电视剧详情解析季度并用英文补齐缺失季度海报', () async {
  final client = TmdbClient(apiKey: 'key', dio: dio);

  final metadata = await client.details(42, TmdbMediaType.tv);

  expect(metadata.seasons.map((item) => item.seasonNumber), <int>[1, 2]);
  expect(metadata.seasons.first.name, '第 1 季');
  expect(metadata.seasons.first.episodeCount, 8);
  expect(metadata.seasons.first.posterUrl, '/season-1-zh.jpg');
  expect(metadata.seasons.last.posterUrl, '/season-2-en.jpg');
});
```

测试适配器对 `zh-CN` 返回第 1、2 季但第 2 季缺少 `poster_path`，对 `en-US` 返回 `/season-2-en.jpg`。

- [ ] **Step 2：运行测试确认先失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\tmdb_client_test.dart`

Expected: FAIL，提示 `TmdbMetadata` 没有 `seasons`。

- [ ] **Step 3：实现季度模型和 JSON 往返**

在 `lib/modules/local/tmdb_metadata.dart` 增加：

```dart
class TmdbSeasonMetadata {
  const TmdbSeasonMetadata({
    required this.id,
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.overview,
    this.airDate,
    this.posterUrl,
    this.posterCachePath,
  });

  final int id;
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? overview;
  final String? airDate;
  final String? posterUrl;
  final String? posterCachePath;

  factory TmdbSeasonMetadata.fromJson(Map<String, dynamic> json) =>
      TmdbSeasonMetadata(
        id: TmdbMetadata.asInt(json['id']),
        seasonNumber: TmdbMetadata.asInt(json['seasonNumber']),
        name: json['name'] as String? ?? '',
        episodeCount: TmdbMetadata.asInt(json['episodeCount']),
        overview: TmdbMetadata.asString(json['overview']),
        airDate: TmdbMetadata.asString(json['airDate']),
        posterUrl: TmdbMetadata.asString(json['posterUrl']),
        posterCachePath: TmdbMetadata.asString(json['posterCachePath']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'seasonNumber': seasonNumber,
        'name': name,
        'episodeCount': episodeCount,
        if (overview != null) 'overview': overview,
        if (airDate != null) 'airDate': airDate,
        if (posterUrl != null) 'posterUrl': posterUrl,
        if (posterCachePath != null) 'posterCachePath': posterCachePath,
      };

  TmdbSeasonMetadata copyWith({
    String? overview,
    String? airDate,
    String? posterUrl,
    String? posterCachePath,
  }) => TmdbSeasonMetadata(
        id: id,
        seasonNumber: seasonNumber,
        name: name,
        episodeCount: episodeCount,
        overview: overview ?? this.overview,
        airDate: airDate ?? this.airDate,
        posterUrl: posterUrl ?? this.posterUrl,
        posterCachePath: posterCachePath ?? this.posterCachePath,
      );
}
```

给 `TmdbMetadata` 增加 `List<TmdbSeasonMetadata> seasons = const []`，并在 `fromJson`、`toJson`、`copyWith` 中完整处理该列表。将原私有转换函数改为同库可复用的静态函数 `asInt`、`asDouble`、`asString`。

- [ ] **Step 4：解析并合并季度数据**

在 `TmdbClient._fromJson` 中解析：

```dart
seasons: mediaType == TmdbMediaType.tv && json['seasons'] is List
    ? (json['seasons'] as List)
        .whereType<Map<Object?, Object?>>()
        .map((value) => _seasonFromJson(Map<String, dynamic>.from(value)))
        .where((value) => value.seasonNumber > 0)
        .toList(growable: false)
    : const <TmdbSeasonMetadata>[],
```

`_seasonFromJson` 映射 `season_number`、`episode_count`、`air_date` 和 `poster_path`。`details` 的英文降级按季号合并：中文字段优先，只补充空的简介、首播日期和海报；不创建 `season_number == 0` 的特别篇季度卡。

- [ ] **Step 5：运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\tmdb_client_test.dart test\tmdb_settings_language_test.dart`

Expected: PASS。

Commit:

```powershell
git add lib/modules/local/tmdb_metadata.dart lib/services/tmdb/tmdb_client.dart test/tmdb_client_test.dart
git commit -m "支持 TMDB 季度元数据"
```

## Task 2：季度信息持久化、规则传播与季度海报缓存

**Files:**
- Modify: `lib/modules/cloud/cloud_resource_tmdb_record.dart`
- Modify: `lib/modules/cloud/cloud_series_match_rule.dart`
- Modify: `lib/services/cloud/cloud_series_match_service.dart`
- Modify: `lib/services/cloud/cloud_resource_tmdb_service.dart`
- Test: `test/cloud_resource_tmdb_record_test.dart`
- Test: `test/cloud_resource_tmdb_service_test.dart`
- Test: `test/cloud_series_match_service_test.dart`

- [ ] **Step 1：写持久化和规则传播失败测试**

增加以下断言：

```dart
expect(
  CloudResourceTmdbRecord.fromJson(record.toJson())
      .seasons.single.posterCachePath,
  r'D:\cache\season-1.jpg',
);
expect(inheritedRecord.seasons.single.seasonNumber, 1);
expect(inheritedRecord.seasons.single.posterUrl, '/season-1.jpg');
```

其中锚点记录的 `TmdbMetadata.seasons` 同时包含远程季度海报和本地缓存路径，验证 `CloudSeriesMatchRule.toJson/fromJson` 及后续分集继承不会丢失。

- [ ] **Step 2：写季度海报缓存失败测试**

在 `test/cloud_resource_tmdb_service_test.dart` 使用记录型 `CloudPosterCache`，选择电视剧候选后验证：

```dart
expect(cache.requests.map((item) => item.stableId), <String>[
  target.stableKey,
  '${target.stableKey}|season:1',
  '${target.stableKey}|season:2',
]);
expect(outcome.record.seasons[0].posterCachePath, endsWith('season-1.jpg'));
expect(outcome.record.seasons[1].posterCachePath, endsWith('season-2.jpg'));
```

- [ ] **Step 3：运行测试确认先失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_tmdb_record_test.dart test\cloud_resource_tmdb_service_test.dart test\cloud_series_match_service_test.dart`

Expected: FAIL，季度字段尚未进入记录、规则和缓存流程。

- [ ] **Step 4：让资源记录和规则完整携带季度数据**

给 `CloudResourceTmdbRecord` 增加不可变字段：

```dart
final List<TmdbSeasonMetadata> seasons;
```

构造器将输入复制为 `List.unmodifiable`；`matched` 从 `metadata.seasons` 赋值；`fromJson`、`toJson`、`_copyWithCustomTitle`、相等比较和哈希全部包含季度。`CloudSeriesMatchService._metadataFromRecord` 将 `record.seasons` 传回 `TmdbMetadata`。`CloudSeriesMatchRule` 的元数据比较和哈希逐项包含季度 JSON，保证规则往返稳定。

- [ ] **Step 5：缓存每个实际季度海报**

在 `CloudResourceTmdbService.selectWithOutcome` 中仅对 `seasonNumber > 0` 且有海报地址的季度执行：

```dart
final resolved = await _posterCache!.resolve(
  sourceId: target.sourceId,
  stableId: '${target.stableKey}|season:${season.seasonNumber}',
  url: _imageUrl(season.posterUrl!),
);
return resolved == _imageUrl(season.posterUrl!)
    ? season
    : season.copyWith(posterCachePath: resolved);
```

单季缓存失败时保留远程 `posterUrl`，不撤销已保存的主记录；`posterCached` 在任一请求失败时为 `false`。保存记录和系列规则时使用带缓存路径的新 `metadata`。

- [ ] **Step 6：运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_tmdb_record_test.dart test\cloud_resource_tmdb_service_test.dart test\cloud_series_match_service_test.dart test\cloud_series_match_rule_repository_test.dart`

Expected: PASS。

Commit:

```powershell
git add lib/modules/cloud/cloud_resource_tmdb_record.dart lib/modules/cloud/cloud_series_match_rule.dart lib/services/cloud/cloud_series_match_service.dart lib/services/cloud/cloud_resource_tmdb_service.dart test/cloud_resource_tmdb_record_test.dart test/cloud_resource_tmdb_service_test.dart test/cloud_series_match_service_test.dart
git commit -m "持久化并缓存网盘季度海报"
```

## Task 3：缓存优先的全根目录扫描控制器

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1：将目录导航测试改为全量扫描测试**

使用 `MemoryCloudMediaIndexStorage` 预置一个旧视频，再让假客户端的两个根目录返回新电影、多层剧集、字幕和小视频，验证：

```dart
await fixture.controller.load();
expect(fixture.controller.entries.map((entry) => entry.id), contains('cached'));
expect(fixture.controller.scanning, isTrue);

await fixture.controller.scanCompletion;
expect(fixture.controller.entries.map((entry) => entry.id),
    containsAll(<String>['movie', 'episode-s1', 'episode-s2']));
expect(fixture.controller.entries.map((entry) => entry.id),
    isNot(contains('folder')));
expect(fixture.controller.entries.map((entry) => entry.id),
    isNot(contains('small-video')));
```

同时验证两个根目录和嵌套目录都被 `listDirectory`，选择来源后没有任何 `currentDirectory`、`isVirtualRoot` 或历史导航行为。

- [ ] **Step 2：增加来源切换、失败保留缓存和字幕引用测试**

新增测试覆盖：

```dart
expect(controller.subtitleFor(video),
    const CloudRemoteRef(id: 'subtitle-id', path: '/影视/Show.S01E01.ass'));
expect(controller.hasSubtitle(video), isTrue);
```

慢来源完成后不得覆盖已切换的新来源；扫描失败时 `entries` 仍保留旧快照并设置来源级错误；无 API Key 时索引扫描仍完成。

- [ ] **Step 3：运行测试确认先失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_controller_test.dart`

Expected: FAIL，控制器仍按单目录加载且没有索引扫描依赖。

- [ ] **Step 4：注入共享索引依赖并转换快照**

给控制器增加：

```dart
late final CloudMediaIndexRepository _mediaIndexRepository;
late final CloudMediaIndexer _mediaIndexer;
final Map<String, CloudMediaIndexItem> _indexedItems =
    <String, CloudMediaIndexItem>{};

bool scanning = false;
int scannedDirectories = 0;
String? currentScanPath;
CloudScanCancellationToken? _scanToken;
Future<void>? _scanFuture;
Future<void> get scanCompletion => _scanFuture ?? Future<void>.value();
```

构造器接收 `CloudMediaIndexRepository? mediaIndexRepository` 和 `CloudMediaIndexer? mediaIndexer`，缺省时保证索引器与仓库使用同一个实例。

实现 `_loadSnapshot`，把 `CloudMediaIndexItem` 转为非目录 `CloudFileEntry`，并以 `cloudResourceTmdbKey` 保存索引项映射。实现：

```dart
CloudRemoteRef? subtitleFor(CloudFileEntry video) =>
    _indexedItemFor(video)?.subtitleRefs.firstOrNull;

bool hasSubtitle(CloudFileEntry video) =>
    _indexedItemFor(video)?.subtitleRefs.isNotEmpty == true;
```

- [ ] **Step 5：实现选择来源后后台递归刷新**

`selectSource` 的顺序固定为：取消本控制器旧 token、清空查询、选择来源、读取快照、立即通知、调度来源级 TMDB、异步启动 `_scanSelectedSource`。扫描方法创建真实 provider client，调用共享 `CloudMediaIndexer.scan`，在进度回调中更新 `scannedDirectories/currentScanPath`，关闭 client 后重读快照。

`refresh()` 等待同一套 `_scanSelectedSource`。`CloudScanInProgressException` 不清空缓存，提示“该来源正在扫描”，并再次读取当前快照。来源切换或释放后只允许旧任务更新仓库，不得更新当前页面。

- [ ] **Step 6：把 TMDB 调度改为来源级视频上下文**

删除 `_showVirtualRoot`、`_loadDirectory`、`openDirectory`、`goBack`、目录历史和目录级标题逻辑。用全部视频调度：

```dart
CloudResourceDirectoryContext(
  source: source,
  directory: CloudRemoteRef(id: 'library:${source.id}', path: '/'),
  entries: List<CloudFileEntry>.unmodifiable(entries),
  isConfiguredRoot: true,
)
```

保持 `applyTmdbCandidate` 的传播候选为完整来源视频列表。`tmdbEntriesForCurrentDirectory` 改名为 `tmdbEntriesForSelectedSource`，只返回符合阈值的视频。

- [ ] **Step 7：运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_controller_test.dart test\cloud_media_indexer_test.dart`

Expected: PASS。

Commit:

```powershell
git add lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_resources_controller_test.dart
git commit -m "改为网盘索引缓存优先扫描"
```

## Task 4：跨目录作品聚合与季度分组

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resource_collection.dart`
- Modify: `test/cloud_resource_collection_test.dart`

- [ ] **Step 1：写跨目录 TMDB 聚合和季度分组失败测试**

构造同一来源不同目录的 S01、S02 分集，其中一集已有 TV TMDB 42，验证：

```dart
expect(collection.groups, hasLength(1));
final show = collection.groups.single;
expect(show.stableKey, 'quark|tmdb|tv|42');
expect(show.seasons.map((season) => season.seasonNumber), <int>[1, 2]);
expect(show.seasons[0].videos.map((video) => video.id),
    <String>['s1e1', 's1e2']);
expect(show.seasons[1].metadata?.posterUrl, '/season-2.jpg');
expect(collection.groups.expand((group) => group.videos),
    isNot(contains(predicate<CloudFileEntry>((item) => item.isDirectory))));
```

再验证不同来源、冲突 TMDB ID、不同标准剧名不合并；搜索能匹配中文标题、原始标题、标准剧名和组内文件名。

- [ ] **Step 2：运行测试确认先失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_collection_test.dart`

Expected: FAIL，现有集合保留文件夹且按父目录系列键分组。

- [ ] **Step 3：建立纯媒体与季度输出模型**

把 `CloudResourceCollection` 简化为只含 `groups`。增加：

```dart
class CloudResourceSeasonGroup {
  CloudResourceSeasonGroup({
    required this.seasonNumber,
    required List<CloudFileEntry> videos,
    this.metadata,
  }) : videos = List<CloudFileEntry>.unmodifiable(videos);

  final int? seasonNumber;
  final List<CloudFileEntry> videos;
  final TmdbSeasonMetadata? metadata;
}
```

`CloudResourceMediaGroup` 增加不可变 `seasons`，并继续保留排序后的扁平 `videos` 供传播和播放使用。

- [ ] **Step 4：实现安全的跨目录聚合**

先遍历条目建立“规范化标准剧名 -> 唯一 TV TMDB ID”映射。只有同一标准剧名恰好对应一个 TMDB ID 时，未匹配分集才可加入该 TMDB 展示组；出现冲突时保持各自组，避免误并。

组键规则：

```dart
final groupKey = matchedTmdbId == null
    ? identity == null
        ? resourceKey
        : '$sourceId|series|${identity.normalizedSeriesName}'
    : '$sourceId|tmdb|${record!.mediaType!.name}|$matchedTmdbId';
```

目录和非视频直接跳过；小于或等于阈值的视频继续由 `LocalVideoFileTypes.isRecognizedVideo` 排除。季度按季号升序，未知季度放最后；季度内按集号、文件名排序。季度元数据从组选中的 TMDB 记录按 `seasonNumber` 精确查找。

- [ ] **Step 5：运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_collection_test.dart test\cloud_series_identity_resolver_test.dart`

Expected: PASS。

Commit:

```powershell
git add lib/pages/cloud/resources/cloud_resource_collection.dart test/cloud_resource_collection_test.dart
git commit -m "按作品和季度聚合网盘视频"
```

## Task 5：只显示海报墙并实现季度选集界面

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1：写无文件夹入口和季度海报失败测试**

在 Widget 测试构造含文件夹、两季视频和两张季度海报的集合，验证：

```dart
expect(find.byKey(const ValueKey<String>('cloud-folder-navigation')),
    findsNothing);
expect(find.text('子目录'), findsNothing);
expect(find.byType(ImmersiveMediaCard), findsOneWidget);

await tester.tap(find.byType(ImmersiveMediaCard));
await tester.pumpAndSettle();
expect(find.byKey(const ValueKey<String>('cloud-season-1')), findsOneWidget);
expect(find.byKey(const ValueKey<String>('cloud-season-2')), findsOneWidget);
expect(find.text('第 1 季'), findsOneWidget);
expect(find.text('第 2 季'), findsOneWidget);
expect(find.byKey(const ValueKey<String>('cloud-season-poster-1')),
    findsOneWidget);
expect(find.byKey(const ValueKey<String>('cloud-season-poster-2')),
    findsOneWidget);
```

再分别覆盖本地季度缓存、远程季度海报、主海报和占位图四级回退，以及只显示实际存在分集。

- [ ] **Step 2：运行测试确认先失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart`

Expected: FAIL，海报墙仍渲染文件夹，选集页未按季度展示。

- [ ] **Step 3：移除海报墙的目录 UI**

删除 `CloudResourcePosterWall.onOpenDirectory` 和文件夹 `ActionChip`。空状态改为“该来源暂时没有符合识别条件的视频”。网格只读取 `collection.groups`，保持现有 `ImmersiveMediaCard` 的控件层级、动画、比例和交互。

- [ ] **Step 4：按季度渲染选集**

`_CloudResourceEpisodeSheet` 改为遍历 `group.seasons`。每个季度使用 `ValueKey('cloud-season-$seasonNumber')`，左侧固定比例海报，右侧显示季度名、首播年份、实际集数和最多三行简介，下方列出该季度真实视频。

海报解析实现：

```dart
Widget _seasonPoster(
  BuildContext context,
  CloudResourceSeasonGroup season,
) {
  final cached = season.metadata?.posterCachePath;
  if (cached != null && File(cached).existsSync()) {
    return Image.file(File(cached), fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _seasonNetworkOrFallback(context, season));
  }
  return _seasonNetworkOrFallback(context, season);
}
```

`_seasonNetworkOrFallback` 先尝试季度 `posterUrl`，失败后使用 `group.record.posterCachePath/posterUrl`，最后显示现有风格占位图。未知季度标题为“未识别季度”。点击集数仍 `Navigator.pop(video)` 返回真实 `CloudFileEntry`。

- [ ] **Step 5：运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart`

Expected: PASS。

Commit:

```powershell
git add lib/pages/cloud/resources/cloud_resource_poster_wall.dart lib/pages/cloud/resources/cloud_resource_episode_sheet.dart test/cloud_resources_page_test.dart
git commit -m "展示网盘季度海报选集"
```

## Task 6：来源级页面、扫描状态与索引字幕播放

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1：写来源级页面和字幕播放失败测试**

验证工具栏和页面不再出现目录概念：

```dart
expect(find.byTooltip('返回上级'), findsNothing);
expect(find.byTooltip('刷新当前来源'), findsOneWidget);
expect(find.byTooltip('刮削当前来源'), findsOneWidget);
expect(find.widgetWithText(TextField, '搜索全部网盘资源'), findsOneWidget);
expect(find.text('已汇总全部媒体根目录'), findsOneWidget);
```

预置 `CloudMediaIndexItem.subtitleRefs` 后点击电影或选集，验证 `CloudPlaybackTarget.subtitleRemoteId/subtitleRemotePath` 来自索引，不依赖字幕文件出现在 `entries`。

增加缓存存在且扫描未完成的测试：海报墙保持可点，页面只显示非阻塞扫描提示；扫描失败后旧海报仍存在。

- [ ] **Step 2：运行测试确认先失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart`

Expected: FAIL，页面仍包含目录路径、返回按钮和目录字幕匹配。

- [ ] **Step 3：改为来源级文案和后台进度**

删除 `_openDirectory`、目录路径标题、`_seriesHeader` 和返回上级按钮。工具栏使用“刷新当前来源”“刮削当前来源”；搜索提示使用“搜索全部网盘资源”。`controller.scanning` 时在海报墙上方显示：

```dart
Text('正在后台扫描 ${controller.scannedDirectories} 个目录')
```

若缓存为空则显示居中的扫描状态；有缓存则继续显示海报墙。`MaterialBanner` 错误不遮挡已有内容。

- [ ] **Step 4：从索引读取字幕引用**

删除 `_matchingSubtitle` 对 `controller.entries` 的字幕文件遍历，改为：

```dart
final subtitle = _controller.subtitleFor(entry);
```

`_subtitleVideoKeys` 使用 `controller.hasSubtitle(entry)`。来源级批量刮削遍历 `tmdbEntriesForSelectedSource`，完成提示改为“当前来源刮削完成”。

- [ ] **Step 5：运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart test\cloud_playback_resolver_test.dart`

Expected: PASS。

Commit:

```powershell
git add lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_resources_page_test.dart
git commit -m "完成来源级网盘海报墙交互"
```

## Task 7：共享索引器注入与全链路回归

**Files:**
- Modify: `lib/pages/index_module.dart`
- Test: `test/cloud_library_integration_test.dart`
- Test: `test/cloud_library_controller_test.dart`
- Test: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1：写共享实例约束测试**

在可测试的模块装配或控制器夹具中验证 `CloudLibraryController` 和 `CloudResourcesController` 使用同一个 `CloudMediaIndexRepository` 存储身份；同一来源重复扫描会得到 `CloudScanInProgressException`，不会并发读取两遍网盘目录，旧快照仍可展示。

- [ ] **Step 2：运行测试确认先失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_library_integration_test.dart test\cloud_library_controller_test.dart test\cloud_resources_controller_test.dart`

Expected: FAIL，`IndexModule` 仍在 `CloudLibraryController` 内联创建索引器。

- [ ] **Step 3：注册并注入单例**

在 `CloudMediaIndexRepository`、`CloudSeriesMatchRuleRepository` 注册之后增加：

```dart
i.addSingleton<CloudMediaIndexer>(
  () => CloudMediaIndexer(
    repository: Modular.get<CloudMediaIndexRepository>(),
    seriesMatchRuleRepository:
        Modular.get<CloudSeriesMatchRuleRepository>(),
    minRecognizedVideoSizeBytesProvider: () =>
        Modular.get<MediaRecognitionSettings>().cloudMinSizeBytes,
  ),
);
```

`CloudLibraryController` 与 `CloudResourcesController` 都注入 `Modular.get<CloudMediaIndexer>()` 和同一个 `CloudMediaIndexRepository`。不改变本地媒体库索引器绑定。

- [ ] **Step 4：运行网盘全链路测试并提交**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\cloud_media_indexer_test.dart test\cloud_media_index_repository_test.dart test\cloud_resource_collection_test.dart test\cloud_resources_controller_test.dart test\cloud_resources_page_test.dart test\cloud_resource_tmdb_service_test.dart test\cloud_resource_tmdb_coordinator_test.dart test\cloud_series_match_service_test.dart test\cloud_library_integration_test.dart test\cloud_library_controller_test.dart
```

Expected: PASS。

Commit:

```powershell
git add lib/pages/index_module.dart test/cloud_library_integration_test.dart test/cloud_library_controller_test.dart test/cloud_resources_controller_test.dart
git commit -m "共享网盘媒体递归索引器"
```

## Task 8：版本 2.1.16 与用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1：先更新版本一致性测试期望**

把当前版本期望改为：

```dart
const expectedVersion = '2.1.16';
const expectedBuildNumber = '20116';
const expectedMsixVersion = '2.1.16.0';
```

版本历史测试要求 2.1.16 文案同时包含“网盘”“海报墙”“季度”“后台扫描”“不会修改网盘文件”。

- [ ] **Step 2：运行测试确认先失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart test\version_history_current_test.dart test\identity_v2_zero_residue_test.dart`

Expected: FAIL，当前仍为 2.1.15。

- [ ] **Step 3：同步版本与面向用户文案**

更新：

```yaml
version: 2.1.16+20116
```

`msix_config.msix_version` 改为 `2.1.16.0`，`AppVersion.current` 和 README 当前版本改为 `2.1.16`。发布文案使用以下含义：

- 网盘资源会递归汇总全部媒体根目录，直接显示与本地媒体库一致的海报墙，不再逐层打开文件夹。
- 打开页面时先显示上次索引，后台自动刷新，新资源扫描完成后原位出现。
- 多季度电视剧按季度展示对应 TMDB 海报和真实分集。
- 非视频和未超过识别大小的视频不显示，字幕仍自动关联。
- 只更新看影音的索引和展示，不修改网盘文件、目录、ID 或播放路径。

- [ ] **Step 4：运行版本测试并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart test\version_history_current_test.dart test\identity_v2_zero_residue_test.dart`

Expected: PASS。

Commit:

```powershell
git add pubspec.yaml lib/core/app_version.dart README.md UPDATE_DIALOG_COPY.md RELEASE_NOTES.md lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git commit -m "更新 2.1.16 发布信息"
```

## Task 9：格式化、完整验证、Windows Release 与签名 MSIX

**Files:**
- Verify: all files modified by Tasks 1–8
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.16.msix`

- [ ] **Step 1：仅格式化本轮 Dart 文件并检查差异**

Run:

```powershell
D:\flutter\bin\dart.bat format lib/modules/local/tmdb_metadata.dart lib/services/tmdb/tmdb_client.dart lib/modules/cloud/cloud_resource_tmdb_record.dart lib/modules/cloud/cloud_series_match_rule.dart lib/services/cloud/cloud_series_match_service.dart lib/services/cloud/cloud_resource_tmdb_service.dart lib/pages/cloud/resources/cloud_resources_controller.dart lib/pages/cloud/resources/cloud_resource_collection.dart lib/pages/cloud/resources/cloud_resource_poster_wall.dart lib/pages/cloud/resources/cloud_resource_episode_sheet.dart lib/pages/cloud/resources/cloud_resources_page.dart lib/pages/index_module.dart lib/core/app_version.dart lib/utils/version_history.dart test/tmdb_client_test.dart test/cloud_resource_tmdb_record_test.dart test/cloud_resource_tmdb_service_test.dart test/cloud_series_match_service_test.dart test/cloud_resources_controller_test.dart test/cloud_resource_collection_test.dart test/cloud_resources_page_test.dart test/cloud_library_integration_test.dart test/cloud_library_controller_test.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
```

随后运行：

```powershell
git status --short
git diff --check
git diff --stat
```

Expected: 无空白错误；`.learnings/ERRORS.md` 与 `.learnings/LEARNINGS.md` 仍保持用户原有未提交状态，不进入任何提交。

- [ ] **Step 2：运行完整测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub`

Expected: 全部测试 PASS，记录总数。

- [ ] **Step 3：运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`。

- [ ] **Step 4：构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: exit 0，`build\windows\x64\runner\Release\kanyingyin.exe` 存在且版本为 2.1.16。

- [ ] **Step 5：按项目打包流程生成签名 MSIX**

读取本机 DPAPI 保存的签名密码到进程内变量，不输出密码，执行：

```powershell
D:\flutter\bin\dart.bat run msix:create --build-windows false --certificate-path "$env:USERPROFILE\.kanyingyin\signing\certificate.pfx" --certificate-password $plainPassword
```

Expected: exit 0，生成 x64 MSIX，包标识 `com.kanyingyin.player`，发布者 `CN=KanYingYin`，清单版本 `2.1.16.0`，包含 `AppxSignature.p7x`。

- [ ] **Step 6：复制桌面并验证清单、签名和哈希**

复制构建产物为：

```powershell
Copy-Item -LiteralPath $msix.FullName -Destination "$env:USERPROFILE\Desktop\看影音-2.1.16.msix" -Force
Get-AuthenticodeSignature -LiteralPath "$env:USERPROFILE\Desktop\看影音-2.1.16.msix"
Get-FileHash -Algorithm SHA256 -LiteralPath "$env:USERPROFILE\Desktop\看影音-2.1.16.msix"
```

Expected: 签名状态 `Valid`；源包和桌面包 SHA-256 一致；展开清单确认 `Identity Name="com.kanyingyin.player" Version="2.1.16.0" ProcessorArchitecture="x64"`。

- [ ] **Step 7：最终检查并提交本轮剩余改动**

Run:

```powershell
git status --short
git diff --check
git diff -- pubspec.yaml RELEASE_NOTES.md lib/utils/version_history.dart
```

只暂存本轮功能、测试、文档和版本文件，明确排除 `.learnings`，然后：

```powershell
git commit -m "交付网盘全量海报墙与季度海报"
```

若 Tasks 1–8 的提交已覆盖全部文件且没有剩余本轮改动，则不创建空提交。

## 自检结果

- 规格覆盖：Tasks 3、6、7 覆盖缓存优先与全根目录递归扫描；Task 4 覆盖扁平作品聚合和大小过滤；Tasks 1、2、5 覆盖季度元数据、季度缓存和选集季度海报；Task 6 覆盖字幕与播放；Task 8、9 覆盖版本、Release 和 MSIX 交付。
- 安全边界：展示层可跨目录按唯一 TMDB 身份聚合，系列规则传播仍使用来源、父目录和标准剧名精确键；任何任务都不写远程文件。
- 类型一致性：季度类型统一为 `TmdbSeasonMetadata`；页面季度分组统一为 `CloudResourceSeasonGroup`；扫描完成等待统一为 `CloudResourcesController.scanCompletion`。
- 无占位实现：所有任务均给出目标文件、失败测试、实现接口、验证命令和预期结果。
- 执行方式：用户明确禁止子智能体，因此只允许当前任务使用 `superpowers:executing-plans` 内联执行。
