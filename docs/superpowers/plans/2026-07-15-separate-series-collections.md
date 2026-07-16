# Separate Series Collections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保留同季度剧集收纳，同时将不同季度、OVA、特别篇和剧场版拆分为独立卡片和播放列表。

**Architecture:** `LocalSeriesGrouper` 继续提取标准化基础作品名，并新增季度/类型维度。只有基础作品名与季度/类型都一致的视频才合并；本地页面和媒体库恢复使用分组器，播放器沿用分组后的隔离播放列表。

**Tech Stack:** Flutter、Dart、MobX、flutter_test、media_kit、MSIX

---

### Task 1: 用测试定义新的收纳边界

**Files:**
- Modify: `test/local_series_grouper_test.dart`
- Modify: `test/local_video_controller_test.dart`

- [ ] 修改原跨季度合并测试：第一季两集合并为一组，第二季、OVA、剧场版分别为独立组。
- [ ] 保留同季度自然排序、字幕和播放标题测试。
- [ ] 修改本地页面源码测试，要求恢复 `LocalSeriesGrouper` 和媒体库入口，不再引用关闭开关。
- [ ] 运行定向测试并确认测试因现有跨季度合并行为失败。

### Task 2: 实现季度和类型分组键

**Files:**
- Modify: `lib/services/local_series_grouper.dart`
- Modify: `lib/pages/local/local_page.dart`
- Delete: `lib/utils/feature_flags.dart`

- [ ] 在 `_SeriesDescriptor` 中增加收纳标识，优先使用 `seasonNumber`，其次识别父目录和剧名中的 OVA、OAD、SP、特别篇与剧场版标记。
- [ ] 分组比较同时要求基础作品键与收纳标识一致，不再把不同季度或类型当作名称变体合并。
- [ ] 显示标题追加 `第一季`、`第二季`、`OVA`、`特别篇` 或 `剧场版`。
- [ ] 恢复本地页面的分组调用、媒体库按钮和系列统计。
- [ ] 运行分组、媒体库构建和播放器定向测试并确认通过。

### Task 3: 版本、验证与安装包

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/request/config/api_endpoints.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`

- [ ] 更新版本为 `1.2.5+10205`，MSIX 版本为 `1.2.5.0`。
- [ ] 更新用户文案，说明同季度继续收纳，不同季度、OVA 和剧场版独立显示。
- [ ] 运行完整 `flutter test`、`flutter analyze` 和 Windows Release 构建。
- [ ] 实机确认媒体库入口恢复，实际目录显示独立季度和特别篇卡片。
- [ ] 生成、验证并复制 `C:\Users\asus\Desktop\看影音-1.2.5.msix`。
