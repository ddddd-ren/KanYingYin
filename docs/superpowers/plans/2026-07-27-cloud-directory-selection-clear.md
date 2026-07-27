# 网盘媒体根目录一键清除 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在夸克、百度和 OpenList 来源编辑页的媒体根目录区域增加一键清除，并以 2.1.57 测试版交付。

**Architecture:** 清除行为保留在各来源编辑页的临时表单状态中，不下沉到仓库或网盘客户端。夸克复用现有目录区块的可选动作，百度和 OpenList 按各自现有布局增加同名按钮；统一目录选择弹窗恢复原有单一职责。

**Tech Stack:** Flutter 3.41.9、Dart、Material 3、flutter_test、PowerShell、Windows MSIX

---

### Task 1: 以编辑器组件测试驱动正确位置的清除入口

**Files:**
- Modify: `test/quark_source_editor_test.dart`
- Modify: `test/baidu_source_editor_test.dart`
- Modify: `test/cloud_sources_ui_test.dart`
- Modify: `test/cloud_directory_picker_page_test.dart`
- Modify: `lib/pages/cloud/quark/quark_source_editor.dart`
- Modify: `lib/pages/cloud/baidu/baidu_source_editor.dart`
- Modify: `lib/pages/cloud/openlist_source_editor.dart`
- Modify: `lib/pages/cloud/widgets/cloud_directory_picker_page.dart`

- [ ] **Step 1: 写入失败测试**

分别在三个编辑器测试中使用已有来源和目录，查找统一键并点击：

```dart
const clearMediaRootsKey = ValueKey<String>('clear-cloud-media-roots');

final clearButton = find.byKey(clearMediaRootsKey);
expect(clearButton, findsOneWidget);
expect(tester.widget<TextButton>(clearButton).onPressed, isNotNull);
await tester.tap(clearButton);
await tester.pump();
expect(find.text('尚未选择'), findsOneWidget);
```

夸克测试额外保留一个默认转存目录，并断言清除媒体根目录后该路径仍显示。OpenList 测试断言旧路径列表消失。百度测试使用现有凭据存储夹具完成页面加载后再点击。

将 `test/cloud_directory_picker_page_test.dart` 中 2.1.56 的“多选页支持一键清除并可重新选择”和“单选页不显示清除已选按钮”改为一个回归断言：

```dart
expect(
  find.byKey(const ValueKey<String>('clear-selected-cloud-directories')),
  findsNothing,
);
```

- [ ] **Step 2: 运行测试确认红灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\quark_source_editor_test.dart test\baidu_source_editor_test.dart test\cloud_sources_ui_test.dart test\cloud_directory_picker_page_test.dart --reporter compact
```

Expected: FAIL，三个编辑页找不到 `clear-cloud-media-roots`，证明测试针对正确的新入口。

- [ ] **Step 3: 实现三个编辑器的表单清除动作**

三个状态类分别增加只清空临时集合的方法：

```dart
void _clearRoots() {
  if (_rootRefs.isEmpty) return;
  setState(_rootRefs.clear);
}
```

OpenList 使用对应强类型字段：

```dart
void _clearDirectories() {
  if (_rootPaths.isEmpty) return;
  setState(_rootPaths.clear);
}
```

清除按钮统一使用：

```dart
TextButton.icon(
  key: const ValueKey<String>('clear-cloud-media-roots'),
  onPressed: busy || rootsEmpty ? null : clearCallback,
  icon: const Icon(Icons.clear_all_rounded),
  label: const Text('清除'),
)
```

夸克 `_DirectorySection` 增加 `showClearAction`、`clearButtonKey` 和可空 `onClear` 参数；只有“媒体根目录”传 `showClearAction: true`，默认转存目录使用默认值 `false`。百度清除按钮不依赖 `_isAuthorized`，只依赖 `_busy` 与 `_rootRefs.isEmpty`。OpenList 空目录时在目录列表区域显示 `const Text('尚未选择')`。

- [ ] **Step 4: 移除目录选择弹窗中的错误入口**

从 `CloudDirectoryPickerPage` 删除 `_clearSelection` 和键为 `clear-selected-cloud-directories` 的顶部按钮，并删除只验证该错误入口的旧测试逻辑。

- [ ] **Step 5: 运行目标测试确认绿灯并提交**

```powershell
D:\flutter\bin\dart.bat format lib\pages\cloud\quark\quark_source_editor.dart lib\pages\cloud\baidu\baidu_source_editor.dart lib\pages\cloud\openlist_source_editor.dart lib\pages\cloud\widgets\cloud_directory_picker_page.dart test\quark_source_editor_test.dart test\baidu_source_editor_test.dart test\cloud_sources_ui_test.dart test\cloud_directory_picker_page_test.dart
D:\flutter\bin\flutter.bat test --no-pub test\quark_source_editor_test.dart test\baidu_source_editor_test.dart test\cloud_sources_ui_test.dart test\cloud_directory_picker_page_test.dart --reporter compact
git diff --check
git add lib/pages/cloud test/quark_source_editor_test.dart test/baidu_source_editor_test.dart test/cloud_sources_ui_test.dart test/cloud_directory_picker_page_test.dart
git diff --cached --check
git commit -m "功能：来源编辑页支持清除媒体目录"
```

Expected: PASS；提交不包含版本或发布文案。

### Task 2: 迭代为 2.1.57 测试版

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

- [ ] **Step 1: 先更新版本测试并确认红灯**

```dart
const expectedVersion = '2.1.57';
const expectedBuildNumber = '20157';
```

当前文案断言包含“来源编辑页”“媒体根目录”“一键清除”“夸克”“百度”“OpenList”“不会修改或删除”。版本历史新增 `versionHistoryForCurrent('2.1.57')` 的测试版断言，身份测试期望 `2.1.57`。

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart test\version_history_current_test.dart test\identity_v2_zero_residue_test.dart --reporter compact
```

Expected: FAIL，实际版本仍为 `2.1.56`。

- [ ] **Step 2: 更新版本与用户文案**

```yaml
version: 2.1.57+20157
msix_version: 2.1.57.0
```

在 2.1.56 历史之前新增 2.1.57 测试版条目，含义统一为：

```text
夸克、百度和 OpenList 的来源编辑页现在可在媒体根目录旁一键清除当前目录列表，再重新选择需要的目录。
清除只改变尚未保存的页面内容，不访问或删除网盘文件；保存前退出页面可以放弃变化。
夸克默认转存目录等单选设置保持不变，统一目录选择页恢复为专注选择目录。
本地与网盘媒体库、TMDB 信息和播放器行为保持不变。
本次更新不会修改或删除网盘原始文件、现有媒体索引、刮削信息或缓存。
```

同步更新 `AppVersion.current`、README 当前版本、更新弹窗、发布说明和版本历史。

- [ ] **Step 3: 确认绿灯并提交**

```powershell
D:\flutter\bin\dart.bat format lib\core\app_version.dart lib\utils\version_history.dart test\version_consistency_test.dart test\version_history_current_test.dart test\identity_v2_zero_residue_test.dart
D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart test\version_history_current_test.dart test\identity_v2_zero_residue_test.dart --reporter compact
git diff --check
git add README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git diff --cached --check
git commit -m "发布：准备二点一五十七测试版"
```

Expected: PASS，版本切片独立提交。

### Task 3: 全量验证与 MSIX 交付

**Files:**
- Verify: `build/windows/x64/runner/Release/kanyingyin.exe`
- Verify: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.57.msix`

- [ ] **Step 1: 运行完整质量门禁**

```powershell
D:\flutter\bin\flutter.bat test --no-pub --reporter compact
D:\flutter\bin\flutter.bat analyze --no-pub
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: 测试 0 失败，分析 `No issues found!`，Release 构建 exit 0。

- [ ] **Step 2: 生成签名 MSIX**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1
```

Expected: 桌面生成 `看影音-2.1.57.msix`，签名验证 0 错误。

- [ ] **Step 3: 独立核验并记录安装版本**

读取桌面 MSIX 内 `AppxManifest.xml`，确认 `com.kanyingyin.player / CN=KanYingYin / 2.1.57.0 / x64`；确认签名 `Valid`、桌面与构建包 SHA-256 一致。再次执行 `Get-AppxPackage -Name com.kanyingyin.player`，若交付脚本或用户安装了新包，则记录已安装版本 `2.1.57.0`。
