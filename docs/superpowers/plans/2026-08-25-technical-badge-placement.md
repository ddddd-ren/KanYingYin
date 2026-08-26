# 海报技术标签位置调整实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将海报技术标签从左上角常驻层移入底部信息面板，默认不遮挡封面，并交付 Windows 2.1.179 Inno 测试版。

**Architecture:** 复用 `ImmersiveMediaCard` 现有悬停/聚焦信息面板和 `MediaTechnicalBadgeRow`，只移动同一标签行的渲染位置；不改变标签解析、颜色、顺序、海报来源或缓存。

**Tech Stack:** Flutter 3.41.9、Dart、flutter_test、PowerShell 7、Inno Setup 6。

---

### Task 1: 更新共享卡片行为测试

**Files:**
- Modify: `test/library_presentation_components_test.dart`

- [ ] **Step 1: 将旧的左上角断言改为默认隐藏断言**

在 `ImmersiveMediaCard` 测试组中，把“技术标签常驻海报左上且空列表不占位”改为覆盖同一行为的测试：`overlayMode` 为 `hover` 时初始 `AnimatedOpacity` 为 0，技术标签行存在于树中但不可见；将鼠标移动到卡片后 opacity 为 1，标签可见；移开后恢复 0；更新为空列表后标签行消失。

保留卡片矩形与标签行矩形断言，但把位置断言改为：悬停后标签行位于 `GlassSurface` 内，且 `row.top >= glass.top`、`row.bottom <= glass.bottom`。

- [ ] **Step 2: 运行测试确认 RED**

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub test\library_presentation_components_test.dart
```

预期：新位置/默认隐藏断言因生产代码仍在左上角而失败。

### Task 2: 移动共享标签渲染位置

**Files:**
- Modify: `lib/features/library/presentation/immersive_media_card.dart`

- [ ] **Step 1: 删除海报 Stack 中的左上角常驻标签层**

删除 `Stack` 中 `Positioned(left: 10, top: 10, ...)` 的 `MediaTechnicalBadgeRow`，保留其稳定键 `media-technical-badges-poster`、标签参数和 `IgnorePointer` 语义。

- [ ] **Step 2: 在底部信息面板内容列中加入标签行**

在 `_buildOverlay` 的 `GlassSurface` 内，详情文本之后、普通 `widget.badges` 之前加入：

```dart
if (widget.technicalBadges.isNotEmpty) ...[
  const SizedBox(height: 8),
  IgnorePointer(
    child: MediaTechnicalBadgeRow(
      key: const ValueKey('media-technical-badges-poster'),
      badges: widget.technicalBadges,
      poster: true,
    ),
  ),
],
```

这样标签仅随现有 overlay 可见逻辑出现；`always` 模式继续常驻，空列表不增加间距。

- [ ] **Step 3: 运行聚焦测试确认 GREEN**

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub test\library_presentation_components_test.dart test\cloud_resources_page_test.dart test\cloud_poster_image_test.dart
```

预期：共享卡片、网盘墙、海报缓存和交互测试通过。

### Task 3: 更新 2.1.179 版本与用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `android/app/build.gradle.kts`
- Modify: `tool/android/build_signed_release.ps1`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/release_config_contract_test.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 同步版本号到 `2.1.179+20179`**

将当前版本契约中的 `2.1.178+20178`、`2.1.178.0`、`20178` 和对应当前版本字符串同步为 `2.1.179+20179`、`2.1.179.0`、`20179`，不改历史 2.1.178 条目。

- [ ] **Step 2: 增加面向用户的更新说明**

在 2.1.179 当前 Windows 测试版文案中加入：技术标签不再常驻遮挡海报，悬停或聚焦卡片时在底部信息面板查看完整标签。保留 Android 手机不打包、Android TV 暂停和原始媒体/缓存安全边界。

- [ ] **Step 3: 运行版本契约测试**

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' test --no-pub test\release_config_contract_test.dart test\version_consistency_test.dart test\version_history_current_test.dart
```

预期：全部通过，当前历史日期为 2026-08-25。

### Task 4: 全量质量门禁与对抗式复核

**Files:**
- Verify: 本轮源码、测试和版本文件

- [ ] **Step 1: 运行完整测试与静态分析**

运行 `flutter test --no-pub`、`flutter analyze --no-pub` 和 Dart 格式检查；失败时只修共享根因并重跑对应门禁。

- [ ] **Step 2: 复核行为边界**

确认技术标签只有一个 `MediaTechnicalBadgeRow` 渲染入口；默认 hover 模式不显示，悬停/聚焦和 always 模式显示；标签行在 `GlassSurface` 内；海报 2:3、深色 1.06、TV 0.78、图片回退和缓存目录均未改变。

- [ ] **Step 3: 检查工作区边界**

运行 `git diff --check`、`git status --short` 和关键 diff，保留此前无关的资源标签、海报统一和文档修改，不执行 `git add` 或 `git commit`。

### Task 5: 构建、安装与视觉验收

**Artifacts:**
- Release: `build/windows/x64/runner/Release/kanyingyin.exe`
- Installer: `C:\Users\asus\Desktop\看影音-2.1.179-测试版-安装程序.exe`
- Install target: `D:\看影音\kanyingyin.exe`

- [ ] **Step 1: 记录安装前状态**

核对已安装主程序版本、产品版本、SHA-256 和旧 MSIX 数量；不得根据 `pubspec.yaml` 推断。

- [ ] **Step 2: 生成 Inno 测试安装器**

运行 `tool\windows\build_exe_release.ps1`，确认 Release 与安装器 ProductVersion 均为 2.1.179，记录大小、SHA-256 和签名状态；不生成 MSIX、Android 手机或 Android TV 产物。

- [ ] **Step 3: 安装并核对安装后版本**

关闭旧实例，运行桌面安装器，核对 `D:\看影音\kanyingyin.exe` 为 2.1.179 且哈希与 Release 主程序一致。

- [ ] **Step 4: 真实视觉验收**

在已安装应用中检查网盘墙、本地主墙、分类页和历史卡片：默认海报左上角无技术标签；悬停或聚焦后底部面板显示完整技术标签；标题、评分、来源、菜单、播放和海报比例正常。

- [ ] **Step 5: 交付收口**

再次检查安装器存在、版本与哈希、`git diff --check` 和工作区状态；如视觉验收受窗口/数据限制无法覆盖，明确记录未验证项，不把构建成功等同于运行验收。
