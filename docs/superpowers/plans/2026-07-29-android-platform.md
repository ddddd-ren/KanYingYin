# 看影音 Android Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保留 Windows 正式版全部现有行为的前提下，为看影音增加完整、可签名交付的 Android 平台工程，支持 SAF 本地媒体、个人网盘、TMDB、播放、字幕、后台音频和系统画中画。

**Architecture:** 继续使用同一套 Flutter Modular、MobX 和领域服务，通过强类型平台能力与媒体位置接口隔离 Windows 文件路径和 Android 文档 URI。Windows 桌面外壳继续封装 `window_manager`/`tray_manager`；Android 由 Kotlin `MainActivity` 提供 SAF、画中画、MediaStore 截图和外部播放器平台通道。

**Tech Stack:** Flutter 3.41.9、Dart 3.11.5、Kotlin、Android API 24/36、Flutter Modular、MobX、Hive CE、media_kit、audio_service、flutter_inappwebview、PowerShell 发布脚本。

**Design spec:** `docs/superpowers/specs/2026-07-29-android-platform-design.md`

**Authoritative setup references:**

- Flutter Android 环境配置：https://docs.flutter.dev/platform-integration/android/setup
- Android `sdkmanager`：https://developer.android.com/tools/sdkmanager
- Android 命令行构建和签名：https://developer.android.com/build/building-cmdline

---

## 文件结构与责任

计划新增或重点修改的文件按责任分组：

- `lib/platform/app_platform.dart`：纯 Dart 平台类型、能力和播放器策略，不调用插件。
- `lib/platform/app_platform_io.dart`：唯一使用 `Platform.isWindows`/`Platform.isAndroid` 的运行时选择器。
- `lib/platform/app_bootstrap.dart`：应用启动阶段的平台初始化端口。
- `lib/platform/android/android_platform_channel.dart`：Android MethodChannel 的强类型 Dart 客户端。
- `lib/platform/android/android_document_provider.dart`：SAF 目录树选择、枚举、授权验证和小文件读取。
- `lib/platform/android/android_system_service.dart`：沉浸模式、亮度、画中画、截图和外部 Intent。
- `lib/modules/local/media_location.dart`：Windows 路径与 Android URI 的强类型值对象。
- `lib/services/local_media_entry_provider.dart`：文件系统和 SAF 的统一目录项接口。
- `lib/services/file_system_media_entry_provider.dart`：现有 Windows 文件系统实现。
- `lib/services/android_media_entry_provider.dart`：Android SAF 实现。
- `android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt`：SAF、PIP、MediaStore 与 Intent 原生实现。
- `tool/android/build_signed_release.ps1`：不保存密码的签名 APK/AAB 构建、验证和桌面交付。
- `test/platform_*`、`test/media_location_test.dart`、`test/android_*`：平台边界与 Android 契约测试。

生成的 Android Gradle/资源文件由 Flutter 3.41.9 模板建立，再通过显式差异修改；不覆盖现有 `lib/`、`assets/` 或 `windows/`。

---

### Task 1: 建立 Android 工具链与平台工程基线

**Files:**

- Create: `android/**`（由 Flutter 模板生成）
- Modify: `.metadata`
- Modify: `.gitignore`
- Test: `test/android_project_contract_test.dart`

- [ ] **Step 1: 安装固定的 Android 命令行工具**

从 Android 官方下载 `commandlinetools-win-15859902_latest.zip`，先验证 SHA-256 为 `90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a`，再解压到 `C:\Users\asus\AppData\Local\Android\Sdk\cmdline-tools\latest`。使用 PowerShell：

```powershell
chcp 65001 > $null
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$archive = Join-Path $env:TEMP 'commandlinetools-win-15859902_latest.zip'
Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip' -OutFile $archive
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
if ($hash -ne '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a') { throw "Android 工具校验失败: $hash" }
$extract = Join-Path $env:TEMP 'kanyingyin-android-tools'
if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
Expand-Archive -LiteralPath $archive -DestinationPath $extract
New-Item -ItemType Directory -Force -Path (Join-Path $sdk 'cmdline-tools\latest') | Out-Null
Copy-Item -Path (Join-Path $extract 'cmdline-tools\*') -Destination (Join-Path $sdk 'cmdline-tools\latest') -Recurse -Force
```

Expected: `Test-Path "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat"` 返回 `True`。

- [ ] **Step 2: 安装 API 36 构建组件并接受许可证**

```powershell
chcp 65001 > $null
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$manager = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
1..20 | ForEach-Object { 'y' } | & $manager --sdk_root=$sdk --licenses
& $manager --sdk_root=$sdk 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'cmdline-tools;latest'
& 'D:\flutter\bin\flutter.bat' config --android-sdk $sdk
& 'D:\flutter\bin\flutter.bat' doctor -v
```

Expected: `Android toolchain - develop for Android devices` 为通过状态；Flutter 仍解析自 `D:\flutter`。

- [ ] **Step 3: 写 Android 工程契约失败测试**

Create `test/android_project_contract_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 平台工程使用看影音身份和 API 24/36', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(gradle, contains('namespace = "com.kanyingyin.player"'));
    expect(gradle, contains('applicationId = "com.kanyingyin.player"'));
    expect(gradle, contains('minSdk = 24'));
    expect(manifest, contains('android:label="看影音"'));
    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
  });
}
```

- [ ] **Step 4: 运行测试并确认因 Android 工程缺失而失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\android_project_contract_test.dart
```

Expected: FAIL，错误指出 `android/app/build.gradle.kts` 不存在。

- [ ] **Step 5: 用固定 Flutter SDK 生成 Android 模板**

Run:

```powershell
D:\flutter\bin\flutter.bat create --platforms=android --org com.kanyingyin .
```

生成后只保留 Android 平台和 `.metadata` 的必要更新；确认 `pubspec.yaml`、`lib/`、`assets/`、`windows/` 没有被模板覆盖。将 `android/app/build.gradle.kts` 中 namespace/applicationId 改为 `com.kanyingyin.player`，将 MainActivity 包路径移动到 `android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt`。

- [ ] **Step 6: 固定 Android SDK 基线**

Modify `android/app/build.gradle.kts`:

```kotlin
android {
    namespace = "com.kanyingyin.player"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.kanyingyin.player"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
}
```

Modify `android/app/src/main/AndroidManifest.xml` 的 application label：

```xml
<application
    android:label="看影音"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher">
```

- [ ] **Step 7: 运行契约测试和首次 Debug 构建**

Run:

```powershell
D:\flutter\bin\flutter.bat pub get
D:\flutter\bin\flutter.bat test --no-pub test\android_project_contract_test.dart
D:\flutter\bin\flutter.bat build apk --debug --no-pub
```

Expected: 契约测试 PASS；Debug 构建若失败，只允许暴露当前 Windows 专属 Dart 启动问题，不允许仍是 SDK 或平台目录缺失。

- [ ] **Step 8: 提交平台基线**

```powershell
git add .metadata .gitignore android test/android_project_contract_test.dart
git commit -m "构建：建立安卓平台工程"
```

---

### Task 2: 建立强类型平台能力与启动隔离

**Files:**

- Create: `lib/platform/app_platform.dart`
- Create: `lib/platform/app_platform_io.dart`
- Create: `lib/platform/app_bootstrap.dart`
- Modify: `lib/main.dart`
- Modify: `lib/utils/utils.dart`
- Test: `test/platform_capabilities_test.dart`
- Test: `test/platform_bootstrap_test.dart`

- [ ] **Step 1: 写平台能力失败测试**

Create `test/platform_capabilities_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  test('Windows 和 Android 能力边界互不混淆', () {
    expect(AppPlatformCapabilities.windows.desktopShell, isTrue);
    expect(AppPlatformCapabilities.windows.systemPictureInPicture, isFalse);
    expect(AppPlatformCapabilities.android.desktopShell, isFalse);
    expect(AppPlatformCapabilities.android.systemPictureInPicture, isTrue);
    expect(AppPlatformCapabilities.android.storageAccessFramework, isTrue);
  });

  test('Android 不暴露 Windows 解码器', () {
    expect(AppPlatformCapabilities.android.hardwareDecoders, ['auto', 'no']);
    expect(
      AppPlatformCapabilities.windows.hardwareDecoders,
      contains('d3d11va-copy'),
    );
  });
}
```

- [ ] **Step 2: 运行并确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\platform_capabilities_test.dart`

Expected: FAIL，`app_platform.dart` 不存在。

- [ ] **Step 3: 实现纯 Dart 平台类型**

Create `lib/platform/app_platform.dart`:

```dart
enum AppPlatformKind { windows, android }

class AppPlatformCapabilities {
  const AppPlatformCapabilities({
    required this.kind,
    required this.desktopShell,
    required this.storageAccessFramework,
    required this.systemPictureInPicture,
    required this.windowBrightness,
    required this.hardwareDecoders,
    required this.videoRenderers,
  });

  static const windows = AppPlatformCapabilities(
    kind: AppPlatformKind.windows,
    desktopShell: true,
    storageAccessFramework: false,
    systemPictureInPicture: false,
    windowBrightness: false,
    hardwareDecoders: <String>[
      'auto', 'no', 'auto-safe', 'auto-copy', 'd3d11va-copy',
      'd3d11va', 'dxva2-copy', 'dxva2',
    ],
    videoRenderers: <String>[],
  );

  static const android = AppPlatformCapabilities(
    kind: AppPlatformKind.android,
    desktopShell: false,
    storageAccessFramework: true,
    systemPictureInPicture: true,
    windowBrightness: true,
    hardwareDecoders: <String>['auto', 'no'],
    videoRenderers: <String>['auto', 'gpu', 'gpu-next', 'mediacodec_embed'],
  );

  final AppPlatformKind kind;
  final bool desktopShell;
  final bool storageAccessFramework;
  final bool systemPictureInPicture;
  final bool windowBrightness;
  final List<String> hardwareDecoders;
  final List<String> videoRenderers;

  bool get isWindows => kind == AppPlatformKind.windows;
  bool get isAndroid => kind == AppPlatformKind.android;
  bool supportsAnime4k(String renderer) =>
      isWindows || renderer == 'gpu' || renderer == 'gpu-next';
}
```

- [ ] **Step 4: 实现唯一运行时选择器**

Create `lib/platform/app_platform_io.dart`:

```dart
import 'dart:io';

import 'package:kanyingyin/platform/app_platform.dart';

AppPlatformCapabilities detectAppPlatform() {
  if (Platform.isWindows) return AppPlatformCapabilities.windows;
  if (Platform.isAndroid) return AppPlatformCapabilities.android;
  throw UnsupportedError('看影音当前只支持 Windows 和 Android');
}
```

- [ ] **Step 5: 写启动端口失败测试**

Create `test/platform_bootstrap_test.dart`，使用记录调用次数的 fake，验证 Android 初始化不会调用桌面窗口方法：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/app_bootstrap.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  test('Android 启动跳过桌面窗口初始化', () async {
    final port = _FakeDesktopWindowPort();
    await AppBootstrap(
      capabilities: AppPlatformCapabilities.android,
      desktopWindow: port,
    ).prepareWindow(showWindowButtons: false, lowResolution: false);
    expect(port.initializeCalls, 0);
  });
}

class _FakeDesktopWindowPort implements DesktopWindowPort {
  int initializeCalls = 0;

  @override
  Future<void> initialize({
    required bool showWindowButtons,
    required bool lowResolution,
  }) async {
    initializeCalls++;
  }

  @override
  Future<void> showStorageFailureWindow() async {
    initializeCalls++;
  }
}
```

- [ ] **Step 6: 实现启动端口并迁移 main**

Create `lib/platform/app_bootstrap.dart`:

```dart
import 'package:kanyingyin/platform/app_platform.dart';

abstract interface class DesktopWindowPort {
  Future<void> initialize({
    required bool showWindowButtons,
    required bool lowResolution,
  });

  Future<void> showStorageFailureWindow();
}

class AppBootstrap {
  const AppBootstrap({
    required this.capabilities,
    required this.desktopWindow,
  });

  final AppPlatformCapabilities capabilities;
  final DesktopWindowPort desktopWindow;

  Future<void> prepareWindow({
    required bool showWindowButtons,
    required bool lowResolution,
  }) {
    if (!capabilities.desktopShell) return Future<void>.value();
    return desktopWindow.initialize(
      showWindowButtons: showWindowButtons,
      lowResolution: lowResolution,
    );
  }

  Future<void> prepareStorageFailureWindow() {
    if (!capabilities.desktopShell) return Future<void>.value();
    return desktopWindow.showStorageFailureWindow();
  }
}
```

在 `lib/main.dart` 中构造 `detectAppPlatform()`，将两段无条件 `windowManager.ensureInitialized()` 迁移到 `DesktopWindowPort` 的 Windows 实现；Android 直接 `runApp`。`main.dart` 不再 import `window_manager`。

- [ ] **Step 7: 统一 Utils 平台判断**

将 `Utils.isDesktop/isTablet/isCompact` 改为依赖 `AppPlatformCapabilities` 与 MediaQuery 宽度；生产调用不得再假设所有设备都是桌面。

```dart
static bool isDesktop() => detectAppPlatform().desktopShell;
static bool isTablet() => !isDesktop() &&
    WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.shortestSide /
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio >= 600;
static bool isCompact() => !isDesktop() && !isTablet();
```

- [ ] **Step 8: 验证并提交**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\platform_capabilities_test.dart test\platform_bootstrap_test.dart test\app_widget_lifecycle_test.dart
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: 全部 PASS，analyze 无错误。

```powershell
git add lib/platform lib/main.dart lib/utils/utils.dart test/platform_capabilities_test.dart test/platform_bootstrap_test.dart
git commit -m "重构：隔离安卓与桌面启动能力"
```

---

### Task 3: 隔离 Windows 应用外壳并提供 Android 安全外壳

**Files:**

- Create: `lib/platform/app_shell_host.dart`
- Create: `lib/platform/windows/windows_app_shell_host.dart`
- Modify: `lib/app_widget.dart`
- Modify: `lib/services/windows_app_shell_service.dart`
- Modify: `lib/pages/settings/theme_settings_page.dart`
- Modify: `lib/utils/diagnostic_log_exporter.dart`
- Modify: `lib/utils/windows_shortcut.dart`
- Modify: `lib/services/cloud/cloud_cache_directories.dart`
- Test: `test/app_shell_host_test.dart`
- Test: `test/app_widget_lifecycle_test.dart`

- [ ] **Step 1: 写 AppShellHost 失败组件测试**

Create `test/app_shell_host_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_shell_host.dart';

void main() {
  testWidgets('Android 外壳只构建子页面', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AppShellHost(
        capabilities: AppPlatformCapabilities.android,
        child: Text('内容'),
      ),
    ));
    expect(find.text('内容'), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-app-shell')), findsNothing);
  });
}
```

- [ ] **Step 2: 运行并确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\app_shell_host_test.dart`

Expected: FAIL，`AppShellHost` 不存在。

- [ ] **Step 3: 创建共享外壳选择器**

Create `lib/platform/app_shell_host.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/windows/windows_app_shell_host.dart';

class AppShellHost extends StatelessWidget {
  const AppShellHost({
    super.key,
    required this.capabilities,
    required this.child,
  });

  final AppPlatformCapabilities capabilities;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!capabilities.desktopShell) return child;
    return WindowsAppShellHost(
      key: const ValueKey('desktop-app-shell'),
      child: child,
    );
  }
}
```

- [ ] **Step 4: 移动桌面生命周期而不改变行为**

将 `AppWidget` 中的 `TrayListener`、`WindowListener`、关闭弹窗、托盘菜单与 `WindowsAppShellService` 生命周期移动到 `lib/platform/windows/windows_app_shell_host.dart`。保留原有 case 分支、弹窗文字、动画和 shutdown coordinator 调用。`AppWidget` 只负责主题、MaterialApp.router 和 `AppShellHost`。

同时把外观页的标题栏亮度、诊断日志目录打开、Windows 快捷方式和 Windows 路径大小写规范化改为通过能力/端口调用；Android 设置页只保留“导出诊断日志”，不显示“打开日志目录”。除 `app_platform_io.dart` 外不再直接写 `Platform.isWindows` 或 `Platform.isAndroid`。

- [ ] **Step 5: 调整现有测试归属**

把 `app_widget_lifecycle_test.dart` 中纯 Windows shell 测试的 import 改为 `windows_app_shell_host.dart`；保留所有并发初始化、detach/dispose 和关闭流程断言，不删除测试来换取通过。

- [ ] **Step 6: 验证 Windows 和 Android 外壳**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\app_shell_host_test.dart test\app_widget_lifecycle_test.dart test\app_shutdown_coordinator_test.dart
D:\flutter\bin\flutter.bat build apk --debug --no-pub
D:\flutter\bin\flutter.bat build windows --debug --no-pub
```

Expected: 测试与两个平台 Debug 构建通过。

- [ ] **Step 7: 提交**

```powershell
git add lib/app_widget.dart lib/platform/app_shell_host.dart lib/platform/windows/windows_app_shell_host.dart lib/services/windows_app_shell_service.dart lib/pages/settings/theme_settings_page.dart lib/utils/diagnostic_log_exporter.dart lib/utils/windows_shortcut.dart lib/services/cloud/cloud_cache_directories.dart test/app_shell_host_test.dart test/app_widget_lifecycle_test.dart
git commit -m "重构：拆分桌面应用外壳"
```

---

### Task 4: 实现 Android 原生系统通道

**Files:**

- Create: `lib/platform/android/android_platform_channel.dart`
- Create: `lib/platform/android/android_system_service.dart`
- Modify: `android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Test: `test/android_platform_channel_test.dart`
- Test: `test/android_manifest_contract_test.dart`

- [ ] **Step 1: 写 Dart 通道失败测试**

Create `test/android_platform_channel_test.dart`，对测试 MethodChannel 注入 mock handler，验证方法和参数：

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/android/android_platform_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.kanyingyin.player/android.test');

  tearDown(() => TestDefaultBinaryMessengerBinding.instance
      .defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('进入画中画传递合法宽高比', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });
    final client = AndroidPlatformChannel(channel: channel);
    expect(await client.enterPictureInPicture(width: 1920, height: 1080), isTrue);
    expect(received!.method, 'enterPictureInPicture');
    expect(received!.arguments, {'width': 1920, 'height': 1080});
  });
}
```

- [ ] **Step 2: 运行并确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\android_platform_channel_test.dart`

Expected: FAIL，客户端类型不存在。

- [ ] **Step 3: 实现强类型 Dart 客户端**

Create `lib/platform/android/android_platform_channel.dart`，公开固定通道 `com.kanyingyin.player/android`，实现：

```dart
class AndroidPlatformChannel {
  const AndroidPlatformChannel({
    MethodChannel channel = const MethodChannel('com.kanyingyin.player/android'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<bool> enterPictureInPicture({required int width, required int height}) =>
      _invokeBool('enterPictureInPicture', <String, int>{
        'width': width > 0 ? width : 16,
        'height': height > 0 ? height : 9,
      });

  Future<void> setImmersive(bool enabled) =>
      _channel.invokeMethod<void>('setImmersive', enabled);

  Future<void> setBrightness(double value) =>
      _channel.invokeMethod<void>('setBrightness', value.clamp(0.01, 1.0));

  Future<String?> saveScreenshot(Uint8List bytes) =>
      _channel.invokeMethod<String>('saveScreenshot', bytes);

  Future<bool> openWithMime(String uri, String mimeType) =>
      _invokeBool('openWithMime', <String, String>{'url': uri, 'mimeType': mimeType});

  Future<bool> _invokeBool(String method, [Object? arguments]) async =>
      await _channel.invokeMethod<bool>(method, arguments) ?? false;
}
```

- [ ] **Step 4: 写 Android 清单失败测试**

Create `test/android_manifest_contract_test.dart`，断言 `INTERNET`、`WAKE_LOCK`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PLAYBACK`、`POST_NOTIFICATIONS`、仅限 API 28 及以下的 `WRITE_EXTERNAL_STORAGE`、`supportsPictureInPicture="true"`、audio_service service/receiver 存在，同时断言不含 `MANAGE_EXTERNAL_STORAGE` 和 `READ_MEDIA_VIDEO`。

- [ ] **Step 5: 实现 Kotlin 系统能力**

`MainActivity` 继承 `AudioServiceActivity`，在 `configureFlutterEngine` 注册 MethodChannel。实现 `enterPictureInPicture`、`setImmersive`、`setBrightness`、`saveScreenshot` 和 `openWithMime`。核心入口结构：

```kotlin
package com.kanyingyin.player

import android.app.PictureInPictureParams
import android.content.Intent
import android.os.Build
import android.util.Rational
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val channelName = "com.kanyingyin.player/android"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPictureInPicture" -> enterPictureInPicture(call, result)
                    "setImmersive" -> setImmersive(call.arguments == true, result)
                    "setBrightness" -> setBrightness(call.arguments, result)
                    "saveScreenshot" -> saveScreenshot(call.arguments, result)
                    "openWithMime" -> openWithMime(call.arguments, result)
                    else -> result.notImplemented()
                }
            }
    }
}
```

截图使用 MediaStore `Pictures/看影音`；API 29 及以上直接使用 scoped MediaStore，API 24–28 在取得 `WRITE_EXTERNAL_STORAGE` 运行时授权后写入；外部 Intent 使用 `ACTION_VIEW`、`FLAG_GRANT_READ_URI_PERMISSION` 和传入 MIME，不附加 Referer 或 Cookie。画中画在 API 26 以下固定返回 `false`，不得调用不存在的系统 API。

- [ ] **Step 6: 配置 AndroidManifest**

加入权限、PIP 和 audio_service 组件；Activity 设置 `supportsPictureInPicture="true"`，service 设置 `foregroundServiceType="mediaPlayback"`，receiver 只接收 `MEDIA_BUTTON`。不加入任何全盘存储权限。

- [ ] **Step 7: 验证并提交**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\android_platform_channel_test.dart test\android_manifest_contract_test.dart test\external_player_test.dart
D:\flutter\bin\flutter.bat build apk --debug --no-pub
```

Expected: 测试和 APK Debug 构建通过。

```powershell
git add android/app/src/main lib/platform/android test/android_platform_channel_test.dart test/android_manifest_contract_test.dart
git commit -m "功能：接入安卓系统播放能力"
```

---

### Task 5: 恢复移动端布局、安全区和系统返回行为

**Files:**

- Modify: `lib/pages/menu/adaptive_navigation_shell.dart`
- Modify: `lib/bean/appbar/sys_app_bar.dart`
- Modify: `lib/pages/index_page.dart`
- Modify: `lib/pages/video/video_page.dart`
- Modify: `lib/pages/player/player_item.dart`
- Create: `lib/features/player/application/player_back_policy.dart`
- Test: `test/adaptive_navigation_android_test.dart`
- Test: `test/player_back_policy_test.dart`

- [ ] **Step 1: 写窄屏导航失败测试**

扩展 `test/desktop_shell_test.dart` 或创建 `test/adaptive_navigation_android_test.dart`，在宽度 390 下断言不显示桌面侧栏和窗口按钮，显示移动端 `NavigationBar`，内容位于 `SafeArea` 内。

```dart
expect(find.byKey(const ValueKey('desktop-sidebar-expanded')), findsNothing);
expect(find.byType(NavigationBar), findsOneWidget);
expect(find.byKey(const ValueKey('mobile-safe-content')), findsOneWidget);
```

- [ ] **Step 2: 写返回顺序失败测试**

Create `test/player_back_policy_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/player_back_policy.dart';

void main() {
  test('返回键按浮层、全屏、播放器顺序消费', () {
    expect(PlayerBackPolicy.decide(overlayVisible: true, fullscreen: true),
        PlayerBackAction.closeOverlay);
    expect(PlayerBackPolicy.decide(overlayVisible: false, fullscreen: true),
        PlayerBackAction.exitFullscreen);
    expect(PlayerBackPolicy.decide(overlayVisible: false, fullscreen: false),
        PlayerBackAction.leavePlayer);
  });
}
```

- [ ] **Step 3: 实现纯策略并接入 PopScope**

Create `player_back_policy.dart`:

```dart
enum PlayerBackAction { closeOverlay, exitFullscreen, leavePlayer }

class PlayerBackPolicy {
  static PlayerBackAction decide({
    required bool overlayVisible,
    required bool fullscreen,
  }) {
    if (overlayVisible) return PlayerBackAction.closeOverlay;
    if (fullscreen) return PlayerBackAction.exitFullscreen;
    return PlayerBackAction.leavePlayer;
  }
}
```

`VideoPage` 的 PopScope 使用该策略；Android 离开播放器前等待现有资源释放，Windows 原有 PIP 分支不变。

- [ ] **Step 4: 实现自适应导航和标题栏能力判断**

以现有断点为基础，窄屏使用 `NavigationBar`，宽屏继续现有侧栏。`SysAppBar` 只在 `capabilities.desktopShell` 时构建 `DragToMoveArea` 与 `DesktopWindowControls`。

- [ ] **Step 5: 接入沉浸模式与方向恢复**

Android 进入播放器全屏时调用 `AndroidSystemService.setImmersive(true)`，退出时调用 `false`；仅视频播放页允许横屏，dispose 时恢复 `DeviceOrientation.portraitUp`。Windows 继续调用原有窗口全屏实现。

- [ ] **Step 6: 验证并提交**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\desktop_shell_test.dart test\adaptive_navigation_android_test.dart test\player_back_policy_test.dart test\player_exit_lifecycle_test.dart
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: PASS，无分析错误。

```powershell
git add lib/pages/menu/adaptive_navigation_shell.dart lib/bean/appbar/sys_app_bar.dart lib/pages/index_page.dart lib/pages/video/video_page.dart lib/pages/player/player_item.dart lib/features/player/application/player_back_policy.dart test/adaptive_navigation_android_test.dart test/player_back_policy_test.dart test/desktop_shell_test.dart
git commit -m "功能：适配安卓导航与返回交互"
```

---

### Task 6: 平台化播放器解码器、渲染器与 Anime4K

**Files:**

- Create: `lib/features/player/application/player_platform_policy.dart`
- Modify: `lib/utils/constants.dart`
- Modify: `lib/features/settings/application/typed_settings.dart`
- Create: `lib/pages/settings/renderer_settings.dart`
- Modify: `lib/pages/settings/decoder_settings.dart`
- Modify: `lib/pages/settings/player_settings.dart`
- Modify: `lib/pages/settings/settings_module.dart`
- Modify: `lib/features/player/application/player_runtime_preferences.dart`
- Modify: `lib/pages/player/player_controller.dart`
- Modify: `lib/pages/settings/super_resolution_settings.dart`
- Test: `test/player_platform_policy_test.dart`
- Test: `test/android_player_settings_test.dart`

- [ ] **Step 1: 写平台播放器策略失败测试**

Create `test/player_platform_policy_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/player_platform_policy.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  test('Android 使用独立解码器和渲染器设置', () {
    final policy = PlayerPlatformPolicy(AppPlatformCapabilities.android);
    expect(policy.normalizeDecoder('d3d11va-copy'), 'auto');
    expect(policy.normalizeRenderer('mediacodec_embed'), 'mediacodec_embed');
    expect(policy.supportsAnime4k('mediacodec_embed'), isFalse);
    expect(policy.supportsAnime4k('gpu'), isTrue);
  });
}
```

- [ ] **Step 2: 运行并确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\player_platform_policy_test.dart`

Expected: FAIL，策略不存在。

- [ ] **Step 3: 实现平台策略**

`PlayerPlatformPolicy` 通过能力列表规范化 decoder/renderer，提供 `decoderSettingKey`、`rendererSettingKey`、`supportsAnime4k`。新增设置键：

```dart
static const String androidHardwareDecoder = 'androidHardwareDecoder',
    androidVideoRenderer = 'androidVideoRenderer',
    androidAutoEnterPip = 'androidAutoEnterPip';
```

Windows 继续使用 `hardwareDecoder`，Android 使用新键，避免数据互相污染。

- [ ] **Step 4: 恢复 Android 渲染器设置页**

新增 `/settings/player/renderer` 路由和 `RendererSettingsPage`，选项严格来自 `androidVideoRenderersList`；Windows 播放设置不显示该入口。

- [ ] **Step 5: 让 PlayerRuntimeSettings 携带平台配置**

增加强类型字段：

```dart
final String hardwareDecoder;
final String? videoRenderer;
final bool anime4kSupported;
final bool androidAutoEnterPip;
```

读取时使用 `PlayerPlatformPolicy` 选择平台专属键。现有 Windows 默认值和测试保持不变。

- [ ] **Step 6: 接入 VideoControllerConfiguration**

在 `PlayerController` 创建控制器时设置：

```dart
VideoControllerConfiguration(
  vo: runtimeSettings.videoRenderer,
  enableHardwareAcceleration: hAenable,
  hwdec: hAenable ? runtimeSettings.hardwareDecoder : 'no',
  androidAttachSurfaceAfterVideoParameters:
      runtimeSettings.videoRenderer == 'mediacodec_embed',
)
```

Anime4K coordinator 在 `anime4kSupported == false` 时返回 `incompatibleRenderer` 并清空 shader，不抛出播放初始化错误。

- [ ] **Step 7: 验证设置与播放器测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\player_platform_policy_test.dart test\android_player_settings_test.dart test\hardware_decoder_settings_test.dart test\player_runtime_preferences_test.dart test\anime4k_policy_test.dart test\anime4k_player_controller_test.dart test\anime4k_player_ui_test.dart
```

Expected: Android/Windows 两套策略均 PASS。

- [ ] **Step 8: 提交**

```powershell
git add lib/features/player/application/player_platform_policy.dart lib/utils/constants.dart lib/features/settings/application/typed_settings.dart lib/pages/settings/renderer_settings.dart lib/pages/settings/decoder_settings.dart lib/pages/settings/player_settings.dart lib/pages/settings/settings_module.dart lib/features/player/application/player_runtime_preferences.dart lib/pages/player/player_controller.dart lib/pages/settings/super_resolution_settings.dart test/player_platform_policy_test.dart test/android_player_settings_test.dart test/hardware_decoder_settings_test.dart
git commit -m "功能：恢复安卓解码与渲染设置"
```

---

### Task 7: 引入 Windows 路径与 Android URI 的媒体位置模型

**Files:**

- Create: `lib/modules/local/media_location.dart`
- Modify: `lib/modules/local/local_media_source.dart`
- Modify: `lib/modules/local/local_file_item.dart`
- Modify: `lib/modules/local/local_media_index_item.dart`
- Modify: `lib/repositories/local_media_source_repository.dart`
- Modify: `lib/repositories/local_media_index_repository.dart`
- Modify: `lib/features/library/application/local_library_source_coordinator.dart`
- Test: `test/media_location_test.dart`
- Create: `test/local_media_source_test.dart`
- Test: `test/local_media_index_repository_cache_test.dart`

- [ ] **Step 1: 写媒体位置序列化失败测试**

Create `test/media_location_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/media_location.dart';

void main() {
  test('文件路径和文档 URI 使用不同稳定 ID', () {
    final file = MediaLocation.file(r'D:\Media\A.mkv');
    final document = MediaLocation.document(
      uri: 'content://provider/document/video%3A1',
      treeUri: 'content://provider/tree/video',
    );
    expect(file.kind, MediaLocationKind.file);
    expect(document.kind, MediaLocationKind.document);
    expect(file.stableId, isNot(document.stableId));
    expect(MediaLocation.fromJson(document.toJson()), document);
  });
}
```

- [ ] **Step 2: 运行并确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\media_location_test.dart`

Expected: FAIL，模型不存在。

- [ ] **Step 3: 实现强类型值对象**

Create `media_location.dart`：

```dart
import 'package:path/path.dart' as p;

enum MediaLocationKind { file, document }

class MediaLocation {
  const MediaLocation._({
    required this.kind,
    required this.value,
    this.treeUri,
  });

  factory MediaLocation.file(String path) {
    final value = p.normalize(path.trim());
    if (value.isEmpty || value == '.') {
      throw const FormatException('文件路径不能为空');
    }
    return MediaLocation._(kind: MediaLocationKind.file, value: value);
  }

  factory MediaLocation.document({
    required String uri,
    required String treeUri,
  }) {
    final document = Uri.tryParse(uri.trim());
    final tree = Uri.tryParse(treeUri.trim());
    if (document?.scheme != 'content' || tree?.scheme != 'content') {
      throw const FormatException('Android 文档位置必须使用 content URI');
    }
    return MediaLocation._(
      kind: MediaLocationKind.document,
      value: document.toString(),
      treeUri: tree.toString(),
    );
  }

  factory MediaLocation.fromJson(Map<Object?, Object?> json) {
    final kind = json['kind']?.toString();
    final value = json['value']?.toString() ?? '';
    return switch (kind) {
      'document' => MediaLocation.document(
          uri: value,
          treeUri: json['treeUri']?.toString() ?? '',
        ),
      'file' => MediaLocation.file(value),
      _ => throw FormatException('未知媒体位置类型: $kind'),
    };
  }

  final MediaLocationKind kind;
  final String value;
  final String? treeUri;

  String get stableId => kind == MediaLocationKind.file
      ? 'file:${p.normalize(value).toLowerCase()}'
      : 'document:$value';
  bool get isFile => kind == MediaLocationKind.file;
  bool get isDocument => kind == MediaLocationKind.document;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'value': value,
        if (treeUri != null) 'treeUri': treeUri,
      };

  @override
  bool operator ==(Object other) =>
      other is MediaLocation && other.stableId == stableId;

  @override
  int get hashCode => stableId.hashCode;
}
```

旧 JSON 没有 location 时从 `path` 构造 file location。

- [ ] **Step 4: 将来源和索引增加 location**

`LocalMediaSource` 和 `LocalFileItem` 新增 `MediaLocation location`。`LocalMediaIndexItem` 新增 `location`、`parentLocation`、`sourceLocation` 三个强类型字段，保证 SAF 选集分组不依赖 `path.dirname(contentUri)`。保留现有 `path`、`parentPath`、`sourcePath` getter 分别返回对应 location.value，以减少一次性破坏。`toJson` 写入三个 location，同时暂时保留旧字符串字段供旧版本读取；`fromJson` 优先读取 location，旧 JSON 则从原三个路径构造 file location。

来源仓库接口统一为：

```dart
LocalMediaSource? getByLocation(MediaLocation location);
Future<LocalMediaSource> upsertLocation(
  MediaLocation location, {
  required String displayName,
});
Future<bool> removeLocation(MediaLocation location);
Future<void> updateScanSummary({
  required MediaLocation location,
  required int fileCount,
  required int videoCount,
  required int directoryCount,
  required int skippedCount,
});
```

保留 `upsertPath/removePath/getByPath` 作为调用上述接口的 Windows 兼容 wrapper，直到所有调用迁移完成。

- [ ] **Step 5: 修正 ID 和规范化逻辑**

文件位置继续使用 `path.normalize(...).toLowerCase()`；文档 URI 不经过 `package:path`，使用原 URI 作为大小写敏感稳定 ID。索引仓库新增 `getBySourceLocation`、`getByLocation`、`saveForSourceLocation` 和 `removeSourceLocation`，旧 String API 作为 Windows wrapper；内部一律按 `location.stableId` 查询、去重和删除来源。

- [ ] **Step 6: 抽象来源可用性**

`LocalLibrarySourceCoordinator` 的默认可用性只处理 file；document availability 由注入的异步 provider 查询。将同步 `isAvailable` 改为缓存状态，控制器刷新时异步更新，不对 URI 调用 `Directory(uri)`。

- [ ] **Step 7: 运行迁移和仓库测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\media_location_test.dart test\local_media_source_test.dart test\local_media_index_repository_cache_test.dart test\local_media_indexer_test.dart test\local_controller_test.dart
```

Expected: 新旧 JSON 都 PASS；现有 Windows 索引测试不变。

- [ ] **Step 8: 提交**

```powershell
git add lib/modules/local/media_location.dart lib/modules/local/local_media_source.dart lib/modules/local/local_file_item.dart lib/modules/local/local_media_index_item.dart lib/repositories/local_media_source_repository.dart lib/repositories/local_media_index_repository.dart lib/features/library/application/local_library_source_coordinator.dart test/media_location_test.dart test/local_media_source_test.dart test/local_media_index_repository_cache_test.dart
git commit -m "重构：支持安卓文档媒体位置"
```

---

### Task 8: 实现 Android SAF 目录选择、授权与枚举

**Files:**

- Create: `lib/platform/android/android_document_provider.dart`
- Modify: `lib/platform/android/android_platform_channel.dart`
- Modify: `android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt`
- Modify: `lib/pages/local/local_directory_picker.dart`
- Modify: `lib/pages/local/local_page.dart`
- Modify: `lib/pages/settings/interface_settings.dart`
- Test: `test/android_document_provider_test.dart`
- Test: `test/local_directory_picker_test.dart`

- [ ] **Step 1: 写 SAF 客户端失败测试**

Create `test/android_document_provider_test.dart`，mock channel 返回：

```dart
{
  'treeUri': 'content://provider/tree/video',
  'documentUri': 'content://provider/document/video',
  'name': '视频'
}
```

断言 `pickDirectory()` 转换为 `MediaLocation.document`，`listChildren()` 将 MIME `vnd.android.document/directory` 转为目录，将 `video/x-matroska` 转为文件，并保留 size/modified。

- [ ] **Step 2: 运行并确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\android_document_provider_test.dart`

Expected: FAIL，provider 不存在。

- [ ] **Step 3: 实现 Dart provider**

定义：

```dart
class AndroidDocumentEntry {
  const AndroidDocumentEntry({
    required this.location,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modified,
    required this.mimeType,
  });
  final MediaLocation location;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime modified;
  final String mimeType;
}

abstract interface class AndroidDocumentProvider {
  Future<({MediaLocation location, String name})?> pickDirectory();
  Future<bool> canAccess(MediaLocation location);
  Future<List<AndroidDocumentEntry>> listChildren(MediaLocation parent);
  Future<Uint8List> readSmallFile(MediaLocation location, {required int maxBytes});
}

class MethodChannelAndroidDocumentProvider implements AndroidDocumentProvider {
  const MethodChannelAndroidDocumentProvider(this._channel);

  final AndroidPlatformChannel _channel;

  @override
  Future<({MediaLocation location, String name})?> pickDirectory() async {
    final raw = await _channel.pickDocumentDirectory();
    if (raw == null) return null;
    return (
      location: MediaLocation.document(
        uri: _string(raw, 'documentUri'),
        treeUri: _string(raw, 'treeUri'),
      ),
      name: _string(raw, 'name'),
    );
  }

  @override
  Future<bool> canAccess(MediaLocation location) =>
      _channel.canAccessDocument(location.value, location.treeUri!);

  @override
  Future<List<AndroidDocumentEntry>> listChildren(
    MediaLocation parent,
  ) async {
    final raw = await _channel.listDocumentChildren(
      parent.value,
      parent.treeUri!,
    );
    return raw.map((item) {
      final mimeType = _string(item, 'mimeType');
      return AndroidDocumentEntry(
        location: MediaLocation.document(
          uri: _string(item, 'documentUri'),
          treeUri: parent.treeUri!,
        ),
        name: _string(item, 'name'),
        isDirectory: mimeType == 'vnd.android.document/directory',
        size: _int(item, 'size'),
        modified: DateTime.fromMillisecondsSinceEpoch(_int(item, 'modified')),
        mimeType: mimeType,
      );
    }).toList(growable: false);
  }

  @override
  Future<Uint8List> readSmallFile(
    MediaLocation location, {
    required int maxBytes,
  }) => _channel.readSmallDocument(location.value, maxBytes);

  static String _string(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Android 文档响应缺少 $key');
  }

  static int _int(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}
```

同时在 `AndroidPlatformChannel` 增加四个底层方法：

```dart
Future<Map<Object?, Object?>?> pickDocumentDirectory() =>
    _channel.invokeMapMethod<Object?, Object?>('pickDirectory');

Future<bool> canAccessDocument(String documentUri, String treeUri) =>
    _invokeBool('canAccessDocument', <String, String>{
      'documentUri': documentUri,
      'treeUri': treeUri,
    });

Future<List<Map<Object?, Object?>>> listDocumentChildren(
  String documentUri,
  String treeUri,
) async {
  final values = await _channel.invokeListMethod<Object?>('listDocumentChildren', {
    'documentUri': documentUri,
    'treeUri': treeUri,
  });
  return (values ?? const <Object?>[])
      .whereType<Map<Object?, Object?>>()
      .toList(growable: false);
}

Future<Uint8List> readSmallDocument(String documentUri, int maxBytes) async =>
    await _channel.invokeMethod<Uint8List>('readSmallDocument', {
      'documentUri': documentUri,
      'maxBytes': maxBytes,
    }) ?? Uint8List(0);
```

平台响应必须验证字段类型、URI scheme 和最大读取长度；错误转换为 `AndroidDocumentException(code)`，日志不记录完整 URI。

- [ ] **Step 4: 实现 Kotlin SAF 方法**

在同一 MethodChannel 增加：

- `pickDirectory`：`ACTION_OPEN_DOCUMENT_TREE`，flags 包含 read/write/persistable/prefix，成功后 `takePersistableUriPermission`。
- `canAccessDocument`：查询根 document 一行，不读取媒体内容。
- `listDocumentChildren`：使用 `DocumentsContract.buildChildDocumentsUriUsingTree` 查询 ID、name、mime、size、lastModified。
- `readSmallDocument`：流式读取，超过 Dart 传入 maxBytes 立即返回 `FileTooLarge`。

任何 pending picker 存在时再次调用返回 `PickerBusy`；Activity 销毁时完成 pending result，不能悬挂 Future。

- [ ] **Step 5: 平台化目录选择器**

`LocalDirectoryPickerPage.pick` 接收平台能力与 Android provider。Windows 继续现有应用内盘符浏览；Android 直接调系统目录树选择器，并返回带 location/name 的 `LocalDirectorySelection`，不显示手工路径输入框。

- [ ] **Step 6: 更新本地页和设置页调用**

`local_page.dart` 与 `interface_settings.dart` 接收 `LocalDirectorySelection`，通过 source repository 的 `upsertLocation` 保存；Windows 旧路径入口继续工作。

- [ ] **Step 7: 验证**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\android_document_provider_test.dart test\local_directory_picker_test.dart test\local_controller_test.dart
D:\flutter\bin\flutter.bat build apk --debug --no-pub
```

Expected: PASS，APK 构建成功，Manifest 无全盘权限。

- [ ] **Step 8: 提交**

```powershell
git add lib/platform/android/android_document_provider.dart lib/platform/android/android_platform_channel.dart android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt lib/pages/local/local_directory_picker.dart lib/pages/local/local_page.dart lib/pages/settings/interface_settings.dart test/android_document_provider_test.dart test/local_directory_picker_test.dart
git commit -m "功能：接入安卓本地目录授权"
```

---

### Task 9: 统一文件系统与 SAF 扫描、索引和来源状态

**Files:**

- Create: `lib/services/local_media_entry_provider.dart`
- Create: `lib/services/file_system_media_entry_provider.dart`
- Create: `lib/services/android_media_entry_provider.dart`
- Modify: `lib/services/local_media_scanner.dart`
- Modify: `lib/services/local_media_indexer.dart`
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `lib/features/library/application/local_library_source_coordinator.dart`
- Test: `test/local_media_entry_provider_test.dart`
- Test: `test/android_local_media_scan_test.dart`
- Test: `test/local_media_scanner_test.dart`
- Test: `test/local_media_indexer_test.dart`

- [ ] **Step 1: 写统一目录项端口失败测试**

Create `test/local_media_entry_provider_test.dart`，定义 fake document tree，验证递归扫描只保留视频和目录、跳过隐藏项、保持 URI 不变，并统计不可访问项。

- [ ] **Step 2: 运行并确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\local_media_entry_provider_test.dart`

Expected: FAIL，端口不存在。

- [ ] **Step 3: 实现统一目录项接口**

Create `local_media_entry_provider.dart`:

```dart
class LocalMediaEntry {
  const LocalMediaEntry({
    required this.location,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.modified,
    this.mimeType,
  });
  final MediaLocation location;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime modified;
  final String? mimeType;
}

abstract interface class LocalMediaEntryProvider {
  bool supports(MediaLocation location);
  Future<bool> canAccess(MediaLocation location);
  Future<List<LocalMediaEntry>> listChildren(MediaLocation directory);
}
```

- [ ] **Step 4: 搬迁现有文件系统实现**

`FileSystemMediaEntryProvider` 使用 `Directory`/`FileStat` 复现当前行为。保留 Windows 系统目录过滤、符号链接不跟随和异常计数。

- [ ] **Step 5: 实现 SAF provider adapter**

`AndroidMediaEntryProvider` 仅把 `AndroidDocumentEntry` 映射为统一项，不在业务层调用 MethodChannel。

- [ ] **Step 6: 改造 scanner/indexer**

构造函数注入 `List<LocalMediaEntryProvider>`，按 location 选择 provider。索引器不再收集 `File`，而收集 `LocalMediaEntry`；使用以下工厂构造索引项。目录 fingerprint 使用稳定子项 ID、size、modified 和 MIME，不读取视频正文。

```dart
factory LocalMediaIndexItem.fromEntry({
  required LocalMediaEntry entry,
  required MediaLocation parentLocation,
  required MediaLocation sourceLocation,
  required LocalEpisodeInfo? episodeInfo,
  required DateTime indexedAt,
}) => LocalMediaIndexItem(
  location: entry.location,
  parentLocation: parentLocation,
  sourceLocation: sourceLocation,
  name: entry.name,
  size: entry.size,
  modified: entry.modified,
  seriesName: episodeInfo?.seriesName ?? parentLocation.value,
  seasonNumber: episodeInfo?.seasonNumber,
  episodeNumber: episodeInfo?.episodeNumber,
  indexedAt: indexedAt,
);
```

- [ ] **Step 7: 来源失效保留索引**

控制器刷新 `canAccess` 后维护 source availability。失效来源显示“需要重新授权”，不自动调用 `removeSource`；“清理不可用来源”继续只删除来源记录和派生索引，不删除用户文档。

- [ ] **Step 8: 验证**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\local_media_entry_provider_test.dart test\android_local_media_scan_test.dart test\local_media_scanner_test.dart test\local_media_indexer_test.dart test\local_controller_test.dart test\local_library_source_coordinator_test.dart
```

Expected: Windows 原有扫描断言与 Android URI 断言全部 PASS。

- [ ] **Step 9: 提交**

```powershell
git add lib/services/local_media_entry_provider.dart lib/services/file_system_media_entry_provider.dart lib/services/android_media_entry_provider.dart lib/services/local_media_scanner.dart lib/services/local_media_indexer.dart lib/pages/local/local_controller.dart lib/features/library/application/local_library_source_coordinator.dart test/local_media_entry_provider_test.dart test/android_local_media_scan_test.dart test/local_media_scanner_test.dart test/local_media_indexer_test.dart test/local_controller_test.dart test/local_library_source_coordinator_test.dart
git commit -m "重构：统一本地媒体扫描接口"
```

---

### Task 10: 支持 content URI 播放、字幕、封面和小文件缓存

**Files:**

- Modify: `lib/utils/media_uri_utils.dart`
- Modify: `lib/services/local_playback_request_builder.dart`
- Modify: `lib/services/local_subtitle_matcher.dart`
- Modify: `lib/services/local_subtitle_importer.dart`
- Modify: `lib/services/local_cover_finder.dart`
- Modify: `lib/services/local_custom_cover_service.dart`
- Modify: `lib/services/local_media_probe.dart`
- Modify: `lib/services/local_thumbnail_cache.dart`
- Modify: `lib/services/local_poster_scraper.dart`
- Create: `lib/services/android_document_cache.dart`
- Modify: `lib/pages/player/player_item.dart`
- Modify: `lib/pages/player/player_controller.dart`
- Test: `test/android_content_playback_test.dart`
- Test: `test/media_uri_utils_test.dart`
- Test: `test/local_subtitle_matcher_test.dart`
- Create: `test/local_cover_finder_test.dart`

- [ ] **Step 1: 写 content URI 播放失败测试**

扩展 `media_uri_utils_test.dart`：

```dart
test('MediaUriUtils 保留 Android content URI', () {
  const uri = 'content://provider/document/video%3A42';
  expect(MediaUriUtils.toPlayableUri(uri, isLocalPlayback: true), uri);
});
```

Create `android_content_playback_test.dart`，验证同一 document parent 下的 URI 能组成选集且不会经过 `path.dirname`。

- [ ] **Step 2: 运行并确认至少选集测试失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\media_uri_utils_test.dart test\android_content_playback_test.dart`

Expected: URI 保留测试可通过；选集构建因 path 语义失败，证明测试覆盖缺口。

- [ ] **Step 3: 平台化播放列表分组**

`LocalPlaybackRequestBuilder` 接收已经索引的 `LocalFileItem`/`MediaLocation`，用 parent stableId 分组；文件路径继续使用 path parser，document URI 使用 entry 的 displayName 解析季集。Road.data 存储可播放 URI。

- [ ] **Step 4: 支持 SAF 同目录字幕**

为 `LocalSubtitleMatcher` 增加基于 `List<LocalMediaEntry>` 的纯匹配方法，使用文件名而非 URI 比较。匹配到 document subtitle 时，`AndroidDocumentCache` 通过 `readSmallFile(maxBytes: 10 * 1024 * 1024)` 写入应用 cache，再把临时文件路径传给 mpv；退出播放时只删除应用缓存。

- [ ] **Step 5: 支持 SAF 封面**

本地封面候选通过目录项文件名识别；只允许 `jpg/jpeg/png/webp` 且最大 20 MiB，缓存到应用专属 `local_document_covers`。TMDB 海报和现有应用缓存路径不变。

自定义封面在 Android 复制到应用专属封面目录；媒体探测和缩略图生成使用 `MediaUriUtils.toPlayableUri` 返回的 content URI，不对 URI 构造 `File`。TMDB 刮削海报在 SAF 来源下写入应用缓存并更新索引，只有 Windows 文件来源继续尝试写入视频目录。

- [ ] **Step 6: 处理字幕导入权限**

用户选择外部字幕后，Android 默认复制到应用专属字幕目录；只有 provider 明确提供写权限时才显示“保存到视频目录”。失败不删除原字幕文件。

- [ ] **Step 7: 验证播放器相关测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\android_content_playback_test.dart test\media_uri_utils_test.dart test\local_playback_request_builder_test.dart test\local_subtitle_matcher_test.dart test\local_subtitle_importer_test.dart test\local_cover_finder_test.dart test\player_subtitle_coordinator_test.dart
```

Expected: PASS。

- [ ] **Step 8: 提交**

```powershell
git add lib/utils/media_uri_utils.dart lib/services/local_playback_request_builder.dart lib/services/local_subtitle_matcher.dart lib/services/local_subtitle_importer.dart lib/services/local_cover_finder.dart lib/services/local_custom_cover_service.dart lib/services/local_media_probe.dart lib/services/local_thumbnail_cache.dart lib/services/local_poster_scraper.dart lib/services/android_document_cache.dart lib/pages/player/player_item.dart lib/pages/player/player_controller.dart test/android_content_playback_test.dart test/media_uri_utils_test.dart test/local_subtitle_matcher_test.dart
git commit -m "功能：支持安卓本地视频与字幕"
```

---

### Task 11: 接入 Android 画中画、亮度、截图、外部播放器和后台音频

**Files:**

- Modify: `lib/utils/window_utils.dart`
- Modify: `lib/utils/pip_utils.dart`
- Modify: `lib/utils/external_player.dart`
- Modify: `lib/pages/player/player_item.dart`
- Modify: `lib/pages/player/player_item_panel.dart`
- Modify: `lib/pages/player/smallest_player_item_panel.dart`
- Modify: `lib/pages/video/video_page.dart`
- Modify: `lib/services/audio_controller.dart`
- Test: `test/player_system_capabilities_test.dart`
- Test: `test/external_player_test.dart`
- Test: `test/player_audio_service_coordinator_test.dart`

- [ ] **Step 1: 写系统能力分派失败测试**

Create `test/player_system_capabilities_test.dart`，注入 fake Windows/Android ports，断言 Android PIP 只调用 `enterPictureInPicture`，Windows 只调用桌面窗口 PIP；Android 亮度限制在 0.01..1.0；截图走 Android MediaStore port。

- [ ] **Step 2: 运行并确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\player_system_capabilities_test.dart`

Expected: FAIL，统一服务不存在。

- [ ] **Step 3: 将 WindowUtils/PipUtils 改为端口分派**

公开 `PlayerSystemService`，构造时注入 capabilities、desktop port、Android system service。Windows 方法体保持原样；Android 全屏、PIP、亮度与截图调用 Kotlin 通道。

- [ ] **Step 4: Android 触控手势接系统音量和亮度**

右侧竖滑继续调用 `FlutterVolumeController`；左侧竖滑调用 Android window brightness。鼠标滚轮和键盘快捷键只在桌面/键盘输入路径启用。

- [ ] **Step 5: 扩展外部播放器通道兼容 Android**

`ExternalPlayerClient` 保持同一 `openWithMime` API；Android MainActivity 处理 content URI 并授予临时读取权限。带 referer 路径继续固定返回 `UnsupportedHeaders`。

- [ ] **Step 6: 完成 audio_service Android 配置**

确认 `AudioController` 初始化通知频道 `com.kanyingyin.player.channel.audio`，Manifest service/receiver 与 MainActivity 引擎复用正确。恢复 `becomingNoisyEventStream`：Android 耳机拔出调用 `_safePause()`；Windows 不改变。

首次开启后台播放时，API 33 及以上请求 `POST_NOTIFICATIONS`；拒绝后仍允许前台播放，但关闭后台播放开关并显示原因。API 24–28 首次保存公共截图时请求清单中 `maxSdkVersion="28"` 的旧存储权限；拒绝后不写入公共目录，并允许用户改用应用专属导出。

- [ ] **Step 7: 自动画中画生命周期**

当 Android 设置 `androidAutoEnterPip` 开启、视频正在播放且 Activity 进入后台时请求 PIP；暂停、音频-only 或用户关闭时不自动进入。

- [ ] **Step 8: 验证**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\player_system_capabilities_test.dart test\external_player_test.dart test\player_audio_service_coordinator_test.dart test\player_exit_lifecycle_test.dart test\player_overlay_coordinator_test.dart
D:\flutter\bin\flutter.bat build apk --debug --no-pub
```

Expected: PASS。

- [ ] **Step 9: 提交**

```powershell
git add lib/utils/window_utils.dart lib/utils/pip_utils.dart lib/utils/external_player.dart lib/pages/player/player_item.dart lib/pages/player/player_item_panel.dart lib/pages/player/smallest_player_item_panel.dart lib/pages/video/video_page.dart lib/services/audio_controller.dart test/player_system_capabilities_test.dart test/external_player_test.dart test/player_audio_service_coordinator_test.dart
git commit -m "功能：完善安卓播放器系统交互"
```

---

### Task 12: 验证 Android 网盘、WebView、安全存储与网络策略

**Files:**

- Modify: `lib/pages/cloud/xunlei/xunlei_verification_dialog.dart`
- Modify: `lib/utils/proxy_manager.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `test/android_cloud_platform_contract_test.dart`
- Modify: `test/xunlei_verification_security_test.dart`
- Modify: `test/cloud_library_integration_test.dart`

- [ ] **Step 1: 写 Android 网盘平台契约失败测试**

Create `test/android_cloud_platform_contract_test.dart`，断言：

- pubspec Android 插件解析包含 `flutter_inappwebview_android`、`flutter_secure_storage`、`media_kit_libs_android_video`。
- 迅雷验证页继续拒绝下载、新窗口和非受信任导航。
- Android 启动不执行 Windows 本地代理端口探测。
- Manifest 允许用户自配 OpenList HTTP 地址，但没有放宽 WebView 下载与权限策略。

- [ ] **Step 2: 运行并确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\android_cloud_platform_contract_test.dart`

Expected: FAIL，当前代理或清单契约不满足。

- [ ] **Step 3: 平台化代理初始化**

Windows 保留当前本机代理探测；Android 只使用用户明确保存的代理 URL，不扫描 localhost 端口。TMDB、海报和播放器 HTTP proxy 继续复用格式化策略。

- [ ] **Step 4: 验证 Android WebView 配置**

在 Android 真机/模拟器加载固定迅雷验证入口。平台差异只允许处理 user agent 和 WebView 初始化，不放宽 host、scheme、下载、新窗口、console 或权限守卫。

- [ ] **Step 5: 配置 HTTP 兼容策略**

为用户自建 OpenList 保留 HTTP 访问能力，在 Manifest 明确 `android:usesCleartextTraffic="true"`；UI 已显示来源 URL，凭据仍在安全存储，日志继续脱敏。该配置不得影响迅雷验证的 HTTPS 主机白名单。

- [ ] **Step 6: 验证云端测试和 Android 构建**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\android_cloud_platform_contract_test.dart test\xunlei_verification_security_test.dart test\xunlei_verification_bridge_test.dart test\cloud_library_integration_test.dart test\openlist_client_test.dart test\quark_drive_client_test.dart test\baidu_drive_client_test.dart test\xunlei_drive_client_test.dart
D:\flutter\bin\flutter.bat build apk --debug --no-pub
```

Expected: PASS。

- [ ] **Step 7: 提交**

```powershell
git add lib/pages/cloud/xunlei/xunlei_verification_dialog.dart lib/utils/proxy_manager.dart android/app/src/main/AndroidManifest.xml test/android_cloud_platform_contract_test.dart test/xunlei_verification_security_test.dart test/cloud_library_integration_test.dart
git commit -m "功能：适配安卓网盘与安全存储"
```

---

### Task 13: Android 图标、压缩、签名和本地发布脚本

**Files:**

- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `.gitignore`
- Modify: `android/app/build.gradle.kts`
- Create: `android/app/proguard-rules.pro`
- Create: `android/key.properties.example`
- Create: `tool/android/build_signed_release.ps1`
- Create: `test/android_release_packaging_test.dart`

- [ ] **Step 1: 写发布脚本失败测试**

Create `test/android_release_packaging_test.dart`，读取 Gradle 与 PowerShell，断言：

- Release 签名只从 `KANYINGYIN_ANDROID_*` 环境变量读取。
- 仓库不存在 `.jks`/`.keystore`/真实 `key.properties`。
- 脚本执行 `flutter build apk --release --no-pub` 和 `flutter build appbundle --release --no-pub`。
- 使用 `apksigner verify` 与 `jarsigner -verify`。
- 复制为桌面 `看影音-版本号.apk` 和 `看影音-版本号.aab`。

- [ ] **Step 2: 运行并确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\android_release_packaging_test.dart`

Expected: FAIL，发布脚本和签名配置不存在。

- [ ] **Step 3: 配置 adaptive icon 与启动资源**

`flutter_launcher_icons` 增加 Android 配置，前景使用 `assets/images/logo/logo_rounded.png`，背景使用项目品牌蓝。运行：

```powershell
D:\flutter\bin\flutter.bat pub get
D:\flutter\bin\dart.bat run flutter_launcher_icons
```

生成资源只位于 `android/app/src/main/res`，Windows 图标配置保持不变。

- [ ] **Step 4: 配置 Release 签名和压缩**

`build.gradle.kts` 从以下环境变量读取：

```text
KANYINGYIN_ANDROID_KEYSTORE
KANYINGYIN_ANDROID_STORE_PASSWORD
KANYINGYIN_ANDROID_KEY_ALIAS
KANYINGYIN_ANDROID_KEY_PASSWORD
```

任何 release task 缺少变量时抛 `GradleException`。Release 设置 `isMinifyEnabled = true`、`isShrinkResources = true`，ProGuard 保留 Flutter、audio_service、flutter_inappwebview 和 media_kit 通过 manifest/反射访问的类。

- [ ] **Step 5: 提供无秘密模板和忽略规则**

`android/key.properties.example` 只写变量名称说明，不写值；`.gitignore` 加入：

```gitignore
/android/key.properties
*.jks
*.keystore
/tool/android/private-output/
```

- [ ] **Step 6: 实现签名发布脚本**

脚本先验证四个环境变量和 keystore 文件，再构建 APK/AAB；从 pubspec 读取版本；使用 SDK 36 build-tools 的 `apksigner.bat` 验证 APK，使用 JDK 17 `jarsigner.exe -verify -strict -verbose -certs` 验证 AAB；检查 APK badging 的包名/versionName/versionCode；最后复制到桌面。`finally` 清除 PowerShell 变量，不输出密码。

- [ ] **Step 7: 生成本机发布密钥**

密钥存放到 `$env:USERPROFILE\.kanyingyin\android\kanyingyin-release.jks`。使用 `keytool` RSA 4096、有效期 10000 天、alias `kanyingyin`；密码由安全随机值生成并保存在用户受控密码管理器或当前会话 SecretManagement，不提交仓库。

- [ ] **Step 8: 验证发布契约**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\android_release_packaging_test.dart test\release_config_contract_test.dart
git status --short
```

Expected: PASS，状态中没有密钥或密码文件。

- [ ] **Step 9: 提交**

```powershell
git add pubspec.yaml pubspec.lock .gitignore android/app/build.gradle.kts android/app/proguard-rules.pro android/key.properties.example android/app/src/main/res tool/android/build_signed_release.ps1 test/android_release_packaging_test.dart
git commit -m "构建：配置安卓签名发布"
```

---

### Task 14: 将 CI 与平台守卫从 Windows-only 升级为双平台

**Files:**

- Modify: `.github/workflows/pr.yaml`
- Modify: `test/windows_ci_workflow_test.dart`
- Replace: `test/windows_only_residue_test.dart` → `test/platform_boundary_test.dart`
- Modify: `test/settings_ui_residue_test.dart`

- [ ] **Step 1: 写双平台 CI 失败测试**

修改 `windows_ci_workflow_test.dart`：PR workflow 必须有 `windows-quality` 和 `android-quality` 两个 job；Android job 在 `ubuntu-latest` 执行 pub get、analyze、test 和 `flutter build apk --debug --no-pub`；Windows job继续执行 Release 构建。

- [ ] **Step 2: 改写平台边界守卫**

将 Windows-only 禁止项测试替换为：

- `Platform.isWindows/isAndroid` 只允许出现在 `lib/platform/app_platform_io.dart`；Windows/Android 具体实现接收已经选择好的 capabilities，不重复判断操作系统。
- 共享业务层不得 import `window_manager`、`tray_manager` 或 `android.*`。
- pubspec 同时解析 Android media_kit、WebView、安全存储与 Windows 插件实现。
- Android Manifest 不含全盘权限；Windows 注册文件不含 Android-only 插件。

- [ ] **Step 3: 运行并确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\windows_ci_workflow_test.dart test\platform_boundary_test.dart test\settings_ui_residue_test.dart
```

Expected: FAIL，当前 PR workflow 仍只有 Windows job，旧测试仍禁止 Android。

- [ ] **Step 4: 增加 Android CI job**

在 `.github/workflows/pr.yaml` 新增独立 `android-quality`，使用与 Windows 相同固定 SHA 的 checkout/flutter-action，执行 Debug APK；不读取发布签名 secrets。

- [ ] **Step 5: 更新设置守卫**

Windows 断言桌面设置不出现 Android renderer/PIP；Android widget 注入 capabilities 后断言出现渲染器、滑动手势和自动画中画。删除“所有源码都不能出现 Android”这种与新目标冲突的断言。

- [ ] **Step 6: 验证并提交**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\windows_ci_workflow_test.dart test\platform_boundary_test.dart test\settings_ui_residue_test.dart
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: PASS。

```powershell
git add .github/workflows/pr.yaml test/windows_ci_workflow_test.dart test/platform_boundary_test.dart test/settings_ui_residue_test.dart
git rm test/windows_only_residue_test.dart
git commit -m "持续集成：增加安卓质量门禁"
```

---

### Task 15: Android 模拟器和实机功能验收

**Files:**

- Create: `docs/testing/android-release-checklist.md`
- Create: `docs/testing/android-device-results.md`

- [ ] **Step 1: 安装模拟器组件并创建 API 36 AVD**

```powershell
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$manager = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
& $manager --sdk_root=$sdk 'emulator' 'system-images;android-36;google_apis;x86_64'
'no' | & (Join-Path $sdk 'cmdline-tools\latest\bin\avdmanager.bat') create avd --force --name 'kanyingyin_api36' --package 'system-images;android-36;google_apis;x86_64' --device 'pixel_7'
```

Expected: `flutter emulators` 列出 `kanyingyin_api36`。

- [ ] **Step 2: 启动模拟器并安装 Debug APK**

```powershell
D:\flutter\bin\flutter.bat emulators --launch kanyingyin_api36
D:\flutter\bin\flutter.bat devices
D:\flutter\bin\flutter.bat install -d emulator-5554
```

Expected: 设备在线且应用安装成功。

- [ ] **Step 3: 执行模拟器验收清单**

记录冷启动、导航、安全区、网盘设置页、TMDB 无 Key、横竖屏、返回键、后台通知、PIP、WebView 和基础网络。日志使用：

```powershell
adb logcat -c
adb shell am force-stop com.kanyingyin.player
adb shell monkey -p com.kanyingyin.player 1
adb logcat -d | Select-String -Pattern 'FATAL EXCEPTION|AndroidRuntime|com.kanyingyin.player'
```

Expected: 无看影音相关 fatal exception。

- [ ] **Step 4: 执行物理 Android 设备验收**

至少使用一台 API 24+ ARM64 真机，逐项验证 SAF 目录授权/撤销/重授、content URI 播放、四类网盘、字幕、音轨、选集、MediaCodec、后台通知、耳机拔出、系统 PIP、截图、外部播放器和支持/不支持 renderer 的 Anime4K 状态。

- [ ] **Step 5: 记录证据**

`android-device-results.md` 记录设备型号、Android 版本、ABI、APK 版本、每项通过/失败、失败日志分类和复测结果；不记录账户、Token、媒体完整 URI 或本地路径。

- [ ] **Step 6: 提交验收文档**

```powershell
git add docs/testing/android-release-checklist.md docs/testing/android-device-results.md
git commit -m "测试：记录安卓设备验收"
```

---

### Task 16: 更新版本、发布资料并生成双平台交付物

**Files:**

- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `README.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`

- [ ] **Step 1: 发布前重新记录 Windows 已安装版本**

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name,Version,PackageFullName,InstallLocation
```

Expected: 记录结果；当前已知版本为 `2.1.82.0`，但以本步骤实时结果为准。

- [ ] **Step 2: 写版本一致性失败测试**

将 `version_consistency_test.dart` 增加 Android 断言：pubspec build number 等于 Android versionCode 来源；当前发布说明包含 APK/AAB 版本与 Android 支持；README 平台表同时列出 Windows 与 Android。

- [ ] **Step 3: 运行并确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart`

Expected: FAIL，当前版本和说明仍是 2.1.82/Windows-only。

- [ ] **Step 4: 更新到 2.1.83**

统一修改：

```yaml
version: 2.1.83+20183
msix_config:
  msix_version: 2.1.83.0
```

`AppVersion.current` 改为 `2.1.83`。发布文案面向普通用户，说明新增 Android、本地目录授权、网盘、播放/PIP/后台能力，并明确不会删除原始视频；不得声称未完成实机验证的功能。

- [ ] **Step 5: 完整自动化验证**

Run:

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: 所有命令 exit 0，无测试失败和分析错误。

- [ ] **Step 6: 生成并验证 Windows MSIX**

使用现有 `tool\windows\build_signed_release.ps1`，验证清单 `2.1.83.0`、身份 `com.kanyingyin.player`、签名有效，并复制到桌面 `看影音-2.1.83.msix`。

- [ ] **Step 7: 生成并验证 Android APK/AAB**

设置四个本机签名环境变量并运行：

```powershell
.\tool\android\build_signed_release.ps1
```

Expected: 桌面存在 `看影音-2.1.83.apk` 与 `看影音-2.1.83.aab`；APK `apksigner verify`、AAB `jarsigner -verify -strict` 均通过，包名和 versionName/versionCode 为 `com.kanyingyin.player`、`2.1.83`、`20183`。

- [ ] **Step 8: 核对安装包与安装版本**

安装 APK 到验收设备后运行：

```powershell
adb shell dumpsys package com.kanyingyin.player | Select-String -Pattern 'versionName|versionCode'
```

若安装 Windows MSIX，再次执行 `Get-AppxPackage`；否则明确记录未执行安装。核对桌面三个产物名称与版本一致。

- [ ] **Step 9: 提交发布资料**

先检查：

```powershell
git status --short
git diff -- pubspec.yaml lib/core/app_version.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md README.md lib/utils/version_history.dart test/version_consistency_test.dart
```

只暂存本轮相关文件：

```powershell
git add pubspec.yaml lib/core/app_version.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md README.md lib/utils/version_history.dart test/version_consistency_test.dart
git commit -m "发布：交付安卓二点一八十三版本"
```

构建目录、APK、AAB、MSIX 和密钥不进入 Git。

---

## 最终完成审计

实现结束后逐项取得当前证据，不能只以测试未报错代替功能完成：

- [ ] `android/` 可由 Flutter 3.41.9 构建，applicationId/namespace 为 `com.kanyingyin.player`。
- [ ] Android 启动路径不调用桌面插件，Windows 窗口/托盘/快捷方式回归通过。
- [ ] SAF 授权、递归扫描、授权失效和重授权在真机通过，且没有 `MANAGE_EXTERNAL_STORAGE`。
- [ ] 本地 content URI 与 OpenList、夸克、百度、迅雷视频均在真机播放。
- [ ] TMDB、字幕、音轨、选集、进度、MediaCodec、后台通知、耳机拔出、PIP、截图和外部播放器有实机记录。
- [ ] Anime4K 在 GPU renderer 成功或形成明确、可复现的不支持结论；普通播放不受影响。
- [ ] `flutter test --no-pub`、`flutter analyze --no-pub`、Windows Release、签名 MSIX、签名 APK、签名 AAB 全部有最新 exit 0 证据。
- [ ] APK/AAB/MSIX 的身份、版本、架构、权限和签名验证通过。
- [ ] 桌面存在 `看影音-2.1.83.msix`、`看影音-2.1.83.apk`、`看影音-2.1.83.aab`。
- [ ] Git 状态不包含密钥、凭据、构建缓存或无关用户改动。
