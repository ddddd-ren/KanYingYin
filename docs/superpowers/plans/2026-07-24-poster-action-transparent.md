# 海报卡操作按钮透明化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将本地与网盘海报卡三点操作按钮统一为透明背景、32 像素点击区域和 16 像素图标。

**Architecture:** 保留本地和网盘现有菜单实现，仅将各自外层 `Material` 改为 `MaterialType.transparency`，并统一 `PopupMenuButton` 样式。不抽取共享组件，不修改工具栏或目录选择功能。

**Tech Stack:** Flutter 3.41.9、Material 3、flutter_test、Windows MSIX

---

### Task 1: 统一本地与网盘海报卡菜单样式

**Files:**
- Modify: `test/cloud_resources_page_test.dart`
- Modify: `test/library_presentation_components_test.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Modify: `lib/pages/local/local_page.dart`

- [ ] **Step 1: 编写网盘透明背景失败测试**

在现有网盘按钮尺寸断言后加入：

```dart
final actionSurface = tester.widget<Material>(
  find.byKey(const ValueKey<String>('cloud-resource-action-surface')),
);
expect(actionSurface.type, MaterialType.transparency);
```

- [ ] **Step 2: 编写本地菜单样式失败测试**

在 `LocalPage 实际组合三个媒体库展示组件` 测试中截取 `_localMediaMenu` 源码并断言：

```dart
final menuStart = source.indexOf('Widget _localMediaMenu');
final menuEnd = source.indexOf('Future<void> _copyGroupPath', menuStart);
expect(menuStart, isNonNegative);
expect(menuEnd, greaterThan(menuStart));
final menuSource = source.substring(menuStart, menuEnd);
expect(
  menuSource,
  contains("key: const ValueKey<String>('local-media-action-surface')"),
);
expect(menuSource, contains('type: MaterialType.transparency'));
expect(menuSource, contains('minimumSize: const Size.square(32)'));
expect(menuSource, contains('maximumSize: const Size.square(32)'));
expect(menuSource, contains('iconSize: 16'));
```

- [ ] **Step 3: 运行测试确认红灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_resources_page_test.dart test/library_presentation_components_test.dart --reporter compact
```

Expected: FAIL，网盘缺少表面 key 且仍使用半透明表面色，本地仍为 40 像素默认按钮和 20 像素图标。

- [ ] **Step 4: 修改网盘海报卡按钮**

将 `_resourceMenu` 开头改为：

```dart
return Material(
  key: const ValueKey<String>('cloud-resource-action-surface'),
  type: MaterialType.transparency,
  shape: const CircleBorder(),
  child: PopupMenuButton<_ResourceAction>(
```

删除不再使用的 `colors` 局部变量，其余 `32 × 32 / 16` 样式保持不变。

- [ ] **Step 5: 修改本地海报卡按钮**

将 `_localMediaMenu` 开头改为：

```dart
return Material(
  key: const ValueKey<String>('local-media-action-surface'),
  type: MaterialType.transparency,
  shape: const CircleBorder(),
  child: PopupMenuButton<_LocalMediaAction>(
    tooltip: '本地媒体操作',
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

删除不再使用的 `colors` 局部变量，菜单项和操作回调保持不变。

- [ ] **Step 6: 运行定向测试确认绿灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_resources_page_test.dart test/library_presentation_components_test.dart --reporter compact
```

Expected: PASS。

- [ ] **Step 7: 提交界面修改**

```powershell
git add lib/pages/cloud/resources/cloud_resource_poster_wall.dart lib/pages/local/local_page.dart test/cloud_resources_page_test.dart test/library_presentation_components_test.dart
git diff --cached --check
git commit -m "优化：统一海报操作按钮透明样式"
```

### Task 2: 发布 2.1.54 测试版

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

- [ ] **Step 1: 查询并记录当前已安装版本**

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name, Version, Architecture, Publisher
```

- [ ] **Step 2: 先更新版本测试并确认红灯**

将预期版本改为：

```dart
const expectedVersion = '2.1.54';
const expectedBuildNumber = '20154';
```

将当前版本历史查询和身份断言同步为 `2.1.54`，并断言当前文案包含“透明背景”“本地与网盘”“三点按钮”“夸克”“百度”“OpenList”“播放器”“TMDB”“不会修改或删除”。

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart --reporter compact
```

Expected: FAIL，实际配置仍为 `2.1.53`。

- [ ] **Step 3: 更新版本和用户文案**

版本配置：

```yaml
version: 2.1.54+20154
msix_version: 2.1.54.0
```

当前版本文案统一使用：

```text
本测试版将 Windows 本地与网盘媒体库海报卡右上角的三点按钮改为透明背景，并统一为紧凑尺寸，减少对封面的遮挡。
本地与网盘的资源操作菜单内容、悬停与点击反馈、播放器入口保持不变。
夸克、百度和 OpenList 的目录选择，以及本地媒体库目录下拉继续可用。
TMDB 信息、字幕、全屏、硬件解码和 Anime4K 播放行为保持不变。
本次界面调整不会修改或删除本地与网盘中的原始视频或用户媒体数据。
```

同步修改 `AppVersion.current`、README、发布说明、更新弹窗和版本历史。

- [ ] **Step 4: 运行版本测试确认绿灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart --reporter compact
```

Expected: PASS。

- [ ] **Step 5: 提交版本修改**

```powershell
git add README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git diff --cached --check
git commit -m "发布：准备二点一五十四测试版"
```

### Task 3: 完整验证与 Windows 交付

**Files:**
- Verify: `build/windows/x64/runner/Release/kanyingyin.exe`
- Verify: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.54.msix`

- [ ] **Step 1: 执行全量测试、分析和 Release 构建**

```powershell
D:\flutter\bin\flutter.bat test --no-pub --reporter compact
D:\flutter\bin\flutter.bat analyze --no-pub
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: 全量测试通过、`No issues found!`、Windows Release 生成成功。

- [ ] **Step 2: 生成签名 MSIX**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1
```

Expected: 桌面生成 `看影音-2.1.54.msix`，签名验证 0 错误。

- [ ] **Step 3: 独立核验并收尾**

读取 MSIX 清单并确认 `com.kanyingyin.player / CN=KanYingYin / 2.1.54.0 / x64`；确认签名为 `Valid`、构建包与桌面包 SHA-256 一致，并再次查询已安装版本。

```powershell
git status --short
git diff --check
git log -4 --oneline
```

Expected: 工作区干净，本轮设计、计划、界面和版本提交完整存在。
