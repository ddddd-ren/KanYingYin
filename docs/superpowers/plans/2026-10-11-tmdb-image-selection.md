# TMDB 图片选择 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在本地媒体库和网盘资源的 TMDB 刮削结果中，允许用户按剧集、季度或单集选择备用图片，并持久化选择。

**Architecture:** 复用现有 TMDB API Key、客户端上下文、代理恢复和缓存。图片候选通过共享图片能力获取，选择结果以覆盖值保存到本地元数据和网盘 TMDB 记录，再同步索引；默认刮削值保留，清除覆盖后恢复默认图片。

**Tech Stack:** Flutter/Dart、现有 `TmdbClient`、本地元数据仓储、网盘媒体索引与 `CloudPosterCache`。

---

### Task 1: 共享图片候选和 TMDB 请求能力

**Files:**
- Create: `lib/modules/local/tmdb_image_metadata.dart`
- Modify: `lib/services/tmdb/tmdb_client_capabilities.dart`
- Modify: `lib/services/tmdb/tmdb_client.dart`
- Modify: `lib/services/tmdb/tmdb_scrape_cache.dart`
- Test: `test/tmdb_image_client_test.dart`

- [ ] 定义图片类型、目标和候选值对象，支持剧集、季度、单集图片。
- [ ] 在可选能力接口中增加图片列表方法，避免修改 `ITmdbClient` 并破坏现有测试 fake。
- [ ] 使用现有客户端认证和 endpoint recovery 请求 TMDB Images API，增加独立缓存键。
- [ ] 解析 `posters`、`backdrops`、`stills`，按 `file_path` 去重。
- [ ] 添加接口解析、语言参数和错误回退测试。

### Task 2: 元数据和网盘记录保存图片覆盖

**Files:**
- Modify: `lib/modules/local/tmdb_metadata.dart`
- Modify: `lib/modules/cloud/cloud_resource_tmdb_record.dart`
- Modify: `lib/modules/cloud/cloud_work_tmdb_record.dart`
- Modify: `lib/modules/cloud/cloud_media_index_item.dart`
- Modify: `lib/repositories/tmdb_metadata_repository.dart`
- Test: `test/tmdb_metadata_serialization_test.dart`

- [ ] 为剧集、季度、单集增加可选图片覆盖值并保持旧 JSON 兼容。
- [ ] 网盘资源记录和作品记录保存、复制、迁移、索引同步这些覆盖值。
- [ ] 重新刮削合并时保留覆盖值，清除覆盖值时恢复默认路径。
- [ ] 添加本地和网盘记录序列化回归测试。

### Task 3: 本地和网盘统一选择界面及保存入口

**Files:**
- Create: `lib/widgets/tmdb_image_picker_dialog.dart`
- Modify: `lib/pages/local/local_series_detail_page.dart`
- Modify: `lib/pages/cloud/resources/cloud_media_details_dialog.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `lib/services/cloud/cloud_resource_tmdb_service.dart`
- Modify: `lib/services/cloud/cloud_work_tmdb_service.dart`
- Modify: `lib/services/cloud/cloud_poster_cache.dart`
- Test: `test/tmdb_image_picker_dialog_test.dart`

- [ ] 使用同一个弹窗展示海报、背景图、季度海报和单集剧照，并标记当前选择。
- [ ] 本地入口保存到本地元数据并刷新媒体索引。
- [ ] 网盘资源入口保存到资源/作品记录并同步 `CloudMediaIndexItem`。
- [ ] 云端只更新本地索引和缓存，不修改远程文件。
- [ ] 网络失败保留现有图片，图片缓存失败不阻断元数据保存。

### Task 4: 验证

**Files:**
- Modify: relevant existing tests only when failures identify required contracts.

- [ ] Run focused TMDB image, metadata, local and cloud tests.
- [ ] Run `flutter analyze --no-pub`.
- [ ] Run the relevant full test suite and report unrelated pre-existing failures separately.
