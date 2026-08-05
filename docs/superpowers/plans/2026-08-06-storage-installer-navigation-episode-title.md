# 存储迁移、安装器、导航与剧集名称实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为看影音增加可配置的数据/缓存目录与可回滚迁移能力，提供默认安装到 D 盘的当前用户 Inno Setup 测试安装器，统一本地与网盘逐集 TMDB 标题显示，并将设置与深色模式按钮并排放到底部工具条。

**Architecture:** 在 Hive 初始化之前引入独立于 Hive 的启动配置和路径解析器；业务缓存统一从路径解析器取得根目录，迁移服务使用临时目录、清单校验和保留源目录的回滚策略。TMDB 逐集名称作为 `TmdbScrapeOptions` 的兼容字段，展示层通过同一个解析器组合有效作品标题、季集编号和集名。桌面安装器使用 Inno Setup 脚本包装已验证的 Windows Release 目录，MSIX 继续走现有签名流程。

**Tech Stack:** Flutter/Dart、Hive CE、path_provider、provider、Inno Setup、PowerShell、Flutter test/analyze/build。

---

### Task 1: 存储路径解析与启动配置

**Files:**
- Create: `lib/services/storage/storage_path_resolver.dart`
- Create: `lib/services/storage/storage_startup_config.dart`
- Modify: `lib/main.dart`
- Modify: `lib/utils/storage.dart`
- Test: `test/storage_path_resolver_test.dart`

- [ ] **Step 1: 写路径配置和解析器测试**

覆盖默认路径、显式路径、非法路径回退、旧配置缺少字段按默认值处理，并断言数据/缓存子目录稳定。

- [ ] **Step 2: 实现启动配置和路径解析器**

配置写入应用启动目录下的独立 JSON，包含版本、数据目录、缓存目录、迁移状态和上一次成功路径；解析器在 Windows 上默认使用 `D:\看影音\数据`、`D:\看影音\缓存`，不可用时回退到 `path_provider` 路径。

- [ ] **Step 3: 在 Hive 初始化前接入解析器**

`main.dart` 先初始化路径解析器，再以解析出的数据目录初始化 Hive；`GStorage` 接收解析后的 Hive 路径，不再自行调用 `getApplicationSupportDirectory`。

- [ ] **Step 4: 运行定向测试**

运行 `flutter test test/storage_path_resolver_test.dart`，预期全部通过。

### Task 2: 数据与缓存迁移服务

**Files:**
- Create: `lib/services/storage/app_data_migration_service.dart`
- Modify: `lib/services/cloud/cloud_cache_directories.dart`
- Modify: `lib/services/cloud/cloud_poster_cache.dart`
- Modify: `lib/services/cloud/cloud_subtitle_cache.dart`
- Modify: `lib/services/cloud/range/cloud_range_chunk_cache.dart`
- Modify: `lib/services/local_image_cache_service.dart`
- Test: `test/app_data_migration_service_test.dart`

- [ ] **Step 1: 写迁移成功、校验失败、回滚和缓存清理测试**

使用临时目录构造 Hive/日志/WebView/海报/字幕文件，验证复制清单、SHA-256、目标不可写/中断时源目录不变，清理缓存不触碰媒体文件和索引。

- [ ] **Step 2: 实现安全迁移服务**

迁移到同级临时目录，记录相对路径、文件数、字节数和校验摘要；写完成标记后切换正式目录，更新启动配置；异常删除目标临时副本并保留源目录。

- [ ] **Step 3: 统一业务缓存根目录**

所有网盘海报、字幕、范围中转和图片缓存通过 `StoragePathResolver.cacheRoot` 注入；保留现有 Android provider 行为。

- [ ] **Step 4: 运行定向测试**

运行 `flutter test test/app_data_migration_service_test.dart test/android_content_playback_test.dart`，预期通过。

### Task 3: 设置页存储目录入口

**Files:**
- Create: `lib/pages/settings/storage_settings_page.dart`
- Modify: `lib/pages/settings/settings_module.dart`
- Modify: `lib/pages/my/my_page.dart`
- Modify: `lib/features/settings/presentation/settings_presentation.dart`
- Test: `test/storage_settings_page_test.dart`

- [ ] **Step 1: 写设置页组件测试**

断言页面显示“应用数据目录”“缓存目录”、当前路径、复制/选择/迁移/清理动作和迁移状态；清理动作只调用缓存清理服务。

- [ ] **Step 2: 实现目录选择与确认对话框**

使用 Windows 目录选择器；长路径以省略文本显示并支持复制完整路径；迁移前确认，成功后提示重启，失败显示可恢复错误。

- [ ] **Step 3: 接入“设置”页面并统一文案**

将“本地媒体库”改为“媒体库”，“播放器设置”改为“设置”，不改路由兼容键。

- [ ] **Step 4: 运行定向测试**

运行 `flutter test test/storage_settings_page_test.dart test/about_page_content_test.dart`。

### Task 4: 逐集 TMDB 名称开关与统一标题合并

**Files:**
- Modify: `lib/services/tmdb/tmdb_scrape_options.dart`
- Modify: `lib/features/settings/application/typed_settings.dart`
- Modify: `lib/services/cloud/cloud_media_library.dart`
- Modify: `lib/services/local_media_library_builder.dart`
- Modify: `lib/services/tmdb/tmdb_episode_title_resolver.dart`
- Modify: `lib/services/cloud/cloud_resource_tmdb_coordinator.dart`
- Modify: `lib/services/tmdb/local_tmdb_scrape_service.dart`
- Test: `test/tmdb_episode_title_resolver_test.dart`
- Test: `test/tmdb_scrape_options_test.dart`

- [ ] **Step 1: 写默认值、兼容 JSON 和标题组合测试**

覆盖缺少字段默认开启、开启时 TMDB 集名覆盖旧值、详情成功但集名为空时清除旧值、详情失败保留旧数据、关闭时隐藏旧集名，以及自定义剧名 `回魂计 S01E01 死而复生` / `回魂计 S01E01`。

- [ ] **Step 2: 扩展 `TmdbScrapeOptions`**

增加 `scrapeEpisodeNames` 字段，版本兼容 JSON 缺失时使用 `true`；本次刮削关闭时写入空集名展示字段。

- [ ] **Step 3: 统一本地和网盘展示解析器**

让两条媒体库构建路径都调用同一个解析器，使用有效作品标题作为前缀，不改变文件名、播放 ID、远程路径或字幕关联。

- [ ] **Step 4: 接入 TMDB 合并策略**

成功详情按开关覆盖或清除集名；请求失败保留已有元数据并回退季集编号/原始文件名。

- [ ] **Step 5: 运行定向测试**

运行 `flutter test test/tmdb_episode_title_resolver_test.dart test/tmdb_scrape_options_test.dart test/cloud_media_library_test.dart`。

### Task 5: 侧边栏底部工具条

**Files:**
- Modify: `lib/pages/menu/adaptive_navigation_shell.dart`
- Modify: `lib/pages/navigation/navigation_config.dart`
- Test: `test/adaptive_navigation_shell_test.dart`

- [ ] **Step 1: 写布局测试**

断言桌面侧边栏底部有并排的设置和深色模式图标按钮，按钮有 tooltip，主题切换仍写入现有设置键；移动端底部导航不增加重复入口。

- [ ] **Step 2: 实现底部工具条**

从主导航目的地中分离设置项，在侧边栏底部添加设置按钮和深色模式切换按钮，保持侧栏宽度、动画和现有选中路由行为。

- [ ] **Step 3: 运行定向测试**

运行 `flutter test test/adaptive_navigation_shell_test.dart test/adaptive_navigation_android_test.dart`。

### Task 6: Inno Setup 当前用户测试安装器

**Files:**
- Create: `tool/windows/installer/看影音测试版.iss`
- Create: `tool/windows/installer/build_inno_setup.ps1`
- Modify: `tool/windows/installer/安装说明.txt`
- Test: `test/windows_installer_contract_test.dart`

- [ ] **Step 1: 写安装器契约测试**

断言脚本使用 `PrivilegesRequired=lowest`、默认 `D:\看影音`、目录选择、旧 MSIX 检测、卸载入口、安装后启动验证和不自动删除旧数据。

- [ ] **Step 2: 实现 Inno Setup 脚本和构建脚本**

安装 Release 目录、创建开始菜单和卸载入口，安装前显示当前 MSIX 版本；安装后仅提示用户是否卸载旧 MSIX，失败保留 EXE 使用能力。构建脚本预检 `ISCC.exe`，缺失时失败。

- [ ] **Step 3: 运行安装器契约测试和编译预检**

运行 `flutter test test/windows_installer_contract_test.dart`；若系统存在 `ISCC.exe`，执行构建脚本并验证安装目录、卸载入口、SHA-256 和 Authenticode 状态。

### Task 7: 测试版版本同步与交付

**Files:**
- Modify: `pubspec.yaml`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_contract_test.dart`

- [ ] **Step 1: 更新版本到 `2.1.135` / `2.1.135.0`**

同步 Flutter、MSIX、版本历史、发布说明和契约测试。

- [ ] **Step 2: 运行完整验证**

依次运行 `flutter test`、`flutter analyze`、`flutter build windows --release`，确认无测试失败、无分析错误且 Release 目录生成。

- [ ] **Step 3: 生成并验证 MSIX**

使用现有签名脚本生成 `看影音-2.1.135.0.msix`，验证身份、版本、x64、签名和 SHA-256，并复制到当前用户桌面。

- [ ] **Step 4: 生成并验证 EXE**

用 Inno Setup 包装 Release 目录，验证文件版本、默认目录、卸载入口、快捷方式目标、SHA-256 和 Authenticode 状态；缺少代码签名证书时明确记录未签名。

- [ ] **Step 5: 检查最终 Git 状态并提交**

运行 `git status --short` 和关键 diff，只暂存本轮相关文件，提交信息使用 `新增 D 盘存储迁移与剧集名称设置`。
