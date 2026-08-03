# 网盘标签筛选与媒体库边界实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让本地媒体库只显示本地资源，并在网盘媒体库当前来源名称右侧提供来源隔离的 TMDB 类型多选筛选。

**Architecture:** 使用纯函数 `CloudGenreFilter` 负责网盘标签去重、失效选择收敛和 OR 筛选，`CloudResourcesController` 负责当前来源的选择状态与集合失效通知，页面只负责菜单呈现。本地媒体库改用只包含本地条目的 `localMediaLibrary`，不再把 `combinedMediaLibrary` 的网盘系列用于计数、空状态、标签或列表。

**Tech Stack:** Flutter 3.41.9、Dart、Material、MobX、Flutter Modular、`flutter_test`、Windows x64/MSIX。

---

## 文件结构

- 新建 `lib/features/cloud/application/cloud_genre_filter.dart`：无 UI 依赖的网盘标签查询策略。
- 新建 `test/cloud_genre_filter_test.dart`：标签排序、OR 匹配和失效选择测试。
- 修改 `lib/pages/cloud/resources/cloud_resources_controller.dart`：保存当前来源标签状态，在分组前筛选索引并在来源/索引变化时清理状态。
- 修改 `test/cloud_resources_controller_test.dart`：验证来源隔离、搜索/目录组合和来源切换。
- 修改 `lib/pages/cloud/resources/cloud_resources_page.dart`：在来源名称右侧增加标签菜单。
- 修改 `test/cloud_resources_page_test.dart`：验证入口位置、多选、清除和空标签禁用状态。
- 修改 `lib/pages/local/local_controller.dart`、`lib/pages/local/local_controller.g.dart`：提供纯本地媒体库并让本地入口计数只统计本地视频。
- 修改 `lib/pages/local/library_sheet.dart`：移除来源菜单和网盘系列渲染，标签只使用本地系列。
- 修改 `test/cloud_library_integration_test.dart`、`test/local_controller_test.dart`：验证本地页面不再出现网盘资源。
- 修改 `pubspec.yaml`、`lib/core/app_version.dart`、`README.md`、`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`lib/utils/version_history.dart` 及版本契约测试：发布 Windows `2.1.105` 测试版。

### Task 1: 建立纯网盘标签筛选策略

**Files:**
- Create: `lib/features/cloud/application/cloud_genre_filter.dart`
- Create: `test/cloud_genre_filter_test.dart`

- [ ] **Step 1: 写失败测试**

创建测试，使用两个来源的 `CloudMediaIndexItem`，断言只从传入的当前来源项目生成去重排序标签，并验证多选为 OR、无标签项目在筛选启用时被排除：

```dart
test('标签去重排序且多选按任一匹配', () {
  const filter = CloudGenreFilter();
  final items = <CloudMediaIndexItem>[
    _item('a', const <String>['科幻', '动作', '科幻']),
    _item('b', const <String>['纪录片']),
    _item('c', const <String>[]),
  ];

  expect(filter.availableGenres(items), <String>['动作', '科幻', '纪录片']);
  expect(
    filter
        .apply(items, const <String>{'科幻', '纪录片'})
        .map((item) => item.remoteId),
    <String>['a', 'b'],
  );
});

test('索引变化后移除已经不存在的选择', () {
  const filter = CloudGenreFilter();
  expect(
    filter.retainAvailable(
      const <String>{'科幻', '动画'},
      const <String>['科幻', '剧情'],
    ),
    const <String>{'科幻'},
  );
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_genre_filter_test.dart`

Expected: FAIL，提示 `CloudGenreFilter` 尚不存在。

- [ ] **Step 3: 实现最小纯策略**

```dart
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';

class CloudGenreFilter {
  const CloudGenreFilter();

  List<String> availableGenres(Iterable<CloudMediaIndexItem> items) {
    final genres = <String>{};
    for (final item in items) {
      genres.addAll(item.tmdbGenres.map((value) => value.trim()).where(
            (value) => value.isNotEmpty,
          ));
    }
    return genres.toList(growable: false)..sort();
  }

  List<CloudMediaIndexItem> apply(
    Iterable<CloudMediaIndexItem> items,
    Set<String> selectedGenres,
  ) {
    if (selectedGenres.isEmpty) return items.toList(growable: false);
    return items
        .where((item) => item.tmdbGenres.any(selectedGenres.contains))
        .toList(growable: false);
  }

  Set<String> retainAvailable(
    Set<String> selectedGenres,
    Iterable<String> availableGenres,
  ) => selectedGenres.intersection(availableGenres.toSet());
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_genre_filter_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add -- lib/features/cloud/application/cloud_genre_filter.dart test/cloud_genre_filter_test.dart
git commit -m "功能：新增网盘标签筛选策略"
```

### Task 2: 将标签状态接入当前网盘控制器

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `test/cloud_resources_controller_test.dart`

- [ ] **Step 1: 写来源隔离和组合条件失败测试**

在控制器夹具中为 `source-a` 写入“科幻”和“纪录片”索引，为 `source-b` 写入“动画”索引。断言：

```dart
expect(controller.availableGenres, <String>['科幻', '纪录片']);
controller.toggleGenre('科幻');
expect(controller.selectedGenres, const <String>{'科幻'});
expect(controller.collection.groups.map((group) => group.displayName),
    contains('科幻作品'));
expect(controller.collection.groups.map((group) => group.displayName),
    isNot(contains('纪录片作品')));

controller.setQuery('不存在于科幻作品的词');
expect(controller.collection.groups, isEmpty);

await controller.selectSource('source-b');
expect(controller.selectedGenres, isEmpty);
expect(controller.availableGenres, <String>['动画']);
```

再增加目录范围用例，确认标签不会绕过 `currentDirectoryScope`。

- [ ] **Step 2: 运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_controller_test.dart`

Expected: FAIL，控制器尚无 `availableGenres`、`selectedGenres` 和 `toggleGenre`。

- [ ] **Step 3: 添加控制器状态和命令**

```dart
final CloudGenreFilter _genreFilter = const CloudGenreFilter();
final Set<String> _selectedGenres = <String>{};

Set<String> get selectedGenres => Set<String>.unmodifiable(_selectedGenres);

List<String> get availableGenres =>
    _genreFilter.availableGenres(_indexedItems.values);

void toggleGenre(String genre) {
  final normalized = genre.trim();
  if (normalized.isEmpty || !availableGenres.contains(normalized)) return;
  if (!_selectedGenres.remove(normalized)) _selectedGenres.add(normalized);
  _invalidateCollection();
  _notify();
}

void clearGenres() {
  if (_selectedGenres.isEmpty) return;
  _selectedGenres.clear();
  _invalidateCollection();
  _notify();
}
```

在 `_selectSource` 开始处清空 `_selectedGenres`。在 `_loadSnapshot` 更新 `_indexedItems` 后调用私有 `_reconcileGenres()`，将选择集合与新 `availableGenres` 求交；集合变化时使作品缓存失效。

- [ ] **Step 4: 在作品分组前应用标签**

将 `visibleIndexedItems` 的来源集合先经过 `_genreFilter.apply`，再应用隐藏和目录范围。旧版 entries 分组分支通过 `_indexedItemFor(entry)` 使用同一匹配规则，确保没有作品身份数据时行为一致：

```dart
bool _matchesSelectedGenres(CloudMediaIndexItem item) =>
    _selectedGenres.isEmpty ||
    item.tmdbGenres.any(_selectedGenres.contains);
```

搜索继续由 `CloudResourceCollectionGrouper.query` 处理，因此搜索、目录与标签自然为 AND。

- [ ] **Step 5: 运行控制器测试确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_controller_test.dart test\cloud_resources_flat_library_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交**

```powershell
git add -- lib/pages/cloud/resources/cloud_resources_controller.dart test/cloud_resources_controller_test.dart
git commit -m "功能：限定当前网盘标签筛选"
```

### Task 3: 在网盘名称右侧增加标签菜单

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 写界面失败测试**

在包含标签索引的页面夹具中，取得来源选择器与标签入口位置，验证标签入口紧随来源选择器；再选择两个标签并清除：

```dart
final sourceSelector = find.byKey(
  const ValueKey<String>('cloud-source-selector'),
);
final genreFilter = find.byKey(
  const ValueKey<String>('cloud-genre-filter'),
);
expect(tester.getTopLeft(genreFilter).dx,
    greaterThan(tester.getTopRight(sourceSelector).dx));

await tester.tap(find.byTooltip('筛选 TMDB 类型'));
await tester.pumpAndSettle();
expect(find.byType(CheckedPopupMenuItem<String>), findsWidgets);
await tester.tap(find.text('科幻'));
await tester.pumpAndSettle();
expect(find.text('纪录片作品'), findsNothing);
```

另写当前来源无标签时入口存在但 `enabled == false` 的断言。

- [ ] **Step 2: 运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart`

Expected: FAIL，找不到 `cloud-genre-filter`。

- [ ] **Step 3: 在来源下拉右侧添加稳定尺寸菜单**

在 `_toolbar` 的 `DropdownButtonHideUnderline` 后插入固定 `40x40` 的 `PopupMenuButton<String>`，使用 `Icons.sell_outlined`，活动时用 `Badge.count` 显示数量：

```dart
const SizedBox(width: 4),
SizedBox.square(
  dimension: 40,
  child: PopupMenuButton<String>(
    key: const ValueKey<String>('cloud-genre-filter'),
    tooltip: '筛选 TMDB 类型',
    enabled: selected != null && _controller.availableGenres.isNotEmpty,
    onSelected: (value) {
      if (value == '__clear__') {
        _controller.clearGenres();
      } else {
        _controller.toggleGenre(value);
      }
    },
    itemBuilder: (_) => <PopupMenuEntry<String>>[
      if (_controller.selectedGenres.isNotEmpty)
        const PopupMenuItem<String>(
          value: '__clear__',
          child: Text('清除'),
        ),
      ..._controller.availableGenres.map(
        (genre) => CheckedPopupMenuItem<String>(
          value: genre,
          checked: _controller.selectedGenres.contains(genre),
          child: Text(genre),
        ),
      ),
    ],
    icon: _controller.selectedGenres.isEmpty
        ? const Icon(Icons.sell_outlined)
        : Badge.count(
            count: _controller.selectedGenres.length,
            child: const Icon(Icons.sell_outlined),
          ),
  ),
),
```

- [ ] **Step 4: 运行页面测试确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart`

Expected: PASS，且既有工具栏、扫描、刮削、隐藏资源测试不回归。

- [ ] **Step 5: 提交**

```powershell
git add -- lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_resources_page_test.dart
git commit -m "界面：在网盘名称旁增加标签筛选"
```

### Task 4: 让本地媒体库严格只显示本地资源

**Files:**
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `lib/pages/local/local_controller.g.dart`
- Modify: `lib/pages/local/library_sheet.dart`
- Modify: `test/cloud_library_integration_test.dart`
- Modify: `test/local_controller_test.dart`

- [ ] **Step 1: 将现有云系列展示测试改为边界失败测试**

保留一个本地系列和一个网盘系列，断言本地媒体库只显示本地标题，并且不存在来源筛选入口、网盘标题和网盘名称：

```dart
expect(find.text('本地作品'), findsOneWidget);
expect(find.text('中文网盘片名 S01'), findsNothing);
expect(find.text('家庭网盘'), findsNothing);
expect(find.byTooltip('筛选媒体来源'), findsNothing);
expect(find.byTooltip('筛选 TMDB 类型'), findsOneWidget);
```

将原“类型菜单支持多选”夹具改为本地 `TmdbMetadata.genres`，并添加网盘独有“纪录片”标签，断言菜单不出现该标签。

- [ ] **Step 2: 添加控制器计数失败测试**

```dart
controller.cloudLibraryItems.add(_cloudItem());
expect(controller.mediaLibraryVideoCount, 0);
controller.localLibraryItems.add(_localItem());
expect(controller.mediaLibraryVideoCount, 1);
```

- [ ] **Step 3: 运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_library_integration_test.dart test\local_controller_test.dart`

Expected: FAIL，当前页面和计数仍包含网盘资源。

- [ ] **Step 4: 提供纯本地媒体库数据**

在 `LocalController` 中保留 `combinedMediaLibrary` 供非本地页数据流程使用，但新增并让 UI 使用：

```dart
CloudMediaLibrary get localMediaLibrary =>
    const CloudMediaLibraryAggregator().build(
      localItems: localLibraryItems,
      cloudItems: const <CloudMediaIndexItem>[],
      cloudSources: const <CloudSource>[],
    );

@computed
int get mediaLibraryVideoCount => localLibraryItems.length;
```

运行代码生成器，仅接受 `local_controller.g.dart` 对该 computed getter 的预期更新：

Run: `D:\flutter\bin\dart.bat run build_runner build --delete-conflicting-outputs`

- [ ] **Step 5: 删除本地页面的网盘呈现分支**

`LibrarySheetContent` 使用 `controller.localMediaLibrary`。删除 `selectedLibrarySourceId`、`cloudSeries`、`_cloudSeriesTile` 及来源 `PopupMenuButton` 的页面引用。标签行只根据本地系列计算：

```dart
final library = widget.controller.localMediaLibrary;
if (library.series.isEmpty) return _empty(context, cs, tt);
final genreFiltered = _libraryQuery.apply(
  series: library.series,
  sourceId: 'local',
  selectedGenres: _selectedGenres,
);
final localSeriesKeys = genreFiltered
    .map((item) => item.seriesKey)
    .toSet();
final all = widget.controller.localLibrarySeries
    .where((item) => localSeriesKeys.contains(item.key))
    .toList(growable: false);
```

标题视频计数改用 `localLibraryItems.length`，类型菜单继续使用本地 `library.series`。清理仅供云系列卡片使用的私有方法和 import，确保 `flutter analyze` 无未使用成员。

- [ ] **Step 6: 运行测试确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_library_integration_test.dart test\local_controller_test.dart`

Expected: PASS；本地页不显示网盘资源，本地类型多选仍按 OR 工作。

- [ ] **Step 7: 提交**

```powershell
git add -- lib/pages/local/local_controller.dart lib/pages/local/local_controller.g.dart lib/pages/local/library_sheet.dart test/cloud_library_integration_test.dart test/local_controller_test.dart
git commit -m "修复：本地媒体库仅显示本地资源"
```

### Task 5: 更新 Windows 测试版版本与用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/release_config_contract_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 记录更新前安装版本**

Run: `Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name,Version,Architecture,InstallLocation`

Expected: 明确记录当前安装版本；未安装时明确记录“未安装”。

- [ ] **Step 2: 先更新版本契约测试为 2.1.105**

将测试期望改为：

```dart
expect(appVersion, '2.1.105');
expect(pubspecVersion, '2.1.105+20105');
expect(msixVersion, '2.1.105.0');
```

- [ ] **Step 3: 运行版本测试确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\identity_v2_zero_residue_test.dart test\release_config_contract_test.dart test\version_consistency_test.dart test\version_history_current_test.dart`

Expected: FAIL，实际版本仍为 `2.1.104`。

- [ ] **Step 4: 更新版本和面向用户的说明**

- `pubspec.yaml`: `version: 2.1.105+20105`、`msix_version: 2.1.105.0`。
- `lib/core/app_version.dart`: 当前版本 `2.1.105`。
- 发布文案说明“本地媒体库恢复为仅显示本地资源”“网盘媒体库支持当前来源标签筛选”“本轮仅 Windows 测试版，未测试安卓”。
- 不修改 Android Gradle 版本，不生成安卓交付物。

- [ ] **Step 5: 运行版本测试确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\identity_v2_zero_residue_test.dart test\release_config_contract_test.dart test\version_consistency_test.dart test\version_history_current_test.dart`

Expected: PASS。

- [ ] **Step 6: 提交**

```powershell
git add -- pubspec.yaml lib/core/app_version.dart README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/utils/version_history.dart test/identity_v2_zero_residue_test.dart test/release_config_contract_test.dart test/version_consistency_test.dart test/version_history_current_test.dart
git commit -m "发布：准备2.1.105媒体库筛选测试版"
```

### Task 6: Windows-only 回归、构建与 MSIX 交付

**Files:**
- Verify only; do not modify tracked source unless a verification failure requires a scoped fix.

- [ ] **Step 1: 检查提交边界**

Run: `git status --short`

Run: `git diff --check`

Expected: 工作树干净，无空白错误；只存在本计划相关提交。

- [ ] **Step 2: 执行非安卓专属测试**

用 PowerShell 枚举 `test/**/*_test.dart`，排除完整路径匹配 `(?i)android` 的文件，每批最多 20 个文件执行：

```powershell
$testFiles = @(Get-ChildItem test -Recurse -Filter *_test.dart -File |
  Where-Object { $_.FullName -notmatch '(?i)android' } |
  ForEach-Object { $_.FullName })
for ($start = 0; $start -lt $testFiles.Count; $start += 20) {
  $end = [Math]::Min($start + 19, $testFiles.Count - 1)
  $batch = $testFiles[$start..$end]
  & D:\flutter\bin\flutter.bat test --no-pub @batch
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

Expected: 所有非安卓专属批次 PASS。不要运行安卓专属测试、APK、AAB、模拟器或真机步骤。

- [ ] **Step 3: 静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`。

- [ ] **Step 4: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: `build\windows\x64\runner\Release\kanyingyin.exe` 和 `data\app.so` 为本轮新产物。

- [ ] **Step 5: 生成签名 MSIX**

先确保看影音进程已退出，再运行：

Run: `.\tool\windows\build_signed_release.ps1`

Expected: 生成并验签 `build\windows\x64\runner\Release\kanyingyin.msix`，复制为 `C:\Users\asus\Desktop\看影音-2.1.105.msix`，同时生成异机安装 ZIP。

- [ ] **Step 6: 独立验证交付物**

直接读取 MSIX 中 `AppxManifest.xml`，确认：

```text
Name=com.kanyingyin.player
Version=2.1.105.0
ProcessorArchitecture=x64
Publisher=CN=KanYingYin
```

再执行 `Get-AuthenticodeSignature`、源与桌面 `Get-FileHash -Algorithm SHA256`，要求签名 `Valid` 且哈希一致。

- [ ] **Step 7: 核对安装和 Git 状态**

再次运行 `Get-AppxPackage -Name com.kanyingyin.player`。本计划不主动执行 `Add-AppxPackage`；如果系统安装版本发生变化，记录部署日志和实际状态，不猜测触发来源。

Run: `git status --short`

Expected: 工作树干净。不要推送或合并，除非用户另行明确要求。
