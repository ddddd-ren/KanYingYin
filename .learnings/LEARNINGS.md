# Learnings

Corrections, insights, and knowledge gaps captured during development.

**Categories**: correction | insight | knowledge_gap | best_practice

---

## [LRN-20260623-001] best_practice

**Logged**: 2026-06-23T03:15:21+08:00
**Priority**: high
**Status**: pending
**Area**: infra

### Summary
KanYingYin Windows/MSIX 打包应优先使用锁文件离线恢复依赖，再用 `--no-pub` 构建，避免 Flutter 依赖解析改写 lockfile 或触发 Dart VM 崩溃。

### Details
本次 `flutter build windows --release` 先触发 `pubspec.lock` 镜像源改写，随后 Dart VM 在依赖解析/assemble 路径出现崩溃。有效路径是先还原 `pubspec.lock`，用项目内独立 `.dart_appdata` 配合 `PUB_HOSTED_URL=https://pub.dev`、`FLUTTER_STORAGE_BASE_URL=https://storage.googleapis.com` 执行 `flutter pub get --offline --enforce-lockfile`，然后执行 `flutter build windows --release --no-pub`。

### Suggested Action
后续 KanYingYin 打包前先确认 `git status --short`，打包依赖恢复使用锁文件离线模式；构建和 MSIX 阶段尽量加 `--no-pub` 或 `--build-windows=false`，结束后清理 `.dart_appdata` 并确认 `pubspec.lock` 未变。

### Metadata
- Source: conversation
- Related Files: pubspec.yaml, pubspec.lock
- Tags: kanyingyin, flutter, msix, lockfile, windows
- Pattern-Key: kanyingyin.package.locked_no_pub
- Recurrence-Count: 1
- First-Seen: 2026-06-23
- Last-Seen: 2026-06-23

---

## [LRN-20260717-001] best_practice

**Logged**: 2026-07-17T02:20:00+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
PowerShell 双引号字符串中，变量后紧接中文字符时应使用 `${variable}` 明确边界。

### Details
`"第$episode集"` 会把 `episode集` 解析为变量名，导致集号消失；应写成 `"第${episode}集"`。媒体改名必须先检查重复目标，才能在写入前发现这类错误。

### Suggested Action
PowerShell 生成中文路径时统一使用 `${variable}`，并在批量移动或复制前按目标路径分组检查冲突。

### Metadata
- Source: error
- Related Files: none
- Tags: powershell, unicode, file-rename, preflight

---

## [LRN-20260623-002] best_practice

**Logged**: 2026-06-23T03:15:21+08:00
**Priority**: high
**Status**: pending
**Area**: infra

### Summary
KanYingYin 的 `media_kit_libs_windows_video` 如遇 `mpv-dev...7z` 0 字节或 SHA 校验失败，可手动用 `curl --ssl-no-revoke` 下载并校验目标 SHA 后重跑构建。

### Details
插件 CMake 会下载 `https://github.com/Predidit/libmpv-win32-video-cmake/releases/download/20251210/mpv-dev-x86_64-20251210-git-ad59ff1.7z` 到 `build\windows\x64`，要求 SHA256 为 `53212bb8886d76d041ecd023a29e6213ada6fb5afedb8970610b396435833b99`。CMake 内置下载在本机生成 0 字节文件并失败；普通 `curl` 又因 Schannel 吊销检查失败。加入 `--ssl-no-revoke` 后下载成功，SHA 匹配，后续构建通过该步骤。

### Suggested Action
遇到同类错误时删除损坏的 `build\windows\x64\mpv-dev-x86_64-20251210-git-ad59ff1.7z`，用 `curl.exe --ssl-no-revoke -L --fail --retry 3` 下载到同一路径，并用 `Get-FileHash -Algorithm SHA256` 校验后再构建。

### Metadata
- Source: error
- Related Files: windows/flutter/ephemeral/.plugin_symlinks/media_kit_libs_windows_video/windows/CMakeLists.txt
- Tags: kanyingyin, media-kit, libmpv, cmake, download
- Pattern-Key: kanyingyin.package.libmpv_manual_download
- Recurrence-Count: 1
- First-Seen: 2026-06-23
- Last-Seen: 2026-06-23

---

## [LRN-20260722-001] best_practice

**Logged**: 2026-07-22T08:55:00+08:00
**Priority**: high
**Status**: active
**Area**: release

### Summary
[LEARN] Release: 每次看影音版本更新开始前，必须查询并记录 Windows 当前已安装的 MSIX 版本，不得仅根据 `pubspec.yaml` 推断；交付后再次核对安装包版本。

### Details
Mistake：2.1.34 更新前未先查询系统已安装版本。

Correction：使用 `Get-AppxPackage -Name com.kanyingyin.player` 检测；未安装也要明确记录。生成安装包后核对包版本，若执行安装则再次查询已安装版本。

本规则首次执行时，当前用户已安装 `com.kanyingyin.player 2.1.34.0 x64`。

### 检查记录
- 2026-07-22：重新打包前复核，当前用户已安装 `com.kanyingyin.player 2.1.34.0 x64`。

### Metadata
- Source: user_correction
- Related Files: AGENTS.md, pubspec.yaml, tool/windows/build_signed_release.ps1
- Tags: kanyingyin, release, msix, installed-version
- Pattern-Key: kanyingyin.release.check_installed_version
- Recurrence-Count: 1
- First-Seen: 2026-07-22
- Last-Seen: 2026-07-22

---

## [LRN-20260623-003] best_practice

**Logged**: 2026-06-23T03:15:21+08:00
**Priority**: medium
**Status**: pending
**Area**: infra

### Summary
KanYingYin Release 构建成功后，MSIX 打包可用 `dart run msix:create --build-windows=false` 复用已有 Release 目录，避免重复编译和重复触发依赖问题。

### Details
`msix` 3.17.0 支持 CLI 参数 `--build-windows=false`。本次在 `flutter build windows --release --no-pub` 成功后，用该参数直接从 `build\windows\x64\runner\Release` 生成 MSIX，避免重复触发 Flutter build、NuGet 下载或 Dart VM 依赖解析路径。

### Suggested Action
后续 KanYingYin 若已成功生成 Release 目录，优先使用 `D:\flutter\bin\cache\dart-sdk\bin\dart.exe run msix:create --build-windows=false`。打包完成后复制为 `C:\Users\asus\Desktop\看影音-<版本>.msix` 并校验源/目标大小一致。

### Metadata
- Source: conversation
- Related Files: pubspec.yaml
- Tags: kanyingyin, msix, packaging
- Pattern-Key: kanyingyin.package.msix_reuse_release
- Recurrence-Count: 1
- First-Seen: 2026-06-23
- Last-Seen: 2026-06-23

---

## [LRN-20260623-004] insight

**Logged**: 2026-06-23T03:15:21+08:00
**Priority**: medium
**Status**: pending
**Area**: infra

### Summary
自我反思：打包任务不应在首次失败后继续把过期产物当成功，应明确区分历史产物、失败构建和当前可交付包。

### Details
Release 构建失败时，输出目录可能仍有历史 MSIX。正确处理是拒绝把它当成本轮产物，先清理并重建，直到构建和 `msix:create` 都明确成功，再复制到桌面。这条做法可以避免误交付过期产物。

### Suggested Action
后续所有 release-like 任务都按“构建命令成功 -> 产物时间戳/大小校验 -> 复制到交付位置 -> 再次校验”的顺序收口，不用目录里已有文件替代本轮成功证据。

### Metadata
- Source: self_reflection
- Related Files: build/windows/x64/runner/Release/*.msix
- Tags: release, artifact, verification
- Pattern-Key: release.artifact_current_success_only
- Recurrence-Count: 1
- First-Seen: 2026-06-23
- Last-Seen: 2026-06-23

---
