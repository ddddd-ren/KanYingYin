# 网盘媒体库视觉精简实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 缩小网盘海报卡操作按钮并移除网盘媒体库内容区目录导航条，同时保留来源配置目录选择能力。

**Architecture:** 修改范围仅限网盘媒体库表现层。海报卡菜单使用 `PopupMenuButton.style` 收紧到 32 像素；网盘页面移除目录导航条及随之失去用途的表现层依赖，但保留控制器目录范围模型和三个网盘目录选择器。

**Tech Stack:** Flutter 3.41.9、Material 3、flutter_test、Windows MSIX

---

## 文件结构

- `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`：网盘海报卡及资源操作按钮。
- `lib/pages/cloud/resources/cloud_resources_page.dart`：网盘媒体库工具栏、搜索和海报墙布局。
- `test/cloud_resources_page_test.dart`：按钮尺寸、目录导航移除和页面主要能力回归测试。
- `pubspec.yaml`、`lib/core/app_version.dart`：应用与 MSIX 版本。
- `RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`lib/utils/version_history.dart`、`README.md`：普通用户可见版本文案。
- `test/version_consistency_test.dart`、`test/version_history_current_test.dart`、`test/identity_v2_zero_residue_test.dart`：版本一致性门禁。

### Task 1: 精简网盘媒体库表现层

**Files:**
- Modify: `test/cloud_resources_page_test.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`

- [ ] **Step 1: 编写海报卡紧凑按钮失败测试**

在 `季度海报墙和选集只显示当前季度虚拟名称` 测试完成首次 `pump` 后加入：

```dart
final resourceAction = find.byTooltip('资源操作');
expect(tester.getSize(resourceAction), const Size.square(32));
final actionIcon = tester.widget<Icon>(
  find.descendant(of: resourceAction, matching: find.byType(Icon)),
);
expect(actionIcon.size, 16);
```

- [ ] **Step 2: 将网盘路径测试改为导航条移除失败测试**

把 `网盘路径下拉按目录过滤海报墙并可返回上级` 改为：

```dart
testWidgets('网盘媒体库不显示目录导航且展示全部海报', (tester) async {
  final fixture = await _PageFixture.create(
    source: _quarkSource,
    entries: <CloudFileEntry>[
      CloudFileEntry(
        id: 'movie-a',
        remotePath: '/影视/电影/影片 A.mkv',
        name: '影片 A.mkv',
        size: 1024 * 1024 * 700,
        modifiedAt: DateTime(2026, 7, 24),
        isDirectory: false,
      ),
      CloudFileEntry(
        id: 'show-b',
        remotePath: '/影视/剧集/剧集 B.mkv',
        name: '剧集 B.mkv',
        size: 1024 * 1024 * 700,
        modifiedAt: DateTime(2026, 7, 24),
        isDirectory: false,
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp(home: CloudResourcesPage(controller: fixture.controller)),
  );
  await tester.pumpAndSettle();

  expect(
    find.byKey(const ValueKey<String>('cloud-directory-address')),
    findsNothing,
  );
  expect(find.text('已汇总全部媒体根目录'), findsNothing);
  expect(find.byTooltip('返回上级'), findsNothing);
  expect(find.text('影片 A.mkv'), findsOneWidget);
  expect(find.text('剧集 B.mkv'), findsOneWidget);
  fixture.controller.dispose();
});
```

- [ ] **Step 3: 运行测试并确认按预期失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_resources_page_test.dart --reporter compact
```

Expected: FAIL，按钮仍大于 `32 × 32`，页面仍存在 `cloud-directory-address`。

- [ ] **Step 4: 收紧资源操作按钮**

将 `_resourceMenu` 的外观和按钮参数调整为：

```dart
return Material(
  color: colors.surface.withValues(alpha: 0.62),
  shape: const CircleBorder(),
  child: PopupMenuButton<_ResourceAction>(
    tooltip: '资源操作',
    padding: EdgeInsets.zero,
    iconSize: 16,
    style: IconButton.styleFrom(
      minimumSize: const Size.square(32),
      maximumSize: const Size.square(32),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: const Icon(Icons.more_vert),
```

菜单回调和 `itemBuilder` 保持原样。

- [ ] **Step 5: 删除网盘内容区目录导航条**

从 `cloud_resources_page.dart` 删除：

```dart
import 'package:kanyingyin/features/library/presentation/directory_address_dropdown.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
```

删除 `_providerRegistry` 字段，并将 `_directoryContent()` 开头改为：

```dart
Widget _directoryContent() => Column(
      children: [
        if (_autoOrganizing && _autoOrganizeProgress != null)
```

即移除原先第一个 `Padding` 目录导航子组件，其余进度条、搜索和海报墙保持原样。

- [ ] **Step 6: 运行定向测试并确认通过**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_resources_page_test.dart test/cloud_directory_picker_page_test.dart test/directory_address_dropdown_test.dart --reporter compact
```

Expected: PASS。目录选择器和本地共用地址下拉测试继续通过。

- [ ] **Step 7: 提交表现层修改**

```powershell
git add lib/pages/cloud/resources/cloud_resource_poster_wall.dart lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_resources_page_test.dart
git diff --cached --check
git commit -m "优化：精简网盘媒体库视觉"
```

### Task 2: 发布 2.1.53 测试版

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

- [ ] **Step 1: 记录修改前已安装版本**

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name, Version, Architecture, Publisher
```

Expected: 明确记录已安装版本；若未安装则记录“未安装”。

- [ ] **Step 2: 编写 2.1.53 版本失败测试**

将三处版本断言更新为：

```dart
const expectedVersion = '2.1.53';
const expectedBuildNumber = '20153';
```

```dart
final entries = versionHistoryForCurrent('2.1.53');
```

```dart
expect(currentVersion, '2.1.53');
```

版本历史测试还应断言当前文案包含“资源操作按钮”“网盘媒体库”“目录导航”“夸克”“百度”“OpenList”“播放器”“TMDB”“不会修改或删除”，并且 `isPrerelease` 为真。

- [ ] **Step 3: 运行版本测试并确认按预期失败**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart --reporter compact
```

Expected: FAIL，实际版本仍为 `2.1.52`。

- [ ] **Step 4: 同步版本配置**

在 `pubspec.yaml` 使用：

```yaml
version: 2.1.53+20153
```

```yaml
msix_version: 2.1.53.0
```

将 `AppVersion.current` 和 README 当前版本同步为 `2.1.53`。

- [ ] **Step 5: 更新用户文案**

在三个当前版本文案入口加入一致的五点说明：

```text
本测试版缩小了 Windows 网盘媒体库海报上的资源操作按钮，保留原有菜单能力，同时减少对海报画面的遮挡。
网盘媒体库移除了不再需要的目录导航条，来源切换、搜索、刷新、刮削和播放器入口保持不变。
夸克、百度和 OpenList 的来源配置仍可使用统一目录选择页面，多根媒体目录配置不受影响。
本地媒体库目录下拉、TMDB 信息、字幕、全屏、硬件解码和 Anime4K 播放行为保持不变。
本次界面精简不会修改或删除本地及网盘中的原始视频或用户媒体数据。
```

`RELEASE_NOTES.md` 新增 `2.1.53+20153`，`UPDATE_DIALOG_COPY.md` 替换当前版本段，`version_history.dart` 在列表首部新增 `2.1.53` 且 `isPrerelease: true`。

- [ ] **Step 6: 运行版本测试并确认通过**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart --reporter compact
```

Expected: PASS。

- [ ] **Step 7: 提交版本修改**

```powershell
git add README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git diff --cached --check
git commit -m "发布：准备二点一五十三测试版"
```

### Task 3: 完整验证与 Windows 交付

**Files:**
- Verify: `build/windows/x64/runner/Release/kanyingyin.exe`
- Verify: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.53.msix`

- [ ] **Step 1: 执行全量测试**

```powershell
D:\flutter\bin\flutter.bat test --no-pub --reporter compact
```

Expected: 全部测试通过。

- [ ] **Step 2: 执行静态分析**

```powershell
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: `No issues found!`

- [ ] **Step 3: 构建 Windows Release**

```powershell
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: 生成 `build/windows/x64/runner/Release/kanyingyin.exe`。

- [ ] **Step 4: 生成签名 MSIX**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1
```

Expected: 生成并复制 `C:\Users\asus\Desktop\看影音-2.1.53.msix`，签名脚本验证 0 错误。

- [ ] **Step 5: 独立核验安装包**

直接读取 MSIX 内 `AppxManifest.xml`，确认：

```text
Name=com.kanyingyin.player
Publisher=CN=KanYingYin
Version=2.1.53.0
ProcessorArchitecture=x64
```

运行 `Get-AuthenticodeSignature` 确认 `Status=Valid`，并确认构建包与桌面包 SHA-256 一致。

- [ ] **Step 6: 再次核对已安装版本和工作区**

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name, Version, Architecture, Publisher
git status --short
git diff --check
git log -3 --oneline
```

Expected: 若脚本执行安装，版本为 `2.1.53.0`；工作区干净，两个本轮代码提交均存在。
