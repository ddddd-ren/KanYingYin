# TMDB 刮削选项与桌面界面调整 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 增加可持久化且能实际影响匹配行为的 TMDB 刮削选项，补齐桌面窗口控制栏，并删除关于页外部链接。

**Architecture:** 使用强类型 `TmdbScrapeOptions` 统一设置页、自动扫描和手动刮削参数；匹配器通过可配置阈值工作，服务层负责字段覆盖与锁定优先级。桌面窗口按钮封装为独立组件，由 `SysAppBar` 复用，关于页只做定向删除。

**Tech Stack:** Flutter、Dart、Hive CE、MobX、Dio、window_manager、flutter_test、MSIX。

---

### Task 1: 建立 TMDB 刮削配置模型

**Files:**
- Create: `lib/services/tmdb/tmdb_scrape_options.dart`
- Create: `test/tmdb_scrape_options_test.dart`

- [ ] **Step 1: 写失败测试**

测试默认语言为 `zh-CN`、类型为自动、置信度为标准；测试 Map 往返保留覆盖和图片开关。

- [ ] **Step 2: 运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test test/tmdb_scrape_options_test.dart`

Expected: FAIL，提示配置模型不存在。

- [ ] **Step 3: 实现强类型配置**

定义 `TmdbMediaTypeMode`、`TmdbConfidenceMode` 和不可变 `TmdbScrapeOptions`，包含 `defaults`、`fromMap`、`toMap`、`copyWith`，并提供最低分和领先分差映射。

- [ ] **Step 4: 运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test test/tmdb_scrape_options_test.dart`

Commit: `feat: 增加 TMDB 刮削配置模型`

### Task 2: 让配置进入匹配和合并流程

**Files:**
- Modify: `lib/services/tmdb/tmdb_matcher.dart`
- Modify: `lib/services/tmdb/tmdb_scraper.dart`
- Modify: `lib/services/tmdb/local_tmdb_scrape_service.dart`
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `test/tmdb_matcher_test.dart`
- Modify: `test/local_tmdb_integration_test.dart`

- [ ] **Step 1: 写失败测试**

覆盖保守/宽松阈值、强制电影/电视剧、首选语言传递、禁止覆盖已有标题、允许覆盖简介、关闭海报和背景图获取、锁定字段最高优先级。

- [ ] **Step 2: 运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test test/tmdb_matcher_test.dart test/local_tmdb_integration_test.dart`

- [ ] **Step 3: 实现参数传递**

`TmdbMatcher.choose` 接受最低分与领先分差；`TmdbScraper.scrape` 接受语言和阈值；`LocalTmdbScrapeService` 接受 `TmdbScrapeOptions`，解析媒体类型并按覆盖、图片和锁定规则合并。

- [ ] **Step 4: 控制器读取全局配置**

使用单个 `tmdbScrapeOptions` Map 存储配置；自动扫描和批量刮削使用全局值，手动方法允许传入临时配置。

- [ ] **Step 5: 运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test test/tmdb_matcher_test.dart test/tmdb_scraper_test.dart test/local_tmdb_integration_test.dart`

Commit: `feat: 应用 TMDB 刮削策略`

### Task 3: 增加设置页与单次刮削选项

**Files:**
- Modify: `lib/pages/settings/tmdb_settings.dart`
- Create: `lib/pages/local/tmdb_scrape_options_sheet.dart`
- Modify: `lib/pages/local/library_sheet.dart`
- Create: `test/tmdb_settings_options_test.dart`

- [ ] **Step 1: 写配置展示失败测试**

断言设置页源码包含语言、媒体类型、置信度、三个覆盖开关和两个图片开关；断言手动刮削入口使用临时配置弹层。

- [ ] **Step 2: 实现设置控件**

使用下拉菜单选择语言，分段或下拉选择媒体类型和置信度，使用 `SwitchListTile` 实现覆盖和图片开关；保存时写入 `tmdbScrapeOptions`。

- [ ] **Step 3: 实现单次选项弹层**

弹层从全局配置初始化，仅展示媒体类型与三个覆盖开关，确认后返回临时 `TmdbScrapeOptions`，取消不发起请求。

- [ ] **Step 4: 接入媒体库动作并提交**

“刮削信息”和“重新匹配”先打开弹层，再调用控制器；自动扫描保持无交互。

Commit: `feat: 增加 TMDB 刮削选项界面`

### Task 4: 增加桌面窗口控制栏

**Files:**
- Create: `lib/bean/appbar/desktop_window_controls.dart`
- Modify: `lib/bean/appbar/sys_app_bar.dart`
- Create: `test/desktop_window_controls_test.dart`

- [ ] **Step 1: 写组件失败测试**

测试桌面控制栏包含置顶、最小化、最大化/还原和关闭四个语义按钮；非桌面环境不由 `SysAppBar` 注入。

- [ ] **Step 2: 实现状态组件**

组件实现 `WindowListener`，监听最大化、还原和置顶状态；按钮调用 `setAlwaysOnTop`、`minimize`、`maximize/unmaximize`、`close`，关闭按钮提供红色悬停状态。

- [ ] **Step 3: 接入 SysAppBar**

替换现有单独 `CloseButton`，保留页面 actions、拖动区和原生标题栏设置分支，避免重复显示系统按钮。

- [ ] **Step 4: 运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test test/desktop_window_controls_test.dart`

Commit: `feat: 增加桌面窗口控制栏`

### Task 5: 删除关于页外部链接

**Files:**
- Modify: `lib/pages/about/about_page.dart`
- Create: `test/about_page_content_test.dart`

- [ ] **Step 1: 写失败测试**

扫描关于页源码，禁止出现“外部链接、项目主页、代码仓库、图标创作、番剧索引、以图搜番”。

- [ ] **Step 2: 删除整个外部链接区块**

同步清理不再使用的 URL、导入和点击处理，保留版本、许可证和本项目信息。

- [ ] **Step 3: 运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test test/about_page_content_test.dart`

Commit: `refactor: 删除关于页外部链接`

### Task 6: 文件组操作菜单增加 TMDB 刮削

**Files:**
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `lib/pages/local/local_page.dart`
- Modify: `test/local_tmdb_integration_test.dart`

- [ ] **Step 1: 写路径定位失败测试**

验证控制器能根据当前文件组的视频路径找到索引中的真实系列名称，未索引路径返回空值。

- [ ] **Step 2: 实现路径定位**

新增只读方法，从 `localLibraryItems` 中按标准化路径查找第一个有效 `seriesName`。

- [ ] **Step 3: 接入菜单动作**

在“在线查找封面”之前增加“TMDB 刮削”；先打开 `TmdbScrapeOptionsSheet`，再执行刮削，低置信度时打开 `TmdbMatchSheet` 并保存用户候选。

- [ ] **Step 4: 验证并提交**

Run: `D:\flutter\bin\flutter.bat test test/local_tmdb_integration_test.dart`

Commit: `feat: 在文件组菜单增加 TMDB 刮削`

### Task 7: 版本迭代、完整验证和交付

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/request/config/api_endpoints.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: 迭代版本**

从 `1.1.0+10100` 更新为 `1.1.1+10101`，MSIX 更新为 `1.1.1.0`，同步版本常量和用户更新日志。

- [ ] **Step 2: 完整验证**

Run:

```powershell
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
D:\flutter\bin\flutter.bat build windows --release --no-pub
D:\flutter\bin\cache\dart-sdk\bin\dart.exe run msix:create --build-windows false --output-name kanyingyin
```

Expected: 全部测试通过；静态检查无问题；Windows Release 和 MSIX 成功。

- [ ] **Step 3: 验证安装包**

确认清单版本 `1.1.1.0`、签名有效、桌面存在 `看影音-1.1.1.msix`，并确认快捷方式仍指向最新 Release。

- [ ] **Step 4: 最终提交**

Commit: `release: 发布看影音 1.1.1`
