# 桌面快捷方式图标修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 自动修复 Windows 桌面已有“看影音”快捷方式的旧 AUMID 和失效图标路径，同时保留缺失快捷方式时由用户确认创建的行为。

**Architecture:** Windows 原生层提供快捷方式存在性检查，并让创建函数始终以当前包身份和当前 EXE 图标覆盖保存。Dart 初始化流程先判断快捷方式是否存在：存在则静默修复，不存在则执行现有首次询问；发布版本升级为 2.0.9 并重新生成签名 MSIX。

**Tech Stack:** Flutter 3.41.9、Dart 3.11、Flutter MethodChannel、Windows Shell Link COM、MSIX、flutter_test。

---

### Task 1: 修复 Windows 原生快捷方式目标与图标

**Files:**
- Modify: `windows/runner/shortcut_utils.h`
- Modify: `windows/runner/shortcut_utils.cpp`
- Modify: `windows/runner/platform_channels.cpp`
- Create: `test/windows_shortcut_repair_test.dart`
- Modify: `test/runtime_identity_residue_test.dart`

- [ ] **Step 1: 写原生源码契约失败测试**

```dart
test('原生快捷方式会覆盖旧文件并使用当前包与当前图标', () {
  final source = File('windows/runner/shortcut_utils.cpp').readAsStringSync();
  expect(source, isNot(contains('INVALID_FILE_ATTRIBUTES) return true')));
  expect(source, contains('SetArguments'));
  expect(source, contains(r'shell:AppsFolder\'));
  expect(source, contains('SetIconLocation(exePath, 0)'));
  expect(source, contains('GetWindowsDirectoryW'));
});

test('原生通道提供存在性检查并使用看影音文案', () {
  final source = File('windows/runner/platform_channels.cpp').readAsStringSync();
  expect(source, contains('desktopShortcutExists'));
  expect(source, contains(r'\x770B\x5F71\x97F3'));
  expect(source, isNot(contains(r'\x5C31\x770B')));
  expect(source, isNot(contains(r'\x5728\x7EBF')));
});
```

- [ ] **Step 2: 运行测试确认旧实现失败**

Run: `D:\flutter\bin\flutter.bat test test\windows_shortcut_repair_test.dart test\runtime_identity_residue_test.dart`

Expected: FAIL，指出已有快捷方式提前返回、缺少 `desktopShortcutExists`、缺少显式图标和旧文案仍存在。

- [ ] **Step 3: 实现原生覆盖与存在性检查**

在 `ShortcutUtils` 增加：

```cpp
static bool DesktopShortcutExists(const std::wstring& shortcutName);
```

`CreateDesktopShortcut` 不再因 `.lnk` 存在而返回。取得当前 `exePath` 后，两种运行模式都调用：

```cpp
pShellLink->SetIconLocation(exePath, 0);
```

MSIX 模式使用 Windows `explorer.exe` 和 AppsFolder 参数：

```cpp
std::wstring arguments = L"shell:AppsFolder\\" + aumid;
pShellLink->SetPath(explorerPath.c_str());
pShellLink->SetArguments(arguments.c_str());
```

保留 `PKEY_AppUserModel_ID`。便携模式直接 `SetPath(exePath)`。保存时使用 `IPersistFile::Save(..., TRUE)` 覆盖旧快捷方式。

原生通道处理两个方法：

```cpp
if (call.method_name() == "desktopShortcutExists") { ... }
if (call.method_name() == "createDesktopShortcut") { ... }
```

名称使用 `L"\x770B\x5F71\x97F3"`，描述使用 `L"\x542F\x52A8\x770B\x5F71\x97F3"`。

- [ ] **Step 4: 运行原生契约测试转绿**

Run: `D:\flutter\bin\flutter.bat test test\windows_shortcut_repair_test.dart test\runtime_identity_residue_test.dart`

Expected: PASS。

### Task 2: 启动时只修复已有快捷方式

**Files:**
- Modify: `lib/utils/windows_shortcut.dart`
- Modify: `lib/pages/init_page.dart`
- Modify: `test/windows_shortcut_repair_test.dart`

- [ ] **Step 1: 写 Dart 流程失败测试**

源码契约必须确认：

```dart
expect(shortcutSource, contains("invokeMethod<bool>('desktopShortcutExists')"));
expect(initSource, contains('await WindowsShortcut.desktopShortcutExists()'));
expect(initSource, contains('await WindowsShortcut.createDesktopShortcut()'));
expect(initSource.indexOf('desktopShortcutExists'),
    lessThan(initSource.indexOf('shortcutDialogShown')));
```

这保证已有快捷方式在读取“已询问”标志前就会修复，而不存在时仍受原标志与弹窗控制。

- [ ] **Step 2: 运行测试确认 Dart API 和流程尚不存在**

Run: `D:\flutter\bin\flutter.bat test test\windows_shortcut_repair_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现存在性 API 与初始化修复**

`WindowsShortcut` 新增：

```dart
static Future<bool> desktopShortcutExists() async {
  if (!Platform.isWindows) return false;
  try {
    return await _channel.invokeMethod<bool>('desktopShortcutExists') ?? false;
  } catch (error) {
    debugPrint('Failed to inspect desktop shortcut: $error');
    return false;
  }
}
```

`_showShortcutDialog` 开头执行：

```dart
final shortcutExists = await WindowsShortcut.desktopShortcutExists();
if (shortcutExists) {
  await WindowsShortcut.createDesktopShortcut();
  return;
}
```

之后保留现有 `shortcutDialogShown`、询问和创建逻辑。

- [ ] **Step 4: 运行快捷方式和初始化测试**

Run: `D:\flutter\bin\flutter.bat test test\windows_shortcut_repair_test.dart test\runtime_identity_residue_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交功能修复**

```powershell
git add -- windows/runner/shortcut_utils.h windows/runner/shortcut_utils.cpp windows/runner/platform_channels.cpp lib/utils/windows_shortcut.dart lib/pages/init_page.dart test/windows_shortcut_repair_test.dart test/runtime_identity_residue_test.dart
git commit -m "修复桌面快捷方式图标"
```

### Task 3: 更新 2.0.9 发布版本

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/request/config/api_endpoints.dart`
- Modify: `README.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 写 2.0.9 版本与文案失败测试**

更新版本测试期望 `2.0.9+20009` / `2.0.9.0`，并要求当前版本区块包含“桌面快捷方式”“图标”“自动修复”。

- [ ] **Step 2: 运行版本测试确认当前 2.0.8 失败**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart`

Expected: FAIL，实际版本为 2.0.8 且缺少修复文案。

- [ ] **Step 3: 更新版本与用户文案**

版本更新为：

```yaml
version: 2.0.9+20009
msix_version: 2.0.9.0
```

发布说明、更新弹窗和版本历史置顶写明：

```text
- 修复应用升级后桌面快捷方式可能显示空白图标的问题。
- 启动应用时会自动修复已有快捷方式的目标和图标，不会静默创建用户已删除的快捷方式。
```

同步 API 版本和 README 当前版本。

- [ ] **Step 4: 运行版本测试转绿并提交**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart`

Expected: PASS。

```powershell
git add -- pubspec.yaml lib/request/config/api_endpoints.dart README.md UPDATE_DIALOG_COPY.md RELEASE_NOTES.md lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart
git commit -m "更新二点零点九版本说明"
```

### Task 4: 验证、打包并修复当前桌面

**Files:**
- Verify: all changed files
- Output: `%USERPROFILE%\Desktop\看影音-2.0.9.msix`
- Update: `%USERPROFILE%\Desktop\看影音.lnk`

- [ ] **Step 1: 运行完整质量检查**

Run: `D:\flutter\bin\flutter.bat test --reporter compact`

Expected: exit 0。

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`。

- [ ] **Step 2: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: exit 0，`kanyingyin.exe` 和 `data\app.so` 为本轮时间。

- [ ] **Step 3: 生成签名 MSIX**

从 `%USERPROFILE%\.kanyingyin\signing\certificate-password.clixml` 读取 DPAPI `SecureString`，安全传给：

```powershell
D:\flutter\bin\cache\dart-sdk\bin\dart.exe run msix:create --build-windows false --certificate-password $password
```

不得输出或保存明文密码。

- [ ] **Step 4: 验证并复制安装包**

读取 MSIX 中 `AppxManifest.xml`，确认：

```text
Identity.Name=com.kanyingyin.player
Identity.Version=2.0.9.0
DisplayName=看影音
Signature=Valid
```

复制为 `%USERPROFILE%\Desktop\看影音-2.0.9.msix`，比较源包和桌面包 SHA-256。

- [ ] **Step 5: 立即修复当前桌面快捷方式**

查询已安装的正式 `com.kanyingyin.player` 包，取得当前 `PackageFamilyName`、`InstallLocation` 和 `kanyingyin.exe`。覆盖 `%USERPROFILE%\Desktop\看影音.lnk`：

```text
TargetPath=%WINDIR%\explorer.exe
Arguments=shell:AppsFolder\<PackageFamilyName>!kanyingyin
IconLocation=<InstallLocation>\kanyingyin.exe,0
Description=启动看影音
```

验证快捷方式目标存在、图标文件存在，且不再引用 `.v2` 或旧版本目录。

- [ ] **Step 6: 最终提交与状态检查**

确认 `git status --short` 干净，所有源码提交已进入 `main`。构建产物和桌面快捷方式不加入 Git。
