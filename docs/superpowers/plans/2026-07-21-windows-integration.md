# Windows 外部播放器与快捷方式优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Windows 外部播放器可靠支持非 ASCII 路径并安全清理临时播放列表，同时按桌面与开始菜单入口的真实状态决定是否修复或询问快捷方式。

**Architecture:** 外部播放器原生层使用可注入操作集合把 UTF-8 转换、临时文件写入、启动与清理编排分离，以原生单元测试覆盖关键生命周期；Flutter 通道返回明确状态，带 Referer 的 Windows 请求返回受支持范围之外的失败。快捷方式原生层返回桌面与开始菜单组合状态，Dart 纯策略决定修复、询问、跳过或稍后重试，`InitPage` 只负责执行决策与展示文案。

**Tech Stack:** Flutter、Dart、Windows C++17、Win32 Shell API、Flutter MethodChannel、flutter_test、CMake/MSVC。

---

### Task 1: 外部播放器原生核心与行为测试

**Files:**
- Modify: `windows/runner/external_player_utils.h`
- Modify: `windows/runner/external_player_utils.cpp`
- Create: `windows/runner/external_player_utils_test.cpp`
- Modify: `windows/runner/CMakeLists.txt`

- [ ] **Step 1: 添加原生失败测试和独立测试目标**

在 `external_player_utils_test.cpp` 使用伪操作集合覆盖三类行为：

```cpp
const std::string chinese_path = u8R"(D:\视频\电影.mkv)";
ExternalPlayerOperationState state;
const auto opened = ExternalPlayerUtils::OpenWithPlayer(
    chinese_path, state.BuildOperations(/* launch_success=*/true));
assert(opened == ExternalPlayerOpenStatus::kOpened);
assert(state.written_value == L"D:\\视频\\电影.mkv");
assert(state.deleted_now.empty());
assert(state.deleted_later == state.playlist_path);

const auto failed = ExternalPlayerUtils::OpenWithPlayer(
    chinese_path, state.BuildOperations(/* launch_success=*/false));
assert(failed == ExternalPlayerOpenStatus::kLaunchFailed);
assert(state.deleted_now == state.playlist_path);
assert(state.deleted_later.empty());

const auto invalid = ExternalPlayerUtils::Utf8ToUtf16("\xFF");
assert(!invalid.has_value());
```

在 `CMakeLists.txt` 增加 `EXCLUDE_FROM_ALL` 测试目标，链接 `shell32.lib` 与 `ole32.lib`：

```cmake
add_executable(kanyingyin_external_player_tests EXCLUDE_FROM_ALL
  "external_player_utils_test.cpp"
  "external_player_utils.cpp"
)
apply_standard_settings(kanyingyin_external_player_tests)
target_compile_options(kanyingyin_external_player_tests PRIVATE /utf-8)
target_compile_definitions(kanyingyin_external_player_tests PRIVATE "NOMINMAX")
target_link_libraries(kanyingyin_external_player_tests PRIVATE shell32.lib ole32.lib)
```

- [ ] **Step 2: 构建测试目标并确认缺少新接口**

```powershell
D:\flutter\bin\flutter.bat build windows --release
& 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows\x64 --config Release --target kanyingyin_external_player_tests
```

预期：第二条命令 FAIL，提示缺少 `ExternalPlayerOpenStatus`、`Utf8ToUtf16` 或接受操作集合的重载。

- [ ] **Step 3: 实现 UTF-8 转换和可测试生命周期编排**

在头文件定义强类型结果与操作边界：

```cpp
enum class ExternalPlayerOpenStatus {
  kOpened,
  kInvalidUtf8,
  kTemporaryFileFailed,
  kLaunchFailed,
};

struct ExternalPlayerOperations {
  std::function<std::optional<std::wstring>()> create_playlist_path;
  std::function<bool(const std::wstring&, const std::wstring&)> write_playlist;
  std::function<bool(const std::wstring&)> launch;
  std::function<void(const std::wstring&)> delete_now;
  std::function<void(const std::wstring&)> delete_later;
};
```

`Utf8ToUtf16` 必须调用 `MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, ...)`。生产操作使用 `CoCreateGuid` 与 `StringFromGUID2` 在 `GetTempPathW` 返回目录中生成 `kanyingyin_stream_<GUID>.m3u8`，用 UTF-8 BOM 和 `#EXTM3U` 写入播放目标，不把目标内容写入日志。

编排顺序固定为：转换失败返回 `kInvalidUtf8`；路径或写入失败删除已创建文件并返回 `kTemporaryFileFailed`；`ShellExecuteExW` 失败立即 `DeleteFileW` 并返回 `kLaunchFailed`；成功后启动受控线程，30 秒后删除文件，删除失败仅输出不含路径的固定警告。

- [ ] **Step 4: 运行原生行为测试**

```powershell
& 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows\x64 --config Release --target kanyingyin_external_player_tests
& .\build\windows\x64\runner\Release\kanyingyin_external_player_tests.exe
```

预期：构建和进程均以 exit code 0 结束。

- [ ] **Step 5: 提交**

```powershell
git add windows/runner/external_player_utils.h windows/runner/external_player_utils.cpp windows/runner/external_player_utils_test.cpp windows/runner/CMakeLists.txt
git commit -m "修复Windows外部播放临时文件"
```

### Task 2: 外部播放器通道返回明确状态

**Files:**
- Modify: `windows/runner/platform_channels.cpp`
- Modify: `lib/utils/external_player.dart`
- Create: `test/external_player_test.dart`

- [ ] **Step 1: 写入 MethodChannel 行为失败测试**

新增可注入 `MethodChannel` 与警告回调的 `ExternalPlayerClient`，静态 `ExternalPlayer` 继续作为现有调用门面。用 `TestDefaultBinaryMessengerBinding` 注册通道处理器，测试正常 MIME 请求返回 `true`，平台拒绝时返回 `false`，Windows 带 Referer 请求只调用 `openWithReferer` 且收到 `UnsupportedHeaders` 后返回 `false`。注入的警告回调只应收到固定错误分类，不得收到测试 URL、Referer 或令牌。

```dart
final calls = <MethodCall>[];
final warnings = <String>[];
TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMethodCallHandler(ExternalPlayer.platform, (call) async {
  calls.add(call);
  throw PlatformException(code: 'UnsupportedHeaders');
});
expect(
  await ExternalPlayerClient(
    channel: ExternalPlayer.platform,
    warningReporter: warnings.add,
  ).launchURLWithReferer(
    'https://example.com/video?token=secret',
    'https://example.com/private',
  ),
  isFalse,
);
expect(calls.single.method, 'openWithReferer');
expect(warnings, ['UnsupportedHeaders']);
```

- [ ] **Step 2: 运行测试并确认错误处理或可观察接口不满足断言**

```powershell
D:\flutter\bin\flutter.bat test test\external_player_test.dart
```

预期：FAIL，缺少 `ExternalPlayerClient` 与可注入警告回调。

- [ ] **Step 3: 映射原生状态并固定脱敏日志**

`platform_channels.cpp` 对 `openWithMime` 使用 `ExternalPlayerOpenStatus`：仅 `kOpened` 返回 `true`，其余返回固定错误码。对 `openWithReferer` 明确返回：

```cpp
result->Error("UnsupportedHeaders",
              "Windows external playback does not support request headers");
```

`ExternalPlayerClient` 捕获 `PlatformException` 与 `MissingPluginException`，只向警告回调传递 `UnsupportedHeaders`、`LaunchFailed`、`InvalidInput` 或 `PlatformUnavailable` 分类，不传递 `e.message`、URL、Referer 或参数；两种启动方法都以平台返回的 `bool` 为准。静态 `ExternalPlayer` 使用生产客户端并通过 `AppLogger` 记录固定分类，保持 `PlayerController` 调用点不变。

- [ ] **Step 4: 运行外部播放器测试与播放器控制器回归**

```powershell
D:\flutter\bin\flutter.bat test test\external_player_test.dart test\cloud_playback_resolver_test.dart test\local_playback_request_builder_test.dart
```

预期：PASS。

- [ ] **Step 5: 提交**

```powershell
git add windows/runner/platform_channels.cpp lib/utils/external_player.dart test/external_player_test.dart
git commit -m "明确Windows外部播放失败状态"
```

### Task 3: 快捷方式组合状态与纯决策策略

**Files:**
- Modify: `windows/runner/shortcut_utils.h`
- Modify: `windows/runner/shortcut_utils.cpp`
- Modify: `windows/runner/platform_channels.cpp`
- Modify: `lib/utils/windows_shortcut.dart`
- Create: `lib/services/windows_shortcut_startup_policy.dart`
- Create: `test/windows_shortcut_startup_policy_test.dart`

- [ ] **Step 1: 写入入口组合行为失败测试**

测试纯策略的完整状态矩阵：

```dart
expect(decideShortcutStartup(
  state: WindowsShortcutEntryState.desktopOnly,
  dialogAlreadyShown: false,
), ShortcutStartupDecision.repairDesktop);
expect(decideShortcutStartup(
  state: WindowsShortcutEntryState.startMenuOnly,
  dialogAlreadyShown: false,
), ShortcutStartupDecision.skip);
expect(decideShortcutStartup(
  state: WindowsShortcutEntryState.none,
  dialogAlreadyShown: false,
), ShortcutStartupDecision.askToCreateDesktop);
expect(decideShortcutStartup(
  state: WindowsShortcutEntryState.unknown,
  dialogAlreadyShown: false,
), ShortcutStartupDecision.reportDetectionFailure);
```

另用 mock MethodChannel 验证原生整数 `0..3` 映射为 `none`、`desktopOnly`、`startMenuOnly`、`desktopAndStartMenu`，平台异常映射为 `unknown`。

- [ ] **Step 2: 运行测试并确认状态与策略不存在**

```powershell
D:\flutter\bin\flutter.bat test test\windows_shortcut_startup_policy_test.dart
```

预期：FAIL，找不到组合状态或 `decideShortcutStartup`。

- [ ] **Step 3: 实现原生组合状态**

在 C++ 定义：

```cpp
enum class ShortcutEntryState {
  kNone = 0,
  kDesktopOnly = 1,
  kStartMenuOnly = 2,
  kDesktopAndStartMenu = 3,
};

static std::optional<ShortcutEntryState> InspectShortcutEntries(
    const std::wstring& shortcut_name);
```

桌面路径继续使用当前用户桌面；开始菜单先判断当前进程是否具有有效包标识，MSIX 包内运行视为存在开始菜单入口，便携运行则检查当前用户 `FOLDERID_Programs` 与公共 `FOLDERID_CommonPrograms` 下同名 `.lnk`。任一路径解析失败且无法得出可靠结果时返回 `std::nullopt`，平台通道返回 `ShortcutInspectionFailed`，不能把未知状态当成不存在。

- [ ] **Step 4: 实现 Dart 状态映射与决策函数**

```dart
enum WindowsShortcutEntryState {
  none,
  desktopOnly,
  startMenuOnly,
  desktopAndStartMenu,
  unknown,
}

enum ShortcutStartupDecision {
  repairDesktop,
  askToCreateDesktop,
  skip,
  reportDetectionFailure,
}
```

规则为：桌面存在时修复；仅开始菜单存在时跳过；两者都不存在且本次安装未询问时询问；已询问时跳过；检测失败时报告并保留下次重试。

- [ ] **Step 5: 运行快捷方式状态测试**

```powershell
D:\flutter\bin\flutter.bat test test\windows_shortcut_startup_policy_test.dart test\windows_shortcut_repair_test.dart
```

预期：PASS。

- [ ] **Step 6: 提交**

```powershell
git add windows/runner/shortcut_utils.h windows/runner/shortcut_utils.cpp windows/runner/platform_channels.cpp lib/utils/windows_shortcut.dart lib/services/windows_shortcut_startup_policy.dart test/windows_shortcut_startup_policy_test.dart
git commit -m "区分Windows快捷方式入口状态"
```

### Task 4: 启动页执行快捷方式决策

**Files:**
- Modify: `lib/pages/init_page.dart`
- Modify: `test/windows_shortcut_repair_test.dart`
- Create: `test/windows_shortcut_startup_coordinator_test.dart`

- [ ] **Step 1: 写入启动协调器失败测试**

把快捷方式启动流程抽成可注入回调的 `WindowsShortcutStartupCoordinator`，用内存回调测试：桌面存在时调用一次修复且不询问；仅开始菜单存在时两者都不调用；均不存在时按用户选择创建并记住已询问；检测失败时报告一次且不写 `shortcutDialogShown`。

```dart
final result = await coordinator.run(
  state: WindowsShortcutEntryState.unknown,
  dialogAlreadyShown: false,
  askToCreate: () async => true,
  repairOrCreate: () async => true,
);
expect(result.reportDetectionFailure, isTrue);
expect(result.markDialogShown, isFalse);
expect(askCount, 0);
```

- [ ] **Step 2: 运行测试并确认协调器不存在**

```powershell
D:\flutter\bin\flutter.bat test test\windows_shortcut_startup_coordinator_test.dart
```

预期：FAIL，找不到 `WindowsShortcutStartupCoordinator`。

- [ ] **Step 3: 实现协调器并接入 `InitPage`**

协调器只返回强类型结果，不依赖 Widget、Hive 或静态对话框。`InitPage._showShortcutDialog()` 读取状态和 `shortcutDialogShown` 后执行协调器：

- `repairDesktop`：覆盖修复现有桌面快捷方式，失败显示“桌面快捷方式修复失败”。
- `askToCreateDesktop`：保留现有不可遮罩对话框；用户明确拒绝或创建后才将 `shortcutDialogShown` 写为 `true`。
- `skip`：不写设置、不弹窗。
- `reportDetectionFailure`：显示“无法检查快捷方式状态，将在下次启动时重试”，不写设置、不创建快捷方式。

- [ ] **Step 4: 运行启动流程和应用生命周期回归**

```powershell
D:\flutter\bin\flutter.bat test test\windows_shortcut_startup_coordinator_test.dart test\windows_shortcut_repair_test.dart test\app_widget_lifecycle_test.dart
```

预期：PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/pages/init_page.dart lib/services/windows_shortcut_startup_policy.dart test/windows_shortcut_startup_coordinator_test.dart test/windows_shortcut_repair_test.dart
git commit -m "修复启动快捷方式询问逻辑"
```

### Task 5: 第三批完整验证

**Files:**
- Verify only

- [ ] **Step 1: 运行原生外部播放器测试**

```powershell
& 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows\x64 --config Release --target kanyingyin_external_player_tests
& .\build\windows\x64\runner\Release\kanyingyin_external_player_tests.exe
```

- [ ] **Step 2: 执行 Flutter 格式、完整测试和分析**

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed .
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
```

- [ ] **Step 3: 构建 Windows Release**

```powershell
D:\flutter\bin\flutter.bat build windows --release
```

预期：全部命令 exit code 0。实机验收补充检查中文本地路径唤起、成功/失败临时文件清理、Referer 明确失败、桌面与开始菜单四种入口组合；若自动化环境无法操作默认播放器或开始菜单，只记录未覆盖的人工验收项，不伪报通过。
