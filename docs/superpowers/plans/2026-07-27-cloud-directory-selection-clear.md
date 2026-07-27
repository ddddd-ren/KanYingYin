# 网盘多选目录一键清除 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为夸克、百度和 OpenList 的多选媒体目录页面增加“一键清除已选”，并以 2.1.56 测试版完成 Windows MSIX 交付。

**Architecture:** 复用现有 `CloudDirectoryPickerPage` 的内部选择集合，在页面层增加仅多选模式可见的清除动作，不向各网盘适配器复制逻辑，也不接触远程文件、索引、刮削或缓存服务。组件行为使用 `flutter_test` 按红—绿顺序验证，版本元数据和用户文案由现有一致性测试约束。

**Tech Stack:** Flutter 3.41.9、Dart、Material 3、flutter_test、PowerShell、Windows MSIX

---

## 文件职责

- `lib/pages/cloud/widgets/cloud_directory_picker_page.dart`：统一网盘目录选择页及其临时选择状态。
- `test/cloud_directory_picker_page_test.dart`：多选清除行为和单选隔离的组件测试。
- `pubspec.yaml`：应用版本和 MSIX 清单版本源。
- `lib/core/app_version.dart`、`README.md`、`UPDATE_DIALOG_COPY.md`：当前版本展示和更新弹窗文案。
- `RELEASE_NOTES.md`、`lib/utils/version_history.dart`：2.1.56 用户可见发布记录。
- `test/version_consistency_test.dart`、`test/version_history_current_test.dart`、`test/identity_v2_zero_residue_test.dart`：版本、测试版标记和发布文案一致性。

### Task 1: 以组件测试驱动多选清除交互

**Files:**
- Modify: `test/cloud_directory_picker_page_test.dart`
- Modify: `lib/pages/cloud/widgets/cloud_directory_picker_page.dart`

- [ ] **Step 1: 写入多选清除和单选隔离的失败测试**

在 `test/cloud_directory_picker_page_test.dart` 中加入：

```dart
testWidgets('多选页可一键清除全部已选目录并重新选择', (tester) async {
  const folder = CloudFileEntry(
    id: 'tv',
    remotePath: '/影视',
    name: '影视',
    size: 0,
    modifiedAt: null,
    isDirectory: true,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: CloudDirectoryPickerPage<List<CloudRemoteRef>>(
        title: '选择网盘目录',
        root: const CloudRemoteRef(id: '0', path: '/'),
        initialSelection: const <CloudRemoteRef>[
          CloudRemoteRef(id: 'tv', path: '/影视'),
        ],
        loader: (_) async => const <CloudFileEntry>[folder],
        resultBuilder: (selected) => selected,
      ),
    ),
  );
  await tester.pumpAndSettle();

  final clearFinder = find.byKey(
    const ValueKey<String>('clear-selected-cloud-directories'),
  );
  expect(clearFinder, findsOneWidget);
  expect(tester.widget<TextButton>(clearFinder).onPressed, isNotNull);
  expect(
    tester
        .widget<Checkbox>(
          find.byKey(const ValueKey<String>('select-tv')),
        )
        .value,
    isTrue,
  );

  await tester.tap(clearFinder);
  await tester.pump();

  expect(find.text('已选 0 个'), findsOneWidget);
  expect(tester.widget<TextButton>(clearFinder).onPressed, isNull);
  expect(
    tester
        .widget<Checkbox>(
          find.byKey(const ValueKey<String>('select-tv')),
        )
        .value,
    isFalse,
  );
  expect(
    tester.widget<TextButton>(find.widgetWithText(TextButton, '确定')).onPressed,
    isNull,
  );

  await tester.tap(find.byKey(const ValueKey<String>('select-tv')));
  await tester.pump();

  expect(find.text('已选 1 个'), findsOneWidget);
  expect(tester.widget<TextButton>(clearFinder).onPressed, isNotNull);
  expect(
    tester.widget<TextButton>(find.widgetWithText(TextButton, '确定')).onPressed,
    isNotNull,
  );
});

testWidgets('单选目录页不显示清除已选', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CloudDirectoryPickerPage<List<CloudRemoteRef>>(
        title: '选择默认转存目录',
        root: const CloudRemoteRef(id: '0', path: '/'),
        initialSelection: const <CloudRemoteRef>[
          CloudRemoteRef(id: 'tv', path: '/影视'),
        ],
        loader: (_) async => const <CloudFileEntry>[],
        resultBuilder: (selected) => selected,
        singleSelection: true,
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(
    find.byKey(const ValueKey<String>('clear-selected-cloud-directories')),
    findsNothing,
  );
});
```

- [ ] **Step 2: 运行目标测试并确认红灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_directory_picker_page_test.dart --reporter compact
```

Expected: FAIL，找不到键 `clear-selected-cloud-directories`；失败来自功能尚未实现，而不是测试编译错误。

- [ ] **Step 3: 实现最小页面状态操作**

在 `_CloudDirectoryPickerPageState` 中加入：

```dart
void _clearSelection() {
  if (_selected.isEmpty) return;
  setState(_selected.clear);
}
```

在 `AppBar.actions` 的“选择当前目录”之前加入：

```dart
if (!widget.singleSelection)
  TextButton.icon(
    key: const ValueKey<String>('clear-selected-cloud-directories'),
    onPressed: _selected.isEmpty ? null : _clearSelection,
    icon: const Icon(Icons.clear_all_rounded),
    label: const Text('清除已选'),
  ),
```

该操作只清空 `_selected`，不调用 `loader`、`resultBuilder` 或任何持久化服务。

- [ ] **Step 4: 运行目标测试并确认绿灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_directory_picker_page_test.dart --reporter compact
```

Expected: PASS，清除后数量归零、确定按钮禁用，重新勾选可恢复提交，单选页无清除入口。

- [ ] **Step 5: 验证三种多选入口仍使用统一页面**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_sources_ui_test.dart test/quark_source_editor_test.dart test/baidu_source_editor_test.dart test/architecture_dependency_test.dart --reporter compact
```

Expected: PASS；夸克、百度和 OpenList 的选择结果类型与现有保存流程不变。

- [ ] **Step 6: 格式化、检查并提交功能切片**

```powershell
D:\flutter\bin\dart.bat format lib/pages/cloud/widgets/cloud_directory_picker_page.dart test/cloud_directory_picker_page_test.dart
git diff --check
git status --short
git add lib/pages/cloud/widgets/cloud_directory_picker_page.dart test/cloud_directory_picker_page_test.dart
git diff --cached --check
git commit -m "功能：网盘多选目录支持一键清除"
```

Expected: 仅包含统一选择页和组件测试，提交成功。

### Task 2: 以一致性测试驱动 2.1.56 测试版元数据

**Files:**
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: 更新版本测试并确认红灯**

在 `test/version_consistency_test.dart` 中使用：

```dart
const expectedVersion = '2.1.56';
const expectedBuildNumber = '20156';
```

将当前版本的发布类型断言改为：

```dart
expect(currentReleaseNotes, contains('测试版'));
expect(updateDialogCopy, contains('测试版'));
expect(currentVersionHistory, contains('isPrerelease: true'));
for (final copy in <String>[
  currentReleaseNotes,
  currentVersionHistory,
  updateDialogCopy,
]) {
  expect(copy, contains('一键'));
  expect(copy, contains('清除已选'));
  expect(copy, contains('多选'));
  expect(copy, contains('不会修改或删除'));
  for (final feature in [
    '夸克',
    '百度',
    'OpenList',
    '媒体库',
    '播放器',
    'TMDB',
  ]) {
    expect(copy, contains(feature));
  }
}
```

删除只适用于 1.0.1 累积正式版的“正式版、转存目录、铺满、动漫番剧、快捷方式”等当前版本断言。将 `test/identity_v2_zero_residue_test.dart` 的当前版本期望改为 `2.1.56`。

在 `test/version_history_current_test.dart` 添加：

```dart
test('二点一五十六说明网盘多选目录一键清除', () {
  final entries = versionHistoryForCurrent('2.1.56');

  expect(entries, hasLength(1));
  final entry = entries.single;
  final changes = entry.changes.join('\n');
  expect(entry.isPrerelease, isTrue);
  expect(changes, contains('清除已选'));
  expect(changes, contains('夸克'));
  expect(changes, contains('百度'));
  expect(changes, contains('OpenList'));
  expect(changes, contains('不会修改或删除'));
});
```

运行：

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart --reporter compact
```

Expected: FAIL，实际项目版本仍为 `1.0.1`，且尚无 2.1.56 历史记录。

- [ ] **Step 2: 更新版本源和当前版本展示**

使用以下版本：

```yaml
version: 2.1.56+20156
msix_version: 2.1.56.0
```

同时将 `AppVersion.current`、README 当前版本、更新弹窗版本和日期改为 `2.1.56`、`2.1.56.0`、`2026-07-27`，弹窗标题为“看影音 2.1.56 测试版”。

- [ ] **Step 3: 写入普通用户可读的发布说明**

在 `RELEASE_NOTES.md` 顶部和 `lib/utils/version_history.dart` 当前条目中同步以下含义，版本历史设置 `isPrerelease: true`：

```text
本测试版为夸克、百度和 OpenList 的多选媒体目录页面增加“清除已选”，可一键取消全部已选目录，无需逐项取消。
没有已选目录时清除按钮自动禁用；清除后必须重新选择至少一个目录并点击“确定”，才会写回来源配置。
夸克默认转存目录等单选页面保持原有交互不变。
本地与网盘媒体库、TMDB 信息和播放器的字幕、全屏、硬件解码、Anime4K 行为保持不变。
本次目录选择改进不会修改或删除网盘原始文件、现有媒体索引、刮削信息或缓存。
```

`UPDATE_DIALOG_COPY.md` 使用同一组用户含义，避免发布渠道文案分叉。

- [ ] **Step 4: 运行版本测试并确认绿灯**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart --reporter compact
```

Expected: PASS，版本号、测试版标记、用户文案和应用身份一致。

- [ ] **Step 5: 格式化、检查并提交版本切片**

```powershell
D:\flutter\bin\dart.bat format lib/core/app_version.dart lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git diff --check
git status --short
git add pubspec.yaml README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/core/app_version.dart lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git diff --cached --check
git commit -m "发布：准备二点一五十六测试版"
```

Expected: 仅包含 2.1.56 元数据、用户文案和对应测试，提交成功。

### Task 3: 完整验证、签名 MSIX 与桌面交付

**Files:**
- Verify: `build/windows/x64/runner/Release/kanyingyin.exe`
- Verify: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.56.msix`

- [ ] **Step 1: 确认安装版本记录和工作区范围**

本轮版本更新开始前已执行：

```powershell
Get-AppxPackage -Name com.kanyingyin.player
```

记录结果为已安装 `com.kanyingyin.player 2.1.55.0`。再次运行 `git status --short` 和关键 diff，确认没有用户的无关改动被纳入本轮提交。

- [ ] **Step 2: 运行全量测试和静态分析**

```powershell
D:\flutter\bin\flutter.bat test --no-pub --reporter compact
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: 全量测试 0 失败，静态分析输出 `No issues found!`。

- [ ] **Step 3: 构建 Windows Release**

```powershell
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: exit 0，生成本轮 `build/windows/x64/runner/Release/kanyingyin.exe` 和 `data/app.so`。

- [ ] **Step 4: 生成并验证签名 MSIX**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1
```

Expected: 脚本完成 Release 重建、MSIX 封装、签名、清单和哈希验证，并复制 `C:\Users\asus\Desktop\看影音-2.1.56.msix`；不得用未签名包替代最终交付物。

- [ ] **Step 5: 独立核验安装包和安装版本**

```powershell
$desktopMsix = Join-Path $env:USERPROFILE 'Desktop\看影音-2.1.56.msix'
Get-Item -LiteralPath $desktopMsix
Get-AuthenticodeSignature -LiteralPath $desktopMsix
Get-FileHash -LiteralPath $desktopMsix -Algorithm SHA256
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name, Version, PackageFullName
```

读取 MSIX 内 `AppxManifest.xml`，确认 `Name=com.kanyingyin.player`、`Publisher=CN=KanYingYin`、`Version=2.1.56.0`、`ProcessorArchitecture=x64`。本计划不主动安装 MSIX，因此已安装版本应仍记录为 `2.1.55.0`；只有实际执行安装后才要求再次确认已安装版本为 `2.1.56.0`。

- [ ] **Step 6: 最终审查和状态确认**

```powershell
git status --short
git log -4 --oneline
```

Expected: 功能、版本和计划相关提交存在，工作区没有未提交的本轮改动；报告测试、分析、Release、MSIX 清单、签名、SHA-256、桌面路径和已安装版本记录。
