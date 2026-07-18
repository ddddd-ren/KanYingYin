# 项目结构优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 在不改变播放器交互和用户数据语义的前提下，修复 Windows 交付链路，降低应用根组件、本地媒体库和播放器核心控制器的职责密度，并建立可持续执行的依赖与质量边界。

**架构：** 采用渐进式提取，不进行一次性目录搬迁。新提取的组件放入对应功能目录或 `core` 目录，通过构造函数注入回原控制器；页面只负责展示与用户事件，应用服务负责业务编排，持久化组件负责 Hive/安全存储访问。

**技术栈：** Flutter 3.41.9、Dart、Flutter Modular、MobX、Hive CE、GitHub Actions、Windows/MSIX。

**交付状态：** 本轮按 `2.0.12` 测试版交付；未经用户明确说明，不标记或发布为正式版本。

---

### 任务 1：收敛 Windows CI/CD

**文件：**
- 修改：`.github/workflows/pr.yaml`
- 修改：`.github/workflows/release.yaml`
- 新建：`test/windows_ci_workflow_test.dart`

- [ ] 新增失败测试，断言 PR 流程执行格式检查、静态分析、测试和 Windows Release 构建，发布流程不再引用缺失平台或 `mortis.dart`。
- [ ] 运行 `D:\flutter\bin\flutter.bat test --no-pub test/windows_ci_workflow_test.dart`，确认测试先失败。
- [ ] 将 PR 流程改为 Windows 单作业质量门禁，将发布流程改为 Windows Release、MSIX、签名和发布单链路。
- [ ] 在发布流程中校验 `pubspec.yaml` 版本、`msix_version`、清单身份和最终文件名。
- [ ] 运行目标测试并提交 `ci: 收敛 Windows 构建与发布流程`。

### 任务 2：移除 AppWidget 构建阶段副作用

**文件：**
- 修改：`lib/app_widget.dart`
- 新建：`lib/services/windows_app_shell_service.dart`
- 新建：`test/app_widget_lifecycle_test.dart`

- [ ] 新增失败测试，断言 `build()` 不调用托盘初始化和窗口亮度写操作。
- [ ] 创建 Windows 应用壳服务，集中托盘初始化、窗口亮度同步和监听清理。
- [ ] 在 `initState`、主题变化和 `dispose` 生命周期调用服务，保持现有菜单、关闭弹窗和动画行为不变。
- [ ] 消除主题颜色读取中的 `dynamic`。
- [ ] 运行目标测试、静态分析并提交 `refactor: 隔离 Windows 应用壳副作用`。

### 任务 3：拆分本地媒体库持久化与编排职责

**文件：**
- 修改：`lib/pages/local/local_controller.dart`
- 修改：`lib/pages/index_module.dart`
- 新建：`lib/features/library/application/local_library_preferences.dart`
- 新建：`lib/features/library/application/local_library_metadata_coordinator.dart`
- 新建：`test/local_library_preferences_test.dart`
- 新建：`test/local_library_metadata_coordinator_test.dart`

- [ ] 为最近目录、默认目录和扫描后元数据编排建立失败测试。
- [ ] 将 Hive 目录偏好读写提取到强类型 `LocalLibraryPreferences`。
- [ ] 将海报、媒体信息、缩略图和扫描后 TMDB 编排提取到 `LocalLibraryMetadataCoordinator`。
- [ ] 通过 Flutter Modular 注入两个组件，控制器保留 MobX 可观察状态和兼容入口。
- [ ] 运行本地媒体库相关测试、完整静态分析并提交 `refactor: 拆分本地媒体库编排职责`。

### 任务 4：拆分本地媒体库页面组件

**文件：**
- 修改：`lib/pages/local/local_page.dart`
- 新建：`lib/features/library/presentation/library_path_bar.dart`
- 新建：`lib/features/library/presentation/library_media_grid.dart`
- 新建：`lib/features/library/presentation/library_source_menu.dart`
- 修改：相关本地媒体库组件测试

- [ ] 为提取后的路径栏、来源菜单和媒体网格补充组件测试。
- [ ] 提取纯展示组件，通过强类型回调传递用户操作。
- [ ] 保持现有控件层级、尺寸、动画时长和交互行为。
- [ ] 运行本地页面组件测试和静态分析并提交 `refactor: 拆分本地媒体库页面组件`。

### 任务 5：拆分播放器设置和兼容性策略

**文件：**
- 修改：`lib/pages/player/player_controller.dart`
- 修改：`lib/pages/index_module.dart`
- 新建：`lib/features/player/application/subtitle_preferences.dart`
- 新建：`lib/features/player/application/truehd_fallback_policy.dart`
- 新建：`test/subtitle_preferences_test.dart`
- 新建：`test/truehd_fallback_policy_test.dart`

- [ ] 为字幕样式/延迟持久化和 TrueHD 兼容音轨选择建立失败测试。
- [ ] 将字幕设置 Hive 读写提取为强类型仓储。
- [ ] 将 TrueHD 错误判定和兼容音轨选择提取为无 UI 策略。
- [ ] 控制器保留 media-kit 生命周期、公开方法和现有行为。
- [ ] 运行播放器、字幕、音轨相关测试和静态分析并提交 `refactor: 拆分播放器设置与兼容策略`。

### 任务 6：拆分播放器界面组件

**文件：**
- 修改：`lib/pages/player/player_item.dart`
- 修改：`lib/pages/player/player_item_panel.dart`
- 新建：`lib/features/player/presentation/player_shortcut_handler.dart`
- 新建：`lib/features/player/presentation/player_overlay_coordinator.dart`
- 修改：相关播放器组件测试

- [ ] 为快捷键分发和浮层互斥状态建立失败测试。
- [ ] 提取快捷键处理和字幕/信息浮层协调逻辑。
- [ ] 保持播放器控件层级、动画、全屏、画中画和手势行为不变。
- [ ] 运行播放器测试和静态分析并提交 `refactor: 拆分播放器界面交互职责`。

### 任务 7：整理基础设施依赖边界

**文件：**
- 移动：`lib/request/**` 到 `lib/core/network/**`
- 拆分：`lib/utils/utils.dart` 中的平台、格式化和视频辅助能力
- 修改：所有受影响导入
- 新建：`test/architecture_dependency_test.dart`

- [ ] 新增依赖方向测试，禁止 `core/network -> pages`、`modules -> utils/utils.dart` 和 `core -> features/presentation`。
- [ ] 将网络配置、Dio 工厂和端点配置归入 `core/network`，消除 `request <-> utils` 环。
- [ ] 将领域模型对综合 `Utils` 的依赖替换为最小纯函数依赖。
- [ ] 运行架构测试、完整测试和静态分析并提交 `refactor: 明确基础设施依赖边界`。

### 任务 8：收紧类型、依赖和版本交付信息

**文件：**
- 修改：`analysis_options.yaml`
- 修改：`pubspec.yaml`
- 修改：`RELEASE_NOTES.md`
- 修改：`lib/utils/version_history.dart`
- 修改：版本一致性测试

- [ ] 将三个 `any` 依赖固定为与锁文件兼容的约束。
- [ ] 分批启用 `strict-casts`、`strict-inference`、`strict-raw-types`，修复本轮暴露的问题，不使用全局忽略规避。
- [ ] 将测试版本更新为 `2.0.12+20012`、MSIX 版本更新为 `2.0.12.0`。
- [ ] 用面向普通用户的中文更新发布说明和版本历史。
- [ ] 运行版本测试、完整测试和静态分析并提交 `chore: 更新测试版本与质量规则`。

### 任务 9：完整交付验证

**文件：**
- 不新增产品代码；仅在验证失败时修复本计划相关文件。

- [ ] 运行 `D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test`。
- [ ] 运行 `D:\flutter\bin\flutter.bat test --no-pub`。
- [ ] 运行 `D:\flutter\bin\flutter.bat analyze --no-pub`。
- [ ] 运行 `D:\flutter\bin\flutter.bat build windows --release --no-pub`。
- [ ] 生成签名 MSIX，检查 `AppxManifest.xml` 的版本和身份，验证数字签名。
- [ ] 将测试安装包复制到当前用户桌面并命名为 `看影音-2.0.12.msix`，不创建正式发布。
- [ ] 检查 `git status --short` 和关键 diff，只提交本计划相关改动。
