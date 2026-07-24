# 海报填充与圆角抗锯齿实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 统一本地与网盘海报填充方式并改善共享卡片圆角锯齿。

**Architecture:** 本地封面加载边界统一使用 `BoxFit.cover`；共享 `ImmersiveMediaCard` 保留 8 像素圆角并改用 `Clip.antiAlias`。不处理或重写图片文件，不改变网盘已使用的 `BoxFit.cover`。

**Tech Stack:** Flutter 3.41.9、Material 3、flutter_test、Windows MSIX

---

### Task 1: 统一海报填充与圆角裁剪

**Files:**
- Modify: `test/library_presentation_components_test.dart`
- Modify: `lib/features/library/presentation/library_media_grid.dart`
- Modify: `lib/features/library/presentation/immersive_media_card.dart`

- [ ] **Step 1: 编写本地封面铺满失败测试**

在 `网络封面失败后回退本地封面，本地失败后显示占位` 测试中将两条断言改为：

```dart
expect(networkImage.fit, BoxFit.cover);
expect(localFallback.fit, BoxFit.cover);
```

- [ ] **Step 2: 编写圆角抗锯齿失败测试**

在 `always 模式始终显示信息和状态标签` 完成 `pumpWidget` 后加入：

```dart
final cardMaterial = tester
    .widgetList<Material>(find.byType(Material))
    .singleWhere(
      (material) => material.borderRadius == BorderRadius.circular(8),
    );
expect(cardMaterial.clipBehavior, Clip.antiAlias);
```

- [ ] **Step 3: 运行定向测试确认红灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/library_presentation_components_test.dart --reporter compact
```

Expected: FAIL，图片仍为 `BoxFit.contain`，卡片仍为 `Clip.hardEdge`。

- [ ] **Step 4: 统一本地封面填充**

在 `LibraryMediaCoverFallback.buildLocal` 和 `buildNetwork` 的四个 `Image`、`Image.file`、`Image.network` 分支中统一使用：

```dart
fit: BoxFit.cover,
```

- [ ] **Step 5: 启用共享卡片抗锯齿**

在 `ImmersiveMediaCard` 的外层 `Material` 中保留：

```dart
borderRadius: BorderRadius.circular(8),
```

并修改为：

```dart
clipBehavior: Clip.antiAlias,
```

- [ ] **Step 6: 运行媒体库和网盘海报回归测试**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/library_presentation_components_test.dart test/cloud_resources_page_test.dart --reporter compact
```

Expected: PASS，透明三点按钮、海报墙、悬停动画和网盘封面继续通过。

- [ ] **Step 7: 提交显示修复**

```powershell
git add lib/features/library/presentation/library_media_grid.dart lib/features/library/presentation/immersive_media_card.dart test/library_presentation_components_test.dart
git diff --cached --check
git commit -m "修复：统一海报铺满与圆角抗锯齿"
```

### Task 2: 发布 2.1.55 测试版

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

- [ ] **Step 1: 查询并记录已安装版本**

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name, Version, Architecture, Publisher
```

- [ ] **Step 2: 先更新版本测试并确认红灯**

使用：

```dart
const expectedVersion = '2.1.55';
const expectedBuildNumber = '20155';
```

将当前版本历史查询和身份断言同步为 `2.1.55`，版本历史测试断言“本地与网盘”“铺满”“浅色白边”“抗锯齿”“夸克”“百度”“OpenList”“播放器”“TMDB”“不会修改或删除”。

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart --reporter compact
```

Expected: FAIL，实际版本仍为 `2.1.54`。

- [ ] **Step 3: 更新版本和用户文案**

配置改为：

```yaml
version: 2.1.55+20155
msix_version: 2.1.55.0
```

当前版本文案使用：

```text
本测试版统一了 Windows 本地与网盘媒体库的海报显示，本地封面现在和网盘一样铺满卡片，消除比例不同造成的浅色白边。
海报卡圆角改用抗锯齿裁剪，边缘更平滑；卡片比例、透明三点按钮、悬停和播放器入口保持不变。
夸克、百度和 OpenList 的目录选择，以及本地媒体库目录下拉继续可用。
TMDB 信息、字幕、全屏、硬件解码和 Anime4K 播放行为保持不变。
本次显示修复不会修改或删除本地与网盘中的海报源文件、原始视频或用户媒体数据。
```

同步更新 `AppVersion.current`、README、发布说明、更新弹窗和版本历史。

- [ ] **Step 4: 运行版本测试确认绿灯并提交**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart --reporter compact
git add README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git diff --cached --check
git commit -m "发布：准备二点一五十五测试版"
```

Expected: PASS 并完成版本提交。

### Task 3: 完整验证与 Windows 交付

**Files:**
- Verify: `build/windows/x64/runner/Release/kanyingyin.exe`
- Verify: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.55.msix`

- [ ] **Step 1: 运行全量质量门禁**

```powershell
D:\flutter\bin\flutter.bat test --no-pub --reporter compact
D:\flutter\bin\flutter.bat analyze --no-pub
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: 全量测试通过、`No issues found!`、Windows Release 成功。

- [ ] **Step 2: 生成签名安装包**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1
```

Expected: 桌面生成 `看影音-2.1.55.msix`，签名验证 0 错误。

- [ ] **Step 3: 独立核验并收尾**

确认清单为 `com.kanyingyin.player / CN=KanYingYin / 2.1.55.0 / x64`，签名 `Valid`，构建包与桌面包 SHA-256 一致；再次查询安装版本，并确认 `git status --short` 为空。
