# KanYingYin 残留隔离清理实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在独立 worktree 中清除看影音运行时代码和内部标识中的 KanYingYin 残留，仅保留签名证书主体、上游依赖地址与历史文档白名单。

**Architecture:** 先用源码契约测试锁定 Windows/Dart 通道、AUMID、临时文件和工程身份，再同步修改平台两端。随后将日志与弹窗类型改为产品无关的 `App*` 命名，最后为旧 `kanyingyin://` 数据提供只读兼容并让新数据写入 `kanyingyin://`。

**Tech Stack:** Flutter 3.41.9、Dart、Windows C++、CMake、MSIX、flutter_test。

---

### Task 1: 运行时身份与平台通道

**Files:**
- Create: `test/runtime_identity_residue_test.dart`
- Modify: `windows/CMakeLists.txt`
- Modify: `windows/runner/platform_channels.cpp`
- Modify: `windows/runner/shortcut_utils.cpp`
- Modify: `windows/runner/external_player_utils.cpp`
- Modify: `lib/utils/windows_shortcut.dart`
- Modify: `lib/utils/window_utils.dart`
- Modify: `lib/utils/display_utils.dart`
- Modify: `lib/utils/external_player.dart`
- Modify: `lib/utils/pip_utils.dart`
- Modify: `lib/app_widget.dart`
- Modify: `lib/services/audio_controller.dart`

- [ ] **Step 1:** 新增失败测试，禁止运行时代码出现 `com.predidit.kanyingyin`、`!kanyingyin`、`kanyingyin_stream_`、旧托盘与音频标识和 `project(kanyingyin)`。
- [ ] **Step 2:** 运行 `D:\flutter\bin\flutter.bat test test/runtime_identity_residue_test.dart`，确认因旧标识存在而失败。
- [ ] **Step 3:** 将 Dart 与 C++ 通道同步改为 `com.kanyingyin.player/*`，AUMID 改为 Manifest 证实的 `!kanyingyin`，其余运行时标识改为看影音身份。
- [ ] **Step 4:** 重跑测试并通过。

### Task 2: 内部类型与测试前缀

**Files:**
- Modify: `lib/utils/logger.dart`
- Modify: `lib/bean/dialog/dialog_helper.dart`
- Modify: `lib/**/*.dart`
- Modify: `test/**/*.dart`

- [ ] **Step 1:** 扩展失败测试，禁止 `AppLogger`、`KanYingYinLog*`、`KanYingYinDialog*` 及 `kanyingyin_` 测试临时目录前缀。
- [ ] **Step 2:** 运行目标测试确认失败。
- [ ] **Step 3:** 使用 Dart 标识符级重命名改为 `AppLogger`、`AppLog*`、`AppDialog*`，同步测试引用和路由名。
- [ ] **Step 4:** 运行目标测试、日志测试和弹窗相关测试。

### Task 3: 旧协议兼容与签名配置

**Files:**
- Modify: `lib/utils/encoding_utils.dart`
- Modify: `lib/utils/utils.dart`
- Modify: `test/encoding_utils_test.dart`
- Modify: `pubspec.yaml`

- [ ] **Step 1:** 新增失败测试，要求写入 `kanyingyin://`，读取同时兼容 `kanyingyin://` 与 `kanyingyin://`。
- [ ] **Step 2:** 运行目标测试确认失败。
- [ ] **Step 3:** 实现双读单写迁移，并移除 `pubspec.yaml` 中明文证书密码；`CN=KanYingYin` 因现有证书主体列入明确白名单。
- [ ] **Step 4:** 运行协议测试和版本一致性测试。

### Task 4: 版本、回归与交付验证

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/request/config/api_endpoints.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1:** 更新至 `1.4.12+10412` / `1.4.12.0` 并同步普通用户文案。
- [ ] **Step 2:** 运行残留扫描，运行时代码只允许 `CN=KanYingYin` 证书主体和旧协议兼容常量。
- [ ] **Step 3:** 运行 `flutter test` 与 `flutter analyze`。
- [ ] **Step 4:** 运行 `flutter build windows --release --no-pub`，验证 Windows C++ 通道和快捷方式代码可编译。
- [ ] **Step 5:** 检查关键 diff，仅提交本轮相关文件。
