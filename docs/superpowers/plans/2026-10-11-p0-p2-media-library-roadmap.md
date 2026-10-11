# 看影音 P0-P2 功能实施计划

> **执行约束：** 本项目不启动子代理、不执行 Git commit；后续实现只在当前会话逐项完成，并保留与本计划无关的工作区修改。

**目标：** 在不改变“本地与个人网盘媒体库”定位、不修改用户原始媒体的前提下，补齐内容组织、播放器定位和元数据详情体验。

**架构：** 先复用现有 `MediaLibrarySeries.key`、本地/网盘标签仓储、观看历史仓储和媒体库查询层。P0 只增加本地用户状态；P1 只在已有前台扫描和播放器链路上增加可见能力；P2 只对已匹配作品按需加载 TMDB 详情，不改变扫描和播放降级路径。

**技术栈：** Flutter、MobX/Modular、Hive CE、现有 media_kit/mpv、现有 TMDB 客户端与缓存。

---

## 范围与顺序

1. P0：统一收藏/待看/合集；完成后可单独发布。
2. P1：落地手动书签、嵌入章节、时间轴预览和扫描变更队列；时间轴预览只对本地文件生效。
3. P2：TMDB 详情增强；投屏/遥控暂不进入同一迭代。
4. 每个阶段都必须先通过定向测试，再运行 `flutter analyze --no-pub`；全量测试当前仍有既有版本契约失败，修复前不能宣称全绿。

## P0：收藏、待看、合集

### Task 1：增加本地用户状态仓储

**Files:**
- Create: `lib/features/library/application/media_library_user_state.dart`
- Create: `lib/features/library/application/media_library_user_state_repository.dart`
- Modify: `lib/features/settings/application/typed_settings.dart`
- Test: `test/media_library_user_state_repository_test.dart`

- [x] 定义 `MediaLibraryUserState`，只保存 `favorite`、`watchLater`、`collections` 和 `updatedAt`，不保存路径、令牌或媒体文件内容。
- [x] 使用 `MediaLibrarySeries.key` 作为 opaque key；不要重新使用原始文件路径作为用户状态主键。
- [x] 在 `SettingBoxKey` 增加独立键 `mediaLibraryUserStates`，不把系统状态混入已有自定义标签值。
- [x] 仓储提供 `getAll`、`save`、`remove`、`replaceAll`；损坏的单条状态跳过，不能阻塞整个媒体库。
- [x] 覆盖空值、重复合集名、损坏记录和删除状态；并发写入由仓储锁串行化。

### Task 2：把用户状态接入统一媒体库查询

**Files:**
- Modify: `lib/features/library/application/media_library_query.dart`
- Modify: `lib/features/library/application/media_category_runtime.dart`
- Modify: `lib/features/library/presentation/media_category_page.dart`
- Modify: `lib/features/library/presentation/immersive_media_card.dart`
- Modify: `lib/features/library/presentation/library_media_grid.dart`
- Test: `test/media_library_query_test.dart`
- Test: `test/media_category_page_test.dart`

- [x] 给查询增加 `favoriteOnly`、`watchLaterOnly`、`collection` 三个互斥筛选条件；没有筛选时保持现有结果完全一致。
- [x] `MediaCategoryRuntime` 负责加载和保存状态，页面只接收已加载的状态映射和操作回调，避免页面直接访问 Hive。
- [x] 在系列卡片更多菜单提供收藏、待看和合集管理；详情页展示扩展元数据。
- [x] 在现有来源筛选旁增加状态筛选，保留搜索、类型、来源和自定义标签的组合关系。
- [x] 用户状态独立于媒体索引，已删除或暂时不可用的条目不会被扫描结果带走，来源恢复后可按稳定键恢复。
- [x] 覆盖本地与网盘条目混合及收藏、待看、合集筛选。

### Task 3：P0 验收

- [x] 本地电影、本地剧集、网盘剧集共用同一用户状态模型和稳定键。
- [x] 仓储覆盖重启后的持久化接口，且状态与媒体文件生命周期分离。
- [x] 删除来源、清理缓存、重新扫描不会由用户状态仓储删除原始视频。
- [x] 定向测试通过：`flutter test --no-pub test/media_library_user_state_repository_test.dart test/media_library_query_user_state_test.dart test/media_library_query_test.dart test/media_category_page_test.dart`。

## P1-A：章节、书签和时间轴预览

### Task 4：先落地手动书签和嵌入章节

**Files:**
- Create: `lib/features/player/application/player_bookmark.dart`
- Create: `lib/features/player/application/player_chapter.dart`
- Modify: `lib/features/settings/application/typed_settings.dart`
- Modify: `lib/pages/player/player_controller.dart`
- Modify: `lib/pages/player/player_item_panel.dart`
- Modify: `lib/pages/player/player_item.dart`
- Test: `test/player_bookmark_repository_test.dart`, `test/player_chapter_test.dart`

- [x] 用播放历史已有的 `stableKey` 作为书签归属键，不能只用当前路径。
- [x] 书签字段只包含 `position`、`label`、`createdAt`；同一位置在 2 秒范围内合并，最多保留 100 条。
- [x] 播放器控制栏增加“书签/章节”入口；点击条目只调用已有 seek 流程。
- [x] 通过 NativePlayer 的 mpv `chapter-list/count`、`chapter-list/N/title` 和 `chapter-list/N/time` 读取真实嵌入章节；单个损坏章节跳过，不伪造章节数据。
- [x] 没有章节元数据时仍能使用手动书签。
- [x] 测试持久化、重复位置合并和损坏记录隔离；播放结束后的完整 UI 流程留待真机验证。

### Task 5：本地文件懒生成时间轴缩略图

**Files:**
- Create: `lib/services/local_timeline_thumbnail_cache.dart`
- Create: `lib/features/player/application/local_timeline_thumbnail_cache.dart`
- Create: `lib/features/player/presentation/player_timeline_progress_bar.dart`
- Modify: `lib/services/local_thumbnail_cache.dart`
- Modify: `lib/services/local_media_probe.dart`
- Modify: `lib/pages/player/player_item_panel.dart`
- Modify: `lib/pages/player/smallest_player_item_panel.dart`
- Test: `test/local_timeline_thumbnail_cache_test.dart`

- [x] 只对本地文件提供时间轴缩略图，网盘不预下载视频片段或缩略图。
- [x] 用户拖动或悬停进度时按时间桶懒生成，单个视频最多缓存 20 张；截图串行执行，退出时撤销未启动请求，已启动截图完成后丢弃过期结果。
- [x] 复用现有 `.kanyingyin_thumbs` 缓存目录；缓存损坏时删除单张并继续播放。
- [x] 缩略图生成失败、硬解不可用或不支持本地文件时直接退化为普通进度条。
- [x] 测试缓存命中、取消后不写入、上限淘汰、串行截图和失败降级；弹窗双向切换回归通过。

### Task 6：P1-B 扫描变更队列

**Files:**
- Modify: `lib/services/local_media_indexer.dart`
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `lib/pages/local/local_page.dart`
- Test: `test/local_media_indexer_test.dart`
- Test: `test/local_media_index_change_test.dart`

- [x] 在已有 `LocalMediaIndexResult` 上增加可选的逐项变更列表：新增、更新、移除、扫描失败；保留现有计数和构造调用兼容性。
- [x] 变更项只使用路径、显示值和失败原因；不计算完整视频哈希。
- [x] 扫描完成后在本地页显示“本次扫描变更”和失败摘要；队列只保存在当前应用状态。
- [x] 明确保持现有设计：不增加 `Directory.watch`、定时轮询或退出页面后的后台扫描。
- [x] 变更列表不自动覆盖手动 TMDB 匹配。
- [x] 测试新增、更新、移除、失败和取消扫描的边界。

### Task 7：P1 验收

- [x] 播放器无章节文件时仍能使用手动书签，不影响现有播放入口。
- [x] 时间轴缩略图关闭或失败时播放器动画、全屏、字幕、Anime4K 行为不变。
- [x] 扫描队列只在用户触发扫描或现有前台刷新后更新，不产生常驻进程。
- [x] 定向测试通过：`flutter test --no-pub test/player_bookmark_repository_test.dart test/local_media_index_change_test.dart test/local_media_indexer_test.dart test/local_controller_test.dart test/media_category_page_test.dart`。

## P2：TMDB 详情增强

### Task 8：演员、导演和相似作品

**Files:**
- Modify: `lib/modules/local/tmdb_metadata.dart`
- Modify: `lib/services/tmdb/tmdb_client.dart`
- Modify: `lib/features/library/presentation/media_library_details_dialog.dart`
- Test: `test/tmdb_detail_enrichment_test.dart`

- [x] 先只扩展已匹配作品详情页，不增加新的公共在线搜索入口。
- [x] 演员、导演和相似作品作为可选缓存字段；TMDB 不可用时保留已有标题、简介、评分、图片和播放能力。
- [x] 使用现有详情缓存并限制返回数量（主演 20、导演 10、相似作品 20），详情按需请求，不在扫描时批量请求。
- [x] 相似作品只展示已有 TMDB ID 的结果，不伪造本地/网盘可播放资源入口。
- [x] 测试 JSON 持久化、TMDB 客户端兼容和字段为空的降级路径。

## 明确不纳入本轮

- 不增加公共影视搜索、插件规则、WebView 解析、评论、多人同步观看或完整 Jellyfin/Plex 服务端。
- 不实现 Android TV 发布产物和 TV 专属功能。
- 不把 Chromecast/AirPlay/DLNA 与本计划绑定；投屏若需要，另立方案并先确认平台范围。
- 不在当前已有版本契约失败未修复前宣称“全量测试通过”。

## 本轮实现边界

- 最终测试版迭代为 `2.1.218+20218`：迭代前已安装 EXE 为 2.1.217，当前用户没有相关旧 MSIX 包。
- 嵌入章节只读取播放器底层真实暴露的 mpv 属性；无法读取时继续显示手动书签。
- 时间轴缩略图只对可直接访问的本地文件启用，网盘和 Android `content://` 播放源保留普通进度条。
- 本轮没有使用子代理，也不执行 Git commit。

## 统一验收

- [x] 已完成 P0、P1 扫描变更、章节、时间轴缩略图和 P2 详情增强的定向测试；手动书签定向测试通过。
- [x] `flutter analyze --no-pub` 无错误。
- [x] Windows Release 与测试版 Inno EXE 已生成并核对版本；未生成 MSIX、未构建 Android TV。
- [x] 已检查 `git status --short`，保留本轮改动及原有用户改动；本项目不执行 Git commit。
- [ ] 全量测试仍有一个既有失败：`identity_v2_zero_residue_test.dart` 检出仓库根目录 `UPSTREAM.md`，见交付汇报。
- [ ] 真实媒体章节跳转、鼠标悬停/触屏拖动预览及播放器实机体验尚未验收；自动化验证不替代实机验收。

## 2.1.218 最终交付记录

- `flutter test --no-pub`：2185 项通过、1 项失败；唯一失败为上述 `UPSTREAM.md` 身份扫描。
- `flutter analyze --no-pub`：无问题；Windows Release 和 Inno Setup 编译成功，主程序与安装器版本均为 2.1.218。
- 桌面安装器：`C:\Users\asus\Desktop\看影音-2.1.218-测试版-安装程序.exe`，69,974,721 字节，签名状态 `NotSigned`。
- 安装器 SHA256：`132BB1A2F2FFF5144017703286CAFB9DF8C24543BAC069A35D4674BB562EC313`。
- Release 主程序 SHA256：`B9893E5297373947A4005CB04C01C6C682D2FC2D4A22CA3465B88113A1E98ABF`。
- 本轮未安装新包；复核时已安装版本仍为 2.1.217。没有生成 MSIX 或 Android TV 发布产物。
