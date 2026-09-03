# 大文件拆分方案（任务 B）

> 生成时间：2026-09（基于 1.0.13 基线，全量测试 2071 项）。
> 目标：将 5 个超 1500 行的文件按职责拆分为多个协作单元，**对外符号、import 路径与运行时行为完全不变**。
> 执行纪律：每个拆分单元一个独立 commit；每单元完成后必须 `flutter analyze` 无错误、`flutter test` 全绿（基线 2071 项）后才可进入下一单元；某单元测试无法在合理时间内恢复全绿则整体回退该单元并记录原因。

## 0. 全局约束与已确认风险

1. **源码文本契约测试（最大隐性风险）**：多个测试直接 `readAsStringSync` 读取源文件做文本断言，拆分前必须逐条核对断言落点：
   - `test/version_consistency_test.dart`：要求 `lib/utils/version_history.dart` 文本中包含字面量 `const List<VersionHistory> versionHistoryList`，且当前版本（1.0.13）条目位于该声明**之后**的同一文件内；条目文本需含「网盘/Windows/Android/不会修改/手机和平板」且不含 `isPrerelease: true`。
   - `test/release_config_contract_test.dart`：要求 version_history.dart 文本包含 `version: '1.0.13'`。
   - `test/dead_online_code_test.dart`：对 player_controller.dart（不含 syncplay/OnlineSource 等）、player_item.dart（不含 OnlineSource 等）、cloud_resources_controller.dart（不含 currentDirectory;/openDirectory( 等 7 个符号）做**反向**文本断言——拆分不得引入这些符号，且断言只读主文件，代码迁入 part 文件不影响反向断言，但**正向断言**（contains）会受影响。
   - `test/player_resource_lifecycle_test.dart`（40–70 行）：用 `indexOf` 截取 player_controller.dart 中 `_disposePlayerResources` 到 `\n  Future<void> stop()` 的文本区间做断言——**stop() 方法不得迁出主文件**，或同步改测试。
   - `test/player_exit_lifecycle_test.dart`（89–101 行）、`test/local_video_controller_test.dart`（152–263 行，含多行精确匹配）、`test/android_player_media_compatibility_test.dart`（83–202 行）、`test/windows_full_libmpv_config_test.dart`、`test/windows_player_color_settings_test.dart`：对 player_controller.dart/player_item.dart/local_controller.dart 做正向文本断言。
   - `test/network_infrastructure_test.dart`（116–127 行）、`test/http_stream_completion_contract_test.dart`（7–15 行）：要求 local_controller.dart 文本包含 `TmdbImageClient.shared.downloadBytes` 且不含 `HttpClient()`；`test/local_video_controller_test.dart:152` 要求包含 `tmdbPosterUrlForPaths`——这两段必须留在主文件。
2. **MobX 代码生成**：player_controller（49 处 @observable / 16 处 @action）、local_controller（43/23/4）拆分为 mixin part 后，每个含注解的 part 需各自 `part 'xxx.g.dart'` 并重跑 build_runner；门面类（`class PlayerController = _PlayerController with ...`）与 part 声明只能留在主文件。cloud_resources_controller 无 MobX（纯 ChangeNotifier），无生成链。
3. **保护重点（行为冻结）**：全屏、字幕、选集、硬件解码（含 TrueHD/软解回退）、Anime4K 逻辑；「删除媒体源/索引/缓存不得删除用户原始视频文件」的防护门控；TMDB 不可用/无 Key/断网时本地扫描与播放可用的降级路径；播放器表现层控件层级、动画时长、曲线、交互。
4. **part 文件方案**：所有 part 与主文件同库（`part of`），保证私有成员跨单元互访与对外 import 路径不变；part 文件内不得出现 import/library 指令。

## 1. version_history.dart（3497 行，纯数据，风险最低——首个执行）

**结构**：`VersionHistory` 类（1–17）；Android 命名常量表 `_androidXxx`（19–287，仅被 versionHistoryForCurrent 使用）；主列表 `versionHistoryList`（288–3401，约 230 条，最新在前，1.0.x 正式版与 2.1.x 测试版按发布时间交错，末尾 2.1.139 为历史追加）；`versionHistoryForCurrent`（3403–3497）。

**约束**：文本契约测试（上文 0.1）要求列表声明与当前版本条目留在主文件；条目顺序是用户可见顺序，**不得重排**——1.0.x 与 2.1.x 交错意味着「严格按版本族分文件」不可行，必须按**连续行区间**切片。

**方案**（4 个 part，主文件降至约 170 行）：

| 文件 | 内容 | 原行号 | 约行数 |
|---|---|---|---|
| `lib/utils/version_history.dart`（主） | 类、part 声明、versionHistoryList（当前 1.0.13 条目内联 + 末尾 2.1.139 条目内联 + 展开）、versionHistoryForCurrent | 1–17、289–300、3388–3400、3403–3497 | ~170 |
| `version_history/android_release_summaries.dart` | Android 命名常量表 | 19–287 | ~270 |
| `version_history/changelog_2_1_late.dart` | 2.1.203→2.1.104 区段（含交错 1.0.12–1.0.6） | 301–1551 | ~1250 |
| `version_history/changelog_2_1_early.dart` | 1.0.5→2.1.0 区段（含交错 1.0.5–1.0.0） | 1552–2819 | ~1270 |
| `version_history/changelog_stable_legacy.dart` | 2.0.x、1.4.x、1.3.x、1.2.x、1.1.x 早期正式版 | 2820–3387 | ~570 |

主文件列表形如：
```dart
const List<VersionHistory> versionHistoryList = [
  /* 1.0.13 条目内联（文本契约测试要求） */
  VersionHistory(version: '1.0.13', ...),
  ..._changelog21LateHistory,
  ..._changelog21EarlyHistory,
  ..._changelogStableLegacyHistory,
  /* 2.1.139 条目内联（历史上追加在列表末尾） */
  VersionHistory(version: '2.1.139', ...),
];
```
**验证**：重组后逐行比对原 289–3400 行序列必须完全一致；跑 version_consistency / release_config_contract / android_tv_acceptance_contract / version_history_current 四个测试 + 全量套件。

## 2. cloud_resources_controller.dart（1824 行，非 MobX，第二优先）

单类 `CloudResourcesController extends ChangeNotifier`（101–1824），无 UI 依赖。主文件保留 imports、顶层 enum/值类（67–99）、类声明、构造函数与**全部字段**（final 字段不能由 mixin 构造器初始化）、通用工具/dispose；9 个 part mixin 按职责拆分（sources/scan/directory_scope/filter_tags/hidden_videos/tmdb_entry/tmdb_work/episode_match/auto_organize）。测试以子类覆写方式使用公开方法，签名不可变；dead_online_code_test 只做反向断言，不受影响。TMDB 降级分支（_scheduleTmdb 的 catchError、扫描失败保留上次索引、coordinator==null 抛 StateError 但浏览不受影响）需逐行原样迁移。

## 3. player_controller.dart（2072 行，MobX，第三优先）

先用「数据类提取」降体量，再按 mixin part 拆分：
- 单元 3a：`player_controller_params.dart`（43–221 的 PlaybackInitParams、PlayerRuntimeSnapshot、CloudPlaybackRefreshTransaction 及 4 个顶层函数），主文件 `export`——需先确认 7 个文本契约测试不正向断言该区段（已确认 local_video_controller_test 的多行断言落在字幕区段 1092–1777，android_player_media_compatibility_test 落在解码区段）。
- 单元 3b–3h：状态声明（226–501）、初始化/解码核心（503–961，**高风险：hwdec/vo/代理/色彩**）、解码恢复（963–1090+1662–1716，**高风险：硬解回退/TrueHD**）、字幕（1092–1777，**高风险**，可再二分轨道/样式）、Anime4K（1779–1884，**高风险**）、控制/音量倍速（低风险）、生命周期（1940–2042，**stop() 必须留主文件**或同步改 player_resource_lifecycle_test）。
- 每单元后重跑 build_runner，核对 .g.dart 重新生成且门面类混入全部 `_$XxxMixin`。

## 4. local_controller.dart（1884 行，MobX，第四优先）

主文件保留：两个异常类、`LocalController =` 声明、构造/DI、全部 @observable 状态、@computed、**tmdbPosterUrlForPaths 与 _cloudTmdbService（文本契约测试要求）**、TmdbImageClient.shared.downloadBytes 相关段落；7 个 part mixin：navigation/posters/sources/index/tmdb/matching/library。删除防护（removeMediaSource 经 LocalLibrarySourceCoordinator 且扫描中拒绝）与 TMDB 空 Key 降级分支（1134–1137 返回 0 不抛错）必须原位保留门控顺序。

## 5. player_item.dart（1518 行，UI 表现层，最后执行且只做最小拆分）

800+ 行是与 State 字段强耦合的事件处理器，且 6 个测试做正向源码文本断言——**不建议大拆**。受文本断言保护不能迁出：全屏（720–751）、快捷键分发（403–474）、TV 焦点（476–519）、浮层协调调用、退出生命周期、定时器轮询。最小安全拆分集（正向断言不覆盖，保留薄转发方法）：
1. `player_debug_info_panel.dart`：视频信息面板 + 日志面板 UI（897–1027、1116–1181，约 195 行），主文件保留 showVideoInfo 转发。
2. `anime4k_confirm_dialog.dart`：确认对话框构建（656–704，约 50 行）。
3. `subtitle_file_picker.dart`：字幕文件选择/导入 helper（1029–1072，约 45 行）。
硬约束：控件层级、动画时长/曲线、交互行为零变更。

## 6. 执行顺序与状态

| 序 | 单元 | 状态 |
|---|---|---|
| 0 | 方案文档（本文件） | 已完成 |
| 1 | version_history 拆分 | 待执行 |
| 2 | cloud_resources_controller 拆分（9 个 mixin part，可按 2–3 个 commit 分批） | 待执行 |
| 3 | player_controller params 提取 → 状态 → 低风险组 → 高风险组 | 待执行 |
| 4 | local_controller 拆分 | 待执行 |
| 5 | player_item 最小拆分集 | 待执行 |

每单元提交前核对：`git status --short` 只含本单元文件；analyze 无错误；全量 test 全绿（偶发超时类失败需单独复跑确认非本次改动引入）；diff 不触碰全屏/字幕/选集/硬解/Anime4K 行为与文本契约保护段。
