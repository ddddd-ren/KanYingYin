# 内嵌音轨与字幕语种选择实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Windows 播放器提供内嵌音轨与字幕的中文识别、默认选择、手动切换和紧凑菜单。

**Architecture:** 新增独立强类型轨道展示模型，集中负责 media-kit 元数据归一化、标签生成和优先级选择。播放器控制器订阅可用轨道与当前轨道事件，只在每个媒体首次稳定列表时自动选择，并向共享菜单组件暴露 MobX 状态和切换动作；外部字幕继续沿用现有流程。

**Tech Stack:** Flutter 3.41.9、Dart、MobX、media-kit、flutter_test。

---

### Task 1: 轨道识别与优先级模型

**Files:**
- Create: `lib/pages/player/models/embedded_track_info.dart`
- Create: `test/embedded_track_info_test.dart`

- [ ] **Step 1: 编写失败测试**：覆盖中文代码、国语/粤语/台配、简繁字幕、未知标签、编码与声道，以及音轨和字幕优先级。
- [ ] **Step 2: 运行测试确认 RED**：`D:\flutter\bin\flutter.bat test test/embedded_track_info_test.dart`，预期因模型不存在失败。
- [ ] **Step 3: 最小实现**：定义强类型枚举、展示模型、media-kit 映射和纯选择函数。
- [ ] **Step 4: 运行测试确认 GREEN**：同一命令应全部通过。

### Task 2: 控制器轨道生命周期与切换

**Files:**
- Modify: `lib/pages/player/player_controller.dart`
- Modify: `lib/pages/player/player_controller.g.dart`
- Create: `test/player_embedded_track_state_test.dart`

- [ ] **Step 1: 编写失败测试**：覆盖一次性自动选择、手动选择锁定、媒体切换重置、内外字幕互斥和 TrueHD 不覆盖手选。
- [ ] **Step 2: 运行测试确认 RED**：`D:\flutter\bin\flutter.bat test test/player_embedded_track_state_test.dart`。
- [ ] **Step 3: 最小实现**：订阅 `stream.tracks` 与 `stream.track`，维护可观察强类型状态，按优先级选择并记录日志；实现音轨、内嵌字幕和关闭字幕动作。
- [ ] **Step 4: 生成 MobX 代码**：`D:\flutter\bin\dart.bat run build_runner build --delete-conflicting-outputs`。
- [ ] **Step 5: 运行测试确认 GREEN**：轨道状态测试和现有 `local_video_controller_test.dart` 通过。

### Task 3: 桌面与小窗口紧凑菜单

**Files:**
- Create: `lib/pages/player/widgets/embedded_track_menus.dart`
- Modify: `lib/pages/player/player_item_panel.dart`
- Modify: `lib/pages/player/smallest_player_item_panel.dart`
- Create: `test/embedded_track_controls_test.dart`

- [ ] **Step 1: 编写失败测试**：确认两个控制栏均使用共享“字幕”“语言”入口，字幕菜单保留外部字幕设置入口。
- [ ] **Step 2: 运行测试确认 RED**：`D:\flutter\bin\flutter.bat test test/embedded_track_controls_test.dart`。
- [ ] **Step 3: 最小实现**：共享两个 `MenuAnchor`，展示轨道标签、详情、选中标记，并调用控制器动作。
- [ ] **Step 4: 运行测试确认 GREEN**：控件测试通过。

### Task 4: 版本、交付文案与完整验证

**Files:**
- Modify: `pubspec.yaml`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: 更新版本**：提升应用版本与 `msix_config.msix_version`，同步普通用户可读的发布说明和版本历史。
- [ ] **Step 2: 格式化**：`D:\flutter\bin\dart.bat format lib test`。
- [ ] **Step 3: 完整测试**：`D:\flutter\bin\flutter.bat test`。
- [ ] **Step 4: 静态分析**：`D:\flutter\bin\flutter.bat analyze`，要求无错误。
- [ ] **Step 5: Windows Release 构建**：`D:\flutter\bin\flutter.bat build windows --release`。
- [ ] **Step 6: 检查并提交**：检查 `git status --short` 和关键 diff，仅 `git add` 本轮文件并用简洁中文提交。
