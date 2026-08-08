# README User-Focused Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将仓库首页改写为简洁、准确、面向普通用户的产品介绍页，并同步当前 Windows 1.0.7、Android 1.0.4 和 Android TV 暂停状态。

**Architecture:** 只重构根目录 `README.md` 的信息层级和文案，不修改应用代码、版本配置或 GitHub Release 资产。首页先回答“是什么、在哪下载、能做什么”，再集中说明数据安全和快速开始，最后保留压缩后的开发、构建、致谢与许可证信息。

**Tech Stack:** Markdown、Git、PowerShell、GitHub Release 链接

---

## 文件范围

- Modify: `README.md` — 仓库首页的产品介绍、下载、功能、安全、使用和开发信息。
- Reference: `RELEASE_NOTES.md` — 核对 Windows 1.0.7 与 Android 1.0.4 的正式版能力。
- Reference: `AGENTS.md` — 核对项目定位、交付方式和 Android TV 暂停约束。
- Reference: `docs/superpowers/specs/2026-08-09-readme-user-focused-redesign.md` — 已确认的信息结构和验收标准。

### Task 1: 重写顶部产品区和下载入口

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 保留标题与图标，改写一句话定位**

顶部正文必须明确：看影音用于整理和播放用户自己的本地及个人网盘视频，支持 Windows 和 Android 手机，并可通过 TMDB 补充中文元数据。不得描述为在线影视搜索或资源聚合工具。

- [ ] **Step 2: 添加当前正式版下载表格**

表格固定包含：

| 平台 | 当前版本 | 下载文件 | 用途 |
| --- | --- | --- | --- |
| Windows 10/11 x64 | 1.0.7 | `KanYingYin-1.0.7.exe` | 普通用户安装程序 |
| Android 7.0+ | 1.0.4 (10004) | `KanYingYin-1.0.4.apk` | Android 手机安装包 |
| Android 应用商店 | 1.0.4 (10004) | `KanYingYin-1.0.4.aab` | 应用商店交付包 |

三个文件均链接到 `https://github.com/ddddd-ren/KanYingYin/releases/tag/v1.0.7`，并在表格后明确 Android TV 正式版、测试版和 GitHub 发布无限期暂停，不提供 TV 下载资产。

- [ ] **Step 3: 核对顶部一屏信息**

检查标题到下载表格之间不出现测试版文件名、旧版本号或 TV 下载入口。

### Task 2: 精简核心功能和数据安全说明

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 将功能收敛为五组**

功能章节仅保留以下五组，并以用户能感知的能力描述：

1. 本地与个人网盘媒体库：递归扫描、电影/剧集/季度/集数整理、OpenList/夸克/百度/迅雷、后台刷新和多来源汇总。
2. TMDB 元数据：中文标题、简介、评分、海报、季集信息、自动与手动匹配；TMDB 不可用不阻断本地功能。
3. 播放器：常见格式、硬件解码、HDR 方案、Anime4K、选集连播、倍速、画中画、定时停止和外部播放器。
4. 字幕与音轨：内嵌/外挂字幕、网盘字幕、ASS/SSA/SRT/VTT、PGS、样式与时间偏移、兼容音轨回退。
5. 配置与诊断：`.kyyconfig` 迁移、脱敏日志、诊断 ZIP 和 Android 分享。

- [ ] **Step 2: 收敛测试期与过细说明**

按用户要求保留“OpenList 功能仍在调试，当前不建议使用”的提醒；删除“迅雷网盘为测试能力”等其他旧表述；删除具体文件名、目录名、季度号、分辨率和发布标签的长篇识别示例；删除在多个章节重复出现的“不会删除原始文件”说明。

- [ ] **Step 3: 新增集中式数据安全章节**

章节必须包含：只处理用户自己的媒体；删除来源、索引或缓存不会删除、改名或移动原始文件；无 TMDB Key、断网或 TMDB 不可用时仍可扫描、浏览和播放本地媒体；凭据使用系统安全存储；诊断日志隐藏敏感字段；不包含公共在线影视搜索、插件规则、WebView 视频解析或在线评论。

### Task 3: 更新安装、快速开始与开发资料

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 重写安装和快速开始**

Windows 安装说明使用 `KanYingYin-1.0.7.exe`，说明安装向导允许用户自选目录且不要求 D 盘；Android 使用 `KanYingYin-1.0.4.apk`。快速开始保持为添加本地文件夹、可选配置 TMDB、可选添加个人网盘、选择作品播放四步。

- [ ] **Step 2: 压缩开发与构建说明**

保留 Flutter 3.41.9、`flutter pub get`、`flutter test --no-pub`、`flutter analyze --no-pub`、Windows Release、Android 签名构建脚本和 Inno Setup EXE 构建脚本。播放器组件的详细联合验证说明从首页删除，只保留项目已有脚本作为构建入口。

- [ ] **Step 3: 保留结构、致谢和许可证**

保留简化后的项目目录结构，保留 media-kit、mpv、Anime4K、Mi Sans、TMDB 和 OpenList 致谢，并保留 GPL-3.0 许可证说明。不得声称 GPL 本身禁止商业使用；删除与 GPL-3.0 相冲突的“禁止商业用途”表述。

### Task 4: 验证 README 内容

**Files:**
- Test: `README.md`

- [ ] **Step 1: 检查 Markdown 和 Git 差异**

Run:

```powershell
chcp 65001 > $null
git diff --check
git diff -- README.md
```

Expected: `git diff --check` 无输出；差异只包含用户向 README 重构。

- [ ] **Step 2: 检查版本、资产和暂停状态**

Run:

```powershell
$readme = Get-Content -LiteralPath README.md -Encoding UTF8 -Raw
@(
  'Windows 10/11 x64',
  '1.0.7',
  'KanYingYin-1.0.7.exe',
  '1.0.4 (10004)',
  'KanYingYin-1.0.4.apk',
  'KanYingYin-1.0.4.aab',
  'Android TV',
  '无限期暂停'
) | ForEach-Object {
  if (-not $readme.Contains($_)) { throw "README 缺少：$_" }
}
```

Expected: 命令正常结束，无异常。

- [ ] **Step 3: 检查旧文案已经移除**

Run:

```powershell
$readme = Get-Content -LiteralPath README.md -Encoding UTF8 -Raw
@(
  '迅雷网盘为测试能力',
  '看影音-版本号-测试版-安装程序.exe',
  '禁止将本项目用于商业用途'
) | ForEach-Object {
  if ($readme.Contains($_)) { throw "README 仍包含旧文案：$_" }
}
```

Expected: 命令正常结束，无异常。

- [ ] **Step 4: 检查下载链接可访问**

Run:

```powershell
$response = Invoke-WebRequest -Uri 'https://github.com/ddddd-ren/KanYingYin/releases/tag/v1.0.7' -Method Head
if ($response.StatusCode -ne 200) { throw "Release 链接不可用：$($response.StatusCode)" }
```

Expected: HTTP 200。

### Task 5: 提交并推送首页更新

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 复核工作区**

Run:

```powershell
git status --short
git diff --stat
```

Expected: 只包含 `README.md` 的本轮改动。

- [ ] **Step 2: 提交 README**

Run:

```powershell
git add -- README.md
git commit -m '文档：更新用户向仓库首页'
```

Expected: 新提交仅包含 `README.md`。

- [ ] **Step 3: 推送 main**

Run:

```powershell
$env:GIT_CONFIG_GLOBAL = 'NUL'
git -c credential.helper=manager push https://github.com/ddddd-ren/KanYingYin.git main
```

Expected: GitHub `main` 更新到新提交；现有 `v1.0.7` Release 和三个安装资产不变。
