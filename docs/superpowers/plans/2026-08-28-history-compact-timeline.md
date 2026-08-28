# 观看历史紧凑时间线 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将观看历史改成已确认的紧凑时间线，并交付 Windows `2.1.188` 测试版 Inno Setup EXE。

**Architecture:** 保持 `HistoryPage`、`PlaybackHistoryController`、历史仓储和播放器边界不变。页面复用 Flutter Material 的分段控件与弹出菜单，仅精简单条记录结构；版本元数据继续按项目现有契约同步，现有脚本负责 Windows Release 和 Inno Setup 打包。

**Tech Stack:** Flutter 3.41.9、Dart、Material、Flutter Test、PowerShell 7、Inno Setup。

---

## 文件职责

- `lib/features/history/presentation/history_page.dart`：紧凑时间线、筛选工具栏、历史条目元信息和单条删除菜单。
- `test/playback_history_test.dart`：覆盖精简后的元信息和页面结构契约。
- `pubspec.yaml`、`lib/core/app_version.dart`、`android/app/build.gradle.kts`、`tool/android/build_signed_release.ps1`：同步 Windows 测试版版本契约；Android 正式版仍保持 `1.0.7`，不执行 Android 构建。
- `RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`lib/utils/version_history.dart`：新增面向用户的 `2.1.188` 测试版说明。
- `test/release_config_contract_test.dart`、`test/version_history_current_test.dart`：验证版本面和当前版本文案。

本轮不执行 Git commit；保留现有未跟踪文件和其他工作区内容。

### Task 1: 为紧凑时间线建立回归

**Files:**
- Modify: `test/playback_history_test.dart`
- Test: `test/playback_history_test.dart`

- [ ] **Step 1: 先写元信息和结构失败测试**

在现有观看历史页面测试旁补充：

```dart
test('观看历史紧凑显示来源进度和观看时间', () {
  final entry = _entry(position: 27, duration: 100);

  expect(
    formatPlaybackHistoryMeta(entry, '1 天前'),
    '本地 · 已看 27% · 1 天前',
  );
  expect(
    formatPlaybackHistoryMeta(
      _entry(position: 100, duration: 100),
      '刚刚',
    ),
    '本地 · 已看完 · 刚刚',
  );
});

test('观看历史页面使用紧凑时间线和单条菜单', () {
  final source = File('lib/features/history/presentation/history_page.dart')
      .readAsStringSync();

  expect(source, contains('SegmentedButton<bool>'));
  expect(source, contains("Text('\${entries.length} 条')"));
  expect(source, contains('PopupMenuButton<_HistoryMenuAction>'));
  expect(source, contains('width: 44'));
  expect(source, contains('height: 66'));
  expect(source, isNot(contains('_formatDuration(')));
  expect(
    source,
    isNot(contains('本地媒体和网盘媒体的播放进度会统一保存在这里。')),
  );
});
```

保留现有标题、日期分组和相对时间断言；把 `ChoiceChip` 的两条字符串断言改成分段控件中的“继续观看 / 全部历史”断言。

- [ ] **Step 2: 运行测试并确认 RED**

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' test test\playback_history_test.dart --plain-name '观看历史紧凑显示来源进度和观看时间'
& 'D:\flutter\bin\flutter.bat' test test\playback_history_test.dart --plain-name '观看历史页面使用紧凑时间线和单条菜单'
```

预期：第一个测试因 `formatPlaybackHistoryMeta` 不存在而编译失败；补最小函数声明后应因现有结构仍是 `ChoiceChip`、`60 × 90` 海报和独立时长行而失败。

### Task 2: 实现 A 版紧凑时间线

**Files:**
- Modify: `lib/features/history/presentation/history_page.dart`
- Test: `test/playback_history_test.dart`

- [ ] **Step 1: 添加唯一的元信息格式化入口**

在 `formatPlaybackHistoryTitle` 后增加：

```dart
String formatPlaybackHistoryMeta(
  PlaybackHistoryEntry entry,
  String watchedAt,
) {
  final progress = entry.durationSeconds <= 0
      ? 0.0
      : (entry.positionSeconds / entry.durationSeconds).clamp(0.0, 1.0);
  final status = entry.isCompleted
      ? '已看完'
      : '已看 ${(progress * 100).round()}%';
  return '${entry.isCloud ? '网盘' : '本地'} · $status · $watchedAt';
}
```

- [ ] **Step 2: 精简页面头部和筛选工具栏**

从 `KSettingsScaffold` 调用中删除 `description`。把两个 `ChoiceChip` 替换为：

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
  child: Row(
    children: [
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment<bool>(
            value: false,
            label: Text('继续观看'),
          ),
          ButtonSegment<bool>(
            value: true,
            label: Text('全部历史'),
          ),
        ],
        selected: <bool>{_showAllHistory},
        showSelectedIcon: false,
        onSelectionChanged: (selection) {
          setState(() => _showAllHistory = selection.single);
        },
      ),
      const Spacer(),
      Text(
        '${entries.length} 条',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    ],
  ),
)
```

筛选、空状态和 `rows` 日期分组逻辑保持不变。

- [ ] **Step 3: 只在相邻历史条目之间显示分隔线**

把 `ListView.separated` 的分隔器改为：

```dart
separatorBuilder: (_, index) {
  final current = rows[index];
  final next = rows[index + 1];
  if (current is! PlaybackHistoryEntry ||
      next is! PlaybackHistoryEntry) {
    return const SizedBox.shrink();
  }
  return const Divider(height: 1, indent: 56);
},
```

这样日期标题前后不会出现多余横线，条目内容仍保持可扫描的行分隔。

- [ ] **Step 4: 精简历史条目并收起删除动作**

在 `_HistoryTile` 前增加：

```dart
enum _HistoryMenuAction { delete }
```

将 `_HistoryTile.build` 的海报、标题、说明和尾部替换为：

```dart
final watchedAt = TimeUtils.formatTimestampToRelativeTime(
  entry.updatedAt.millisecondsSinceEpoch ~/ 1000,
);
final theme = Theme.of(context);
return ListTile(
  enabled: enabled,
  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
  leading: SizedBox(
    width: 44,
    height: 66,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: _Poster(entry: entry),
    ),
  ),
  title: Text(
    formatPlaybackHistoryTitle(entry),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  ),
  subtitle: Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatPlaybackHistoryMeta(entry, watchedAt),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 7),
        LinearProgressIndicator(
          value: progress,
          minHeight: 3,
          borderRadius: BorderRadius.circular(2),
        ),
      ],
    ),
  ),
  trailing: PopupMenuButton<_HistoryMenuAction>(
    enabled: enabled,
    tooltip: '更多操作',
    onSelected: (action) {
      if (action == _HistoryMenuAction.delete) onDelete();
    },
    itemBuilder: (_) => const [
      PopupMenuItem<_HistoryMenuAction>(
        value: _HistoryMenuAction.delete,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline),
            SizedBox(width: 10),
            Text('删除记录'),
          ],
        ),
      ),
    ],
  ),
  onTap: onTap,
);
```

删除 `_formatDuration`。保留整行播放、`enabled` 防重复打开、海报加载和错误处理。

- [ ] **Step 5: 格式化并确认 GREEN**

运行：

```powershell
& 'D:\flutter\bin\dart.bat' format lib\features\history\presentation\history_page.dart test\playback_history_test.dart
& 'D:\flutter\bin\flutter.bat' test test\playback_history_test.dart
```

预期：测试文件全部通过。

### Task 3: 同步 2.1.188 测试版版本面

**Files:**
- Modify: `test/release_config_contract_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `android/app/build.gradle.kts`
- Modify: `tool/android/build_signed_release.ps1`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: 先把版本契约测试改为 2.1.188**

将测试名与 Windows 测试版断言从 `2.1.187+20187` 更新为 `2.1.188+20188`，保留 Android `1.0.7+10007` 断言。新增：

```dart
test('二点一八八测试版优化观看历史排版', () {
  final entries = versionHistoryForCurrent('2.1.188');

  expect(entries, hasLength(1));
  expect(entries.single.isPrerelease, isTrue);
  final changes = entries.single.changes.join('\n');
  for (final text in <String>[
    '观看历史',
    '紧凑',
    '继续观看',
    '全部历史',
    '不会修改',
  ]) {
    expect(changes, contains(text));
  }
});
```

- [ ] **Step 2: 运行版本测试并确认 RED**

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' test test\release_config_contract_test.dart test\version_history_current_test.dart
```

预期：因源文件仍为 `2.1.187` 且没有 `2.1.188` 历史而失败。

- [ ] **Step 3: 更新构建版本契约**

同步以下值：

```text
pubspec.yaml: version: 2.1.188+20188
pubspec.yaml: msix_version: 2.1.188.0
lib/core/app_version.dart: current = '2.1.188'
android/app/build.gradle.kts: Windows guard = 2.1.188 / 20188
tool/android/build_signed_release.ps1: Windows guard = 2.1.188 / 20188
```

只更新 Android 文件中的 Windows 版本一致性保护，不修改 Android 正式版 `1.0.7`，也不执行 Android 构建。

- [ ] **Step 4: 新增面向用户的 2.1.188 文案**

在 `RELEASE_NOTES.md` 的 `2.1.187` 前新增：

```markdown
## 2.1.188+20188

Windows 测试版：2.1.188

Android 正式版仍为 1.0.7 (10007)，本轮不打包

### Windows 测试版更新内容

标题：看影音 2.1.188 测试版

- 观看历史改为更紧凑的时间线排版，缩小单条海报和留白，一屏可以查看更多记录。
- “继续观看 / 全部历史”改为统一分段切换；每条记录只保留剧集标题、来源、观看进度和上次观看时间。
- 单条删除收进右侧更多菜单，清空全部历史仍保留在页面标题栏。
- Android 手机本轮不打包；Android TV 继续暂停。
- 本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存。
```

`UPDATE_DIALOG_COPY.md` 使用相同用户可见内容，并把日期更新为 `2026-08-28`。

- [ ] **Step 5: 新增版本历史**

在 `versionHistoryList` 的正式版条目之后、`2.1.187` 之前增加：

```dart
VersionHistory(
  version: '2.1.188',
  date: '2026-08-28',
  isPrerelease: true,
  changes: [
    '观看历史改为更紧凑的时间线排版，缩小单条海报和留白，一屏可以查看更多记录',
    '“继续观看 / 全部历史”改为统一分段切换；每条记录只保留剧集标题、来源、观看进度和上次观看时间',
    '单条删除收进右侧更多菜单，清空全部历史仍保留在页面标题栏',
    'Android 手机本轮不打包；Android TV 继续暂停',
    '本次更新不会修改、删除、改名或移动本地及个人网盘中的原始视频、字幕和海报缓存',
  ],
),
```

- [ ] **Step 6: 格式化并确认版本测试 GREEN**

运行：

```powershell
& 'D:\flutter\bin\dart.bat' format lib\core\app_version.dart lib\utils\version_history.dart test\release_config_contract_test.dart test\version_history_current_test.dart
& 'D:\flutter\bin\flutter.bat' test test\release_config_contract_test.dart test\version_consistency_test.dart test\version_history_current_test.dart
```

预期：版本契约、版本一致性和版本历史测试全部通过。

### Task 4: 全量验证和界面验收

**Files:**
- Verify: 本轮修改文件

- [ ] **Step 1: 运行相关回归**

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' test test\playback_history_test.dart test\history_cloud_poster_contract_test.dart test\poster_cover_layout_contract_test.dart test\tmdb_image_network_contract_test.dart test\release_config_contract_test.dart test\version_consistency_test.dart test\version_history_current_test.dart
```

预期：全部通过。

- [ ] **Step 2: 运行完整测试**

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' test
```

预期：退出码 `0`。若出现本机 `127.0.0.1` 测试监听失败，按小批次串行复跑具体失败测试，不把局部通过误报为全量通过。

- [ ] **Step 3: 运行静态分析与差异检查**

运行：

```powershell
& 'D:\flutter\bin\flutter.bat' analyze --no-pub
git diff --check
```

预期：静态分析无 error，差异检查无输出。

### Task 5: 构建并交付 Windows 测试版 EXE

**Files:**
- Execute: `tool/windows/build_exe_release.ps1`
- Verify: `build/windows/x64/runner/Release/kanyingyin.exe`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.188-测试版-安装程序.exe`

- [ ] **Step 1: 记录交付前安装状态**

确认当前已安装 `D:\看影音\kanyingyin.exe` 仍为 `2.1.187`，并再次用 `Get-AppxPackage -Name 'com.kanyingyin.player'` 检查旧 MSIX。该状态与新包构建结果分开记录。

- [ ] **Step 2: 运行项目既有 Windows 打包脚本**

运行：

```powershell
& '.\tool\windows\build_exe_release.ps1'
```

预期：脚本完成 Windows Release 构建、校验 `app.so`、生成 Inno Setup EXE，并把唯一的 `2.1.188` 安装程序复制到桌面。不生成 MSIX、Android 或 Android TV 产物。

- [ ] **Step 3: 核验构建产物**

读取并报告：

```powershell
$release = Get-Item -LiteralPath 'build\windows\x64\runner\Release\kanyingyin.exe'
$installer = Get-Item -LiteralPath "$env:USERPROFILE\Desktop\看影音-2.1.188-测试版-安装程序.exe"
$release.VersionInfo.ProductVersion
$installer.VersionInfo.ProductVersion
Get-FileHash -LiteralPath $release.FullName -Algorithm SHA256
Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA256
Get-AuthenticodeSignature -LiteralPath $installer.FullName
```

预期：Release 主程序和安装器产品版本均为 `2.1.188`；记录两个 SHA-256 和真实签名状态。

- [ ] **Step 4: 运行 Release 主程序检查真实界面**

关闭本轮此前启动的已安装 `2.1.187` 窗口后，直接启动 Release 目录的 `2.1.188` 主程序。使用 Windows UI 自动化进入观看历史，检查：分段控件、数量、`44 × 66` 海报、单行标题、精简元信息、日期分组、三点菜单、窄窗口无重叠；不执行安装。

- [ ] **Step 5: 对抗式审查并收口**

检查：只修改已批准的观看历史排版和测试版元数据；筛选、播放、删除、清空与海报数据流未被改变；Android `1.0.7` 保持不变；未生成 TV 产物；现有未跟踪计划未被覆盖；未执行 Git commit；安装版仍为 `2.1.187`，新 `2.1.188` 只完成构建、运行和桌面安装包交付。
