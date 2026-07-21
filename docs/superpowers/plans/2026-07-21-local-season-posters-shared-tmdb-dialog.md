# 本地季度海报与共享 TMDB 对话框 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复本地季度卡共用总海报的问题，让本地与网盘卡片使用同一种悬停信息层，并让本地通过常驻三点菜单使用完整 TMDB 候选确认对话框。

**Architecture:** 将准备搜索请求、搜索结果和候选确认对话框移到共享 TMDB 边界；本地与网盘仅提供搜索和保存适配回调。本地海报选择继续使用 `TmdbPosterPolicy`，卡片根据封面类型决定本地与网络资源的优先级。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、MobX、TMDB API、flutter_test、PowerShell、MSIX、SignTool。

---

## 文件职责

- `lib/services/tmdb/tmdb_prepared_search.dart`：定义来源无关的准备搜索请求、结果和对话框初始识别信息
- `lib/pages/tmdb_match_dialog.dart`：在页面共享边界呈现 TMDB 搜索和候选确认界面
- `lib/pages/cloud/resources/cloud_tmdb_match_dialog.dart`：保留网盘旧导入路径的兼容别名
- `lib/services/tmdb/local_tmdb_scrape_service.dart`：执行本地只读候选搜索和确认后的持久化
- `lib/pages/local/local_controller.dart`：为本地页面提供识别草稿、准备搜索和季度海报 URL
- `lib/features/library/presentation/library_media_grid.dart`：控制本地封面回退顺序、悬停层和常驻尾部菜单
- `lib/pages/local/local_page.dart`：连接本地三点菜单、共享 TMDB 对话框和现有本地操作
- `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`：将网盘信息层改为悬停显示

### Task 1: 提取共享准备搜索类型和 TMDB 对话框

**Files:**
- Create: `lib/services/tmdb/tmdb_prepared_search.dart`
- Create: `lib/pages/tmdb_match_dialog.dart`
- Modify: `lib/services/cloud/cloud_resource_tmdb_search.dart`
- Modify: `lib/services/cloud/cloud_media_name_parser.dart`
- Modify: `lib/pages/cloud/resources/cloud_tmdb_match_dialog.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Create: `test/tmdb_match_dialog_test.dart`
- Modify: `test/cloud_tmdb_match_dialog_test.dart`

- [ ] **Step 1: 写入共享对话框失败测试**

创建 `test/tmdb_match_dialog_test.dart`，使用泛型 `TmdbMatchDialog<String>` 验证输入、搜索和应用结果：

```dart
testWidgets('共享对话框转发准备搜索参数并返回应用结果', (tester) async {
  TmdbPreparedSearchRequest? request;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) {
      return FilledButton(
        onPressed: () => showDialog<String>(
          context: context,
          builder: (_) => TmdbMatchDialog<String>(
            title: 'TMDB 刮削',
            safetyText: '仅更新看影音资料，不会修改媒体文件',
            draft: const TmdbMatchDraft(
              originalName: '神探夏洛克 S02',
              searchTitle: '神探夏洛克',
              mediaTypeMode: TmdbMediaTypeMode.tv,
              year: 2012,
              seasonNumber: 2,
            ),
            initialOptions: const TmdbScrapeOptions.defaults(),
            onSearch: (value) async {
              request = value;
              return TmdbPreparedSearchOutcome(
                ranked: TmdbRankedResult(
                  candidates: <TmdbRankedCandidate>[_candidate],
                  shouldAutoMatch: true,
                ),
              );
            },
            onApply: (candidate, options) async => 'saved:${candidate.metadata.id}',
          ),
        ),
        child: const Text('打开'),
      );
    }),
  ));

  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
  expect(find.text('第 2 季'), findsOneWidget);
  await tester.tap(find.widgetWithText(FilledButton, '搜索 TMDB'));
  await tester.pumpAndSettle();
  expect(request?.queryTitle, '神探夏洛克');
  expect(request?.queryYear, 2012);
  expect(request?.mediaTypeMode, TmdbMediaTypeMode.tv);
});

final _candidate = TmdbRankedCandidate(
  metadata: TmdbMetadata(
    id: 42,
    mediaType: TmdbMediaType.tv,
    title: '神探夏洛克',
    releaseDate: '2012-01-01',
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026, 7, 21),
    matchConfidence: 1,
  ),
  score: 1,
  titleMatched: true,
  yearMatched: true,
  typeMatched: true,
);
```

同文件增加空搜索词、非法年份、窄窗口布局和安全提示测试。键统一使用 `tmdb-match-dialog`、`tmdb-search-title`、`tmdb-media-type`、`tmdb-year`、`tmdb-stacked` 和 `tmdb-two-column`。

- [ ] **Step 2: 运行测试并确认共享类型不存在**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\tmdb_match_dialog_test.dart
```

预期：FAIL，找不到 `TmdbPreparedSearchRequest` 或 `TmdbMatchDialog`。

- [ ] **Step 3: 定义共享准备搜索类型**

创建 `lib/services/tmdb/tmdb_prepared_search.dart`：

```dart
import 'package:flutter/foundation.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
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

@immutable
class TmdbPreparedSearchRequest {
  const TmdbPreparedSearchRequest({
    required this.queryTitle,
    required this.mediaTypeMode,
    required this.options,
    this.queryYear,
  });

  final String queryTitle;
  final int? queryYear;
  final TmdbMediaTypeMode mediaTypeMode;
  final TmdbScrapeOptions options;
}

@immutable
class TmdbPreparedSearchOutcome {
  const TmdbPreparedSearchOutcome({required this.ranked});
  final TmdbRankedResult ranked;
}
```

将 `cloud_resource_tmdb_search.dart` 中的请求和搜索结果改为兼容别名；保留同文件现有的 `CloudSeriesPropagationSummary` 与 `CloudResourceTmdbSelectionOutcome` 声明：

```dart
import 'package:kanyingyin/services/tmdb/tmdb_prepared_search.dart';

typedef CloudResourceTmdbSearchRequest = TmdbPreparedSearchRequest;
typedef CloudResourceTmdbSearchOutcome = TmdbPreparedSearchOutcome;

// 下方 CloudSeriesPropagationSummary 与
// CloudResourceTmdbSelectionOutcome 保持原实现不变。
```

从 `cloud_media_name_parser.dart` 删除 `TmdbMatchDraft` 定义，改为导入共享文件。

- [ ] **Step 4: 移动并泛化对话框**

将 `cloud_tmdb_match_dialog.dart` 的现有布局迁移到 `tmdb_match_dialog.dart`，执行以下确定替换：

```text
CloudTmdbMatchDialog                         -> TmdbMatchDialog<TResult>
_CloudTmdbMatchDialogState                  -> _TmdbMatchDialogState<TResult>
CloudResourceTmdbSearchRequest              -> TmdbPreparedSearchRequest
CloudResourceTmdbSearchOutcome              -> TmdbPreparedSearchOutcome
CloudResourceTmdbSelectionOutcome           -> TResult
cloud-tmdb-match-dialog                     -> tmdb-match-dialog
cloud-tmdb-search-title                     -> tmdb-search-title
cloud-tmdb-media-type                       -> tmdb-media-type
cloud-tmdb-year                             -> tmdb-year
cloud-tmdb-stacked                          -> tmdb-stacked
cloud-tmdb-two-column                       -> tmdb-two-column
'仅更新看影音中的资料，不会修改网盘文件' -> widget.safetyText
```

共享公开声明为：

```dart
typedef TmdbMatchSearchCallback = Future<TmdbPreparedSearchOutcome> Function(
  TmdbPreparedSearchRequest request,
);
typedef TmdbMatchApplyCallback<TResult> = Future<TResult> Function(
  TmdbRankedCandidate candidate,
  TmdbScrapeOptions options,
);

class TmdbMatchDialog<TResult> extends StatefulWidget {
  const TmdbMatchDialog({
    super.key,
    required this.title,
    required this.safetyText,
    required this.draft,
    required this.initialOptions,
    required this.onSearch,
    required this.onApply,
  });

  final String title;
  final String safetyText;
  final TmdbMatchDraft draft;
  final TmdbScrapeOptions initialOptions;
  final TmdbMatchSearchCallback onSearch;
  final TmdbMatchApplyCallback<TResult> onApply;
}
```

应用成功时调用 `Navigator.of(context).pop<TResult>(outcome)`。其他状态、输入校验、160 ms 以外的既有交互保持不变。

- [ ] **Step 5: 保留网盘兼容入口并更新调用**

将 `cloud_tmdb_match_dialog.dart` 收缩为兼容别名：

```dart
import 'package:kanyingyin/pages/tmdb_match_dialog.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';

export 'package:kanyingyin/pages/tmdb_match_dialog.dart';

typedef CloudTmdbSearchCallback = TmdbMatchSearchCallback;
typedef CloudTmdbApplyCallback =
    TmdbMatchApplyCallback<CloudResourceTmdbSelectionOutcome>;
typedef CloudTmdbMatchDialog =
    TmdbMatchDialog<CloudResourceTmdbSelectionOutcome>;
```

在 `cloud_resources_page.dart` 创建对话框时增加：

```dart
safetyText: '仅更新看影音中的资料，不会修改网盘文件',
```

更新旧测试键名和共享 outcome 类型，不改变网盘断言内容。

- [ ] **Step 6: 运行共享与网盘对话框测试**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\tmdb_match_dialog_test.dart test\cloud_tmdb_match_dialog_test.dart test\cloud_resources_page_test.dart
```

预期：PASS。

- [ ] **Step 7: 提交**

```powershell
git add lib/services/tmdb/tmdb_prepared_search.dart lib/pages/tmdb_match_dialog.dart lib/services/cloud/cloud_resource_tmdb_search.dart lib/services/cloud/cloud_media_name_parser.dart lib/pages/cloud/resources/cloud_tmdb_match_dialog.dart lib/pages/cloud/resources/cloud_resources_page.dart test/tmdb_match_dialog_test.dart test/cloud_tmdb_match_dialog_test.dart test/cloud_resources_page_test.dart
git commit -m "共享TMDB候选确认对话框"
```

### Task 2: 为本地媒体增加只读准备搜索

**Files:**
- Modify: `lib/services/tmdb/local_tmdb_scrape_service.dart`
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `test/local_tmdb_integration_test.dart`
- Modify: `test/local_controller_test.dart`

- [ ] **Step 1: 写入候选搜索不修改索引的失败测试**

在 `test/local_tmdb_integration_test.dart` 增加：

```dart
test('本地准备搜索返回候选但不修改索引', () async {
  final original = _item('Season 2/a.mkv', seasonNumber: 2);
  final index = _MemoryIndexRepository(<LocalMediaIndexItem>[original]);
  final service = LocalTmdbScrapeService(
    indexRepository: index,
    metadataRepository: _MemoryMetadataRepository(),
    clientFactory: (_) => _FakeClient(),
  );

  final outcome = await service.searchPrepared(
    apiKey: 'configured-key',
    seriesName: '流浪地球',
    request: const TmdbPreparedSearchRequest(
      queryTitle: '流浪地球',
      queryYear: 2019,
      mediaTypeMode: TmdbMediaTypeMode.tv,
      options: TmdbScrapeOptions.defaults(),
    ),
  );

  expect(outcome.ranked.candidates, isNotEmpty);
  expect(index.getByPath(original.path), same(original));
});
```

增加空 API Key 抛出 `StateError('请先在设置中填写 TMDB API Key')` 的测试。

- [ ] **Step 2: 运行测试并确认方法不存在**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\local_tmdb_integration_test.dart
```

预期：FAIL，找不到 `searchPrepared()`。

- [ ] **Step 3: 实现本地只读搜索**

在 `LocalTmdbScrapeService` 增加：

```dart
Future<TmdbPreparedSearchOutcome> searchPrepared({
  required String apiKey,
  required String seriesName,
  required TmdbPreparedSearchRequest request,
}) async {
  final key = apiKey.trim();
  if (key.isEmpty) throw StateError('请先在设置中填写 TMDB API Key');
  final normalizedSeries = seriesName.trim().toLowerCase();
  final items = indexRepository
      .getAll()
      .where((item) => item.seriesName.trim().toLowerCase() == normalizedSeries)
      .toList(growable: false);
  if (items.isEmpty) throw StateError('本地媒体索引中没有该作品');
  final base = subjectBuilder.build(seriesName: seriesName, items: items);
  final subject = TmdbScrapeSubject(
    stableKey: base.stableKey,
    titleCandidates: <String>[request.queryTitle],
    year: request.queryYear,
    seasonNumbers: base.seasonNumbers,
    episodeNumbers: base.episodeNumbers,
    mediaEvidence: base.mediaEvidence,
    existingMetadata: base.existingMetadata,
    fieldLocks: base.fieldLocks,
    matchOrigin: base.matchOrigin,
    ruleVersion: base.ruleVersion,
  );
  final outcome = await TmdbScrapeEngine(client: clientFactory(key)).search(
    subject,
    request.options.copyWith(mediaTypeMode: request.mediaTypeMode),
  );
  return TmdbPreparedSearchOutcome(ranked: outcome.ranked);
}
```

- [ ] **Step 4: 为控制器增加草稿和搜索适配**

在 `LocalController` 增加：

```dart
TmdbMatchDraft localTmdbDraftForPaths({
  required String originalName,
  required Iterable<String> paths,
}) {
  final ids = paths.map(LocalMediaIndexItem.normalizePath).toSet();
  final items = localLibraryItems.where((item) => ids.contains(item.id)).toList();
  if (items.isEmpty) throw StateError('请先扫描媒体库，再进行 TMDB 刮削');
  final seasons = items.map((item) => item.seasonNumber).whereType<int>().where((value) => value > 0).toSet();
  final episodes = items.map((item) => item.episodeNumber).whereType<int>().where((value) => value > 0).toSet();
  final releaseDate = items.map((item) => item.tmdb?.releaseDate).whereType<String>().firstOrNull;
  final year = releaseDate != null && releaseDate.length >= 4
      ? int.tryParse(releaseDate.substring(0, 4))
      : null;
  return TmdbMatchDraft(
    originalName: originalName,
    searchTitle: items.first.seriesName,
    mediaTypeMode: seasons.isNotEmpty || episodes.isNotEmpty
        ? TmdbMediaTypeMode.tv
        : TmdbMediaTypeMode.auto,
    year: year,
    seasonNumber: seasons.length == 1 ? seasons.single : null,
    episodeNumber: episodes.length == 1 ? episodes.single : null,
  );
}

Future<TmdbPreparedSearchOutcome> searchLocalTmdb(
  String seriesName,
  TmdbPreparedSearchRequest request,
) {
  return _tmdbScrapeService.searchPrepared(
    apiKey: _tmdbApiKey,
    seriesName: seriesName,
    request: request,
  );
}
```

为 `localTmdbDraftForPaths()` 增加单季、跨季和电影测试。

- [ ] **Step 5: 运行本地服务和控制器测试**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\local_tmdb_integration_test.dart test\local_controller_test.dart
```

预期：PASS。

- [ ] **Step 6: 提交**

```powershell
git add lib/services/tmdb/local_tmdb_scrape_service.dart lib/pages/local/local_controller.dart test/local_tmdb_integration_test.dart test/local_controller_test.dart
git commit -m "支持本地TMDB准备搜索"
```

### Task 3: 修复本地季度海报选择和封面回退顺序

**Files:**
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `lib/pages/local/local_page.dart`
- Modify: `lib/features/library/presentation/library_media_grid.dart`
- Modify: `test/local_controller_test.dart`
- Modify: `test/library_presentation_components_test.dart`

- [ ] **Step 1: 写入不同季度 URL 和封面优先级失败测试**

在 `test/local_controller_test.dart` 构造同一作品第 1、2 季索引项，元数据包含 `/season-1.jpg`、`/season-2.jpg` 和 `/show.jpg`，断言：

```dart
expect(
  controller.tmdbPosterUrlForPaths(<String>[season1.path]),
  'https://image.tmdb.org/t/p/w780/season-1.jpg',
);
expect(
  controller.tmdbPosterUrlForPaths(<String>[season2.path]),
  'https://image.tmdb.org/t/p/w780/season-2.jpg',
);
```

在 `test/library_presentation_components_test.dart` 使用两个 `MemoryImage`，断言 `preferLocalCover: true` 时首个 `Image` 使用本地 provider，`false` 时使用网络 provider。

- [ ] **Step 2: 运行测试并确认仍返回作品总海报**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\local_controller_test.dart test\library_presentation_components_test.dart
```

预期：FAIL，第 1、2 季都返回 `/show.jpg`，且 view data 没有 `preferLocalCover`。

- [ ] **Step 3: 按单季证据选择季度海报**

修改 `tmdbPosterUrlForPaths()`：

```dart
String? tmdbPosterUrlForPaths(Iterable<String> paths) {
  final ids = paths.map(LocalMediaIndexItem.normalizePath).toSet();
  final matches = localLibraryItems.where((item) => ids.contains(item.id)).toList();
  final metadata = matches.map((item) => item.tmdb).nonNulls.firstOrNull;
  if (metadata == null) return null;
  final seasons = matches.map((item) => item.seasonNumber).whereType<int>().where((value) => value > 0).toSet();
  final poster = const TmdbPosterPolicy().select(
    metadata,
    seasonNumber: seasons.length == 1 ? seasons.single : null,
    options: const TmdbScrapeOptions.defaults(),
  );
  return _tmdbImageUrl(poster);
}
```

季度海报缺失和跨季分组继续由 `TmdbPosterPolicy` 回退总海报。

- [ ] **Step 4: 增加本地封面优先标记**

为 `LibraryMediaItemViewData` 增加：

```dart
final bool preferLocalCover;
```

构造器默认 `false`。在 `LocalPage._mediaItemData()` 传入：

```dart
preferLocalCover: !group.needsOnlinePoster,
```

为 `LibraryMediaCoverFallback` 增加统一入口：

```dart
static Widget build(
  LibraryMediaItemViewData item, {
  required WidgetBuilder placeholderBuilder,
}) {
  Widget local(BuildContext context) => buildLocal(
        item,
        placeholderBuilder: placeholderBuilder,
      );
  Widget network(BuildContext context) => buildNetwork(
        item,
        localBuilder: placeholderBuilder,
      );
  if (item.preferLocalCover) {
    return buildLocal(item, placeholderBuilder: network);
  }
  return buildNetwork(item, localBuilder: local);
}
```

`_LibraryMediaTile._cover()` 改为调用 `LibraryMediaCoverFallback.build()`。

- [ ] **Step 5: 运行海报与媒体网格回归**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\local_controller_test.dart test\library_presentation_components_test.dart test\local_tmdb_integration_test.dart
```

预期：PASS。

- [ ] **Step 6: 提交**

```powershell
git add lib/pages/local/local_controller.dart lib/pages/local/local_page.dart lib/features/library/presentation/library_media_grid.dart test/local_controller_test.dart test/library_presentation_components_test.dart
git commit -m "修复本地季度海报选择"
```

### Task 4: 统一悬停信息层并接入本地三点菜单

**Files:**
- Modify: `lib/features/library/presentation/library_media_grid.dart`
- Modify: `lib/pages/local/local_page.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Modify: `test/library_presentation_components_test.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 写入两端悬停和本地菜单失败测试**

在 `test/cloud_resources_page_test.dart` 将卡片断言改为：

```dart
expect(
  tester.widget<ImmersiveMediaCard>(find.byType(ImmersiveMediaCard)).overlayMode,
  ImmersiveMediaCardOverlayMode.hover,
);
expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0);
final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
await mouse.addPointer(location: Offset.zero);
await mouse.moveTo(tester.getCenter(find.byType(ImmersiveMediaCard)));
await tester.pump(const Duration(milliseconds: 160));
expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1);
expect(find.byTooltip('资源操作'), findsOneWidget);
```

在 `test/library_presentation_components_test.dart` 为 `LibraryMediaGrid` 传入尾部构建器：

```dart
trailingBuilder: (item) => PopupMenuButton<String>(
  tooltip: '本地媒体操作',
  itemBuilder: (_) => const <PopupMenuEntry<String>>[
    PopupMenuItem(value: 'scrape', child: Text('TMDB 刮削')),
    PopupMenuItem(value: 'rematch', child: Text('重新匹配')),
  ],
),
```

断言菜单在悬停前存在，标题信息层透明度为 0，悬停后为 1。

- [ ] **Step 2: 运行测试并确认网盘仍为 always 且本地无菜单入口**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\library_presentation_components_test.dart test\cloud_resources_page_test.dart
```

预期：FAIL，网盘 `overlayMode` 为 `always`，`LibraryMediaGrid` 没有 `trailingBuilder`。

- [ ] **Step 3: 为本地网格增加常驻尾部组件**

定义：

```dart
typedef LibraryMediaTrailingBuilder = Widget Function(
  BuildContext context,
  LibraryMediaItemViewData item,
);
```

`LibraryMediaGrid` 增加可空 `trailingBuilder`，传给 `_LibraryMediaTile`。卡片构造增加：

```dart
trailing: widget.trailingBuilder?.call(context, item),
```

尾部组件继续由 `ImmersiveMediaCard` 放在覆盖层之外，因此悬停前保持可见。

- [ ] **Step 4: 增加本地三点菜单和完整对话框**

在 `local_page.dart` 定义：

```dart
enum _LocalMediaAction {
  play,
  editTitle,
  customCover,
  scrapeTmdb,
  rematchTmdb,
  findPoster,
  copyPath,
}
```

`_mediaGrid()` 传入 `trailingBuilder`，返回带 `tooltip: '本地媒体操作'` 的 `PopupMenuButton<_LocalMediaAction>`。菜单必须包含 **TMDB 刮削** 和 **重新匹配**，并把其他操作转发到现有方法。

新增 `_openLocalTmdbDialog()`：

```dart
Future<void> _openLocalTmdbDialog(
  BuildContext context,
  LocalVideoGroup group, {
  required bool rematch,
}) async {
  final paths = group.episodes.map((item) => item.path);
  final seriesName = localController.indexedSeriesNameForPaths(paths);
  if (seriesName == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先扫描媒体库，再进行 TMDB 刮削')),
    );
    return;
  }
  final draft = localController.localTmdbDraftForPaths(
    originalName: group.title,
    paths: paths,
  );
  final result = await showDialog<TmdbScrapeResult>(
    context: context,
    builder: (_) => TmdbMatchDialog<TmdbScrapeResult>(
      title: rematch ? '重新匹配 TMDB' : 'TMDB 刮削',
      safetyText: '仅更新看影音中的资料，不会修改本地文件',
      draft: draft,
      initialOptions: localController.tmdbScrapeOptions,
      onSearch: (request) => localController.searchLocalTmdb(
        seriesName,
        request,
      ),
      onApply: (candidate, options) async {
        final selected = await localController.selectTmdbCandidate(
          seriesName,
          candidate.metadata,
          options: options,
        );
        if (selected.status != TmdbScrapeStatus.matched) {
          throw StateError('保存匹配结果失败');
        }
        return selected;
      },
    ),
  );
  if (!context.mounted || result == null) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(
      result.posterDownloadFailures > 0
          ? 'TMDB 信息已更新，部分封面下载失败'
          : 'TMDB 信息已更新',
    )),
  );
}
```

现有长按操作表中的 **TMDB 刮削** 改为调用该方法。删除本页不再使用的 `TmdbScrapeOptionsSheet` 和 `TmdbMatchSheet` 流程，不影响其他页面使用这两个组件。

- [ ] **Step 5: 将网盘信息层改为悬停显示**

在 `cloud_resource_poster_wall.dart` 修改一行：

```dart
overlayMode: ImmersiveMediaCardOverlayMode.hover,
```

保留 `trailing: _resourceMenu(context, group)`，三点菜单继续常驻。

- [ ] **Step 6: 运行本地、网盘和对话框 UI 回归**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\library_presentation_components_test.dart test\cloud_resources_page_test.dart test\tmdb_match_dialog_test.dart test\cloud_tmdb_match_dialog_test.dart test\cloud_library_integration_test.dart
```

预期：PASS。

- [ ] **Step 7: 提交**

```powershell
git add lib/features/library/presentation/library_media_grid.dart lib/pages/local/local_page.dart lib/pages/cloud/resources/cloud_resource_poster_wall.dart test/library_presentation_components_test.dart test/cloud_resources_page_test.dart
git commit -m "统一本地网盘卡片悬停交互"
```

### Task 5: 版本 2.1.33 验收和签名交付

**Files:**
- Modify: `pubspec.yaml`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 写入 2.1.33 版本和文案失败测试**

将版本测试期望更新为：

```dart
const expectedVersion = '2.1.33';
const expectedBuildNumber = '20133';
```

新增当前版本历史断言：

```dart
test('二点一三十三说明季度海报、悬停标签和本地刮削对话框', () {
  final changes = versionHistoryForCurrent('2.1.33').single.changes.join('\n');
  expect(changes, contains('季度海报'));
  expect(changes, contains('鼠标'));
  expect(changes, contains('TMDB 刮削'));
  expect(changes, contains('不会修改'));
});
```

- [ ] **Step 2: 运行版本测试并确认仍为 2.1.32**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart test\version_history_current_test.dart
```

预期：FAIL，当前版本仍为 `2.1.32`。

- [ ] **Step 3: 更新版本和用户文案**

同步以下值：

```yaml
version: 2.1.33+20133
msix_version: 2.1.33.0
```

`AppVersion.current` 改为 `2.1.33`。发布说明包含：本地每季使用对应海报、本地与网盘标签悬停显示、本地新增完整 TMDB 刮削与重新匹配对话框、候选搜索不修改媒体文件、断网时扫描与播放继续可用。

- [ ] **Step 4: 运行完整质量门禁**

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed .
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

预期：全部 exit code 0。

- [ ] **Step 5: 生成签名 MSIX 和异机包**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1
```

预期桌面生成：

```text
C:\Users\asus\Desktop\看影音-2.1.33.msix
C:\Users\asus\Desktop\看影音-2.1.33-异机安装包.zip
```

独立验证 `Get-AuthenticodeSignature` 为 `Valid`，清单为 `com.kanyingyin.player / CN=KanYingYin / 2.1.33.0 / x64`，桌面 MSIX 与构建产物 SHA-256 相同，ZIP 仍只有固定 6 个文件。

- [ ] **Step 6: 检查并提交交付版本**

```powershell
git status --short
git diff --check
git add pubspec.yaml README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/core/app_version.dart lib/utils/version_history.dart test/version_consistency_test.dart test/identity_v2_zero_residue_test.dart test/version_history_current_test.dart
git commit -m "发布本地季度海报修复测试版"
```

提交不得包含 `.learnings/ERRORS.md`、`.learnings/LEARNINGS.md`、`build/`、MSIX、ZIP、PFX、证书密码或任何 API Key。
