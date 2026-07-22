# 路径导航与本地文件夹地址输入实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正媒体库工具栏路径的空白胶囊和右对齐问题，并让本地文件夹选择器支持输入、粘贴和验证 Windows 地址。

**Architecture:** `LocalDirectoryPickerPage` 继续通过现有可注入的磁盘与目录加载器读取内容，新增地址控制器、输入规范化、最新请求编号和“浏览错误/手动输入错误”分离状态。`LibraryPathBar` 不修改构造参数、三行结构和回调，只把路径区域改为左对齐且长路径反向优先显示当前目录的轻量导航。

**Tech Stack:** Flutter 3.41.9、Dart、Material 3、flutter_test、Windows MSIX。

---

## 文件结构

- `lib/pages/local/local_directory_picker.dart`：地址输入、路径规范化、异步导航、错误状态和文件夹列表编排。
- `test/local_directory_picker_test.dart`：地址输入、Enter/按钮提交、空地址、引号、错误保留和选择结果回归。
- `lib/features/library/presentation/library_path_bar.dart`：媒体库第一行路径导航与上级目录图标表现。
- `test/library_presentation_components_test.dart`：路径左对齐、图标、多宽度和动作转发回归。
- 版本文件：`pubspec.yaml`、`lib/core/app_version.dart`、`README.md`、`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`lib/utils/version_history.dart`、`test/version_consistency_test.dart`、`test/identity_v2_zero_residue_test.dart`。

### Task 1: 本地文件夹地址输入与安全导航

**Files:**
- Modify: `test/local_directory_picker_test.dart`
- Modify: `lib/pages/local/local_directory_picker.dart`

- [ ] **Step 1: 编写地址规范化失败测试**

在 `test/local_directory_picker_test.dart` 增加：

```dart
test('本地目录地址去除空白和成对双引号', () {
  expect(normalizeLocalDirectoryAddress(r'  D:\a TV  '), r'D:\a TV');
  expect(normalizeLocalDirectoryAddress(r'"D:\a TV"'), r'D:\a TV');
  expect(normalizeLocalDirectoryAddress(r'  "D:\a TV"  '), r'D:\a TV');
  expect(normalizeLocalDirectoryAddress(r'"D:\a TV'), r'"D:\a TV');
  expect(normalizeLocalDirectoryAddress('   '), isEmpty);
});
```

- [ ] **Step 2: 编写输入、提交和错误状态失败测试**

添加以下 Widget 测试，固定公开 key：

```dart
testWidgets('地址栏按 Enter 跳转并同步成功路径', (tester) async {
  final loadedPaths = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: LocalDirectoryPickerPage(
        initialPath: r'D:\旧目录',
        directoryLoader: (path) async {
          loadedPaths.add(path);
          return switch (path) {
            r'D:\旧目录' => <String>[r'D:\旧目录\原文件夹'],
            r'E:\新目录' => <String>[r'E:\新目录\新文件夹'],
            _ => throw const FileSystemException('不存在'),
          };
        },
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const ValueKey('local-directory-address')),
    r'E:\新目录',
  );
  await tester.testTextInput.receiveAction(TextInputAction.go);
  await tester.pumpAndSettle();

  expect(loadedPaths.last, r'E:\新目录');
  expect(find.text('新文件夹'), findsOneWidget);
  final field = tester.widget<TextField>(
    find.byKey(const ValueKey('local-directory-address')),
  );
  expect(field.controller!.text, r'E:\新目录');
});

testWidgets('跳转按钮处理带引号地址且空地址返回磁盘列表', (tester) async {
  var driveLoads = 0;
  final loadedPaths = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: LocalDirectoryPickerPage(
        initialPath: r'D:\旧目录',
        driveRootsProvider: () async {
          driveLoads++;
          return <String>[r'C:\', r'D:\'];
        },
        directoryLoader: (path) async {
          loadedPaths.add(path);
          return <String>[];
        },
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const ValueKey('local-directory-address')),
    r' "E:\媒体" ',
  );
  await tester.tap(find.byKey(const ValueKey('local-directory-go')));
  await tester.pumpAndSettle();
  expect(loadedPaths.last, r'E:\媒体');

  await tester.enterText(
    find.byKey(const ValueKey('local-directory-address')),
    '',
  );
  await tester.tap(find.byKey(const ValueKey('local-directory-go')));
  await tester.pumpAndSettle();
  expect(driveLoads, 1);
  expect(find.text(r'C:\'), findsOneWidget);
});

testWidgets('无效手动地址保留当前目录和列表', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LocalDirectoryPickerPage(
        initialPath: r'D:\有效目录',
        directoryLoader: (path) async => switch (path) {
          r'D:\有效目录' => <String>[r'D:\有效目录\仍然可见'],
          _ => throw const FileSystemException('不存在'),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const ValueKey('local-directory-address')),
    r'Z:\不存在',
  );
  await tester.tap(find.byKey(const ValueKey('local-directory-go')));
  await tester.pumpAndSettle();

  expect(find.text('仍然可见'), findsOneWidget);
  expect(find.text('目录不存在或无法访问'), findsOneWidget);
  expect(
    tester
        .widget<TextField>(
          find.byKey(const ValueKey('local-directory-address')),
        )
        .controller!
        .text,
    r'Z:\不存在',
  );
});

testWidgets('本地目录选择器使用圆角无直杆的上级图标', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: LocalDirectoryPickerPage(
        initialPath: r'D:\',
        directoryLoader: (_) async => <String>[],
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
  expect(find.byIcon(Icons.arrow_upward), findsNothing);
});
```

- [ ] **Step 3: 运行测试并确认 RED**

Run:

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\local_directory_picker_test.dart
```

Expected: FAIL，原因是 `normalizeLocalDirectoryAddress`、地址框 key、跳转按钮和新图标尚不存在。

- [ ] **Step 4: 实现地址规范化与状态字段**

在 `local_directory_picker.dart` 顶部增加：

```dart
String normalizeLocalDirectoryAddress(String value) {
  var normalized = value.trim();
  if (normalized.length >= 2 &&
      normalized.startsWith('"') &&
      normalized.endsWith('"')) {
    normalized = normalized.substring(1, normalized.length - 1).trim();
  }
  return normalized;
}
```

在 State 中增加并初始化：

```dart
late final TextEditingController _addressController;
String? _addressError;
int _navigationGeneration = 0;

@override
void initState() {
  super.initState();
  final initialPath = widget.initialPath?.trim() ?? '';
  _addressController = TextEditingController(text: initialPath);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    if (initialPath.isEmpty) {
      _loadDrives();
    } else {
      _loadDirectory(initialPath);
    }
  });
}

@override
void dispose() {
  _navigationGeneration++;
  _addressController.dispose();
  super.dispose();
}
```

- [ ] **Step 5: 实现最新请求保护和两类错误**

将磁盘和目录读取改为只有最新 generation 可以提交结果：

```dart
Future<void> _loadDrives() async {
  final generation = ++_navigationGeneration;
  setState(() {
    _loading = true;
    _addressError = null;
    _errorMessage = null;
  });
  try {
    final drives = await widget.driveRootsProvider();
    if (!mounted || generation != _navigationGeneration) return;
    setState(() {
      _entries = drives;
      _currentPath = null;
      _addressController.clear();
    });
  } on Object {
    if (!mounted || generation != _navigationGeneration) return;
    setState(() => _errorMessage = '无法读取磁盘列表');
  } finally {
    if (mounted && generation == _navigationGeneration) {
      setState(() => _loading = false);
    }
  }
}

Future<void> _loadDirectory(
  String path, {
  bool preserveContentOnFailure = false,
}) async {
  final generation = ++_navigationGeneration;
  setState(() {
    _loading = true;
    _addressError = null;
    _errorMessage = null;
  });
  try {
    final directories = await widget.directoryLoader(path);
    if (!mounted || generation != _navigationGeneration) return;
    setState(() {
      _entries = directories;
      _currentPath = path;
      _addressController.text = path;
    });
  } on Object {
    if (!mounted || generation != _navigationGeneration) return;
    setState(() {
      if (preserveContentOnFailure) {
        _addressError = '目录不存在或无法访问';
      } else {
        _entries = <String>[];
        _currentPath = path;
        _addressController.text = path;
        _errorMessage = '无法读取该目录，移动硬盘可能已断开';
      }
    });
  } finally {
    if (mounted && generation == _navigationGeneration) {
      setState(() => _loading = false);
    }
  }
}

Future<void> _submitAddress() async {
  final path = normalizeLocalDirectoryAddress(_addressController.text);
  if (path.isEmpty) {
    await _loadDrives();
  } else {
    await _loadDirectory(path, preserveContentOnFailure: true);
  }
}
```

现有 `_navigateUp` 和文件夹 `onTap` 继续调用非保留模式的 `_loadDirectory`。

- [ ] **Step 6: 重建地址行**

将原 `ListTile` 替换为：

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          IconButton(
            tooltip: '上级目录',
            onPressed: _currentPath == null || _loading ? null : _navigateUp,
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              key: const ValueKey('local-directory-address'),
              controller: _addressController,
              enabled: !_loading,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submitAddress(),
              decoration: InputDecoration(
                hintText: '输入文件夹地址',
                prefixIcon: const Icon(Icons.folder_outlined, size: 20),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const ValueKey('local-directory-go'),
            onPressed: _loading ? null : _submitAddress,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('跳转'),
          ),
        ],
      ),
      if (_addressError != null) ...[
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 54),
          child: Text(
            _addressError!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ),
      ],
    ],
  ),
)
```

保留其后的 `Divider`、内容列表和 AppBar 动作。

- [ ] **Step 7: 格式化并运行目录选择器测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\pages\local\local_directory_picker.dart test\local_directory_picker_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\local_directory_picker_test.dart
```

Expected: 全部通过，原移动硬盘进入、选择与断开错误测试继续通过。

- [ ] **Step 8: 提交地址输入能力**

```powershell
git add lib\pages\local\local_directory_picker.dart test\local_directory_picker_test.dart
git commit -m "支持输入本地文件夹地址"
```

### Task 2: 修正媒体库工具栏路径与上级图标

**Files:**
- Modify: `test/library_presentation_components_test.dart`
- Modify: `lib/features/library/presentation/library_path_bar.dart`

- [ ] **Step 1: 编写路径视觉契约失败测试**

在现有 `LibraryPathBar` group 中增加：

```dart
testWidgets('路径导航左对齐且使用轻量上级图标', (tester) async {
  await pumpPathBar(tester, width: 900);

  final surface = find.byKey(
    const ValueKey('library-path-breadcrumb-surface'),
  );
  expect(surface, findsOneWidget);
  expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
  expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
  expect(find.byIcon(Icons.arrow_upward), findsNothing);
  expect(
    tester.getCenter(find.text('D:')).dx,
    lessThan(tester.getCenter(surface).dx),
  );
});
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart --plain-name "LibraryPathBar 路径导航左对齐且使用轻量上级图标"
```

Expected: FAIL，因为当前使用 `Icons.arrow_upward`，且短路径因 `reverse: true` 靠右。

- [ ] **Step 3: 替换上级目录图标**

将第一行按钮：

```dart
_button(
  context,
  Icons.keyboard_arrow_up_rounded,
  '上级目录',
  data.canNavigateUp ? onNavigateUp : null,
)
```

- [ ] **Step 4: 将路径改为无胶囊的左对齐导航**

用以下实现替换 `_breadcrumbs`，保留原 key 和点击回调：

```dart
Widget _breadcrumbs(BuildContext context, ColorScheme colors) => LayoutBuilder(
  key: const ValueKey('library-path-breadcrumb-surface'),
  builder: (context, constraints) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: constraints.maxWidth),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 6),
              child: Icon(
                Icons.folder_outlined,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ),
            for (var i = 0; i < data.breadcrumbs.length; i++) ...[
              if (i > 0)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: colors.outline,
                ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: data.breadcrumbs[i].isCurrent
                      ? null
                      : () async => await onBreadcrumbSelected(
                            data.breadcrumbs[i].path,
                          ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: Text(
                      data.breadcrumbs[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: data.breadcrumbs[i].isCurrent
                                ? colors.onSurface
                                : colors.primary,
                            fontWeight: data.breadcrumbs[i].isCurrent
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  },
);
```

不再给路径区域单独添加背景、边框或圆角。

- [ ] **Step 5: 运行工具栏和桌面壳测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\features\library\presentation\library_path_bar.dart test\library_presentation_components_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart test\desktop_shell_test.dart
```

Expected: 全部通过，1280、900、640px 无溢出，动作转发顺序不变。

- [ ] **Step 6: 提交路径导航修正**

```powershell
git add lib\features\library\presentation\library_path_bar.dart test\library_presentation_components_test.dart
git commit -m "优化媒体库路径导航视觉"
```

### Task 3: 发布 2.1.41

**Files:**
- Modify: `test/version_consistency_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: 查询当前 Windows 已安装版本**

Run:

```powershell
Get-AppxPackage -Name com.kanyingyin.player |
  Select-Object Name,Version,Architecture
```

Expected: 明确记录实际结果；计划编写时为 `2.1.40.0 / X64`。

- [ ] **Step 2: 先更新版本测试并确认 RED**

将 `test/version_consistency_test.dart` 更新为：

```dart
const expectedVersion = '2.1.41';
const expectedBuildNumber = '20141';
```

将 `test/identity_v2_zero_residue_test.dart` 当前版本断言改为 `2.1.41`，运行：

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart
```

Expected: FAIL，实际版本仍为 2.1.40。

- [ ] **Step 3: 更新全部版本源**

精确更新：

```text
pubspec.yaml: version: 2.1.41+20141
pubspec.yaml: msix_version: 2.1.41.0
lib/core/app_version.dart: current = '2.1.41'
README.md: | 当前版本 | 2.1.41 |
```

在 `RELEASE_NOTES.md` 顶部和 `UPDATE_DIALOG_COPY.md` 当前正文使用：

```markdown
标题：看影音 2.1.41 测试版

- 本地文件夹选择页新增常驻地址栏，可直接输入或粘贴盘符与网络路径，按 Enter 或点击“跳转”即可进入。
- 无效地址会保留当前目录和文件列表并给出清晰提示，不会把尚未验证的路径作为选择结果。
- 媒体库顶部路径改为左对齐的轻量导航，移除空白大胶囊，并统一上级目录图标；原三行结构、搜索、排序和扫描逻辑不变。
- 播放器退出卡死修复、本地与网盘经典海报墙及其操作动画继续保留；播放器字幕、选集、硬件解码与 Anime4K 行为不变。
- 没有 TMDB Key 或断网时，应用启动、本地与网盘媒体库和播放器仍可使用；本次不会修改或删除本地原始媒体，也不会修改网盘文件。
```

在 `versionHistoryList` 首位加入：

```dart
VersionHistory(
  version: '2.1.41',
  date: '2026-07-23',
  isPrerelease: true,
  changes: [
    '本地文件夹选择页新增常驻地址栏，可直接输入或粘贴盘符与网络路径，按 Enter 或点击“跳转”即可进入',
    '无效地址会保留当前目录和文件列表并给出清晰提示，不会把尚未验证的路径作为选择结果',
    '媒体库顶部路径改为左对齐的轻量导航，移除空白大胶囊，并统一上级目录图标；原三行结构、搜索、排序和扫描逻辑不变',
    '播放器退出卡死修复、本地与网盘经典海报墙及其操作动画继续保留；播放器字幕、选集、硬件解码与 Anime4K 行为不变',
    '没有 TMDB Key 或断网时，应用启动、本地与网盘媒体库和播放器仍可使用；本次不会修改或删除本地原始媒体，也不会修改网盘文件',
  ],
),
```

- [ ] **Step 4: 格式化并运行版本测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\core\app_version.dart lib\utils\version_history.dart test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart
```

Expected: 全部通过。

- [ ] **Step 5: 提交版本更新**

```powershell
git add pubspec.yaml lib\core\app_version.dart README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib\utils\version_history.dart test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart
git commit -m "发布 2.1.41 路径导航优化版"
```

### Task 4: 完整门禁与签名交付

**Files:**
- Verify: all tracked project files
- Build: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `C:/Users/asus/Desktop/看影音-2.1.41.msix`
- Deliver: `C:/Users/asus/Desktop/看影音-2.1.41-异机安装包.zip`

- [ ] **Step 1: 检查格式、边界和工作树**

Run:

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed .
git diff --check main...HEAD
git diff --exit-code 527b055..HEAD -- lib\pages\player lib\features\library\presentation\immersive_media_card.dart
git status --short
git -C D:\KanYingYin status --short
```

Expected: 格式 0 改动；播放器和经典海报卡无差异；除隔离 worktree 内测试 `.dart_appdata` 外无未提交文件；主工作区干净。

- [ ] **Step 2: 串行运行完整测试与静态分析**

Run:

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
```

Expected: 全部测试通过，`No issues found!`。

- [ ] **Step 3: 安全清理测试 APPDATA**

解析 `D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata` 绝对路径，确认位于隔离 worktree 内且末级目录严格等于 `.dart_appdata` 后，使用 PowerShell `Remove-Item -LiteralPath ... -Recurse -Force` 清理。再次检查两个工作区状态。

- [ ] **Step 4: 生成 Windows Release 与签名包**

Run:

```powershell
Get-Process -Name kanyingyin -ErrorAction SilentlyContinue
& .\tool\windows\build_signed_release.ps1
```

Expected: 构建前无运行中的看影音；Release、MSIX 和 SignTool 验证成功，0 warning / 0 error，桌面生成两个 2.1.41 文件。

- [ ] **Step 5: 独立验证交付物**

使用 `Get-AuthenticodeSignature`、`System.IO.Compression.ZipFile` 和 `Get-FileHash` 验证：

```text
签名状态：Valid
签名者：CN=KanYingYin
证书指纹：A4A2CAA9623FBB8CD27ABC4838D186202EFC1AD6
Identity Name：com.kanyingyin.player
Version：2.1.41.0
ProcessorArchitecture：x64
构建目录 MSIX SHA-256 = 桌面 MSIX SHA-256 = ZIP 内 MSIX SHA-256
ZIP：MSIX、看影音.cer、安装看影音.ps1、安装看影音.cmd、安装说明.txt、SHA256.txt
```

- [ ] **Step 6: 最终版本和隔离状态**

运行 `Get-AppxPackage -Name com.kanyingyin.player`。若流程未安装，版本保持构建前记录；若用户在期间安装，记录实际版本。保留 `codex/ui-refresh-v1` 和当前 worktree，不合并、不删除。
