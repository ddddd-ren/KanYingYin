# 看影音 README 重写实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为独立 Windows 项目“看影音”编写与 2.0.5 当前功能、安装方式和开源来源一致的 README。

**Architecture:** README 采用用户优先结构，正文独立介绍看影音，开发与许可证信息置于后半部分。功能表述只引用当前源码和配置；Kazumi 仅在文末作为播放器 UI 与交互逻辑的开源来源说明。

**Tech Stack:** Markdown、Flutter 3.41.9、Windows MSIX、Flutter Modular、MobX、media-kit/mpv

---

### Task 1: 重写项目 README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 用独立项目结构替换旧 README**

README 按以下顺序完整编写：

```text
# 看影音
项目图标与一句话定位

## 主要功能
本地媒体库、OpenList、TMDB、播放器、字幕与音轨、Anime4K、历史记录与诊断

## 系统要求
Windows 10/11、MSIX、当前版本 2.0.5

## 安装
当前仓库 Releases、证书提示、首次启动快捷方式询问

## 数据与隐私
不删除原始视频、无遥测、TMDB/网络失败不影响本地能力

## 开发与构建
固定 SDK、pub get、test、analyze、Release、MSIX 命令

## 项目结构
lib/pages、lib/services、lib/repositories、windows、test

## 开源来源与致谢
Kazumi、media-kit、Anime4K、Mi Sans、TMDB、OpenList

## 许可证
GPL-3.0
```

- [ ] **Step 2: 确保当前项目身份准确**

README 必须包含以下当前配置：

```text
应用名称：看影音
Dart 包名：kanyingyin
Windows 包标识：com.kanyingyin.player.v2
当前版本：2.0.5
Flutter：3.41.9
```

- [ ] **Step 3: 保留必要的派生来源说明**

文末使用以下含义明确但克制的说明：

```text
看影音是独立维护的 Windows 媒体库与播放器项目。播放器界面和交互逻辑基于 Kazumi 的开源实现，并围绕本地媒体库、TMDB、OpenList 和 Windows MSIX 交付进行了扩展与重构。
```

### Task 2: 验证 README 内容

**Files:**
- Verify: `README.md`

- [ ] **Step 1: 检查旧内容已移除**

Run:

```powershell
rg -n "就看|F-Droid|Flathub|AUR|WebView|规则编辑器|番剧搜索|一起看|SyncPlay|Yuquanaaa" README.md
```

Expected: 无匹配。

- [ ] **Step 2: 检查必要内容存在**

Run:

```powershell
rg -n "看影音|Windows 10|MSIX|OpenList|TMDB|Anime4K|Kazumi|GPL-3.0|flutter test|flutter analyze" README.md
```

Expected: 每个关键词均有匹配。

- [ ] **Step 3: 运行项目验证**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: 全部测试通过，静态分析无问题。

### Task 3: 提交并同步远程仓库

**Files:**
- Commit: `README.md`
- Commit: `docs/superpowers/plans/2026-07-16-readme-rewrite.md`

- [ ] **Step 1: 检查差异**

Run:

```powershell
git status --short
git diff --check
git diff -- README.md
```

Expected: 只有 README 和本次计划文档相关改动，无空白错误。

- [ ] **Step 2: 提交**

Run:

```powershell
git add README.md docs/superpowers/plans/2026-07-16-readme-rewrite.md
git commit -m "重写看影音项目说明"
```

Expected: 提交成功。

- [ ] **Step 3: 推送并核验**

将 `main` 推送到私有仓库 `ddddd-ren/KanYingYin`，随后确认本地 `main` 与 `origin/main` 指向同一提交。
