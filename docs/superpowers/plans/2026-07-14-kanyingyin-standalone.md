# 看影音独立项目 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 从 `D:\KanYingYin-src` 创建独立的 Windows Flutter 应用 `D:\KanYingYin`，完整保留“就看”的本地媒体库、播放器 UI 与动画，并加入 TMDB 刮削，移除全部在线播放能力。

**Architecture:** 先复制现有项目并建立独立应用身份，再以 `LocalMediaSeries`、`LocalEpisode`、`LocalPlaybackSession` 替换本地播放对 `BangumiItem`、`Road` 和在线 `VideoPageController` 的依赖。媒体库继续使用现有扫描、索引和 Hive 存储，新增 TMDB 客户端、匹配器与缓存仓储；播放器表现层保持原结构，只收窄控制器依赖。

**Tech Stack:** Flutter 3.41.9、Dart 3、Flutter Modular、MobX、Hive CE、Dio、media_kit、Anime4K、Windows MSIX。

---

### Task 1: 创建独立可构建副本

**Files:**
- Create: `D:\KanYingYin\`
- Delete from copy: `D:\KanYingYin\.git\`

- [ ] **Step 1: 确认源项目工作区干净**

Run: `git -C D:\KanYingYin-src status --short`

Expected: 无输出。

- [ ] **Step 2: 复制项目并排除 Git 与构建产物**

Run: `robocopy D:\KanYingYin-src D:\KanYingYin /E /XD .git build .dart_tool .idea /XF *.msix`

Expected: `pubspec.yaml`、`lib`、`windows`、`assets`、`test` 存在，robocopy 退出码小于 8。

- [ ] **Step 3: 初始化独立仓库并验证基线**

Run:

```powershell
git -C D:\KanYingYin init
git -C D:\KanYingYin add .
git -C D:\KanYingYin commit -m "chore: 初始化看影音项目"
D:\flutter\bin\flutter.bat pub get
D:\flutter\bin\flutter.bat analyze
```

Workdir: `D:\KanYingYin`

Expected: 新仓库产生首个提交；依赖安装成功；analyze 无 error。

### Task 2: 建立应用身份和独立存储

**Files:**
- Create: `D:\KanYingYin\lib\utils\app_identity.dart`
- Modify: `D:\KanYingYin\pubspec.yaml`
- Modify: `D:\KanYingYin\lib\main.dart`
- Modify: `D:\KanYingYin\lib\app_widget.dart`
- Modify: `D:\KanYingYin\lib\utils\storage.dart`
- Modify: `D:\KanYingYin\windows\runner\Runner.rc`
- Modify: `D:\KanYingYin\windows\runner\main.cpp`
- Test: `D:\KanYingYin\test\app_identity_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/app_identity.dart';

void main() {
  test('使用独立的看影音应用身份', () {
    expect(AppIdentity.displayName, '看影音');
    expect(AppIdentity.packageName, 'kanyingyin');
    expect(AppIdentity.windowsIdentity, 'com.kanyingyin.player');
    expect(AppIdentity.storageNamespace, 'kanyingyin');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test test\app_identity_test.dart`

Expected: FAIL，提示 `app_identity.dart` 不存在。

- [ ] **Step 3: 实现身份常量**

```dart
abstract final class AppIdentity {
  static const displayName = '看影音';
  static const packageName = 'kanyingyin';
  static const windowsIdentity = 'com.kanyingyin.player';
  static const storageNamespace = 'kanyingyin';
}
```

将 `pubspec.yaml` 包名改为 `kanyingyin`，机械替换 `package:jiukan/` 导入，窗口标题、退出文案、Windows 产品信息和 MSIX 显示名改为“看影音”。Hive 使用独立的 `kanyingyin/hive` 数据目录。

- [ ] **Step 4: 验证并提交**

Run:

```powershell
D:\flutter\bin\flutter.bat pub get
D:\flutter\bin\flutter.bat test test\app_identity_test.dart
D:\flutter\bin\flutter.bat analyze
git add pubspec.yaml lib windows test/app_identity_test.dart
git commit -m "chore: 建立看影音应用身份"
```

Expected: 测试 PASS；analyze 无 error；提交成功。

### Task 3: 建立本地播放领域模型

**Files:**
- Create: `D:\KanYingYin\lib\modules\local\local_episode.dart`
- Create: `D:\KanYingYin\lib\modules\local\local_media_series.dart`
- Create: `D:\KanYingYin\lib\modules\video\local_playback_session.dart`
- Modify: `D:\KanYingYin\lib\services\local_playback_request_builder.dart`
- Test: `D:\KanYingYin\test\local_playback_session_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_episode.dart';
import 'package:kanyingyin/modules/video/local_playback_session.dart';

void main() {
  test('会话使用本地剧集定位当前集', () {
    final episodes = [
      const LocalEpisode(id: 'e1', path: r'D:\Video\01.mkv', title: '第1集', episodeNumber: 1),
      const LocalEpisode(id: 'e2', path: r'D:\Video\02.mkv', title: '第2集', episodeNumber: 2),
    ];
    final session = LocalPlaybackSession(
      seriesId: 'series',
      seriesTitle: '测试动画',
      episodes: episodes,
      currentEpisodeId: 'e2',
    );
    expect(session.currentIndex, 1);
    expect(session.currentEpisode.path, r'D:\Video\02.mkv');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `D:\flutter\bin\flutter.bat test test\local_playback_session_test.dart`

Expected: FAIL，提示领域模型不存在。

- [ ] **Step 3: 实现模型和构建器**

`LocalEpisode` 包含 `id`、`path`、`title`、季集编号、字幕和时长；`LocalMediaSeries` 包含系列元数据和有序剧集；`LocalPlaybackSession` 校验剧集非空并提供当前、上一集、下一集。`LocalPlaybackRequestBuilder.build()` 改为返回该会话，保持现有播放列表隔离、排序和字幕匹配算法。

- [ ] **Step 4: 验证并提交**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\local_playback_session_test.dart test\local_playback_request_builder_test.dart
git add lib/modules/local lib/modules/video lib/services/local_playback_request_builder.dart test
git commit -m "refactor: 建立本地播放领域模型"
```

Expected: 全部 PASS。

### Task 4: 解耦播放器控制链路并保留动画

**Files:**
- Create: `D:\KanYingYin\lib\pages\video\local_video_controller.dart`
- Modify: `D:\KanYingYin\lib\pages\video\video_page.dart`
- Modify: `D:\KanYingYin\lib\pages\player\player_controller.dart`
- Modify: `D:\KanYingYin\lib\pages\player\player_item.dart`
- Modify: `D:\KanYingYin\lib\pages\player\player_item_panel.dart`
- Modify: `D:\KanYingYin\lib\pages\player\smallest_player_item_panel.dart`
- Test: `D:\KanYingYin\test\local_video_controller_test.dart`

- [ ] **Step 1: 写控制器失败测试**

测试 `openSession()` 把当前集路径、标题、字幕和恢复进度转换为播放器参数，并在切换下一集时更新当前集 ID。

- [ ] **Step 2: 实现本地控制器**

控制器只依赖 `PlayerController`、本地历史仓储和 `LocalPlaybackSession`。删除插件、WebView、下载、在线评论和线路解析依赖。

- [ ] **Step 3: 保留表现层**

保留 `VideoPage` 的 `AnimationController`、曲线、时长、全屏和面板显隐代码；保留 `player/` 控件树、手势和动画，仅删除在线专属按钮与分支。

- [ ] **Step 4: 收窄播放器参数**

保留文件路径、恢复进度、剧集 ID、标题、封面、系列名和字幕；移除 Bangumi ID、插件名、HTTP 头、广告拦截、referer、在线测速、代理、同步播放和投屏。

- [ ] **Step 5: 验证并提交**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\local_video_controller_test.dart
D:\flutter\bin\flutter.bat analyze
git add lib/pages/video lib/pages/player test/local_video_controller_test.dart
git commit -m "refactor: 独立本地播放器控制链路"
```

Expected: 测试 PASS；analyze 无 error。

### Task 5: 升级本地索引为 TMDB 元数据模型

**Files:**
- Create: `D:\KanYingYin\lib\modules\local\tmdb_metadata.dart`
- Modify: `D:\KanYingYin\lib\modules\local\local_media_index_item.dart`
- Modify: `D:\KanYingYin\lib\repositories\local_media_index_repository.dart`
- Test: `D:\KanYingYin\test\local_media_index_tmdb_test.dart`

- [ ] **Step 1: 写 JSON 兼容失败测试**

测试旧 `bangumiNameCn`、`bangumiSummary`、`bangumiCoverUrl` 可兼容读取，新保存格式只写 `tmdb`；标题、封面和简介锁定字段往返不丢失。

- [ ] **Step 2: 实现 TMDB 元数据**

字段固定为 `id`、`mediaType`、`title`、`originalTitle`、`overview`、`releaseDate`、`rating`、`posterUrl`、`backdropUrl`、`language`、`matchedAt`、`matchConfidence`。

- [ ] **Step 3: 替换 Bangumi 字段**

`fromJson` 对旧字段做一次性映射，`toJson` 只输出 `tmdb`；新增 `titleLocked`、`posterLocked`、`overviewLocked`、`scrapeStatus`。

- [ ] **Step 4: 验证并提交**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\local_media_index_tmdb_test.dart
git add lib/modules/local lib/repositories/local_media_index_repository.dart test/local_media_index_tmdb_test.dart
git commit -m "feat: 扩展本地媒体 TMDB 元数据"
```

Expected: PASS。

### Task 6: 实现 TMDB 客户端、匹配器和缓存

**Files:**
- Create: `D:\KanYingYin\lib\services\tmdb\tmdb_client.dart`
- Create: `D:\KanYingYin\lib\services\tmdb\tmdb_matcher.dart`
- Create: `D:\KanYingYin\lib\services\tmdb\tmdb_scraper.dart`
- Create: `D:\KanYingYin\lib\repositories\tmdb_metadata_repository.dart`
- Test: `D:\KanYingYin\test\tmdb_matcher_test.dart`
- Test: `D:\KanYingYin\test\tmdb_scraper_test.dart`

- [ ] **Step 1: 写匹配和语言回退失败测试**

覆盖完全同名、年份差异、类型冲突、多候选低置信度；使用 Dio mock 验证先请求 `zh-CN`，缺失简介或图片时请求 `en-US`。

- [ ] **Step 2: 实现客户端**

封装 TMDB v3 的电影/电视剧搜索、详情和季度接口；API Key 从设置读取，日志不得输出 Key。

- [ ] **Step 3: 实现匹配器和刮削器**

匹配器返回候选、分数和自动匹配标志。刮削器支持单项、批量、取消、失败重试和锁定字段合并，单项失败不终止批次。

- [ ] **Step 4: 实现缓存仓储**

Hive 保存结构化元数据；图片写入应用缓存目录，文件名使用 TMDB ID、类型和图片路径哈希。

- [ ] **Step 5: 验证并提交**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\tmdb_matcher_test.dart test\tmdb_scraper_test.dart
D:\flutter\bin\flutter.bat analyze
git add lib/services/tmdb lib/repositories/tmdb_metadata_repository.dart test/tmdb_*.dart
git commit -m "feat: 支持 TMDB 元数据刮削"
```

Expected: 测试 PASS；analyze 无 error。

### Task 7: 接入媒体库、详情页和设置

**Files:**
- Modify: `D:\KanYingYin\lib\pages\local\local_controller.dart`
- Modify: `D:\KanYingYin\lib\pages\local\local_page.dart`
- Create: `D:\KanYingYin\lib\pages\local\tmdb_match_sheet.dart`
- Create: `D:\KanYingYin\lib\pages\local\local_series_detail_page.dart`
- Create: `D:\KanYingYin\lib\pages\settings\tmdb_settings.dart`
- Test: `D:\KanYingYin\test\local_tmdb_integration_test.dart`

- [ ] **Step 1: 写集成失败测试**

验证仅在开启自动刮削且存在 Key 时触发；低置信度进入待确认；锁定字段不覆盖；无 Key 不影响扫描。

- [ ] **Step 2: 接入媒体库动作**

在现有卡片菜单增加刮削、重新匹配和锁定；工具栏增加批量刮削。保持当前卡片布局、搜索、滚动和动画。

- [ ] **Step 3: 实现匹配弹层和详情页**

候选项展示海报、标题、原名、年份、类型和简介。详情页复用当前主题与转场，展示 TMDB 背景图、海报、简介、评分、季集和观看进度。

- [ ] **Step 4: 实现 TMDB 设置**

提供 API Key、自动刮削、首选语言、连通性测试、元数据缓存清理和图片缓存清理。

- [ ] **Step 5: 验证并提交**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\local_tmdb_integration_test.dart
D:\flutter\bin\flutter.bat analyze
git add lib/pages/local lib/pages/settings test/local_tmdb_integration_test.dart
git commit -m "feat: 接入媒体库 TMDB 刮削"
```

Expected: PASS；无 error。

### Task 8: 收敛导航、历史、存储和依赖注入

**Files:**
- Modify: `D:\KanYingYin\lib\pages\navigation\navigation_config.dart`
- Modify: `D:\KanYingYin\lib\pages\index_module.dart`
- Modify: `D:\KanYingYin\lib\pages\history\history_controller.dart`
- Modify: `D:\KanYingYin\lib\utils\storage.dart`
- Test: `D:\KanYingYin\test\navigation_config_test.dart`
- Test: `D:\KanYingYin\test\storage_registration_test.dart`

- [ ] **Step 1: 写路由和存储失败测试**

断言默认路径为 `/tab/local/`，主导航只保留本地媒体库与设置；存储不再打开收藏、在线搜索、下载和同步变更 box。

- [ ] **Step 2: 收敛模块**

`IndexModule` 只绑定本地索引、媒体源、历史、TMDB、`LocalController`、`LocalVideoController`、`PlayerController`、`ShadersController`。

- [ ] **Step 3: 验证并提交**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\navigation_config_test.dart test\storage_registration_test.dart
D:\flutter\bin\flutter.bat analyze
git add lib/pages/navigation lib/pages/index_module.dart lib/pages/history lib/utils/storage.dart test
git commit -m "refactor: 收敛看影音本地功能入口"
```

Expected: PASS；无 error。

### Task 9: 删除在线模块与依赖

**Files:**
- Delete: `D:\KanYingYin\lib\plugins\`
- Delete: `D:\KanYingYin\lib\webview\`
- Delete: 在线专属页面、请求、视频源 provider 和测试
- Modify: `D:\KanYingYin\pubspec.yaml`
- Test: `D:\KanYingYin\test\no_online_dependencies_test.dart`

- [ ] **Step 1: 写在线残留失败测试**

递归扫描 `lib`，禁止出现 `PluginsController`、`VideoWebview`、`BangumiApi`、`WebDAV`、`Captcha`、`initForDirectUrlPlayback`。

- [ ] **Step 2: 按引用顺序删除**

先删除路由和绑定，再删除页面、控制器、服务、模型和资源，最后移除 WebView、插件解析、WebDAV、投屏和在线专属依赖；保留 Dio 供 TMDB 使用。

- [ ] **Step 3: 验证并提交**

Run:

```powershell
D:\flutter\bin\flutter.bat pub get
D:\flutter\bin\flutter.bat test test\no_online_dependencies_test.dart
D:\flutter\bin\flutter.bat analyze
git add -A
git commit -m "refactor: 移除在线播放与插件模块"
```

Expected: PASS；无 error。

### Task 10: 版本、更新日志、快捷方式和 MSIX

**Files:**
- Modify: `D:\KanYingYin\pubspec.yaml`
- Modify: `D:\KanYingYin\RELEASE_NOTES.md`
- Modify: `D:\KanYingYin\lib\utils\version_history.dart`
- Modify: Windows 快捷方式与 MSIX 配置文件

- [ ] **Step 1: 设置首版版本**

设置 `version: 1.0.0+10000`、`msix_version: 1.0.0.0`，安装包名为 `看影音-1.0.0.msix`。

- [ ] **Step 2: 更新用户日志**

文案包含独立本地媒体库、完整播放器、TMDB 刮削、字幕、Anime4K 和 Windows 安装支持，不写内部路径或构建命令。

- [ ] **Step 3: 回归快捷方式弹窗**

首次启动且桌面或开始菜单快捷方式不存在时必须提示创建，用户可确认或取消，不允许静默跳过。

- [ ] **Step 4: 完整验证**

Run:

```powershell
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
D:\flutter\bin\flutter.bat build windows --release
D:\flutter\bin\dart.bat run msix:create
```

Expected: 测试 PASS；analyze 无 error；Release 和 MSIX 生成成功。

- [ ] **Step 5: 实机视觉检查**

检查 `1280x720`、`1440x900`、`1920x1080` 下的媒体库、详情页、播放器控制层、自动隐藏、全屏、选集、字幕和 Anime4K，确保动画与“就看”一致且无重叠。

- [ ] **Step 6: 最终提交**

Run:

```powershell
git add -A
git commit -m "release: 发布看影音 1.0.0"
git status --short
```

Expected: 提交成功；工作区无输出。
