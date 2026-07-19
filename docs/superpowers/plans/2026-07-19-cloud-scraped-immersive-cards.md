# 网盘刮削沉浸式海报卡片实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将网盘资源中的独立视频和已匹配 TMDB 的目录改为信息始终可见的沉浸式全海报卡片，同时保持普通目录、本地媒体库、播放和导航行为不变，并交付 2.1.12 Windows MSIX。

**Architecture:** 把本地媒体库现有的渐变信息层提取为无业务依赖的 `ImmersiveMediaCard`，以 `hover` 和 `always` 两种模式分别服务本地与网盘。网盘领域对象先由 `CloudResourceCardViewData` 转换为强类型展示数据，再由 `CloudResourcesGrid` 按“独立视频/已匹配目录”和“普通目录”分流渲染；页面只补充已存在于当前目录列表中的同名字幕稳定键。

**Tech Stack:** Flutter 3.41.9、Dart、Material 3、Flutter Modular、MobX、flutter_test、Windows Release、MSIX Packaging Toolchain

---

## 文件结构

- 新建 `lib/features/library/presentation/immersive_media_card.dart`：共享卡片外壳、渐变信息层、状态标签和悬停动画。
- 修改 `lib/features/library/presentation/library_media_grid.dart`：本地媒体库复用共享卡片，保留 Hero、封面降级和原回调。
- 新建 `lib/pages/cloud/resources/cloud_resource_card_view_data.dart`：把网盘条目、TMDB 记录、刮削与字幕状态映射为只读展示数据。
- 修改 `lib/pages/cloud/resources/cloud_resources_grid.dart`：按展示数据渲染媒体卡或目录卡，提供响应式 2/3/4 列布局。
- 修改 `lib/pages/cloud/resources/cloud_resources_page.dart`：从当前完整条目生成有同名字幕的视频稳定键并传给网格。
- 修改 `lib/modules/cloud/cloud_resource_tmdb_record.dart`：持久化 TMDB 上映/首播日期。
- 新建 `test/cloud_resource_card_view_data_test.dart`：覆盖网盘卡片分类、文本组合与状态标签。
- 修改 `test/cloud_resource_tmdb_record_test.dart`、`test/library_presentation_components_test.dart`、`test/cloud_resources_page_test.dart`：模型、共享卡片、本地回归和网盘页面测试。
- 修改 `pubspec.yaml`、`lib/core/app_version.dart`、`lib/utils/version_history.dart`、`README.md`、`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`：2.1.12 版本与普通用户更新文案。

### Task 1：为网盘 TMDB 记录保存上映或首播日期

**Files:**
- Modify: `lib/modules/cloud/cloud_resource_tmdb_record.dart`
- Test: `test/cloud_resource_tmdb_record_test.dart`

- [ ] **Step 1：先写日期持久化失败测试**

在现有 JSON 往返测试的 `TmdbMetadata` 中加入 `releaseDate: '2019-02-05'`，并加入：

```dart
expect(record.releaseDate, '2019-02-05');
expect(record.toJson()['releaseDate'], '2019-02-05');
expect(CloudResourceTmdbRecord.fromJson(record.toJson()), record);
```

在“自定义剧名优先显示”测试的 metadata 中加入 `releaseDate: '2025-01-01'`，并加入：

```dart
expect(customized.releaseDate, '2025-01-01');
expect(restored.releaseDate, '2025-01-01');
```

再新增旧 JSON 兼容测试：

```dart
test('旧版 JSON 缺少上映日期时保持兼容', () {
  final record = CloudResourceTmdbRecord.fromJson(<String, Object?>{
    'sourceId': 'source-a',
    'remoteId': 'folder-a',
    'remotePath': '/影视/A',
    'displayName': 'A',
    'resourceKind': 'directory',
    'status': 'matched',
    'checkedAtMillis': DateTime.utc(2026, 7, 19).millisecondsSinceEpoch,
  });

  expect(record.releaseDate, isNull);
  expect(record.toJson(), isNot(contains('releaseDate')));
});
```

- [ ] **Step 2：运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_tmdb_record_test.dart`

Expected: FAIL，提示 `releaseDate` getter 或命名参数不存在。

- [ ] **Step 3：最小实现 releaseDate 字段**

在构造函数可空字段中加入 `this.releaseDate`，在 `matched` 工厂中加入：

```dart
releaseDate: metadata.releaseDate,
```

在字段、JSON 和复制逻辑中分别加入：

```dart
final String? releaseDate;

// fromJson
releaseDate: _asString(json['releaseDate']),

// toJson
if (releaseDate != null) 'releaseDate': releaseDate,

// _copyWithCustomTitle
releaseDate: releaseDate,
```

并在 `operator ==` 与 `Object.hash` 中把 `releaseDate` 放在 `rating` 与图片字段之间。`asFailed` 继续调用 `failed` 工厂，因此日期会按既有失败语义清除。

- [ ] **Step 4：格式化并运行模型测试**

Run: `D:\flutter\bin\dart.bat format lib\modules\cloud\cloud_resource_tmdb_record.dart test\cloud_resource_tmdb_record_test.dart`

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_tmdb_record_test.dart`

Expected: PASS。

- [ ] **Step 5：提交模型变更**

```powershell
git add -- lib/modules/cloud/cloud_resource_tmdb_record.dart test/cloud_resource_tmdb_record_test.dart
git commit -m "功能：保存网盘影视上映日期"
```

### Task 2：新增共享沉浸式媒体卡组件

**Files:**
- Create: `lib/features/library/presentation/immersive_media_card.dart`
- Modify: `test/library_presentation_components_test.dart`

- [ ] **Step 1：写共享卡片模式和信息层失败测试**

导入共享组件并新增测试，固定验证渐变、标签、动画和交互：

```dart
testWidgets('沉浸式卡片 always 模式始终显示信息和状态标签', (tester) async {
  var tapped = false;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 260,
        height: 380,
        child: ImmersiveMediaCard(
          overlayMode: ImmersiveMediaCardOverlayMode.always,
          cover: const ColoredBox(color: Colors.blue),
          title: '中文片名',
          subtitle: '真实文件名.mkv',
          details: '8.7 ★  ·  电影  ·  2025  ·  2.0 GB',
          badges: const <ImmersiveMediaCardBadge>[
            ImmersiveMediaCardBadge(
              icon: Icons.closed_caption_outlined,
              label: '有字幕',
            ),
            ImmersiveMediaCardBadge(
              icon: Icons.image_search_outlined,
              label: '已刮削',
            ),
          ],
          onTap: () => tapped = true,
        ),
      ),
    ),
  ));

  final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
  expect(opacity.opacity, 1);
  expect(opacity.duration, const Duration(milliseconds: 160));
  expect(opacity.curve, Curves.easeOut);
  expect(find.text('中文片名'), findsOneWidget);
  expect(find.text('真实文件名.mkv'), findsOneWidget);
  expect(find.textContaining('2025'), findsOneWidget);
  expect(find.text('有字幕'), findsOneWidget);
  expect(find.text('已刮削'), findsOneWidget);
  await tester.tap(find.byType(InkWell));
  expect(tapped, isTrue);
});
```

- [ ] **Step 2：运行目标测试确认导入或类型不存在**

Run: `D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart --plain-name "沉浸式卡片 always 模式始终显示信息和状态标签"`

Expected: FAIL，提示共享组件类型不存在。

- [ ] **Step 3：创建组件公开接口与渲染实现**

创建 `immersive_media_card.dart`，公开接口固定为：

```dart
import 'package:flutter/material.dart';

enum ImmersiveMediaCardOverlayMode { hover, always }

class ImmersiveMediaCardBadge {
  const ImmersiveMediaCardBadge({
    required this.icon,
    required this.label,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final bool loading;
}

class ImmersiveMediaCard extends StatefulWidget {
  const ImmersiveMediaCard({
    super.key,
    required this.cover,
    required this.title,
    required this.overlayMode,
    this.subtitle = '',
    this.details = '',
    this.badges = const <ImmersiveMediaCardBadge>[],
    this.trailing,
    this.loading = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
  });

  final Widget cover;
  final String title;
  final String subtitle;
  final String details;
  final List<ImmersiveMediaCardBadge> badges;
  final Widget? trailing;
  final bool loading;
  final ImmersiveMediaCardOverlayMode overlayMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  @override
  State<ImmersiveMediaCard> createState() => _ImmersiveMediaCardState();
}
```

实现时使用 `MouseRegion > Material > InkWell > Stack`；信息层必须是 `IgnorePointer > AnimatedOpacity`，透明度为 `always || hovered ? 1 : 0`，时长 160ms、曲线 `Curves.easeOut`。渐变固定使用 transparent、black 0.2、black 0.82 和 stops `[0, 0.42, 1]`。副标题和详情为空时完全省略，主标题两行，副标题一行，详情两行。标签使用白色半透明胶囊；`loading` 标签以 12×12 的白色 `CircularProgressIndicator` 替代图标。`widget.loading` 在最上层增加只覆盖本卡片的半透明遮罩和居中进度条；`trailing` 置于右上角且不被 `IgnorePointer` 包裹。

- [ ] **Step 4：格式化并运行共享组件测试**

Run: `D:\flutter\bin\dart.bat format lib\features\library\presentation\immersive_media_card.dart test\library_presentation_components_test.dart`

Run: `D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart --plain-name "沉浸式卡片 always 模式始终显示信息和状态标签"`

Expected: PASS。

- [ ] **Step 5：提交共享组件**

```powershell
git add -- lib/features/library/presentation/immersive_media_card.dart test/library_presentation_components_test.dart
git commit -m "功能：新增沉浸式媒体卡组件"
```

### Task 3：让本地媒体库复用共享组件且零行为回退

**Files:**
- Modify: `lib/features/library/presentation/library_media_grid.dart`
- Test: `test/library_presentation_components_test.dart`

- [ ] **Step 1：补强本地回归测试**

在既有 `LibraryMediaGrid` 测试组加入断言，确保复用后仍是 hover 模式、仍显示原标签和 Hero：

```dart
expect(find.byType(ImmersiveMediaCard), findsOneWidget);
expect(
  tester.widget<ImmersiveMediaCard>(find.byType(ImmersiveMediaCard)).overlayMode,
  ImmersiveMediaCardOverlayMode.hover,
);
expect(find.text('有字幕'), findsOneWidget);
expect(find.text('已刮削'), findsOneWidget);
```

现有测试继续验证桌面 3/4 列、Hero tag、初始透明度 0、160ms `easeOut`、左键、长按、右键、重排 hover 状态、加载和封面降级。

- [ ] **Step 2：运行本地组件测试建立绿色基线**

Run: `D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart`

Expected: 新增的共享类型断言在重构前 FAIL，其余既有测试仍 PASS。

- [ ] **Step 3：用共享组件替换 `_LibraryMediaTile` 的外壳和 overlay**

在 `library_media_grid.dart` 导入共享组件。保留 `_LibraryMediaTile` StatefulWidget 和 id 变化时清除 `_hovered` 的语义交给共享组件 key；将 tile 的 `build` 改为构造：

```dart
final details = <String>[
  widget.item.infoText,
  if (widget.item.mediaInfoText.isNotEmpty) widget.item.mediaInfoText,
  widget.item.modifiedText,
].where((part) => part.isNotEmpty).join('  ·  ');
final cover = widget.item.heroTag == null
    ? _cover(colors)
    : Hero(tag: widget.item.heroTag!, child: _cover(colors));
return ImmersiveMediaCard(
  cover: cover,
  title: widget.item.title,
  subtitle: widget.item.subtitle,
  details: details,
  overlayMode: ImmersiveMediaCardOverlayMode.hover,
  badges: <ImmersiveMediaCardBadge>[
    ImmersiveMediaCardBadge(
      icon: Icons.closed_caption_outlined,
      label: widget.item.hasSubtitle ? '有字幕' : '无字幕',
    ),
    ImmersiveMediaCardBadge(
      icon: Icons.image_search_outlined,
      label: widget.item.scrapeLabel,
      loading: widget.item.isScraping,
    ),
  ],
  onLongPress: widget.onShowActions == null
      ? null
      : () async => await widget.onShowActions!(widget.item),
  onSecondaryTap: widget.onShowActions == null
      ? null
      : () async => await widget.onShowActions!(widget.item),
  onTap: widget.onPlay == null
      ? null
      : () async => await widget.onPlay!(widget.item),
);
```

删除 tile 中重复的 `_overlay` 和 `_chip`，但保留 `_cover` 以及 `LibraryMediaCoverFallback` 的网络 → 本地 → 占位顺序和 `BoxFit.contain`。

- [ ] **Step 4：运行本地表现层全文件测试**

Run: `D:\flutter\bin\dart.bat format lib\features\library\presentation\library_media_grid.dart test\library_presentation_components_test.dart`

Run: `D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart`

Expected: PASS，包括原有悬停和封面回退用例。

- [ ] **Step 5：提交本地媒体库复用**

```powershell
git add -- lib/features/library/presentation/library_media_grid.dart test/library_presentation_components_test.dart
git commit -m "重构：本地媒体库复用海报卡片"
```

### Task 4：建立网盘卡片强类型展示模型

**Files:**
- Create: `lib/pages/cloud/resources/cloud_resource_card_view_data.dart`
- Create: `test/cloud_resource_card_view_data_test.dart`

- [ ] **Step 1：写分类、标题、详情和标签失败测试**

测试固定创建四类输入：独立视频、matched 目录、unmatched 目录、failed 独立视频。核心断言如下：

```dart
final matchedDirectory = CloudResourceCardViewData.fromEntry(
  entry: const CloudFileEntry(
    id: 'folder',
    remotePath: '/影视/目录原名',
    name: '目录原名',
    size: 0,
    modifiedAt: null,
    isDirectory: true,
  ),
  record: matchedRecord.withCustomTitle('自定义片名'),
  scraping: false,
  hasSubtitle: false,
);
expect(matchedDirectory.kind, CloudResourceCardKind.media);
expect(matchedDirectory.title, '自定义片名');
expect(matchedDirectory.subtitle, '目录原名');
expect(matchedDirectory.details, '8.7 ★  ·  电视剧  ·  2025');
expect(matchedDirectory.badges.map((badge) => badge.label), contains('已刮削'));

final plainDirectory = CloudResourceCardViewData.fromEntry(
  entry: directory,
  record: CloudResourceTmdbRecord.unmatched(...),
  scraping: false,
  hasSubtitle: false,
);
expect(plainDirectory.kind, CloudResourceCardKind.directory);

final video = CloudResourceCardViewData.fromEntry(
  entry: const CloudFileEntry(
    id: 'video',
    remotePath: '/影视/电影.mkv',
    name: '电影.mkv',
    size: 2147483648,
    modifiedAt: null,
    isDirectory: false,
  ),
  record: null,
  scraping: false,
  hasSubtitle: true,
);
expect(video.kind, CloudResourceCardKind.media);
expect(video.details, '2.0 GB');
expect(video.badges.map((badge) => badge.label), containsAll(<String>['有字幕', '未刮削']));
expect(video.badges.map((badge) => badge.label), isNot(contains('无字幕')));
```

用独立断言覆盖：matched=`已刮削`、unmatched=`未匹配`、unchecked/空记录=`未刮削`、failed=`刮削失败`、scraping 优先为带 loading 的 `刮削中`；主标题和真实名相同时 `subtitle == ''`；非法日期不输出年份；缺失字段不产生连续分隔符。

- [ ] **Step 2：运行新测试确认文件不存在**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_card_view_data_test.dart`

Expected: FAIL，提示导入文件或展示类型不存在。

- [ ] **Step 3：实现不可变展示数据和映射器**

公开类型使用以下接口：

```dart
enum CloudResourceCardKind { media, directory }

class CloudResourceCardViewData {
  const CloudResourceCardViewData({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.details,
    required this.badges,
    required this.isScraping,
    this.posterCachePath,
    this.posterUrl,
  });

  factory CloudResourceCardViewData.fromEntry({
    required CloudFileEntry entry,
    required CloudResourceTmdbRecord? record,
    required bool scraping,
    required bool hasSubtitle,
  });

  final CloudResourceCardKind kind;
  final String title;
  final String subtitle;
  final String details;
  final List<ImmersiveMediaCardBadge> badges;
  final bool isScraping;
  final String? posterCachePath;
  final String? posterUrl;
}
```

工厂规则必须逐项实现：

```dart
final matched = record?.status == CloudResourceTmdbStatus.matched;
final kind = !entry.isDirectory || matched
    ? CloudResourceCardKind.media
    : CloudResourceCardKind.directory;
final title = record?.effectiveTitle.trim().isNotEmpty == true
    ? record!.effectiveTitle.trim()
    : entry.name;
final subtitle = title == entry.name ? '' : entry.name;
```

详情按 rating、`电影/电视剧`、有效四位开头年份、独立视频格式化大小的顺序，以 `  ·  ` 连接。目录不加入大小。标签中只有 `hasSubtitle == true` 才加入“有字幕”，永不加入“无字幕”；刮削状态标签只对媒体卡生成。`badges` 使用 `List.unmodifiable` 冻结。海报字段仅在 matched 时复制。

- [ ] **Step 4：格式化并运行展示数据测试**

Run: `D:\flutter\bin\dart.bat format lib\pages\cloud\resources\cloud_resource_card_view_data.dart test\cloud_resource_card_view_data_test.dart`

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_card_view_data_test.dart`

Expected: PASS。

- [ ] **Step 5：提交展示模型**

```powershell
git add -- lib/pages/cloud/resources/cloud_resource_card_view_data.dart test/cloud_resource_card_view_data_test.dart
git commit -m "功能：整理网盘海报卡展示数据"
```

### Task 5：重构网盘网格为沉浸式媒体卡与普通目录卡

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_grid.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1：写响应式、媒体卡和目录卡失败测试**

将原“卡片显示海报区域”用例扩展为以下断言：

```dart
expect(find.byType(ImmersiveMediaCard), findsOneWidget);
expect(
  tester.widget<ImmersiveMediaCard>(find.byType(ImmersiveMediaCard)).overlayMode,
  ImmersiveMediaCardOverlayMode.always,
);
expect(find.text('中文片名'), findsOneWidget);
expect(find.text('动漫'), findsOneWidget);
expect(find.textContaining('8.7 ★'), findsOneWidget);
expect(find.text('已刮削'), findsOneWidget);
```

新增混合目录用例，传入“未匹配目录 + 独立视频”，断言只有一个 `ImmersiveMediaCard`，目录仍含 `Icons.folder_outlined`。新增三种宽度用例，读取 `SliverGridDelegateWithFixedCrossAxisCount`：宽 620 为 2 列、宽 800 为 3 列、宽 1100 为 4 列，`childAspectRatio == 0.68`、横纵间距均为 12。

- [ ] **Step 2：运行相关页面测试确认新期望失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart --plain-name "卡片显示海报区域、中文标题、评分和原文件名"`

Expected: FAIL，当前网盘卡还不是共享 always 模式。

- [ ] **Step 3：按 ViewData 分流构建卡片**

为 `CloudResourcesGrid` 新增：

```dart
final Set<String> subtitleVideoKeys;
```

构造函数默认要求页面传入。每个条目生成稳定键后构造 `CloudResourceCardViewData.fromEntry`，并用 `ValueKey<String>(key)` 保持状态。`kind == media` 时构造 `ImmersiveMediaCard`：

```dart
ImmersiveMediaCard(
  cover: _mediaPoster(context, entry, data),
  title: data.title,
  subtitle: data.subtitle,
  details: data.details,
  badges: data.badges,
  loading: data.isScraping,
  overlayMode: ImmersiveMediaCardOverlayMode.always,
  trailing: _resourceMenu(context),
  onTap: onTap,
)
```

本地缓存存在时先 `Image.file(... fit: BoxFit.cover)`，失败回退网络海报；网络海报用 `TmdbMatchSheet.imageUrl(..., size: 'w500')` 和 `Image.network(... fit: BoxFit.cover)`，失败回退电影渐变占位。注意缓存图片 `errorBuilder` 必须调用网络层而不是直接占位，保证缓存 → 网络 → 占位完整链路。媒体占位使用 `Icons.movie_outlined`；普通目录单独使用现有渐变、`Icons.folder_outlined`、目录名称与右上菜单，不进入 `ImmersiveMediaCard`。

- [ ] **Step 4：实现 2/3/4 列和统一比例**

`LayoutBuilder` 中固定：

```dart
final columns = constraints.maxWidth < 650
    ? 2
    : constraints.maxWidth < 1000
        ? 3
        : 4;
final width = (constraints.maxWidth - 24 - 12 * (columns - 1)) / columns;
final extent = (width / 0.68).clamp(320.0, 680.0);
```

网格 padding 12、横纵间距 12、`childAspectRatio: 0.68`，有限宽度下设置 `mainAxisExtent: extent`。媒体卡和目录卡使用相同 grid cell，不在目录卡外增加不同高度信息区。

- [ ] **Step 5：格式化并运行页面测试**

Run: `D:\flutter\bin\dart.bat format lib\pages\cloud\resources\cloud_resources_grid.dart test\cloud_resources_page_test.dart`

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart`

Expected: PASS，点击目录、播放、菜单、标题修改、刮削和重新匹配旧用例无回退。

- [ ] **Step 6：提交网盘网格重构**

```powershell
git add -- lib/pages/cloud/resources/cloud_resources_grid.dart test/cloud_resources_page_test.dart
git commit -m "功能：网盘资源使用沉浸式海报卡"
```

### Task 6：把现有同名字幕状态传给网盘卡片

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1：写有字幕与未知字幕状态失败测试**

构造同目录下 `电影.mkv`、`电影.ass` 和 `另一部.mp4`，页面过滤字幕后仍应给第一张视频卡显示“有字幕”，且整个页面不出现“无字幕”：

```dart
expect(find.text('有字幕'), findsOneWidget);
expect(find.text('无字幕'), findsNothing);
```

同时保留播放用例，点击 `电影.mkv` 后断言 `CloudPlaybackTarget.subtitleRemoteId` 与 `subtitleRemotePath` 仍指向原字幕，证明状态计算没有改变播放数据流。

- [ ] **Step 2：运行字幕用例确认标签缺失**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart --plain-name "同名字幕视频卡显示有字幕且不误报无字幕"`

Expected: FAIL，当前网格没有字幕集合输入。

- [ ] **Step 3：复用 `_matchingSubtitle` 生成稳定键集合**

在页面 build 前为当前完整 `_controller.entries` 计算：

```dart
Set<String> _subtitleVideoKeys(String sourceId) => _controller.entries
    .where((entry) => !entry.isDirectory && _matchingSubtitle(entry) != null)
    .map((entry) => cloudResourceTmdbKey(
          sourceId: sourceId,
          remoteId: entry.id,
          remotePath: entry.remotePath,
        ))
    .toSet();
```

把结果作为 `subtitleVideoKeys` 传给 `CloudResourcesGrid`。只使用当前已加载条目，不调用 list、resolve、download 或递归扫描。

- [ ] **Step 4：运行页面测试和夸克播放回归测试**

Run: `D:\flutter\bin\dart.bat format lib\pages\cloud\resources\cloud_resources_page.dart test\cloud_resources_page_test.dart`

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart test\quark_cloud_drive_client_test.dart test\cloud_playback_resolver_test.dart`

Expected: PASS。

- [ ] **Step 5：提交字幕标签数据流**

```powershell
git add -- lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_resources_page_test.dart
git commit -m "功能：网盘视频卡显示已确认字幕"
```

### Task 7：补齐图片降级、键盘和局部加载回归

**Files:**
- Modify: `test/cloud_resources_page_test.dart`
- Modify: `test/library_presentation_components_test.dart`
- Modify: `lib/features/library/presentation/immersive_media_card.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_grid.dart`

- [ ] **Step 1：写剩余边界测试**

用 `MemoryImage`/失败 `ImageProvider` 或可注入 cover widget 验证共享组件不阻断交互；针对网盘卡新增：

```dart
expect(tester.widget<Image>(find.byKey(ValueKey('tmdb-poster-${record.stableKey}'))).fit, BoxFit.cover);
expect(find.byKey(const ValueKey<String>('cloud-media-placeholder')), findsOneWidget);
```

构造两个媒体项且仅把一个稳定键放入 `scrapingKeys`，断言只有目标卡包含 `CircularProgressIndicator` 与“刮削中”，另一张仍可点击。使用 `tester.sendKeyEvent(LogicalKeyboardKey.enter)` 验证获得焦点的卡触发主操作；三点按钮仍可单独获得焦点并打开原三项菜单。

- [ ] **Step 2：运行边界用例确认失败点**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart test\library_presentation_components_test.dart`

Expected: 至少新增的占位 key、局部加载或键盘行为断言 FAIL。

- [ ] **Step 3：最小修复边界行为**

给媒体占位加 `const ValueKey<String>('cloud-media-placeholder')`；共享 `InkWell` 外使用可聚焦 `FocusableActionDetector` 或 Material/InkWell 默认键盘语义，保证 Enter/Space 触发 `onTap`，菜单焦点不冒泡触发卡片。加载遮罩保持在共享卡片 Stack 内，并让右上菜单位于遮罩之上以便重试或查看操作。图片失败只返回下一层 Widget，不更改 record 或回调。

- [ ] **Step 4：运行全部表现层和网盘资源测试**

Run: `D:\flutter\bin\dart.bat format lib\features\library\presentation\immersive_media_card.dart lib\pages\cloud\resources\cloud_resources_grid.dart test\library_presentation_components_test.dart test\cloud_resources_page_test.dart`

Run: `D:\flutter\bin\flutter.bat test test\cloud_resource_tmdb_record_test.dart test\cloud_resource_card_view_data_test.dart test\library_presentation_components_test.dart test\cloud_resources_page_test.dart`

Expected: PASS。

- [ ] **Step 5：提交边界回归**

```powershell
git add -- lib/features/library/presentation/immersive_media_card.dart lib/pages/cloud/resources/cloud_resources_grid.dart test/library_presentation_components_test.dart test/cloud_resources_page_test.dart
git commit -m "测试：完善网盘海报卡交互降级"
```

### Task 8：更新 2.1.12 版本和用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Test: `test/version_consistency_test.dart`
- Test: `test/version_history_current_test.dart`

- [ ] **Step 1：先更新版本一致性期望输入**

不硬编码修改测试逻辑；现有测试会从 `pubspec.yaml` 读取版本并验证其余文件。先把 `pubspec.yaml` 改为：

```yaml
version: 2.1.12+20112

msix_config:
  msix_version: 2.1.12.0
```

- [ ] **Step 2：运行版本一致性测试确认其余文件未同步**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart`

Expected: FAIL，指出 AppVersion、更新历史或发布文案仍为 2.1.11。

- [ ] **Step 3：同步所有版本和普通用户文案**

`AppVersion.current` 改为 `2.1.12`。在 `VersionHistory.versions` 首项加入 2026-07-19 的 2.1.12，changes 精确写为：

```dart
const <String>[
  '网盘资源中的已刮削电影和剧集现已使用沉浸式大海报卡片，标题与状态更清晰。',
  '独立视频统一显示媒体卡，普通未匹配文件夹仍保留目录样式，浏览和播放方式不变。',
  '卡片可显示 TMDB 评分、类型、年份、文件大小和已确认的字幕状态。',
  '海报或 TMDB 暂时不可用时仍可浏览网盘和播放视频，不会修改任何网盘文件。',
]
```

`RELEASE_NOTES.md` 顶部加入 `2.1.12+20112` 与 MSIX `2.1.12.0`；`UPDATE_DIALOG_COPY.md` 当前版本、安装包、标题和正文同步；README 网盘功能补充“沉浸式海报卡会保留真实网盘名称，不会重命名远程文件”。

- [ ] **Step 4：运行版本测试**

Run: `D:\flutter\bin\dart.bat format lib\core\app_version.dart lib\utils\version_history.dart`

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart`

Expected: PASS。

- [ ] **Step 5：提交版本文案**

```powershell
git add -- pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md
git commit -m "发布：更新看影音 2.1.12 文案"
```

### Task 9：完整验证、Windows Release 和签名 MSIX 交付

**Files:**
- Verify only: all files changed in Tasks 1–8
- Output: `build/windows/x64/runner/Release/`
- Output: generated signed `.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.12.msix`

- [ ] **Step 1：检查工作区和关键 diff，排除用户文件**

Run: `git status --short`

Run: `git diff --check`

Run: `git diff --stat HEAD~8..HEAD`

Expected: 没有空白错误；`.learnings/ERRORS.md` 和 `.learnings/LEARNINGS.md` 仍只作为未暂存用户改动存在，任何提交都不包含它们。

- [ ] **Step 2：执行全量测试**

Run: `D:\flutter\bin\flutter.bat test`

Expected: 全部测试 PASS，无失败或跳过的关键回归。

- [ ] **Step 3：执行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze`

Expected: `No issues found!`。

- [ ] **Step 4：构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release`

Expected: 生成 `build\windows\x64\runner\Release\kanyingyin.exe`，退出码 0。

- [ ] **Step 5：按项目 MSIX skill 生成签名安装包**

先读取 `C:\Users\asus\.codex\skills\flutter-windows-msix-packaging\SKILL.md`，按其中项目脚本、证书和清单验证流程执行，不临时改变包标识、发布者或架构。生成后验证清单版本为 `2.1.12.0`，包标识为 `com.kanyingyin.player`，签名状态为 `Valid`。

- [ ] **Step 6：复制并校验桌面交付物**

将最终签名包复制为：

```text
C:\Users\asus\Desktop\看影音-2.1.12.msix
```

Run: `Get-AuthenticodeSignature -LiteralPath 'C:\Users\asus\Desktop\看影音-2.1.12.msix' | Format-List Status,StatusMessage,SignerCertificate`

Run: `Get-FileHash -Algorithm SHA256 -LiteralPath 'C:\Users\asus\Desktop\看影音-2.1.12.msix'`

Expected: `Status: Valid`，文件存在且 SHA-256 非空。

- [ ] **Step 7：提交最终必要修正并核验提交范围**

若构建或打包产生了必须进入仓库的本轮配置修正，只暂存这些精确文件并提交：

```powershell
git status --short
git diff --cached --name-only
git commit -m "构建：完成看影音 2.1.12 交付"
```

若没有必要的仓库修正，则不创建空提交。最终 `git status --short` 只允许保留用户原有 `.learnings` 修改和明确的构建忽略文件。

## 计划自查

- 规格覆盖：Task 1 覆盖年份；Tasks 2–3 覆盖共享视觉和本地回归；Tasks 4–5 覆盖分类、标题、详情、标签、海报降级与网格；Task 6 覆盖字幕；Task 7 覆盖局部加载、键盘和图片异常；Tasks 8–9 覆盖版本、测试、Release、签名 MSIX 和桌面交付。
- 非目标保护：计划没有网盘重命名、移动、删除、递归字幕扫描、播放地址解析或 TMDB API 流程改动。
- 类型一致性：共享类型统一为 `ImmersiveMediaCard`、`ImmersiveMediaCardOverlayMode`、`ImmersiveMediaCardBadge`；网盘映射统一为 `CloudResourceCardViewData.fromEntry` 和 `CloudResourceCardKind`；字幕集合统一为 `Set<String> subtitleVideoKeys`。
- 完整性检查：每个代码修改步骤都有明确接口、实际行为、预期结果和验证命令。
- 执行方式：用户已禁止子智能体，因此实施时固定使用 `superpowers:executing-plans` 在当前任务内执行，不采用推荐的子智能体方案。
