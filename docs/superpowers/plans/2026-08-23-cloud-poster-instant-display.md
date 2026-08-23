# 网盘海报即时显示实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让所有已正确刮削的网盘资源在任意展示界面优先复用本地海报缓存，并在扫描、刷新、刮削和页面切换时不再出现白色封面或无意义的整墙重载。

**Architecture:** 新增统一的 `CloudPosterImage` 组件，集中处理本地缓存优先、TMDB 网络回退、首帧占位、旧帧保留和同身份不重载；首屏只预解码有限数量的本地网盘海报。网盘媒体库通过稳定 Key 保留海报墙子树，分类、选集和历史入口只把网盘资源迁移到统一组件，本地资源保持原实现。

**Tech Stack:** Flutter 3.41.9、Dart 3.11、Material 3、`Image.file`/`ImageCache`、`TmdbImageClient`、Flutter widget tests、PowerShell、Inno Setup 6。

---

## 文件结构

- Create: `lib/widgets/cloud_poster_image.dart` — 统一网盘海报组件、默认占位和本地缓存预热函数。
- Create: `test/cloud_poster_image_test.dart` — 本地优先、同身份不重载、旧画面保留、网络回退和占位测试。
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart` — 网盘媒体库改用统一组件并预热首屏缓存。
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart` — 为动态进度区、搜索栏和海报墙添加稳定 Key。
- Modify: `test/cloud_resources_page_test.dart` — 验证扫描/刮削状态变化不销毁海报墙和卡片。
- Modify: `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`、`test/cloud_resource_episode_sheet_test.dart` — 季度与系列海报统一。
- Modify: `lib/features/library/presentation/media_category_page.dart`、`test/media_category_page_test.dart` — 仅网盘分类卡片统一。
- Modify: `lib/features/history/presentation/history_page.dart`；Create: `test/history_cloud_poster_contract_test.dart` — 仅网盘历史记录统一。
- Modify: 版本、发布文案和对应契约测试 — 同步 Windows 测试版 `2.1.166+20166`。

### Task 0: 记录交付前 Windows 与 Git 基线

**Files:**
- Inspect: `D:/看影音/kanyingyin.exe`
- Inspect: Windows Inno 卸载注册表、AppX/MSIX 状态、`pubspec.yaml`

- [ ] **Step 1: 查询当前安装状态和真实产品版本**

```powershell
$roots = @(
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$inno = Get-ItemProperty $roots -ErrorAction SilentlyContinue |
  Where-Object DisplayName -eq '看影音' |
  Select-Object DisplayName, DisplayVersion, InstallLocation, UninstallString
$exe = Get-Item -LiteralPath 'D:\看影音\kanyingyin.exe' -ErrorAction SilentlyContinue
$msix = Get-AppxPackage -Name 'com.kanyingyin.player' -ErrorAction SilentlyContinue |
  Select-Object Name, Version, InstallLocation
[pscustomobject]@{
  Inno = $inno
  ExePath = $exe.FullName
  ExeProductVersion = $exe.VersionInfo.ProductVersion
  LegacyMsix = $msix
} | Format-List
```

Expected: 记录实际 Inno、主程序产品版本和旧 MSIX；若任何已安装版本高于 `2.1.165`，目标版本改为严格更高的下一个补丁版本。

- [ ] **Step 2: 核对工作区并提交计划**

Run: `git status --short`

Expected: 除本计划外没有未提交修改。然后运行：

```powershell
git add -- docs/superpowers/plans/2026-08-23-cloud-poster-instant-display.md
git commit -m "文档：规划网盘海报即时显示"
```

### Task 1: 用测试定义统一网盘海报组件

**Files:**
- Create: `test/cloud_poster_image_test.dart`
- Create: `lib/widgets/cloud_poster_image.dart`
- Modify if required: `lib/widgets/tmdb_network_image.dart`、`test/tmdb_network_image_test.dart`

- [ ] **Step 1: 写本地缓存优先、占位和同身份测试**

测试用 `Directory.systemTemp.createTemp` 创建临时 PNG，并用 `addTearDown` 清理。核心断言：

```dart
testWidgets('有效网盘缓存直接显示且不请求网络', (tester) async {
  final file = await writePoster('cached.png');
  var requests = 0;
  await tester.pumpWidget(MaterialApp(
    home: CloudPosterImage(
      cachePath: file.path,
      url: 'https://image.tmdb.org/t/p/w500/poster.jpg',
      bytesLoader: (_) async {
        requests++;
        return pngBytes;
      },
    ),
  ));
  await tester.pumpAndSettle();
  expect(find.byType(Image), findsOneWidget);
  expect(requests, 0);
});

testWidgets('父级重建但海报身份不变时只加载一次', (tester) async {
  var requests = 0;
  Widget app(String label) => MaterialApp(
        home: Column(children: [
          Text(label),
          CloudPosterImage(
            cachePath: null,
            url: 'https://image.tmdb.org/t/p/w500/same.jpg',
            bytesLoader: (_) async {
              requests++;
              return pngBytes;
            },
          ),
        ]),
      );
  await tester.pumpWidget(app('第一次'));
  await tester.pumpAndSettle();
  await tester.pumpWidget(app('第二次'));
  await tester.pumpAndSettle();
  expect(requests, 1);
});
```

再用未完成的 `Completer<List<int>>` 断言首次等待时存在 `ValueKey('cloud-poster-placeholder')`；URL 变化时新 Future 完成前仍存在旧 `Image` 且不出现占位。

- [ ] **Step 2: 运行测试确认红灯**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_poster_image_test.dart`

Expected: FAIL，`CloudPosterImage` 尚不存在。

- [ ] **Step 3: 实现公开接口**

`lib/widgets/cloud_poster_image.dart` 必须提供：

```dart
class CloudPosterImage extends StatefulWidget {
  const CloudPosterImage({
    super.key,
    required this.cachePath,
    required this.url,
    this.bytesLoader,
    this.fit = BoxFit.cover,
    this.width = double.infinity,
    this.height = double.infinity,
    this.cacheWidth,
    this.cacheHeight,
    this.filterQuality = FilterQuality.medium,
    this.placeholderBuilder,
  });

  final String? cachePath;
  final String? url;
  final TmdbImageBytesLoader? bytesLoader;
  final BoxFit fit;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final FilterQuality filterQuality;
  final WidgetBuilder? placeholderBuilder;
}

class CloudPosterPlaceholder extends StatelessWidget {
  const CloudPosterPlaceholder({super.key});
}

Future<void> precacheCloudPosterFiles(
  BuildContext context,
  Iterable<String?> paths, {
  required int limit,
  int? cacheWidth,
  int? cacheHeight,
});

int cloudPosterWarmupLimit(
  Size viewport, {
  required double maxCrossAxisExtent,
  required double childAspectRatio,
  int maximum = 48,
});
```

实现规则：规范化空路径；存在的本地文件使用 `Image.file`、`gaplessPlayback: true` 和 `frameBuilder`；第一次首帧前显示 `CloudPosterPlaceholder`，已有成功帧时保留旧帧；本地解码失败才切到 `TmdbNetworkImage`；网络组件必须传 `loadingBuilder` 和 `errorBuilder`。预热函数去重、验证文件存在、最多取 `limit` 个路径，通过 `ResizeImage.resizeIfNeeded` 与 `precacheImage` 只读取本地文件。`cloudPosterWarmupLimit` 按网格最大宽度计算列数、按宽高比计算可见行数，再增加一行缓冲并限制在 `1..maximum`；增加纯 Dart 测试覆盖窄屏、截图所示超宽屏和安全上限。

若 URL 改变测试证明 `FutureBuilder` 没有保留旧字节，只在 `TmdbNetworkImage` 内增加 `_lastBytes`：pending 时继续渲染旧字节，成功后替换；同 URL 不重建 `_bytes` 的现有条件保持不变。

- [ ] **Step 4: 运行共享组件测试确认绿灯**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_poster_image_test.dart test\tmdb_network_image_test.dart`

Expected: PASS；有效缓存不请求网络，同 URL 只请求一次。

- [ ] **Step 5: 提交共享组件**

```powershell
git add -- lib/widgets/cloud_poster_image.dart lib/widgets/tmdb_network_image.dart test/cloud_poster_image_test.dart test/tmdb_network_image_test.dart
git commit -m "修复：统一网盘海报缓存展示"
```

### Task 2: 保持网盘媒体库海报墙和卡片状态

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart:1190-1268`
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart:22-389`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 写扫描状态变化不销毁卡片的失败测试**

复用 `_PageFixture`，让媒体索引扫描由 Completer 控制。页面显示缓存海报后记录卡片 State，触发 `refresh()`，扫描状态行出现和消失后 State 都必须相同：

```dart
final card = find.byKey(const ValueKey<String>('source|work|show|season:1'));
final original = tester.state(card);
final refresh = fixture.controller.refresh();
await tester.pump();
expect(find.textContaining('正在后台扫描'), findsOneWidget);
expect(identical(tester.state(card), original), isTrue);
fixture.indexer.completeWithoutChanges();
await refresh;
await tester.pumpAndSettle();
expect(identical(tester.state(card), original), isTrue);
```

- [ ] **Step 2: 运行测试确认红灯**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart --plain-name "网盘扫描状态变化不会销毁已有海报卡片"`

Expected: FAIL，动态状态行改变后卡片 State 被替换。

- [ ] **Step 3: 添加稳定 Key**

`_directoryContent()` 的直接子项分别使用：`cloud-auto-organize-progress`、`cloud-batch-scrape-progress`、`cloud-tmdb-progress`、`cloud-scan-progress`、`cloud-resource-search-surface`、`cloud-resource-poster-surface`。搜索 Key 放在直接 `Padding`，海报 Key 放在直接 `Expanded`；控件层级、间距和交互不变。

- [ ] **Step 4: 海报墙迁移并预热首屏**

`CloudResourcePosterWall` 转为 `StatefulWidget`；`didChangeDependencies`/`didUpdateWidget` 使用 `MediaQuery.sizeOf(context)`、网格最大宽度 `300` 和宽高比 `0.68` 计算“可见卡片＋一行”的预热数量。只对这批去重后的 `posterCachePath` 计算身份，身份改变时调用 `precacheCloudPosterFiles`。海报构建收敛为：

```dart
return CloudPosterImage(
  cachePath: data.posterCachePath,
  url: TmdbMatchSheet.imageUrl(data.posterUrl, size: 'w500'),
  cacheWidth: decodeSize?.width,
  cacheHeight: decodeSize?.height,
  filterQuality: FilterQuality.medium,
  placeholderBuilder: _mediaPlaceholder,
);
```

保留 `group.stableKey` 与 `findChildIndexCallback`，不得重新访问 TMDB 或修改缓存。

- [ ] **Step 5: 运行并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resources_page_test.dart test\cloud_resource_card_view_data_test.dart`

Expected: PASS。然后：

```powershell
git add -- lib/pages/cloud/resources/cloud_resources_page.dart lib/pages/cloud/resources/cloud_resource_poster_wall.dart test/cloud_resources_page_test.dart
git commit -m "修复：保持网盘海报墙稳定显示"
```

### Task 3: 覆盖其余所有网盘海报入口

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`、`test/cloud_resource_episode_sheet_test.dart`
- Modify: `lib/features/library/presentation/media_category_page.dart`、`test/media_category_page_test.dart`
- Modify: `lib/features/history/presentation/history_page.dart`
- Create: `test/history_cloud_poster_contract_test.dart`

- [ ] **Step 1: 写三个入口的失败测试**

季度测试用真实临时海报断言 `CloudPosterImage.cachePath` 优先取季度缓存，缺失时取作品缓存。分类测试同时构造本地与网盘系列：

```dart
expect(
  find.descendant(
    of: find.byKey(const ValueKey('media-category-card-cloud|tv')),
    matching: find.byType(CloudPosterImage),
  ),
  findsOneWidget,
);
expect(
  find.descendant(
    of: find.byKey(const ValueKey('media-category-card-local|tv')),
    matching: find.byType(CloudPosterImage),
  ),
  findsNothing,
);
```

历史契约测试断言 `_Poster` 仅在 `entry.isCloud` 分支使用 `CloudPosterImage`，本地仍使用原有图片路径。

- [ ] **Step 2: 运行测试确认红灯**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_resource_episode_sheet_test.dart test\media_category_page_test.dart test\history_cloud_poster_contract_test.dart`

Expected: FAIL，三个入口仍分别直接使用 `Image.file`/`TmdbNetworkImage`。

- [ ] **Step 3: 迁移季度与选集**

统一调用：

```dart
CloudPosterImage(
  cachePath: season.metadata?.posterCachePath ??
      group.workRecord?.posterCachePath ??
      group.record?.posterCachePath,
  url: TmdbMatchSheet.imageUrl(
    season.metadata?.posterUrl ??
        group.workRecord?.metadata?.posterUrl ??
        group.record?.posterUrl,
    size: 'w500',
  ),
  cacheWidth: decodeSize?.width,
  cacheHeight: decodeSize?.height,
  placeholderBuilder: _placeholder,
)
```

删除四段重复本地/网络选择逻辑，保留 TV 解码策略和现有占位样式。

- [ ] **Step 4: 仅迁移分类页中的网盘资源**

```dart
if (series.sourceKind == MediaSourceKind.cloud) {
  return CloudPosterImage(
    cachePath: series.posterCachePath,
    url: _tmdbImageUrl(series.tmdbPosterUrl),
    placeholderBuilder: (_) => placeholder(),
  );
}
```

本地分支保持原样。网格增加按 `media-category-card-${series.key}` 映射的 `findChildIndexCallback`；初始化后使用 `MediaQuery.sizeOf(context)`、最大宽度 `280` 和宽高比 `0.68` 计算“可见卡片＋一行”，只预热这部分网盘缓存路径，刷新时保留现有网格。

- [ ] **Step 5: 仅迁移历史页中的网盘资源**

```dart
if (entry.isCloud) {
  return CloudPosterImage(
    cachePath: entry.posterCachePath,
    url: entry.posterUrl,
    placeholderBuilder: _placeholder,
  );
}
```

本地历史逻辑不变；历史列表项增加基于记录稳定标识的 Key，删除其他记录时不重建未变化网盘海报。

- [ ] **Step 6: 运行并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\cloud_poster_image_test.dart test\cloud_resources_page_test.dart test\cloud_resource_episode_sheet_test.dart test\media_category_page_test.dart test\history_cloud_poster_contract_test.dart`

Expected: PASS，本地分类卡和本地历史不使用共享组件。然后提交：

```powershell
git add -- lib/pages/cloud/resources/cloud_resource_episode_sheet.dart test/cloud_resource_episode_sheet_test.dart lib/features/library/presentation/media_category_page.dart test/media_category_page_test.dart lib/features/history/presentation/history_page.dart test/history_cloud_poster_contract_test.dart
git commit -m "修复：统一所有网盘海报入口"
```

### Task 4: 更新 2.1.166 版本与用户文案

**Files:**
- Modify: `pubspec.yaml`、`lib/core/app_version.dart`、`android/app/build.gradle.kts`
- Modify: `tool/android/build_signed_release.ps1`、`tool/windows/installer/看影音测试版.iss`
- Modify: `RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`lib/utils/version_history.dart`
- Modify: 通过 `rg "2.1.165|20165" test tool android lib` 找到的版本契约测试

- [ ] **Step 1: 写版本历史失败测试**

```dart
expect(changes, contains('已刮削的网盘海报会优先从本地缓存显示'));
expect(changes, contains('后台扫描、刷新和刮削时，未变化的海报不再整批重新加载'));
expect(changes, contains('网盘媒体库、分类、选集和观看历史统一避免白色封面'));
```

同时要求 `2.1.166+20166`、Windows `2.1.166` 与历史兼容 `msix_version: 2.1.166.0` 一致，但不进入 MSIX 交付。

- [ ] **Step 2: 运行版本测试确认红灯**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\version_history_current_test.dart test\version_consistency_test.dart test\release_config_contract_test.dart`

Expected: FAIL，当前仍为 `2.1.165+20165`。

- [ ] **Step 3: 同步版本和文案**

更新为 `2.1.166+20166`。三份文案明确：已缓存海报无需重刮；无新增资源的扫描不会让整墙重载；本地资源不变；Android 手机本轮不打包；Android TV 继续暂停。

- [ ] **Step 4: 运行并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\version_history_current_test.dart test\version_consistency_test.dart test\release_config_contract_test.dart test\android_release_packaging_test.dart test\android_tv_release_contract_test.dart`

Expected: PASS。检查关键 diff 后提交：

```powershell
git add -- pubspec.yaml lib/core/app_version.dart android/app/build.gradle.kts tool/android/build_signed_release.ps1 tool/windows/installer/看影音测试版.iss RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/utils/version_history.dart test/version_history_current_test.dart test/version_consistency_test.dart test/release_config_contract_test.dart test/android_release_packaging_test.dart test/android_tv_release_contract_test.dart
git commit -m "发布：更新网盘海报测试版至2.1.166"
```

### Task 5: 全量验证、Windows Release 与 Inno 交付

**Files:**
- Verify: `build/windows/x64/runner/Release/kanyingyin.exe`
- Generate: `build/windows/exe_output/看影音-2.1.166-测试版-安装程序.exe`
- Generate: `C:/Users/asus/Desktop/看影音-2.1.166-测试版-安装程序.exe`

- [ ] **Step 1: 格式化和差异检查**

```powershell
D:\flutter\bin\dart.bat format lib\widgets\cloud_poster_image.dart lib\widgets\tmdb_network_image.dart lib\pages\cloud\resources\cloud_resources_page.dart lib\pages\cloud\resources\cloud_resource_poster_wall.dart lib\pages\cloud\resources\cloud_resource_episode_sheet.dart lib\features\library\presentation\media_category_page.dart lib\features\history\presentation\history_page.dart test\cloud_poster_image_test.dart test\cloud_resources_page_test.dart test\cloud_resource_episode_sheet_test.dart test\media_category_page_test.dart test\history_cloud_poster_contract_test.dart
git diff --check
git status --short
```

Expected: 格式化成功，`git diff --check` 无输出，只含本轮相关文件。

- [ ] **Step 2: 全量测试和静态分析**

```powershell
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: 全部测试 PASS；分析输出 `No issues found!`。

- [ ] **Step 3: 构建 Windows Release 和 Inno EXE**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_exe_release.ps1`

Expected: Release 成功，桌面生成 `看影音-2.1.166-测试版-安装程序.exe`；不生成 MSIX，不运行 Android `tvTest`。

- [ ] **Step 4: 验证版本、哈希和签名**

```powershell
$release = Get-Item -LiteralPath 'D:\KanYingYin\build\windows\x64\runner\Release\kanyingyin.exe'
$installer = Get-Item -LiteralPath "$env:USERPROFILE\Desktop\看影音-2.1.166-测试版-安装程序.exe"
[pscustomobject]@{
  ReleaseProductVersion = $release.VersionInfo.ProductVersion
  InstallerProductVersion = $installer.VersionInfo.ProductVersion
  InstallerLength = $installer.Length
  InstallerSha256 = (Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA256).Hash
  InstallerSignature = (Get-AuthenticodeSignature -LiteralPath $installer.FullName).Status
} | Format-List
```

Expected: 两个产品版本均为 `2.1.166`，安装器非空，并记录真实 SHA-256 与签名状态；未执行安装时不宣称已安装。

- [ ] **Step 5: Windows 可见行为验收**

依次验证：打开网盘媒体库；等待无新增资源扫描结束；重新刮削单项资源；打开分类中的网盘卡、网盘选集和网盘观看历史；确认未变化海报始终保持且本地资源行为不变。若未运行测试版 GUI，明确标记可见行为仍未确认。

- [ ] **Step 6: 最终 Git 审核**

```powershell
git status --short
git diff --stat
git diff --cached --stat
git log -6 --oneline
```

Expected: 未暂存、未跟踪文件为空；验证产生的相关修正必须检查关键 diff、提交并重跑受影响验证。

## 完成标准

- 所有真实网盘海报渲染入口统一使用 `CloudPosterImage`，本地资源不使用。
- 有效 `posterCachePath` 命中时不触发网络请求。
- 扫描、刷新和刮削状态变化不销毁未变化海报卡片。
- 首次解码、网络回退和失败状态不出现白色封面。
- 全量测试、静态分析、Windows Release 和 Inno EXE 验证通过。
- 桌面存在已验证的 `看影音-2.1.166-测试版-安装程序.exe`。
- Android TV 不构建、不交付、不发布。
