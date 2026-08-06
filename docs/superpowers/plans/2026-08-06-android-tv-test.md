# Android TV 通用测试版实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有看影音 Android 代码上交付一个可侧载、可用遥控器完成主要流程的 Android TV/Google TV 测试 APK。

**Architecture:** 保留 `AppPlatformKind.android`，在 `AppPlatformCapabilities` 中增加 TV 形态能力，并在启动阶段异步探测 Android TV 特性后安装到全局能力上下文。TV 使用独立 `tvTest` flavor 和独立包名，业务层、媒体库、网盘、TMDB 和播放器复用现有实现；TV 交互通过焦点表面和遥控器策略补齐。局域网手机配置作为可选辅助功能，使用 TV 临时 HTTP 服务和一次性令牌，不引入云端中继。

**Tech Stack:** Flutter 3.41.9、Dart 3.11.5、Flutter Modular、MobX、Material Focus/Actions、Android Kotlin MethodChannel、`dart:io` `HttpServer`、现有 Full `libmpv` Android bundle、Flutter widget tests、Gradle/aapt/apksigner、ADB 实机验证。

---

### Task 1: 修复 Android 版本合同并建立 TV 构建基线

**Files:**
- Modify: `android/app/build.gradle.kts:29-68`
- Modify: `tool/android/build_signed_release.ps1:53-69,93-157`
- Modify: `test/android_release_packaging_test.dart:1-190`
- Modify: `test/version_consistency_test.dart:1-100`
- Modify: `test/release_config_contract_test.dart:1-40`
- Test: `test/android_tv_release_contract_test.dart`

- [ ] **Step 1: 写版本合同失败测试**

在 `test/android_tv_release_contract_test.dart` 增加以下断言，先确认当前工程因旧 Android 合同失败：

```dart
test('Android 版本与根工程一致且包含 tvTest flavor', () {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  expect(pubspec, contains('version: 2.1.138+20138'));
  expect(gradle, contains('versionName = androidVersionName'));
  expect(gradle, contains('versionCode = androidVersionCode'));
  expect(gradle, contains('create("tvTest")'));
});
```

- [ ] **Step 2: 运行失败测试和 Gradle 配置检查**

运行：

```text
D:\flutter\bin\flutter.bat test --no-pub test/android_tv_release_contract_test.dart
android\gradlew.bat help --offline
```

预期：新测试因不存在 `tvTest` 失败；Gradle 当前在 `android/app/build.gradle.kts` 的旧 `1.0.6+10006` 校验处失败。记录失败文本，不修改历史构建产物。

- [ ] **Step 3: 统一 Android 版本来源并保留 flavor 入口**

把 Gradle 的根版本校验改为读取根 `pubspec.yaml` 的唯一版本字段；`androidVersionName` 和 `androidVersionCode` 直接使用解析结果。增加 `tvTest` flavor 与普通 `mobile` flavor：

```kotlin
flavorDimensions += "device"
productFlavors {
    create("mobile") {
        dimension = "device"
        applicationId = "com.kanyingyin.player"
    }
    create("tvTest") {
        dimension = "device"
        applicationId = "com.kanyingyin.player.tvtest"
    }
}
```

普通 Android 构建必须明确使用 `--flavor mobile`；TV 构建使用 `--flavor tvTest`。不在两个 flavor 中复制业务依赖或签名配置。

- [ ] **Step 4: 更新 Android 签名脚本**

在 `tool/android/build_signed_release.ps1` 增加 `-Flavor` 参数，默认值为 `mobile`；根据 flavor 选择包名和输出路径。保留现有 Full bundle verifier、APK v2、AAB strict 验证，只把 TV 测试 APK 的构建入口单独抽成 `tool/android/build_tv_test.ps1`，该脚本只生成 APK，不生成 AAB，也不复制正式 Android 交付文件名。

- [ ] **Step 5: 更新合同测试并验证通过**

更新现有 Android 打包测试中的旧 `1.0.3/10003` 断言，使其读取当前统一版本和 flavor 规则；增加对 `tvTest` 包名和 `--flavor tvTest` 的断言。运行：

```text
D:\flutter\bin\flutter.bat test --no-pub test/android_tv_release_contract_test.dart test/android_release_packaging_test.dart test/version_consistency_test.dart test/release_config_contract_test.dart
android\gradlew.bat help --offline
```

预期：测试全部通过，Gradle 输出 `BUILD SUCCESSFUL`。

- [ ] **Step 6: 提交基线修复**

执行 `git status --short`，只暂存本任务涉及文件，提交：

```text
git add android/app/build.gradle.kts tool/android/build_signed_release.ps1 tool/android/build_tv_test.ps1 test/android_tv_release_contract_test.dart test/android_release_packaging_test.dart test/version_consistency_test.dart test/release_config_contract_test.dart
git commit -m "统一 Android 版本并增加 TV 构建入口"
```

### Task 2: 增加 TV flavor Manifest、Banner 和原生能力探测

**Files:**
- Create: `android/app/src/tvTest/AndroidManifest.xml`
- Create: `android/app/src/tvTest/res/drawable-xhdpi/banner.png`
- Modify: `android/app/src/main/AndroidManifest.xml:12-43`
- Modify: `android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt:25-90`
- Create: `lib/platform/android/android_device_capabilities.dart`
- Modify: `lib/platform/app_platform.dart:1-58`
- Modify: `lib/platform/app_platform_io.dart:1-12`
- Modify: `lib/main.dart:69-151`
- Modify: `lib/app_widget.dart:40-129`
- Modify: `lib/platform/app_shell_host.dart:5-23`
- Test: `test/android_tv_manifest_contract_test.dart`
- Test: `test/android_tv_capability_test.dart`
- Test: `test/android_platform_channel_test.dart`

- [ ] **Step 1: 写 Manifest 和能力探测失败测试**

在 `test/android_tv_manifest_contract_test.dart` 断言 TV 源集和合并后的主清单包含：

```dart
expect(manifest, contains('android.software.leanback'));
expect(manifest, contains('android.hardware.touchscreen'));
expect(manifest, contains('android.hardware.faketouch'));
expect(manifest, contains('android.intent.category.LEANBACK_LAUNCHER'));
expect(manifest, contains('android:banner="@drawable/banner"'));
```

在 `test/android_tv_capability_test.dart` 覆盖 `leanback=true`、`television=true`、特性查询异常和非 TV Android 回退四种输入。先运行测试，确认新能力字段和方法不存在而失败。

- [ ] **Step 2: 添加 TV flavor 清单和 Banner 资源**

在 `android/app/src/tvTest/AndroidManifest.xml` 合并主 Activity 的 `MAIN/LAUNCHER` 与 `LEANBACK_LAUNCHER`，声明横屏、非必需触摸屏/伪触摸屏，并为 application 指定 `@drawable/banner`。Banner 使用现有 `assets/images/logo/logo_rounded.png` 的品牌元素，生成 320x180 xhdpi PNG，包含“看影音 TV 测试版”文字，不改变普通 Android 的图标资源。

- [ ] **Step 3: 添加原生设备能力方法**

在 `MainActivity.kt` 的现有 `com.kanyingyin.player/android` MethodChannel 中增加 `getDeviceCapabilities`，返回仅包含设备能力的 Map：

```kotlin
mapOf(
    "sdkInt" to Build.VERSION.SDK_INT,
    "leanback" to packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK),
    "television" to packageManager.hasSystemFeature(PackageManager.FEATURE_TELEVISION),
    "touchscreen" to packageManager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN),
    "webView" to (WebView.getCurrentWebViewPackage() != null),
)
```

异常时返回明确的 `CapabilityProbeFailed`，不返回账号、序列号、MAC 地址或目录信息。

- [ ] **Step 4: 安装全局平台能力上下文**

在 `AppPlatformCapabilities` 增加 `television`、`touchscreen`、`androidSdkInt` 和 `webViewAvailable`，为 Windows 和旧测试夹具提供明确默认值。`app_platform_io.dart` 增加异步能力加载和缓存安装函数：

```dart
Future<AppPlatformCapabilities> loadAppPlatformCapabilities() async {
  final base = detectAppPlatform();
  if (!base.isAndroid) return base;
  final device = await AndroidDeviceCapabilities.load();
  final enriched = base.copyWith(
    television: device.leanback || device.television,
    touchscreen: device.touchscreen,
    androidSdkInt: device.sdkInt,
    webViewAvailable: device.webView,
  );
  installAppPlatformCapabilities(enriched);
  return enriched;
}
```

`main.dart` 在 `MediaKit.ensureInitialized()` 后等待加载；`AppWidget`、`AppShellHost`、`AndroidSystemUiSurface` 和依赖能力的页面接收同一个实例，不再在每次 build 时重新创建基础能力。

- [ ] **Step 5: 运行平台边界测试**

运行：

```text
D:\flutter\bin\flutter.bat test --no-pub test/android_tv_manifest_contract_test.dart test/android_tv_capability_test.dart test/android_platform_channel_test.dart test/platform_capabilities_test.dart test/platform_bootstrap_test.dart test/app_widget_lifecycle_test.dart test/app_shell_host_test.dart
```

预期：Windows 测试仍使用 `television=false`；Android 无法探测 TV 时正常启动；TV Map 正确映射为 `isAndroidTv=true`。

- [ ] **Step 6: 提交 TV Manifest 和能力层**

只提交本任务文件：

```text
git add android/app/src/tvTest android/app/src/main/AndroidManifest.xml android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt lib/platform/android/android_device_capabilities.dart lib/platform/app_platform.dart lib/platform/app_platform_io.dart lib/main.dart lib/app_widget.dart lib/platform/app_shell_host.dart test/android_tv_manifest_contract_test.dart test/android_tv_capability_test.dart test/android_platform_channel_test.dart test/platform_capabilities_test.dart test/platform_bootstrap_test.dart test/app_widget_lifecycle_test.dart test/app_shell_host_test.dart
git commit -m "增加 Android TV 设备能力和 TV 清单"
```

### Task 3: 建立 TV 焦点表面和宽屏布局策略

**Files:**
- Create: `lib/features/tv/presentation/tv_focus_surface.dart`
- Create: `lib/features/tv/presentation/tv_layout_policy.dart`
- Modify: `lib/features/library/presentation/immersive_media_card.dart:22-110`
- Modify: `lib/features/library/presentation/library_media_grid.dart:175-326`
- Modify: `lib/features/library/presentation/media_category_page.dart:231-260`
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart:80-145`
- Modify: `lib/pages/menu/adaptive_navigation_shell.dart:33-45,192-247`
- Modify: `lib/pages/menu/menu.dart:60-80`
- Test: `test/tv_focus_surface_test.dart`
- Test: `test/library_presentation_components_test.dart:527-616`
- Test: `test/adaptive_navigation_android_test.dart`

- [ ] **Step 1: 写焦点组件失败测试**

新增 `test/tv_focus_surface_test.dart`，验证焦点、Enter、Space 和禁用状态：

```dart
testWidgets('TV 卡片焦点显示状态且中心键触发主动作', (tester) async {
  var activated = 0;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: TvFocusSurface(
        autofocus: true,
        onPressed: () => activated++,
        child: const SizedBox(width: 320, height: 180),
      ),
    ),
  ));
  await tester.pump();
  expect(find.byKey(const ValueKey('tv-focused-surface')), findsOneWidget);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
  expect(activated, 1);
});
```

- [ ] **Step 2: 实现焦点表面**

`TvFocusSurface` 使用 `Focus`/`FocusableActionDetector` 和 `Actions`/`Shortcuts`，提供 `autofocus`、`onPressed`、`onFocusChange`、`enabled` 和 `child` 参数。焦点状态使用固定外边距、2dp 描边、1.04 倍缩放和阴影；缩放通过外层布局预留空间，不能改变 GridView 的行列尺寸。

- [ ] **Step 3: 让媒体卡同时支持 Hover 和 Focus**

在 `ImmersiveMediaCard` 保留桌面 Hover 动画，把浮层可见条件改为 `overlayMode == always || _hovered || _focused`。TV 模式下卡片必须始终有可辨识焦点边界；`onLongPress` 和 `onSecondaryTap` 不得成为主操作入口。

- [ ] **Step 4: 增加 TV 网格布局策略**

`TvLayoutPolicy` 根据 `isAndroidTv` 提供海报最大宽度、间距、上下内边距和弹窗宽度。TV 网格使用更大的卡片尺寸和至少 16dp 卡间距；普通 Android 和 Windows 保留现有布局数值。`LibraryMediaGrid`、媒体分类页和网盘海报墙统一调用同一策略，避免三套网格规则。

- [ ] **Step 5: 为导航和弹窗建立 FocusTraversalGroup**

`AdaptiveNavigationShell`、分类选择器、侧栏目的地和媒体内容分别形成焦点组。打开分类选择器或详情弹窗时将焦点移入组内，关闭后恢复触发控件；未定义焦点时不把焦点落到不可见的底栏。

- [ ] **Step 6: 运行焦点与布局测试**

运行：

```text
D:\flutter\bin\flutter.bat test --no-pub test/tv_focus_surface_test.dart test/library_presentation_components_test.dart test/adaptive_navigation_android_test.dart test/desktop_shell_test.dart
```

预期：现有桌面 Hover 测试保持通过；新增测试验证 TV Focus、Enter/Space、网格移动和弹窗焦点恢复。

- [ ] **Step 7: 提交焦点和布局改动**

```text
git add lib/features/tv lib/features/library/presentation/immersive_media_card.dart lib/features/library/presentation/library_media_grid.dart lib/features/library/presentation/media_category_page.dart lib/pages/cloud/resources/cloud_resource_poster_wall.dart lib/pages/menu/adaptive_navigation_shell.dart lib/pages/menu/menu.dart test/tv_focus_surface_test.dart test/library_presentation_components_test.dart test/adaptive_navigation_android_test.dart
git commit -m "增加 Android TV 焦点导航和宽屏布局"
```

### Task 4: 实现播放器 TV 遥控器策略

**Files:**
- Create: `lib/features/player/presentation/tv_remote_key_policy.dart`
- Modify: `lib/features/player/presentation/player_shortcut_handler.dart:109-155,176-199`
- Modify: `lib/pages/player/player_item.dart:197-243,609-625,1225-1351`
- Modify: `lib/pages/player/player_item_panel.dart:225-850`
- Modify: `lib/pages/player/smallest_player_item_panel.dart:67-420`
- Test: `test/tv_remote_key_policy_test.dart`
- Test: `test/player_shortcut_handler_test.dart`
- Test: `test/player_tv_focus_test.dart`

- [ ] **Step 1: 写遥控器映射失败测试**

新增 `test/tv_remote_key_policy_test.dart`，用表驱动方式固定输入语义：

```dart
expect(TvRemoteKeyPolicy.actionFor('Enter'), TvRemoteAction.activate);
expect(TvRemoteKeyPolicy.actionFor('Select'), TvRemoteAction.activate);
expect(TvRemoteKeyPolicy.actionFor('Media Play Pause'), TvRemoteAction.playPause);
expect(TvRemoteKeyPolicy.actionFor('Arrow Left'), TvRemoteAction.seekBackward);
expect(TvRemoteKeyPolicy.actionFor('Arrow Right'), TvRemoteAction.seekForward);
expect(TvRemoteKeyPolicy.actionFor('Escape'), TvRemoteAction.back);
```

同时覆盖 `GameButtonA`、`NumpadEnter`、空字符串和未知键，未知键必须返回 `null`。

- [ ] **Step 2: 实现 TV 按键策略**

`TvRemoteKeyPolicy` 只负责标准化 logical key label 和返回动作，不直接访问播放器状态。`PlayerItem` 在 `capabilities.isAndroidTv` 时先调用该策略；普通 Android/Windows 继续走现有用户可配置快捷键。中心键在视频表面调用 `playOrPause`，在控件获得焦点时交给当前 `Button`/`Action`。

- [ ] **Step 3: 修复播放器 Focus 拦截关系**

将播放器视频表面 Focus 与控制栏 Focus 分开：

- 控制栏显示时，`PlayerItemPanel`/`SmallestPlayerItemPanel` 外层使用 `FocusTraversalGroup`。
- 控制栏控件获得焦点后，视频表面 `onKeyEvent` 对方向键返回 `ignored`，不调用快进/音量回调。
- 控制栏隐藏时把焦点恢复到视频表面，并允许左右键执行快进/快退。
- 返回键按字幕设置、播放菜单、控制栏、播放器页面的顺序消费。

- [ ] **Step 4: 验证播放器按键和焦点**

新增 `test/player_tv_focus_test.dart`，至少验证：中心键触发暂停/播放，左右键只在控制栏隐藏时 seek，打开控制栏后方向键移动控件，关闭控制栏后恢复视频焦点。

运行：

```text
D:\flutter\bin\flutter.bat test --no-pub test/tv_remote_key_policy_test.dart test/player_shortcut_handler_test.dart test/player_tv_focus_test.dart test/player_system_capabilities_test.dart test/android_player_settings_test.dart
```

- [ ] **Step 5: 提交播放器 TV 控制**

```text
git add lib/features/player/presentation/tv_remote_key_policy.dart lib/features/player/presentation/player_shortcut_handler.dart lib/pages/player/player_item.dart lib/pages/player/player_item_panel.dart lib/pages/player/smallest_player_item_panel.dart test/tv_remote_key_policy_test.dart test/player_shortcut_handler_test.dart test/player_tv_focus_test.dart
git commit -m "增加 Android TV 播放器遥控器控制"
```

### Task 5: 增加局域网手机配置辅助功能

**Files:**
- Create: `lib/features/tv_pairing/domain/tv_pairing_models.dart`
- Create: `lib/features/tv_pairing/application/tv_pairing_controller.dart`
- Create: `lib/features/tv_pairing/data/tv_pairing_http_server.dart`
- Create: `lib/features/tv_pairing/presentation/tv_pairing_page.dart`
- Modify: `lib/pages/settings/settings_module.dart:150-230`
- Modify: `lib/pages/settings/cloud_sources_settings.dart:1-260`
- Modify: `lib/services/tmdb/tmdb_credential_manager.dart`
- Modify: `lib/repositories/cloud_source_repository.dart:59-175`
- Modify: `pubspec.yaml` and `pubspec.lock` to add `qr_flutter: ^4.1.0`
- Test: `test/tv_pairing_models_test.dart`
- Test: `test/tv_pairing_http_server_test.dart`
- Test: `test/tv_pairing_controller_test.dart`

- [ ] **Step 1: 写配对会话和令牌失败测试**

在 `test/tv_pairing_models_test.dart` 固定会话规则：令牌长度为 32 字节随机值的 URL-safe 编码，TTL 为 5 分钟，成功消费一次后不可重复使用；二维码载荷只能包含 `host`、`port`、`pairingToken` 和协议版本。

```dart
final session = TvPairingSession.issue(
  now: DateTime.utc(2026, 8, 6, 12),
);
expect(session.isExpired(DateTime.utc(2026, 8, 6, 12, 4)), isFalse);
expect(session.isExpired(DateTime.utc(2026, 8, 6, 12, 5)), isTrue);
expect(session.consume(session.token), isTrue);
expect(session.consume(session.token), isFalse);
```

- [ ] **Step 2: 定义可传输配置载荷**

`TvPairingPayload` 包含协议版本、TV 设备显示名、TMDB 凭据和 `CloudSource`/`CloudCredential` 成对数据。序列化时只允许现有强类型字段；禁止序列化 Hive 原始对象、日志、媒体索引、视频路径缓存和设备标识。载荷长度超过 256KB 时返回 `PayloadTooLarge`。

`CloudSourceRepository` 增加仅供配对使用的 `exportForPairing`/`importForPairing`，通过已有 `CloudCredentialStore` 读取和写入安全凭据；`CloudCredential.toString()` 保持脱敏，任何失败日志只记录来源 ID 和错误类型。

- [ ] **Step 3: 实现局域网 HTTP 服务**

`TvPairingHttpServer` 使用 `dart:io` `HttpServer.bind(InternetAddress.anyIPv4, 0)`，只在配对页面打开期间运行。服务端点固定为：

```text
GET  /pair?token={pairingToken}   返回手机配置页
POST /api/pair                  校验 token、JSON 版本和长度
POST /api/cancel                立即失效会话
```

服务只接受当前会话令牌、限制 `Content-Length`、拒绝非 JSON 请求、成功写入前要求 TV 遥控器确认；页面关闭、App 进入后台、TTL 到期或一次成功写入后关闭监听器。

- [ ] **Step 4: 实现二维码与 TV 配对页**

引入 `qr_flutter: ^4.1.0` 并运行离线锁定依赖恢复。该版本使用 `QrImageView` 渲染二维码；TV 页面显示局域网地址、二维码、倒计时、取消按钮和手动配置入口。二维码不包含账号密码、Refresh Token、Cookie 或 TMDB Key，只包含临时地址和配对令牌。手机页面提交前显示配置摘要，TV 端显示确认对话框。

- [ ] **Step 5: 验证配对安全边界**

运行：

```text
D:\flutter\bin\flutter.bat test --no-pub test/tv_pairing_models_test.dart test/tv_pairing_http_server_test.dart test/tv_pairing_controller_test.dart
```

测试必须覆盖错误令牌、过期令牌、重复令牌、超大载荷、非 JSON、取消、后台关闭和敏感字段不出现在日志/二维码字符串中。配对失败不得影响普通配置页和播放启动。

- [ ] **Step 6: 提交局域网配置辅助功能**

```text
git add lib/features/tv_pairing lib/pages/settings/settings_module.dart lib/pages/settings/cloud_sources_settings.dart lib/services/tmdb/tmdb_credential_manager.dart lib/repositories/cloud_source_repository.dart pubspec.yaml pubspec.lock test/tv_pairing_models_test.dart test/tv_pairing_http_server_test.dart test/tv_pairing_controller_test.dart
git commit -m "增加 Android TV 局域网配置辅助"
```

### Task 6: 补齐用户可见文案和 TV 专项测试合同

**Files:**
- Modify: `RELEASE_NOTES.md` current version section
- Modify: `lib/utils/version_history.dart` current Android/TV entry
- Create: `docs/android-tv-test-matrix.md`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/android_project_contract_test.dart`
- Modify: `test/android_manifest_contract_test.dart`
- Create: `test/android_tv_acceptance_contract_test.dart`

- [ ] **Step 1: 写验收合同失败测试**

新增 `test/android_tv_acceptance_contract_test.dart`，断言当前版本文案包含“Android TV 测试版”、遥控器导航、TV flavor 和局域网配置提示；历史版本段落不能被当前版本断言误命中。

- [ ] **Step 2: 更新面向普通用户的文案**

在当前版本段落中说明：支持 Android TV/Google TV 侧载测试、遥控器浏览和播放、同局域网手机配置可选；明确不支持 VIDAA 原生安装。不得在文案中承诺“所有安卓电视硬解码一致”或“无需同一网络”。

- [ ] **Step 3: 编写设备测试矩阵**

`docs/android-tv-test-matrix.md` 固定字段：设备型号、系统类型、API、ABI、Leanback、WebView、安装方式、遥控器、SAF、1080p、4K HEVC、字幕、音轨、网盘、息屏恢复、结果和日志路径。海信设备若无 Android API/ADB 证据，状态写为 `not_android_verified`，不能写成兼容失败或兼容通过。

- [ ] **Step 4: 运行文案和合同测试并提交**

```text
D:\flutter\bin\flutter.bat test --no-pub test/android_tv_acceptance_contract_test.dart test/version_history_current_test.dart test/android_project_contract_test.dart test/android_manifest_contract_test.dart
git add RELEASE_NOTES.md lib/utils/version_history.dart docs/android-tv-test-matrix.md test/version_history_current_test.dart test/android_project_contract_test.dart test/android_manifest_contract_test.dart test/android_tv_acceptance_contract_test.dart
git commit -m "补充 Android TV 测试版文案和验收矩阵"
```

### Task 7: 完成全量静态检查、TV APK 构建和包验证

**Files:**
- Modify: `tool/android/build_tv_test.ps1` to finalize the TV APK verification command
- Test: all existing `test/**/*.dart`
- Artifact: `build/app/outputs/flutter-apk/tvTest/release/app-tvTest-release.apk`

- [ ] **Step 1: 恢复锁定依赖并确认 Full bundle**

运行：

```text
D:\flutter\bin\flutter.bat pub get --offline --enforce-lockfile
Get-Content .dart_tool/package_config.json -Encoding UTF8 | Select-String 'media_kit_libs_android_video_full'
```

预期：`package_config.json` 指向 `third_party/media_kit_libs_android_video_full`，不能使用默认 Android media kit 库。

- [ ] **Step 2: 运行完整测试和分析**

```text
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze
```

预期：测试全部通过，analyzer 无错误；任何失败先按失败文件修复，不能以只运行 TV 测试替代完整回归。

- [ ] **Step 3: 构建 TV Release APK**

```text
D:\flutter\bin\flutter.bat build apk --release --flavor tvTest --no-pub --target-platform android-arm,android-arm64,android-x64
```

预期：生成 TV flavor APK，包名为 `com.kanyingyin.player.tvtest`，版本为当前 Windows 测试版本，包含三种 ABI 的 Full `libmpv.so`。

- [ ] **Step 4: 独立验证 APK**

用最新 Android build-tools 执行：

```text
aapt dump badging build\app\outputs\flutter-apk\tvTest\release\app-tvTest-release.apk
apksigner verify --verbose --print-certs build\app\outputs\flutter-apk\tvTest\release\app-tvTest-release.apk
D:\KanYingYin\tool\android\verify_full_media_bundle.ps1 -PackagePath build\app\outputs\flutter-apk\tvTest\release\app-tvTest-release.apk -PackageKind apk
```

逐项记录包名、版本、`LEANBACK_LAUNCHER`、Banner、触摸屏声明、签名证书、ABI 和 `libmpv` 校验结果。

- [ ] **Step 5: 复制桌面测试包并保留校验记录**

将最终 APK 复制到当前用户桌面，文件名为 `看影音-2.1.138-TV测试版.apk`（版本号以实际当前版本替换）。同时保存构建日志、aapt badging、签名和 Full bundle 验证结果到 `tool/android/private-output/`，该目录保持被 `.gitignore` 排除。

### Task 8: 实机安装和 Android TV 兼容性验收

**Files:**
- Update: `docs/android-tv-test-matrix.md`
- Update: `docs/android-tv-test-report.md`
- No source changes unless a documented failing case identifies a code defect

- [ ] **Step 1: 识别设备系统和 ABI**

对每台设备执行：

```text
\$tvIp = Read-Host '输入电视局域网 IP'
adb connect "\$tvIp`:5555"
adb shell getprop ro.build.version.sdk
adb shell getprop ro.product.cpu.abi
adb shell pm list features | findstr /i "leanback television touchscreen"
adb shell dumpsys webviewupdate
```

海信设备若无法通过 ADB 获取 Android API 和 ABI，先在电视设置中确认是否存在 Android 版本及未知来源安装入口；没有证据时标记 `not_android_verified`。

- [ ] **Step 2: 安装并验证冷启动**

```text
adb install -r 看影音-2.1.138-TV测试版.apk
adb shell monkey -p com.kanyingyin.player.tvtest 1
```

只使用遥控器完成首次启动、返回和退出；记录是否出现在 TV launcher、是否出现黑屏、横屏错误或系统 WebView 缺失。

- [ ] **Step 3: 验证媒体流程**

按矩阵逐项验证本地目录、每种个人网盘、TMDB 缓存/无 Key、电视剧季度/集数、外挂/内嵌字幕、音轨、4K H.264/HEVC、硬解和长时间播放。每一项记录设备、文件样本、结果和日志路径。

- [ ] **Step 4: 验证局域网配对和故障回退**

手机与 TV 连接同一普通家庭 Wi-Fi 时完成一次配对；再在访客网络或开启 AP 隔离的条件下验证失败提示和手动配置回退。确认一次性令牌过期后不能重复写入，敏感字段不出现在 TV/手机 URL、日志和二维码截图中。

- [ ] **Step 5: 形成兼容结论**

只有标准 Android TV 设备完成纯遥控器主流程、真实视频播放和恢复测试，才写“Android TV 测试通过”。海信 VIDAA 或无法侧载 APK 的设备写“系统不属于 Android TV APK 支持范围”，不能通过修改 Flutter Android 平台判断强行归类。

### Task 9: 交付前总验收和最终提交

**Files:**
- Review: all files changed by Tasks 1-8
- Update: `RELEASE_NOTES.md`, `lib/utils/version_history.dart`, `docs/android-tv-test-report.md`

- [ ] **Step 1: 检查工作区和关键 diff**

```text
git status --short
git diff --stat
git diff -- android/app/build.gradle.kts android/app/src/tvTest lib/platform lib/features/tv lib/features/player lib/features/library
```

只保留 TV 方案相关改动；不回退用户已有的无关修改。

- [ ] **Step 2: 运行最终验证**

```text
D:\flutter\bin\flutter.bat pub get --offline --enforce-lockfile
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze
D:\flutter\bin\flutter.bat build apk --release --flavor tvTest --no-pub --target-platform android-arm,android-arm64,android-x64
```

再次执行 APK 签名、Manifest、ABI 和 Full `libmpv` 独立验证；构建成功但实机未通过时，交付结论必须写为“可安装测试包，实机验收未完成”。

- [ ] **Step 3: 提交最终代码**

确认版本、文案、测试、构建记录和实机矩阵均已更新后：

```text
逐项执行 `git add`，只加入前述 Tasks 1-8 的实际修改路径；执行前用 `git status --short` 和 `git diff --stat` 核对，禁止使用 `git add .`。
git commit -m "交付 Android TV 通用测试版"
```

提交前不得把 APK、AAB、密钥、账号、Token 或 `tool/android/private-output/` 加入 Git。
