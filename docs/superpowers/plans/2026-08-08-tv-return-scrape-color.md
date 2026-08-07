# TV 返回、刮削一致性与色彩链路 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Do not use subagents for this project unless the user later explicitly changes that instruction.

**Goal:** 修复 Android TV 播放器返回与选集层级，统一本地和个人网盘 TMDB 匹配链路，并提供可验证的播放器色彩配置与安全的 GLSL 资源更新机制。

**Architecture:** 工作拆成四个可独立验证的批次，但合并为一次最终版本交付。TV 返回由纯策略决定消费顺序，平台方向恢复显式识别 Android TV；TMDB 海报只消费共享刮削引擎选定的稳定身份；色彩处理使用强类型配置映射到受支持的 libmpv 属性；第三方仓库只作为固定来源参考，不执行在线 Lua 代码。

**Tech Stack:** Flutter 3.41.9、Dart、MobX、Flutter Modular、media_kit/libmpv、Android Kotlin、Dio、flutter_test、Inno Setup。

---

## 已确认的证据

- `VideoPage.dispose()` 在所有非桌面平台调用 `Utils.exitFullScreen()`。
- `WindowUtils.exitFullScreen()` 只使用最短边判断平板或手机；Android TV 若被判断为小于 600dp，会请求 `portraitUp`。
- `PlayerBackPolicy` 没有接收 `localVideoController.showTabBody`，右侧选集列表可见时仍可能进入离开播放器路径。
- 异机 2.1.146 日志显示 TMDB API 曾恢复，但 `image.tmdb.org` 多次 TLS 握手失败；`LocalPosterScraper` 随后使用索引备用封面。
- `LocalPosterScraper` 使用 `PosterService.searchPoster()` 的首结果逻辑，绕过本地和网盘共用的 `TmdbScrapeEngine` 排序。
- 异机播放链路为 `libmpv + D3D11 + hevc-d3d11va`，输入为 4K HDR，Anime4K 关闭；日志未记录 tone mapping、色域、色阶和目标峰值。

## 文件边界

- Modify: `lib/utils/window_utils.dart` - Android TV 方向恢复。
- Create: `lib/features/player/application/player_orientation_policy.dart` - 可单测的平台方向策略。
- Modify: `lib/features/player/application/player_back_policy.dart` - 选集侧栏优先级。
- Modify: `lib/pages/video/video_page.dart` - 返回键执行与侧栏动画状态。
- Modify: `lib/services/local_poster_scraper.dart` - 移除独立 TMDB 首结果搜索。
- Modify: `lib/pages/local/local_controller.dart` - 通过统一刮削服务提供海报 URL。
- Modify: `lib/services/poster_service.dart` - 统一图片下载网络配置与代理恢复。
- Modify: `lib/services/tmdb/tmdb_scrape_engine.dart` - 增加脱敏匹配诊断。
- Modify: `lib/features/settings/application/typed_settings.dart` - 色彩配置键。
- Create: `lib/features/player/application/player_color_profile.dart` - 强类型色彩方案。
- Modify: `lib/pages/player/player_controller.dart` - 应用 libmpv 色彩属性并记录诊断。
- Modify: `lib/pages/settings/player_settings.dart` - 色彩方案入口。
- Modify: `lib/shaders/shader_asset_installer.dart` - 固定清单、哈希和原子替换。
- Modify: `lib/shaders/shaders_controller.dart` - 资源版本与回滚状态。
- Create tests: `test/player_orientation_policy_test.dart`、`test/tmdb_scrape_parity_test.dart`、`test/poster_service_test.dart`、`test/player_color_profile_test.dart`、`test/shader_asset_installer_test.dart`。
- Modify tests: `test/player_back_policy_test.dart`、`test/player_tv_focus_test.dart`、`test/android_player_media_compatibility_test.dart`、`test/local_poster_scraper_test.dart`、`test/tmdb_scrape_engine_test.dart`、`test/player_runtime_preferences_test.dart`、`test/android_player_settings_test.dart`、`test/anime4k_player_controller_test.dart`。

### Task 1: 固化 Android TV 方向恢复策略

- [ ] **Step 1: 写失败测试**

Create `test/player_orientation_policy_test.dart`，覆盖 TV、平板和手机：

```dart
test('TV 退出播放器后保持横屏', () {
  expect(
    PlayerOrientationPolicy.afterPlayback(
      isAndroidTv: true,
      isTablet: false,
    ),
    PlayerExitOrientation.landscape,
  );
});

test('手机退出播放器后恢复竖屏', () {
  expect(
    PlayerOrientationPolicy.afterPlayback(
      isAndroidTv: false,
      isTablet: false,
    ),
    PlayerExitOrientation.portrait,
  );
});
```

- [ ] **Step 2: 运行失败测试**

Run: `D:\flutter\bin\flutter.bat test test\player_orientation_policy_test.dart`

Expected: FAIL，因为策略文件尚不存在。

- [ ] **Step 3: 实现纯策略并接入 WindowUtils**

Create `lib/features/player/application/player_orientation_policy.dart`：

```dart
enum PlayerExitOrientation { landscape, portrait }

class PlayerOrientationPolicy {
  const PlayerOrientationPolicy._();

  static PlayerExitOrientation afterPlayback({
    required bool isAndroidTv,
    required bool isTablet,
  }) {
    return isAndroidTv || isTablet
        ? PlayerExitOrientation.landscape
        : PlayerExitOrientation.portrait;
  }
}
```

在 `WindowUtils.exitFullScreen()` 中先读取 `detectAppPlatform()`，TV 必须请求双向横屏，不能进入 `portraitUp` 分支。沉浸模式仍正常关闭，系统栏恢复行为不变。

- [ ] **Step 4: 增加源码契约测试**

在 `test/android_player_media_compatibility_test.dart` 断言 `window_utils.dart` 调用 `PlayerOrientationPolicy.afterPlayback`，并断言 Android TV 分支不会选择 `DeviceOrientation.portraitUp`。

- [ ] **Step 5: 运行定向测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\player_orientation_policy_test.dart test\android_player_media_compatibility_test.dart`

Commit: `fix: 保持电视播放器退出后的横屏方向`

### Task 2: 让返回键按浮层层级逐级消费

- [ ] **Step 1: 写失败策略测试**

在 `test/player_back_policy_test.dart` 增加：

```dart
test('Android TV 选集列表显示时返回键先关闭列表', () {
  expect(
    PlayerBackPolicy.decide(
      overlayVisible: false,
      episodePanelVisible: true,
      controlsVisible: false,
      fullscreen: false,
      isAndroidTv: true,
    ),
    PlayerBackAction.closeEpisodePanel,
  );
});
```

- [ ] **Step 2: 调整返回策略**

`PlayerBackAction` 增加 `closeEpisodePanel`，顺序固定为：应用弹窗、选集侧栏、播放器控制层、桌面全屏、离开播放器。非 TV 行为保持原顺序。

- [ ] **Step 3: 接入 VideoPage**

向策略传入：

```dart
episodePanelVisible:
    capabilities.isAndroidTv && localVideoController.showTabBody,
```

收到 `closeEpisodePanel` 时只执行 `closeTabBodyAnimated()` 并恢复播放器焦点，禁止 `Navigator.pop()`。把侧栏关闭过程改为可等待状态，动画尚未完成时重复返回仍由侧栏消费，避免一次按键穿透到退出路由。

- [ ] **Step 4: 增加页面契约测试**

在 `test/player_tv_focus_test.dart` 断言 `episodePanelVisible`、`closeEpisodePanel`、`closeTabBodyAnimated()` 和焦点恢复均已接入。

- [ ] **Step 5: 运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\player_back_policy_test.dart test\player_tv_focus_test.dart test\player_exit_lifecycle_test.dart`

Commit: `fix: 电视返回键优先收回选集列表`

### Task 3: 统一本地与网盘 TMDB 身份选择

- [ ] **Step 1: 写本地与网盘一致性失败测试**

Create `test/tmdb_scrape_parity_test.dart`。使用同一资源名 `Annihilation.2018.BluRay.2160p.x265.10bit.HDR.mkv` 构造本地和网盘 subject，断言清理后的主查询词、媒体类型证据、年份和最终候选 TMDB ID 一致。

- [ ] **Step 2: 禁止 LocalPosterScraper 独立选首结果**

`LocalPosterScraper` 不再调用 `PosterService.searchPoster()`。它只接收 `LocalTmdbScrapeService` 已确认的 `TmdbMetadata.posterUrl`；没有稳定 TMDB 身份时返回待确认，不允许使用另一套“movie 优先、第一项命中”规则。

- [ ] **Step 3: 明确备用封面规则**

只有以下情况允许使用索引封面：索引 TMDB ID 与当前匹配 TMDB ID 相同，或该封面由用户锁定。网络失败时保留旧资料但显示“图片下载失败，可重试”，不能把旧封面描述为本次刮削成功。

- [ ] **Step 4: 增加脱敏诊断**

`TmdbScrapeEngine` 记录查询词、媒体类型、候选 TMDB ID、分数、最终状态和图片下载阶段；不记录 API Key、代理凭据、网盘令牌或完整路径。

- [ ] **Step 5: 运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\local_poster_scraper_test.dart test\tmdb_scrape_engine_test.dart test\tmdb_scrape_parity_test.dart`

Commit: `fix: 统一本地和网盘刮削身份选择`

### Task 4: 修复 TMDB 图片下载与 API 网络配置分裂

- [ ] **Step 1: 写失败网络测试**

Create `test/poster_service_test.dart`。注入一个首次 TLS/连接失败、代理恢复后成功的下载 Dio，断言图片下载只恢复一次并复用新的网络配置。

- [ ] **Step 2: 复用项目网络工厂**

`PosterService` 禁止直接创建裸 `Dio()`；API 与图片下载都通过 `DioFactory` 和当前 `NetworkConfig` 创建，并共享 `ProxyManager.recoverOnlineResourceProxy()` 的一次恢复策略。

- [ ] **Step 3: 保持失败安全**

图片下载失败不得回滚已经确认的 TMDB 标题、ID、简介和评分，不得覆盖用户锁定封面，不得删除视频或字幕。

- [ ] **Step 4: 运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\poster_service_test.dart test\network_infrastructure_test.dart test\local_poster_scraper_test.dart`

Commit: `fix: 统一 TMDB 图片下载网络配置`

### Task 5: 建立可解释的播放器色彩配置

- [ ] **Step 1: 先补充诊断，不直接调色**

Create `test/player_color_profile_test.dart`，先固定三个方案的预期属性和不支持属性的回退。播放初始化记录输入 `primaries`、`transfer`、`matrix`、`levels`、HDR 元数据、输出显示能力、硬解模式和最终色彩方案。日志只记录枚举和值，不记录媒体路径。

- [ ] **Step 2: 创建强类型方案**

Create `lib/features/player/application/player_color_profile.dart`：

```dart
enum PlayerColorProfile { automatic, hdrPassthrough, hdrToSdr }

class PlayerColorProperties {
  const PlayerColorProperties(this.values);
  final Map<String, String> values;
}
```

`automatic` 不强制覆盖源色域；`hdrPassthrough` 仅在平台报告 HDR 输出能力时启用；`hdrToSdr` 显式配置 tone mapping、目标 BT.709 和目标峰值。不得把 Anime4K 缩放着色器与色彩转换混为同一开关。

- [ ] **Step 3: 接入设置和播放器**

在播放器设置加入单选方案，默认“自动”。`PlayerController` 在媒体轨信息可用后应用属性；不支持的属性记录一次警告并回退自动，不能导致播放失败。

- [ ] **Step 4: 建立测试矩阵**

自动测试覆盖属性映射、回退和持久化；实机覆盖 SDR BT.709、HDR10 BT.2020 PQ、HLG、全/限幅色阶，以及硬解开关。PotPlayer/MPC 对比必须使用同一显示器、同一 HDR 系统状态和相同截图方法。

- [ ] **Step 5: 运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\player_color_profile_test.dart test\player_runtime_preferences_test.dart test\android_player_settings_test.dart`

Commit: `feat: 增加可解释的播放器色彩方案`

### Task 6: 安全借鉴 MPV GLSL 项目并支持资源更新

- [ ] **Step 1: 固定第三方来源**

只选择 MIT 许可且实际需要的 GLSL 文件，记录仓库、固定提交 SHA、许可证和每个文件 SHA-256。`MPV_Glsl_Running_Mode_Cache` 的 Lua 逻辑不直接执行，模式记忆由 Dart 设置实现。

- [ ] **Step 2: 定义看影音自己的签名清单**

清单包含 `version`、`minimumAppVersion`、文件相对路径、大小、SHA-256 和签名。更新只能写入看影音应用数据目录，下载到临时目录，全部校验后原子切换；失败保留上一版。

- [ ] **Step 3: 限制更新能力**

更新器只接受 GLSL 数据文件，不接受 Lua、Dart、动态库或可执行文件。公共 TV 包默认内置已验证版本，断网时继续使用内置资源。

- [ ] **Step 4: 测试篡改与回滚**

Create `test/shader_asset_installer_test.dart`。测试错误哈希、路径穿越、版本降级、不兼容最低版本、下载中断和切换失败，均必须保留旧资源。

- [ ] **Step 5: 运行测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\shader_asset_installer_test.dart test\anime4k_player_controller_test.dart`

Commit: `feat: 增加可校验的着色器资源更新`

### Task 7: 全量验证、版本迭代和交付

- [ ] **Step 1: 查询交付前安装状态**

记录已安装 Windows EXE 产品版本、Inno 卸载器和旧 MSIX 状态；读取当前 `pubspec.yaml` 后自动增加补丁版本和 build number，不硬编码假定版本。

- [ ] **Step 2: 更新发布文案**

同步 `pubspec.yaml`、`RELEASE_NOTES.md`、`lib/utils/version_history.dart` 和 `docs/android-tv-test-report.md`。文案明确 TV 返回、刮削一致性和色彩方案，不宣称未完成的海信实机项目。

- [ ] **Step 3: 运行质量门禁**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
D:\flutter\bin\cache\dart-sdk\bin\dart.exe format --output=none --set-exit-if-changed lib test tool
```

Expected: 全部退出码为 0。

- [ ] **Step 4: 构建 Windows 与两个 TV APK**

生成 Windows Release、Inno 安装器、公共 TV APK 和个人预置 TV APK；个人资源只能通过进程环境变量解密，构建后验证零残留。

- [ ] **Step 5: 海信 Android TV 实机验收**

验收顺序：播放页打开选集列表后返回一次只收回列表；再次返回离开播放器；全程保持横屏；连续播放本地和网盘同一作品得到相同 TMDB ID；HDR/SDR 样片色彩方案可切换且不会闪退。

- [ ] **Step 6: 提交本轮相关文件**

先检查 `git status --short` 和关键 diff，只暂存本轮文件，保留用户已有的本地媒体解析改动。

Commit: `fix: 完成电视播放与刮削一致性优化`

## 执行顺序与停止条件

1. 先交付 Task 1-2 的 TV 返回修复并生成内部 APK；未通过 TV 录屏验收，不进入色彩参数修改。
2. 再执行 Task 3-4；没有候选 TMDB ID 和网络阶段证据时，不通过猜测修改名称规则。
3. Task 5 先诊断后调参；没有 MediaInfo、显示器 HDR 状态和 MPC 配置时，不承诺逐像素一致。
4. Task 6 只更新数据资源，不引入远程可执行代码。
5. 三次修复尝试仍无法解释同一症状时，停止叠加补丁并重新评估播放器生命周期架构。
