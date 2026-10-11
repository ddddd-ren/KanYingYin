# 媒体分类与标签确认实施计划

> **For agentic workers:** 使用 superpowers:subagent-driven-development；先写回归测试并观察失败，再实现。保留所有既有改动，不执行 Git 提交。

**Goal:** 动漫不进入电视剧；提供独立分类置信度门槛、多标签人工选择及可恢复的旧库检查。

**Architecture:** 在共享查询层计算候选与有效分类，底层 TMDB movie/tv 不变。人工分类、题材选择保存在现有 MediaLibraryUserState，null 表示自动，空列表表示明确清空；所有入口使用同一个解析结果。复用现有配置备份与稳定作品 key，不增加依赖。

**Tech Stack:** Flutter、Dart、MobX、Hive、现有 Material 组件。

---

## 接口约定

- `MediaLibraryUserState.categoryOverride` / `genreOverride`：`List<String>?`，分类仅允许电影、动漫、电视剧；动漫和电视剧互斥。`copyWith` 增加 `clearCategoryOverride`、`clearGenreOverride` 恢复自动。
- `MediaClassificationMode { conservative, standard, manual }` 与 `MediaClassificationConfidence { high, medium, low }` 放在 `media_library_classification.dart`。
- `MediaClassificationResolver.resolve(series, {state, mode})` 返回 `MediaClassificationResult`，含 `categories`、`genres`、`categorySuggestions`、`genreSuggestions`、`needsConfirmation`、`isManual`。建议含 `label`、`confidence`、`reason`。
- `MediaLibraryQuery` 增加独立 `selectedCategories`、`classificationMode`；自动/人工题材由 `genresForSeries` 获取。主入口不得使用混合标签筛选类别。
- 分类门槛设置键 `mediaClassificationMode`，默认 conservative。旧设置无该键时兼容。候选强弱不是概率，不显示百分比。
- 高可信单一候选按门槛生效；多个候选、证据冲突、缺元数据须确认。明确动漫证据排除电视剧候选；动画电影提供两个候选，用户选择；人工结果优先且明确空选择有效。

## Task 1：共享规则与证据

文件：`lib/features/library/application/media_library_classification.dart`、`media_library_query.dart`、云端 `cloud_resource_media_library_adapter.dart`；测试 `media_library_classification_test.dart`、`media_library_query_test.dart`、`cloud_resource_media_library_adapter_test.dart`。

- [x] 把动画 tv 进入电视剧的旧预期改为排除，并增加缺失题材、门槛、多分类、人工清空与同名自定义标签的测试；先运行看到行为失败。
- [x] 保留原始媒体类型与完整 TMDB 元数据；统一计算建议与有效分类，不把季集推断当高可信证据。
- [x] 运行上述测试，确认本地与云端行为一致。

## Task 2：人工选择与备份

文件：`media_library_user_state.dart`、`media_library_user_state_repository.dart`、`portable_user_data.dart`、配置用户数据存储与对应测试。

- [x] 测试 null、空列表、非空列表往返、恢复自动、刷新重关联与冲突导入。
- [x] 扩展现有状态，明确空值不能被 isEmpty 删除；分类冲突不能像合集一样并集。自动重关联冲突保留待处理；显式合并报可恢复错误。
- [x] 新门槛和选择接入配置捕获、恢复、映射、回滚；旧包缺字段不抹除新选择。

## Task 3：共享编辑界面与分类页

文件：新增 `media_classification_dialog.dart`，现有 `media_category_page.dart` 与组件测试。

- [x] 测试勾选多标签、互斥分类、明确清空、恢复自动、保存失败保留输入与移动端视口。
- [x] 共享弹窗分分类归属、题材标签、自定义标签；显式保存一次，候选展示可信档位和依据。
- [x] 分类页使用独立分类筛选，加入分类门槛和旧库检查入口；预览完整当前来源的待确认作品，可逐项编辑，未分类作品仍可访问。

## Task 4：本地、网盘、卡片接线

文件：本地/云端页面与控制器、`media_category_runtime.dart`、`media_category_module.dart`、`media_card_info.dart`、`library_media_view_data_builder.dart` 与对应测试。

- [x] 复用共享编辑器，保存人工状态后同步各页；题材筛选和卡片读取有效结果，不再直接用原始 TMDB 类型展示电视剧。
- [x] 自定义标签与类别独立，4K/HDR 等技术标签保持不变；播放、季集及原始文件不变。
- [x] 针对刷新、重刮、备份往返、不同来源、离线缺元数据执行回归。

## Task 5：审查、版本与交付

- [x] 对照用户方案检查完整性，再做独立代码及界面审查。
- [ ] 执行针对性测试、全量 `flutter test --no-pub`、`flutter analyze --no-pub`、Windows Release 构建，分别记录结果。
- [x] 开始前已核对安装状态：EXE 安装位置 `D:\看影音\`，安装器记录和主程序均为 2.1.223；当前用户未查到旧 kanyingyin MSIX。构建前升级到未使用的测试版本 2.1.224+20224，同步版本、发布说明和普通用户更新弹窗。
- [ ] 验证通过后复用 `tool/windows/build_exe_release.ps1` 生成 EXE，核对主程序与安装器版本、哈希、签名并复制桌面。不安装、不生成 MSIX、不构建 Android TV、不发布远端、不提交。

验证命令均使用 `D:\flutter\bin\flutter.bat`；目标测试串行运行，失败时区分断言失败与本地监听基础设施失败。

## 审查收口

- 本地抽屉的分类、题材、自定义标签改为独立条件，覆盖同名标签和失效筛选回归。
- 网盘重刮先失效缓存再校正筛选；本地、网盘入口均依据成员身份保留重分组后的人工状态。
- 分类保存与收藏等标记双向保护，避免旧弹窗或旧界面快照覆盖最近保存的数据。
- 自定义标签写后失败、分类保存失败均补偿恢复旧标签；打开中的选集实时读取新分类。
- 非法或缺失 TMDB 类型只保留旧结构兼容，不获得高可信证据；有效类型及底层播放语义不变。
- 检查弹窗退出后再进入编辑或详情；保留检查范围与滚动位置，搜索空态可清除条件。
- 验证日志保存在 `build/verification/`；全量测试、最终静态分析和 Windows 交付结果待本轮收口后记录。
