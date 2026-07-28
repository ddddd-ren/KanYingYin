# TrueHD 与 PGS 解码器修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Windows 安装包恢复 TrueHD 音频与 PGS 字幕解码，同时保留当前硬件解码零拷贝路径和 Anime4K 行为。

**Architecture:** Windows 构建继续使用现有 media_kit 插件和渲染绑定，但在顶层 CMake 中排除插件携带的精简 `libmpv-2.dll`，改为安装固定版本、固定 SHA-256 的完整标准 x64 libmpv。Dart 播放器代码不改，避免恢复旧版强制 copy 模式和分辨率相关行为。

**Tech Stack:** Flutter 3.41.9、Dart 3.11、media_kit/libmpv、CMake、flutter_test、Windows MSIX、SignTool

---

## 文件结构

- 新建 `windows/cmake/full_libmpv.cmake`：下载、校验、解压并暴露完整 `libmpv-2.dll` 路径。
- 修改 `windows/CMakeLists.txt`：排除插件精简 DLL，安装完整 DLL。
- 修改 `test/windows_full_libmpv_config_test.dart`：锁定完整解码组件和零拷贝代码契约。
- 修改 `pubspec.yaml`：升级应用与 MSIX 版本到 2.1.65。
- 修改 `RELEASE_NOTES.md`：增加面向用户的 2.1.65 更新说明。
- 修改 `lib/utils/version_history.dart`：增加应用内 2.1.65 版本历史。

### Task 1: 建立失败的 Windows 解码组件契约测试

**Files:**
- Modify: `test/windows_full_libmpv_config_test.dart`
- Test: `test/windows_full_libmpv_config_test.dart`

- [x] **Step 1: 将现有精简 DLL 契约改为完整解码 DLL 契约**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 构建覆盖为支持 TrueHD 与 PGS 的完整 libmpv', () {
    final config = File('windows/cmake/full_libmpv.cmake').readAsStringSync();
    final root = File('windows/CMakeLists.txt').readAsStringSync();
    final player =
        File('lib/pages/player/player_controller.dart').readAsStringSync();

    expect(config, contains('mpv-dev-x86_64-20260610-git-304426c.7z'));
    expect(
      config,
      contains(
        'SHA256=8cbb25ea784f01afbb3f904217cab1317430a8bcfd5680fd827a866367f71cc9',
      ),
    );
    expect(config, contains('EXPECTED_HASH'));
    expect(
      root,
      contains('list(FILTER PLUGIN_BUNDLED_LIBRARIES EXCLUDE REGEX'),
    );
    expect(root, contains('FULL_LIBMPV_DLL'));

    final pluginInstall = root.indexOf('if(PLUGIN_BUNDLED_LIBRARIES)');
    final fullMpvInstall =
        root.indexOf('install(FILES "\${FULL_LIBMPV_DLL}"');
    expect(fullMpvInstall, greaterThan(pluginInstall));
    expect(player, isNot(contains('hardwareDecoder = effectiveHardwareDecoder(')));
  });
}
```

- [x] **Step 2: 运行测试并确认红灯原因是完整配置不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/windows_full_libmpv_config_test.dart`

Expected: FAIL，`windows/cmake/full_libmpv.cmake` 不存在或完整 DLL 断言不成立。

### Task 2: 接入完整 libmpv 并保持零拷贝路径

**Files:**
- Create: `windows/cmake/full_libmpv.cmake`
- Modify: `windows/CMakeLists.txt`
- Test: `test/windows_full_libmpv_config_test.dart`

- [x] **Step 1: 新建固定版本与哈希的完整 libmpv 配置**

```cmake
set(FULL_LIBMPV_VERSION "20260610")
set(FULL_LIBMPV_ARCHIVE_NAME "mpv-dev-x86_64-20260610-git-304426c.7z")
set(FULL_LIBMPV_SHA256 "8cbb25ea784f01afbb3f904217cab1317430a8bcfd5680fd827a866367f71cc9")
set(FULL_LIBMPV_CACHE_DIR "${CMAKE_BINARY_DIR}/full_libmpv")
set(FULL_LIBMPV_ARCHIVE "${FULL_LIBMPV_CACHE_DIR}/${FULL_LIBMPV_ARCHIVE_NAME}")
set(FULL_LIBMPV_DIR "${FULL_LIBMPV_CACHE_DIR}/verified")

file(MAKE_DIRECTORY "${FULL_LIBMPV_CACHE_DIR}")

set(FULL_LIBMPV_ARCHIVE_VALID FALSE)
if(EXISTS "${FULL_LIBMPV_ARCHIVE}")
  file(SHA256 "${FULL_LIBMPV_ARCHIVE}" FULL_LIBMPV_CACHED_SHA256)
  if(FULL_LIBMPV_CACHED_SHA256 STREQUAL FULL_LIBMPV_SHA256)
    set(FULL_LIBMPV_ARCHIVE_VALID TRUE)
  else()
    file(REMOVE "${FULL_LIBMPV_ARCHIVE}")
  endif()
endif()

if(NOT FULL_LIBMPV_ARCHIVE_VALID)
  file(DOWNLOAD
    "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/${FULL_LIBMPV_VERSION}/${FULL_LIBMPV_ARCHIVE_NAME}"
    "${FULL_LIBMPV_ARCHIVE}"
    EXPECTED_HASH "SHA256=8cbb25ea784f01afbb3f904217cab1317430a8bcfd5680fd827a866367f71cc9"
    TLS_VERIFY ON
    SHOW_PROGRESS
  )
endif()

file(REMOVE_RECURSE "${FULL_LIBMPV_DIR}")
file(MAKE_DIRECTORY "${FULL_LIBMPV_DIR}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E tar xzf "${FULL_LIBMPV_ARCHIVE}"
  WORKING_DIRECTORY "${FULL_LIBMPV_DIR}"
  COMMAND_ERROR_IS_FATAL ANY
)

set(FULL_LIBMPV_DLL "${FULL_LIBMPV_DIR}/libmpv-2.dll")
if(NOT EXISTS "${FULL_LIBMPV_DLL}")
  message(FATAL_ERROR "完整 libmpv 解压后缺少 libmpv-2.dll")
endif()
```

- [x] **Step 2: 在插件生成后排除精简 DLL**

在 `include(flutter/generated_plugins.cmake)` 后加入：

```cmake
include(cmake/full_libmpv.cmake)

list(FILTER PLUGIN_BUNDLED_LIBRARIES EXCLUDE REGEX "[/\\\\]libmpv-2\\.dll$")
```

- [x] **Step 3: 在插件库安装后复制完整 DLL**

在 `if(PLUGIN_BUNDLED_LIBRARIES)` 安装块后加入：

```cmake
install(FILES "${FULL_LIBMPV_DLL}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
```

- [x] **Step 4: 运行契约测试并确认绿灯**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/windows_full_libmpv_config_test.dart`

Expected: PASS，1 项测试通过。

- [x] **Step 5: 提交解码组件修复**

```powershell
git add -- test/windows_full_libmpv_config_test.dart windows/CMakeLists.txt windows/cmake/full_libmpv.cmake
git diff --cached --check
git commit -m "修复 TrueHD 与 PGS 解码组件"
```

### Task 3: 更新 2.1.65 版本与用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`

- [x] **Step 1: 将应用版本与 MSIX 版本同步升级**

```yaml
version: 2.1.65+20165
```

```yaml
  msix_version: 2.1.65.0
```

- [x] **Step 2: 同步应用常量、README 和版本契约测试**

将 `lib/core/app_version.dart`、`README.md`、`test/identity_v2_zero_residue_test.dart` 和 `test/version_consistency_test.dart` 中的当前版本同步为 `2.1.65`，构建号同步为 `20165`；在 `test/version_history_current_test.dart` 增加 TrueHD、PGS、硬件解码、零拷贝、Anime4K 和原文件保护断言。

- [x] **Step 3: 在发布说明顶部加入 2.1.65 文案**

```markdown
## 2.1.65+20165

MSIX 版本：2.1.65.0

### 更新弹窗文案

标题：看影音 2.1.65 测试版

- 修复只有 TrueHD 音轨的视频能够识别音轨却没有声音的问题。
- 修复蓝光 PGS 内嵌字幕能够识别字幕轨却无法显示的问题。
- 保留现有 Windows 硬件解码、4K 零拷贝渲染和 Anime4K 行为，不改变音轨与字幕选择方式。
- 本次更新只替换播放器解码组件，不会修改或删除，也不会转码本地与网盘媒体库中的原始视频和字幕文件。
```

- [x] **Step 4: 同步更新弹窗文案与版本历史**

```dart
  VersionHistory(
    version: '2.1.65',
    date: '2026-07-28',
    isPrerelease: true,
    changes: [
      '修复只有 TrueHD 音轨的视频能够识别音轨却没有声音的问题',
      '修复蓝光 PGS 内嵌字幕能够识别字幕轨却无法显示的问题',
      '保留现有 Windows 硬件解码、4K 零拷贝渲染和 Anime4K 行为，不改变音轨与字幕选择方式',
      '本次更新只替换播放器解码组件，不会修改或删除，也不会转码本地与网盘媒体库中的原始视频和字幕文件',
    ],
  ),
```

- [x] **Step 5: 运行版本契约测试并核对所有版本位置**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/release_config_contract_test.dart test/identity_v2_zero_residue_test.dart test/version_consistency_test.dart test/version_history_current_test.dart`

Run: `rg -n "2.1.65|20165" pubspec.yaml lib/core/app_version.dart README.md UPDATE_DIALOG_COPY.md RELEASE_NOTES.md lib/utils/version_history.dart test/identity_v2_zero_residue_test.dart test/version_consistency_test.dart`

Expected: 测试 PASS；应用版本、MSIX 版本、发布说明和版本历史均包含 2.1.65 对应内容。

### Task 4: 完整验证 Windows Release 与解码能力

**Files:**
- Verify: `build/windows/x64/runner/Release/libmpv-2.dll`
- Verify: `build/windows/x64/full_libmpv/verified/libmpv-2.dll`

- [x] **Step 1: 运行全量测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub`

Expected: 全部测试通过，0 failures。

- [x] **Step 2: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`

- [x] **Step 3: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: Exit code 0，生成 `build/windows/x64/runner/Release/kanyingyin.exe` 和完整 `libmpv-2.dll`。

- [x] **Step 4: 校验 Release 使用完整 DLL**

```powershell
$releaseDll = 'build\windows\x64\runner\Release\libmpv-2.dll'
$verifiedDll = 'build\windows\x64\full_libmpv\verified\libmpv-2.dll'
if (-not (Test-Path -LiteralPath $releaseDll) -or
    -not (Test-Path -LiteralPath $verifiedDll)) {
  throw '缺少完整 libmpv 构建产物'
}
$releaseHash = (Get-FileHash -LiteralPath $releaseDll -Algorithm SHA256).Hash
$verifiedHash = (Get-FileHash -LiteralPath $verifiedDll -Algorithm SHA256).Hash
if ($releaseHash -ne $verifiedHash) { throw 'Release DLL 不是经过校验的完整 libmpv' }
if ((Get-Item -LiteralPath $releaseDll).Length -le 100MB) {
  throw 'Release libmpv 体积异常，可能仍是精简版'
}
```

Expected: 两份 DLL 的 SHA-256 相同，Release DLL 大于 100 MB。

- [x] **Step 5: 使用独立 TrueHD 与 PGS 样本复验解码器**

通过 libmpv 客户端 API 分别加载 FFmpeg 官方 TrueHD 与 PGS 样本，确认：

```text
Selected decoder: truehd
Using subtitle decoder pgssub
```

同时确认不再出现：

```text
Failed to initialize a decoder for codec 'truehd'
Could not find subtitle decoder for format 'hdmv_pgs_subtitle'
Audio: no audio
```

### Task 5: 生成、验证并提交 2.1.65 MSIX

**Files:**
- Generate: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.65.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.65-异机安装包.zip`

- [x] **Step 1: 使用项目签名脚本生成 Release 与 MSIX**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/windows/build_signed_release.ps1`

Expected: Windows Release 构建、MSIX 创建、SignTool 签名与验证均成功；桌面生成 2.1.65 的 MSIX 和异机安装 ZIP。

- [x] **Step 2: 核对 MSIX 清单与 DLL**

解压读取 `AppxManifest.xml`，确认 Identity 为 `com.kanyingyin.player`、版本为 `2.1.65.0`、架构为 `x64`。读取 MSIX 内 `libmpv-2.dll`，确认其大小大于 100 MB，且 SHA-256 与 Release DLL 相同。

- [x] **Step 3: 检查本轮差异并提交**

```powershell
git status --short
git diff --check
git diff -- pubspec.yaml RELEASE_NOTES.md lib/utils/version_history.dart
git add -- pubspec.yaml RELEASE_NOTES.md lib/utils/version_history.dart docs/superpowers/plans/2026-07-28-truehd-pgs-decoder-repair.md
git diff --cached --check
git commit -m "发布 TrueHD 与 PGS 解码修复"
```

- [x] **Step 4: 最终状态核对**

Run: `git status --short --branch`

Expected: 工作区干净；当前分支包含设计提交、解码组件修复提交和 2.1.65 发布提交。
