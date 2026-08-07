# Android 9 TV 资源加载、网盘播放与选集状态 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox ( - [ ] ) syntax for tracking.

**Goal:** 让 Android 9 TV 优先显示缓存媒体库，以受控海报解码和低峰值网盘播放策略降低等待与闪退风险，并让两个选集界面清晰区分焦点和当前播放项。

**Architecture:** 网盘媒体库把本地快照和远程扫描拆成显式策略，Android TV 进入页面时只加载快照，手动刷新和首次预置导入仍可扫描。图片解码、Range 调度和 MPV 缓存分别增加 TV 档位；选集表现复用一个 TV 状态表面，保持现有页面层级、动画和操作不变。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、MobX、Material 3、media_kit/libmpv、dart:io HTTP Range、flutter_test、Android tvTest、Windows Inno Setup。

---

## 文件结构

- lib/pages/cloud/resources/cloud_resources_controller.dart：快照加载与自动扫描边界。
- lib/pages/cloud/resources/cloud_resources_page.dart：平台策略和脱敏播放失败记录。
- lib/features/tv/presentation/tv_image_decode_policy.dart：TV 海报目标解码尺寸。
- lib/features/tv/presentation/tv_focus_surface.dart：可配置焦点边框和缩放，默认行为不变。
- lib/features/tv/presentation/tv_episode_tile_surface.dart：普通、焦点、当前播放三态共享表面。
- lib/features/library/presentation/library_media_grid.dart、lib/pages/cloud/resources/cloud_resource_poster_wall.dart、lib/pages/cloud/resources/cloud_resource_episode_sheet.dart：图片预算和选集弹窗。
- lib/services/cloud/range/cloud_range_relay_session.dart、lib/services/cloud/range/cloud_range_relay_service.dart：TV Range 调度。
- lib/features/player/application/cloud_playback_cache_policy.dart：TV 普通/低内存 MPV 缓存。
- lib/services/cloud/cloud_playback_resolver.dart、lib/pages/player/player_controller.dart：失败替换租约清理。
- lib/pages/video/video_page.dart：播放器选集三态。
- test/：每个行为先写 RED 测试，再实现 GREEN。
- pubspec.yaml、RELEASE_NOTES.md、UPDATE_DIALOG_COPY.md、lib/utils/version_history.dart、docs/android-tv-test-report.md：版本与交付证据。

## Task 1：Android TV 网盘媒体库快照优先

**Files:**
- Modify: lib/pages/cloud/resources/cloud_resources_controller.dart
- Modify: lib/pages/cloud/resources/cloud_resources_page.dart
- Test: test/cloud_resources_controller_test.dart
- Test: test/cloud_resources_page_test.dart

- [ ] **Step 1：写控制器失败测试**

预置一个索引项，关闭自动扫描后应立即显示快照且没有远端请求；手动刷新仍会访问远端：

~~~dart
test('关闭自动扫描时先显示快照且手动刷新仍扫描', () async {
  final fixture = await _Fixture.create(
    sources: const <CloudSource>[_quarkSource],
    indexedItems: <CloudMediaIndexItem>[
      _indexedVideo(
        sourceId: _quarkSource.id,
        remoteId: 'cached-video',
        remotePath: '/影视/缓存电影.mkv',
      ),
    ],
  );
  await fixture.controller.load(startScan: false);
  expect(fixture.controller.entries.single.id, 'cached-video');
  expect(fixture.clients[_quarkSource.id]!.listed, isEmpty);
  await fixture.controller.refresh();
  expect(fixture.clients[_quarkSource.id]!.listed, isNotEmpty);
  fixture.controller.dispose();
});
~~~

给测试夹具增加强类型 indexedItems 参数并写入 CloudMediaIndexRepository，不改变生产存储格式。

- [ ] **Step 2：运行测试确认 RED**

~~~powershell
D:\flutter\bin\flutter.bat test test\cloud_resources_controller_test.dart --plain-name "关闭自动扫描时先显示快照且手动刷新仍扫描"
~~~

Expected: FAIL，load 尚不接受 startScan。

- [ ] **Step 3：实现控制器参数**

~~~dart
Future<void> load({bool startScan = true}) =>
    _loadSources(startScan: startScan);
~~~

refresh 继续扫描，reloadSourcesAndSnapshot 继续只恢复快照。

- [ ] **Step 4：写页面平台测试并实现**

给 CloudResourcesPage 增加 AppPlatformCapabilities? capabilities。测试记录控制器收到的参数，Android TV API 28 应为 false，Windows 应为 true。实现：

~~~dart
final capabilities = widget.capabilities ?? detectAppPlatform();
_controller.load(startScan: !capabilities.isAndroidTv);
~~~

- [ ] **Step 5：运行 GREEN 并提交**

~~~powershell
D:\flutter\bin\flutter.bat test test\cloud_resources_controller_test.dart test\cloud_resources_page_test.dart
git add lib/pages/cloud/resources/cloud_resources_controller.dart lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_resources_controller_test.dart test/cloud_resources_page_test.dart
git commit -m "perf(tv): 网盘媒体库优先显示缓存快照"
~~~

## Task 2：限制 Android TV 海报解码尺寸

**Files:**
- Create: lib/features/tv/presentation/tv_image_decode_policy.dart
- Modify: lib/features/library/presentation/library_media_grid.dart
- Modify: lib/pages/cloud/resources/cloud_resource_poster_wall.dart
- Modify: lib/pages/cloud/resources/cloud_resource_episode_sheet.dart
- Test: test/tv_image_decode_policy_test.dart
- Test: test/library_presentation_components_test.dart
- Test: test/cloud_resources_page_test.dart

- [ ] **Step 1：写图片预算 RED 测试**

~~~dart
test('Android TV 海报和季度缩略图有上限，Windows 不限制', () {
  final tv = AppPlatformCapabilities.android.copyWith(
    television: true,
    androidSdkInt: 28,
  );
  expect(
    TvImageDecodePolicy.poster(tv, devicePixelRatio: 2),
    const TvImageDecodeSize(width: 720, height: 1080),
  );
  expect(
    TvImageDecodePolicy.seasonThumbnail(tv, devicePixelRatio: 2),
    const TvImageDecodeSize(width: 368, height: 552),
  );
  expect(
    TvImageDecodePolicy.poster(
      AppPlatformCapabilities.windows,
      devicePixelRatio: 2,
    ),
    isNull,
  );
});
~~~

运行 test/tv_image_decode_policy_test.dart，Expected: FAIL，策略不存在。

- [ ] **Step 2：实现纯策略**

创建 TvImageDecodeSize 值类型和 TvImageDecodePolicy。TV 海报使用 360 逻辑像素、上限 720 物理像素；季度缩略图使用 184 逻辑像素、上限 368；高度为宽度的 3/2；非 TV 返回 null。

- [ ] **Step 3：接入图片**

LibraryMediaCoverFallback 增加可空 TvImageDecodeSize? decodeSize。TV 网格、网盘海报墙和季度弹窗显式传入，缓存与网络图片都设置：

~~~dart
cacheWidth: decodeSize?.width,
cacheHeight: decodeSize?.height,
filterQuality: FilterQuality.medium,
~~~

Windows 保持原图行为。

- [ ] **Step 4：运行 GREEN 并提交**

~~~powershell
D:\flutter\bin\flutter.bat test test\tv_image_decode_policy_test.dart test\library_presentation_components_test.dart test\cloud_resources_page_test.dart
git add lib/features/tv/presentation/tv_image_decode_policy.dart lib/features/library/presentation/library_media_grid.dart lib/pages/cloud/resources/cloud_resource_poster_wall.dart lib/pages/cloud/resources/cloud_resource_episode_sheet.dart test/tv_image_decode_policy_test.dart test/library_presentation_components_test.dart test/cloud_resources_page_test.dart
git commit -m "perf(tv): 限制电视海报解码尺寸"
~~~

## Task 3：Android TV 保守 Range 调度

**Files:**
- Modify: lib/services/cloud/range/cloud_range_relay_session.dart
- Modify: lib/services/cloud/range/cloud_range_relay_service.dart
- Test: test/cloud_range_relay_session_test.dart
- Test: test/cloud_range_relay_service_test.dart

- [ ] **Step 1：写 Range RED 测试**

~~~dart
test('Android TV 使用低峰值分段与单路预取', () {
  const tuning = CloudRangeRelayTuning.androidTv;
  expect(tuning.chunkSize, 2 * 1024 * 1024);
  expect(tuning.maxChunks, 16);
  expect(tuning.maxConcurrentReads, 3);
  expect(tuning.maxConcurrentPrefetch, 1);
  expect(tuning.prefetchAheadChunks, 2);
  expect(tuning.adaptivePolicy, isNull);
  expect(tuning.prefetchTailOnStart, isFalse);
});
~~~

服务测试同时验证 TV 夸克、百度都选 androidTv，普通 Android 保留原高吞吐参数。运行两个测试文件，Expected: FAIL。

- [ ] **Step 2：实现 TV 常量与选择**

给 CloudRangeRelayTuning 增加默认 true 的 prefetchTailOnStart，并增加：

~~~dart
static const androidTv = CloudRangeRelayTuning(
  chunkSize: 2 * 1024 * 1024,
  maxChunks: 16,
  maxConcurrentReads: 3,
  maxConcurrentPrefetch: 1,
  prefetchAheadChunks: 2,
  prefetchTailOnStart: false,
);
~~~

CloudRangeRelayService.tuningFor 先判断 capabilities.isAndroidTv，再走现有普通 Android 分支；Windows不变。

- [ ] **Step 3：关闭 TV 文件尾预取**

~~~dart
if (tuning.prefetchTailOnStart && metadata.totalLength > chunkSize) {
  final tailOffset =
      ((metadata.totalLength - 1) ~/ chunkSize) * chunkSize;
  _launchPrefetch(tailOffset, _prefetchGeneration);
}
~~~

增加读取范围测试，TV 启动不会请求最后一个分段。

- [ ] **Step 4：运行 GREEN 并提交**

~~~powershell
D:\flutter\bin\flutter.bat test test\cloud_range_relay_session_test.dart test\cloud_range_relay_service_test.dart test\quark_range_relay_service_test.dart
git add lib/services/cloud/range/cloud_range_relay_session.dart lib/services/cloud/range/cloud_range_relay_service.dart test/cloud_range_relay_session_test.dart test/cloud_range_relay_service_test.dart
git commit -m "perf(tv): 降低网盘分段预取峰值"
~~~

## Task 4：Android TV 播放器缓存档位

**Files:**
- Modify: lib/features/player/application/cloud_playback_cache_policy.dart
- Test: test/cloud_playback_cache_policy_test.dart

- [ ] **Step 1：写缓存 RED 测试**

TV Range 普通模式期待播放器 48 MiB、demuxer 48MiB/8MiB；低内存模式期待 32 MiB、32MiB/4MiB。普通 Android 原断言不变。运行测试，Expected: FAIL，当前仍为 128/64 MiB。

- [ ] **Step 2：实现 TV 策略**

增加 androidTvRangeRelay 和 androidTvRangeRelayLowMemory。普通档位缓存 30 秒，低内存 20 秒；stream-buffer-size 和初始等待保持现值。forTransport 只对 Android TV 的 Range Relay 使用新档位，直连及非 TV 不变。

- [ ] **Step 3：运行 GREEN 并提交**

~~~powershell
D:\flutter\bin\flutter.bat test test\cloud_playback_cache_policy_test.dart test\android_player_media_compatibility_test.dart
git add lib/features/player/application/cloud_playback_cache_policy.dart test/cloud_playback_cache_policy_test.dart
git commit -m "perf(tv): 降低电视网盘播放器缓存"
~~~

## Task 5：两个选集界面的三态焦点

**Files:**
- Modify: lib/features/tv/presentation/tv_focus_surface.dart
- Create: lib/features/tv/presentation/tv_episode_tile_surface.dart
- Modify: lib/pages/cloud/resources/cloud_resource_episode_sheet.dart
- Modify: lib/pages/cloud/resources/cloud_resources_page.dart
- Modify: lib/pages/video/video_page.dart
- Test: test/tv_episode_tile_surface_test.dart
- Test: test/cloud_resource_episode_sheet_test.dart
- Test: test/player_tv_focus_test.dart

- [ ] **Step 1：写共享表面 RED 测试**

~~~dart
testWidgets('TV 选集焦点和当前播放状态可同时辨认', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: TvEpisodeTileSurface(
        autofocus: true,
        current: true,
        onPressed: () {},
        child: const Text('第 1 集'),
      ),
    ),
  ));
  await tester.pump();
  expect(find.byKey(const ValueKey('tv-current-episode-surface')),
      findsOneWidget);
  expect(find.byKey(const ValueKey('tv-focused-surface')), findsOneWidget);
  expect(find.text('正在播放'), findsOneWidget);
});
~~~

运行测试，Expected: FAIL，共享表面不存在。

- [ ] **Step 2：扩展焦点表面并实现共享表面**

TvFocusSurface 增加默认值不变的 focusedScale = 1.04、focusBorderWidth = 2 和 FocusNode? focusNode。新 TvEpisodeTileSurface 使用 focusedScale: 1.02、focusBorderWidth: 3、reserveFocusSpace: false。当前项使用高对比 primaryContainer、加粗文字和“正在播放”，焦点边框独立叠加。

- [ ] **Step 3：接入媒体库选集**

showCloudResourceEpisodeSheet 增加 capabilities 参数。TV 模式使用 FocusTraversalGroup，第一季第一项 autofocus: true，共享表面的 onPressed 唯一触发；非 TV 保留 ListTile.onTap。新增测试验证下键移动、确认只返回一次。

- [ ] **Step 4：接入播放器选集**

把 _buildEpisodeMenuTile 的动作提取为 _selectEpisode。TV 用共享表面包住原 Material 行，current/autofocus 由当前集决定；非 TV 保留原 InkWell。保持现有控件层级、动画时长和曲线。

- [ ] **Step 5：运行 GREEN 并提交**

~~~powershell
D:\flutter\bin\flutter.bat test test\tv_focus_surface_test.dart test\tv_episode_tile_surface_test.dart test\cloud_resource_episode_sheet_test.dart test\player_tv_focus_test.dart
git add lib/features/tv/presentation/tv_focus_surface.dart lib/features/tv/presentation/tv_episode_tile_surface.dart lib/pages/cloud/resources/cloud_resource_episode_sheet.dart lib/pages/cloud/resources/cloud_resources_page.dart lib/pages/video/video_page.dart test/tv_episode_tile_surface_test.dart test/cloud_resource_episode_sheet_test.dart test/player_tv_focus_test.dart
git commit -m "fix(tv): 强化选集焦点和当前播放标识"
~~~

## Task 6：播放替换失败清理与脱敏诊断

**Files:**
- Modify: lib/services/cloud/cloud_playback_resolver.dart
- Modify: lib/pages/player/player_controller.dart
- Modify: lib/pages/cloud/resources/cloud_resources_page.dart
- Test: test/cloud_playback_cache_policy_test.dart
- Test: test/cloud_playback_resolver_test.dart
- Test: test/cloud_resources_page_test.dart

- [ ] **Step 1：写租约失败 RED 测试**

先 adopt(oldLease)，再调用 abortReplacement(candidate)，期待两个租约各关闭一次且 active 为 null。运行单测，Expected: FAIL，方法不存在。

- [ ] **Step 2：实现失败替换原子清理**

~~~dart
Future<void> abortReplacement(CloudPlaybackLease? candidate) async {
  if (candidate != null && !identical(candidate, _active)) {
    await candidate.close();
  }
  await close();
}
~~~

PlayerController._init 异常路径调用它，并用 replacementAborted 防止 finally 二次关闭候选租约；成功路径仍由 adopt 关闭旧租约。

- [ ] **Step 3：写并实现脱敏诊断**

测试 Android TV API 28 诊断包含 provider=quark、sdk=28、profile=android_tv_safe、errorType=StateError，且不包含异常正文和远程地址。实现只记录提供方类型、来源 ID、阶段、SDK、档位和异常类型。

- [ ] **Step 4：运行 GREEN 并提交**

~~~powershell
D:\flutter\bin\flutter.bat test test\cloud_playback_cache_policy_test.dart test\cloud_playback_resolver_test.dart test\cloud_resources_page_test.dart test\player_exit_lifecycle_test.dart
git add lib/services/cloud/cloud_playback_resolver.dart lib/pages/player/player_controller.dart lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_playback_cache_policy_test.dart test/cloud_playback_resolver_test.dart test/cloud_resources_page_test.dart
git commit -m "fix(tv): 清理失败播放会话并补充安全诊断"
~~~

## Task 7：版本 2.1.147 与用户文案

**Files:**
- Modify: pubspec.yaml
- Modify: RELEASE_NOTES.md
- Modify: UPDATE_DIALOG_COPY.md
- Modify: lib/utils/version_history.dart
- Modify: test/release_config_contract_test.dart
- Modify: test/version_history_current_test.dart
- Modify: test/android_tv_acceptance_contract_test.dart

- [ ] **Step 1：先改发布契约并确认 RED**

测试期待 2.1.147+20147、2.1.147.0，当前文案必须包含 Android 9、缓存快照、夸克、百度、播放稳定性、选集、遥控器焦点、不会修改或删除。运行三个发布测试，Expected: FAIL。

- [ ] **Step 2：同步版本与文案**

pubspec 设为：

~~~yaml
version: 2.1.147+20147
~~~

历史兼容 msix_version 同步为 2.1.147.0，但不生成 MSIX。RELEASE_NOTES、UPDATE_DIALOG_COPY 和 version_history 使用一致普通用户文案。

- [ ] **Step 3：运行 GREEN 并提交**

~~~powershell
D:\flutter\bin\flutter.bat test test\release_config_contract_test.dart test\version_history_current_test.dart test\android_tv_acceptance_contract_test.dart
git add pubspec.yaml RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/utils/version_history.dart test/release_config_contract_test.dart test/version_history_current_test.dart test/android_tv_acceptance_contract_test.dart
git commit -m "chore: 更新2.1.147电视优化版本"
~~~

## Task 8：全量验证、Android TV APK、Windows Inno 与最终记录

**Files:**
- Modify: docs/android-tv-test-report.md
- Verify: build/app/outputs/flutter-apk/app-tvTest-release.apk
- Verify: build/windows/x64/runner/Release/kanyingyin.exe
- Deliver: C:/Users/asus/Desktop/看影音-2.1.147-TV个人预置测试版.apk
- Deliver: C:/Users/asus/Desktop/看影音-2.1.147-测试版-安装程序.exe

- [ ] **Step 1：构建前复查安装状态**

重新查询注册表、D:\看影音\kanyingyin.exe 产品版本和 Get-AppxPackage，并记录实际状态；不能只读 pubspec。开始计划时已确认 Inno 2.1.146 已安装、主程序 2.1.146、旧 MSIX 未安装。

- [ ] **Step 2：格式化、定向测试和完整门禁**

~~~powershell
D:\flutter\bin\dart.bat format lib test
D:\flutter\bin\flutter.bat test test\cloud_resources_controller_test.dart test\cloud_resources_page_test.dart test\tv_image_decode_policy_test.dart test\cloud_range_relay_session_test.dart test\cloud_range_relay_service_test.dart test\cloud_playback_cache_policy_test.dart test\tv_episode_tile_surface_test.dart test\cloud_resource_episode_sheet_test.dart test\player_tv_focus_test.dart test\cloud_playback_resolver_test.dart
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze --no-pub
~~~

Expected: 全部测试通过，No issues found!。

- [ ] **Step 3：构建 Windows Release 和 Inno**

~~~powershell
powershell -ExecutionPolicy Bypass -File .\tool\windows\build_exe_release.ps1
~~~

Expected：Release EXE 和桌面 看影音-2.1.147-测试版-安装程序.exe 产品版本均为 2.1.147，记录大小、SHA-256 和签名状态。

- [ ] **Step 4：构建公共 TV 测试 APK**

~~~powershell
powershell -ExecutionPolicy Bypass -File .\tool\android\build_tv_test.ps1
~~~

Expected：2.1.147 (20147) 的包名、Leanback、触摸屏非必需、签名和 Full libmpv 三 ABI 验证通过。

- [ ] **Step 5：构建个人预置 TV APK**

密码只从当前 PowerShell 进程的 KYY_CONFIG_PASSWORD 读取，不得进入命令历史、日志、Git 或最终回复。确认变量已安全注入后执行单行命令：

~~~powershell
& .\tool\android\build_personal_tv.ps1 -ConfigurationPath 'C:\Users\asus\Desktop\看影音配置-20260807.kyyconfig' -MetadataPath 'C:\Users\asus\Desktop\看影音刮削资料-20260807.kyymeta'
~~~

Expected：桌面生成 看影音-2.1.147-TV个人预置测试版.apk，脚本结束后恢复禁用清单并清除临时资产、中间目录和密码变量。

- [ ] **Step 6：验证个人资源残留为零**

~~~powershell
Get-ChildItem -LiteralPath 'assets\tv_preload' -Force
$residue = Get-ChildItem -LiteralPath 'build\app\intermediates' -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('configuration.kyyconfig','metadata.kyymeta') }
if ($residue) { throw 'Android 构建目录仍有个人资源残留' }
git status --short
~~~

Expected：只保留禁用 manifest.json，不出现密码、配置、刮削资料或构建产物。

- [ ] **Step 7：更新报告并最终提交**

把实际测试数、analyze、EXE/安装器版本与哈希、APK 版本与签名、TV 策略覆盖、ADB 状态、安装状态和旧 MSIX 状态写入 docs/android-tv-test-report.md。没有海信 ADB 证据时保持 pending。

~~~powershell
git status --short
git diff --check
git diff --stat
git add docs/android-tv-test-report.md
git diff --cached --check
git commit -m "docs: 更新2.1.147电视验收记录"
~~~

- [ ] **Step 8：交付后复核**

再次核对 Release EXE、桌面安装器和 TV APK 的版本与 SHA-256；未执行安装时如实记录已安装版本；确认 git status --short 为空。

## 计划自检

- 规格覆盖：Task 1 快照优先；Task 2 海报解码；Tasks 3–4 Range 与 MPV 内存峰值；Task 5 两个选集界面；Task 6 播放失败与切集租约；Tasks 7–8 版本和双平台交付。
- 类型一致：load({bool startScan = true})、TvImageDecodeSize、CloudRangeRelayTuning.androidTv、prefetchTailOnStart、TvEpisodeTileSurface、abortReplacement 始终使用同一签名。
- 安全边界：不删除用户媒体；不记录凭据、完整远程 URL 或个人密码；不生成 MSIX；没有实机证据时保持 pending。
