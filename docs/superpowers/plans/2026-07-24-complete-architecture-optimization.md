# 看影音完整架构优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 2.1.50 之后尚未执行的强类型设置、控制器拆分、页面收敛、legacy 隔离和性能优化，并保持现有 Windows 播放与媒体数据语义。

**Architecture:** 保留 Flutter Modular 与 MobX。`pages` 只保留路由、页面状态和事件转发；可独立验证的业务编排放入 `features/*/application`；Hive 访问只经 Repository 或 Preferences；兼容解析只由 Repository 调用 `legacy`；播放器控制器继续作为界面门面，但把字幕、音轨和运行参数交给专用协调器。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular 6、MobX、Hive CE、media-kit、Windows/MSIX。

---

### Task 1: 强类型设置边界

**Files:**
- Create: `lib/features/settings/application/typed_settings.dart`
- Modify: `lib/app/bindings/infrastructure_bindings.dart`
- Modify: `lib/pages/settings/*.dart`
- Modify: `lib/pages/player/*.dart`
- Modify: `lib/pages/local/local_page.dart`
- Test: `test/typed_settings_box_test.dart`
- Test: `test/architecture_dependency_test.dart`

- [ ] 在 `typed_settings_box_test.dart` 先断言 `TypedSettings.read<T>` 对错类型回退、写入与删除，运行测试确认类不存在而失败。
- [ ] 实现 `TypedSettings`，构造参数为 `Box<Object?>`，公开 `read<T>(String,{required T defaultValue})`、`readRaw`、`write<T>` 和 `delete`。
- [ ] 在基础设施绑定中注册单例，并把页面及播放器控制器中的 `GStorage.setting` 替换为构造注入或 `Modular.get<TypedSettings>()`。
- [ ] 在架构测试中禁止 `lib/pages/**` 导入 `utils/storage.dart` 或直接出现 `GStorage.setting`，运行定向测试确认通过。

### Task 2: 本地媒体库控制器拆分

**Files:**
- Create: `lib/features/library/application/local_library_source_coordinator.dart`
- Create: `lib/features/library/application/local_library_tmdb_coordinator.dart`
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `lib/app/bindings/library_bindings.dart`
- Test: `test/local_library_source_coordinator_test.dart`
- Test: `test/local_library_tmdb_coordinator_test.dart`

- [ ] 先测试来源删除在扫描期间被拒绝、失效来源批量删除不触碰原始文件、TMDB 无 Key 时返回可识别失败。
- [ ] 将媒体源增删、扫描摘要和索引清理移动到 `LocalLibrarySourceCoordinator`；其依赖只包含来源与索引 Repository。
- [ ] 将 TMDB 设置读取、候选搜索和扫描后自动刮削移动到 `LocalLibraryTmdbCoordinator`。
- [ ] `LocalController` 保留 MobX 状态、导航和兼容公开方法，通过两个协调器委托，运行全部本地媒体库测试。

### Task 3: 网盘控制器拆分

**Files:**
- Create: `lib/features/cloud/application/cloud_source_coordinator.dart`
- Create: `lib/features/cloud/application/cloud_resource_tmdb_facade.dart`
- Modify: `lib/providers/cloud_library_controller.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `lib/app/bindings/cloud_bindings.dart`
- Test: `test/cloud_source_coordinator_test.dart`
- Test: `test/cloud_resource_tmdb_facade_test.dart`

- [ ] 先测试来源删除只清理索引、凭据与缓存，扫描取消释放状态，TMDB 门面保持来源级上下文。
- [ ] 将来源连接测试、保存、删除和扫描编排放入 `CloudSourceCoordinator`。
- [ ] 将作品与条目 TMDB 搜索、选择、标题保存和重新匹配放入 `CloudResourceTmdbFacade`。
- [ ] 两个原控制器保留 ChangeNotifier/页面状态并委托应用服务，运行 OpenList、夸克、百度及网盘媒体库测试。

### Task 4: 播放器控制器拆分

**Files:**
- Create: `lib/features/player/application/player_runtime_preferences.dart`
- Create: `lib/features/player/application/player_subtitle_coordinator.dart`
- Create: `lib/features/player/application/embedded_track_coordinator.dart`
- Modify: `lib/pages/player/player_controller.dart`
- Modify: `lib/app/bindings/playback_bindings.dart`
- Test: `test/player_runtime_preferences_test.dart`
- Test: `test/player_subtitle_coordinator_test.dart`
- Test: `test/embedded_track_coordinator_test.dart`

- [ ] 先测试播放器运行参数的默认值和错误类型回退、字幕延迟按媒体保存、音轨语言确认只提交当前生命周期结果。
- [ ] `PlayerRuntimePreferences` 集中读取解码、代理、自动播放、宽高比、跳转时间和调试设置。
- [ ] `PlayerSubtitleCoordinator` 负责外部字幕、样式、延迟与恢复；`EmbeddedTrackCoordinator` 负责内嵌字幕/音轨语言识别和选择策略。
- [ ] `PlayerController` 保留 media-kit 生命周期和现有公开 API，内部委托三个对象，运行播放器、字幕、音轨、TrueHD 与 Anime4K 测试。

### Task 5: 页面职责收敛

**Files:**
- Create: `lib/features/library/presentation/library_media_view_data_builder.dart`
- Create: `lib/features/cloud/presentation/cloud_resources_toolbar.dart`
- Create: `lib/features/player/presentation/player_audio_service_coordinator.dart`
- Modify: `lib/pages/local/local_page.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `lib/pages/player/player_item.dart`
- Test: `test/library_media_view_data_builder_test.dart`
- Test: `test/cloud_resources_toolbar_test.dart`
- Test: `test/player_audio_service_coordinator_test.dart`

- [ ] 先测试本地媒体文本格式、网盘工具栏动作映射和音频服务状态同步。
- [ ] 提取纯展示数据构建器、工具栏组件和音频服务协调器，所有用户动作通过强类型回调返回页面。
- [ ] 不改变控件层级、动画时长、动画曲线、快捷键、全屏、画中画或手势，运行页面和播放器组件测试。

### Task 6: 目录与 legacy 边界

**Files:**
- Modify: `lib/modules/local/local_media_index_item.dart`
- Modify: `lib/repositories/local_media_index_repository.dart`
- Modify: `test/architecture_dependency_test.dart`
- Test: `test/legacy_local_media_index_adapter_test.dart`

- [ ] 先增加架构测试，禁止 `lib/modules`、`lib/pages`、`lib/features` 导入 `lib/legacy`，确认当前模型导入导致失败。
- [ ] 将旧 Bangumi 字段转换移动到 `LocalMediaIndexRepository` 的读取边界，领域模型只解析当前 TMDB JSON。
- [ ] 保留旧索引兼容测试，并确认只有存储初始化和 Repository 可以依赖 `legacy`。

### Task 7: 可测量性能优化

**Files:**
- Modify: `lib/repositories/local_media_index_repository.dart`
- Create: `lib/features/library/application/library_performance_trace.dart`
- Modify: `lib/services/local_media_indexer.dart`
- Modify: `lib/services/cloud/cloud_media_indexer.dart`
- Test: `test/local_media_index_repository_cache_test.dart`
- Test: `test/library_performance_trace_test.dart`

- [ ] 先使用可计数存储测试证明连续读取会重复反序列化，并测试跟踪器记录阶段名称与耗时。
- [ ] 为本地索引 Repository 增加实例内不可变快照缓存，所有保存、更新、删除和清空操作同步刷新缓存。
- [ ] 在本地与网盘索引入口记录收集、解析、保存总耗时，只写脱敏阶段与数量，不记录完整路径或凭据。
- [ ] 运行索引、并发、取消和日志脱敏测试，确认性能优化不改变结果顺序和数据语义。

### Task 8: 完整交付

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`
- Modify: version consistency tests

- [ ] 查询并记录 `Get-AppxPackage -Name com.kanyingyin.player` 的安装版本。
- [ ] 更新为下一补丁版本并同步 MSIX、README、更新弹窗、版本历史和普通用户发布说明。
- [ ] 运行相关文件格式检查、`flutter test --no-pub`、`flutter analyze --no-pub` 和 Windows Release 构建。
- [ ] 生成签名 MSIX，验证 Identity、Publisher、Version、x64、签名与桌面哈希；若安装则再次查询安装版本。
- [ ] 检查 Git 状态和关键 diff，只暂存本计划相关文件并使用简洁中文提交。
