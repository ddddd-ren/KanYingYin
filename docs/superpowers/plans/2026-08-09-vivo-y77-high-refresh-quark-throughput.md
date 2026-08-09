# vivo Y77 High Refresh and Quark Throughput Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 vivo Y77 冷启动界面申请 120Hz，并为其天玑 930／MT6877 建立 2 MiB、最高 10 路的夸克专项读取档位，同时保持其他平台和设备行为不变。

**Architecture:** Android 原生层以独立控制器选择同分辨率最高刷新模式，并通过现有平台通道上报设备与显示能力。Dart 平台层把能力映射为强类型性能档位，Range 中转层仅对 Android 手机夸克的 MT6877 档选择专项参数；超规格 4K HDR 120fps 软件解码继续作为独立设备能力边界报告。

**Tech Stack:** Flutter 3.41.9、Dart 3.11、Kotlin/Android API 24-36、JUnit 4、media_kit/libmpv、PowerShell、Inno Setup

---

## 文件范围

- Create: `android/app/src/main/kotlin/com/kanyingyin/player/HighRefreshRateModeSelector.kt` — 纯 Kotlin 的同分辨率最高刷新模式选择。
- Create: `android/app/src/main/kotlin/com/kanyingyin/player/AndroidHighRefreshRateController.kt` — Android Window 显示模式应用与快照。
- Create: `android/app/src/test/kotlin/com/kanyingyin/player/HighRefreshRateModeSelectorTest.kt` — 模式选择单元测试。
- Modify: `android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt` — 生命周期应用高刷并扩展设备能力通道。
- Modify: `lib/platform/android/android_device_capabilities.dart` — 强类型解析设备、SoC 与刷新率字段。
- Create: `lib/platform/android/android_performance_profile.dart` — 标准档与 MT6877 专项档选择。
- Modify: `lib/platform/app_platform.dart` — 保存 Android 性能档位与脱敏设备能力。
- Modify: `lib/platform/app_platform_io.dart` — 启动时安装扩展能力并记录档位。
- Modify: `lib/utils/diagnostic_log_exporter.dart` — 导出设备、刷新率与性能档位。
- Modify: `lib/services/cloud/range/cloud_range_relay_session.dart` — 新增 MT6877 专项 Range 参数。
- Modify: `lib/services/cloud/range/cloud_range_relay_service.dart` — 按平台能力选择专项参数并记录会话配置。
- Modify: `lib/services/cloud/quark/quark_range_remote_reader.dart` — 允许专项档使用最多 10 个同主机连接。
- Modify: `test/android_platform_channel_test.dart` — 原生能力字段契约。
- Modify: `test/android_tv_capability_test.dart` — Dart 能力解析与安全回退。
- Create: `test/android_performance_profile_test.dart` — MT6877/PD2219 匹配边界。
- Modify: `test/android_player_media_compatibility_test.dart` — MainActivity 高刷生命周期契约。
- Modify: `test/cloud_range_relay_service_test.dart` — 提供方和设备档位参数选择。
- Modify: `test/cloud_range_relay_session_test.dart` — `8/7→10/9` 升降档与并发上限。
- Modify: `test/quark_range_remote_reader_test.dart` — 10 路连接配置与现有安全边界回归。
- Modify: `pubspec.yaml`、`lib/core/app_version.dart`、`android/app/build.gradle.kts`、`tool/android/build_signed_release.ps1` — 测试版 `2.1.159+20159` 契约。
- Modify: `RELEASE_NOTES.md`、`lib/utils/version_history.dart`、`UPDATE_DIALOG_COPY.md` — 普通用户可见更新说明。
- Modify: relevant version/release contract tests — 同步 2.1.159、Android 手机交付和 TV 暂停边界。

### Task 1: 记录实施前安装与仓库基线

**Files:**
- Verify: repository and installed Windows state

- [ ] **Step 1: 查询工作区和当前源码版本**

```powershell
git status --short
git log -5 --oneline --decorate
Get-Content -Encoding UTF8 pubspec.yaml | Select-String '^version:|msix_version'
Get-Content -Encoding UTF8 lib\core\app_version.dart
```

Expected: 只有已批准的设计/计划提交，或明确列出用户已有的无关改动；当前源码为 Windows 1.0.8 正式版基线。

- [ ] **Step 2: 查询 Windows EXE 和旧 MSIX 安装状态**

```powershell
$uninstallRoots = @(
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$installed = Get-ItemProperty $uninstallRoots -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -eq '看影音' } |
  Select-Object DisplayName, DisplayVersion, InstallLocation, UninstallString
$installed
$installed | ForEach-Object {
  $exe = Join-Path $_.InstallLocation 'kanyingyin.exe'
  if (Test-Path -LiteralPath $exe) {
    Get-Item -LiteralPath $exe | Select-Object FullName, @{N='ProductVersion';E={$_.VersionInfo.ProductVersion}}
  }
}
Get-AppxPackage -Name 'com.kanyingyin.player' | Select-Object Name, Version, InstallLocation
```

Expected: 记录实际安装版本、主程序产品版本和旧 MSIX 是否存在；不根据 `pubspec.yaml` 推断。

### Task 2: 用 TDD 建立原生高刷模式选择器

**Files:**
- Create: `android/app/src/main/kotlin/com/kanyingyin/player/HighRefreshRateModeSelector.kt`
- Create: `android/app/src/test/kotlin/com/kanyingyin/player/HighRefreshRateModeSelectorTest.kt`

- [ ] **Step 1: 写入失败的纯 Kotlin 选择测试**

测试覆盖同分辨率最高刷新、不同分辨率排除、并列稳定选择和空列表：

```kotlin
package com.kanyingyin.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HighRefreshRateModeSelectorTest {
    private val current = DisplayModeCandidate(1, 1080, 2400, 60f)

    @Test
    fun selectsHighestRefreshRateAtCurrentResolution() {
        val selected = HighRefreshRateModeSelector.select(
            current,
            listOf(
                current,
                DisplayModeCandidate(2, 1080, 2400, 90f),
                DisplayModeCandidate(3, 1080, 2400, 120f),
                DisplayModeCandidate(4, 1440, 3200, 144f),
            ),
        )
        assertEquals(3, selected?.modeId)
    }

    @Test
    fun returnsCurrentModeWhenNoFasterSameResolutionModeExists() {
        assertEquals(current, HighRefreshRateModeSelector.select(current, listOf(current)))
    }

    @Test
    fun returnsNullWhenModesAreUnavailable() {
        assertNull(HighRefreshRateModeSelector.select(null, emptyList()))
    }
}
```

- [ ] **Step 2: 运行测试并确认失败**

```powershell
Set-Location android
.\gradlew.bat testMobileDebugUnitTest --tests 'com.kanyingyin.player.HighRefreshRateModeSelectorTest'
Set-Location ..
```

Expected: FAIL，缺少 `DisplayModeCandidate` 或 `HighRefreshRateModeSelector`。

- [ ] **Step 3: 实现最小选择器**

```kotlin
package com.kanyingyin.player

internal data class DisplayModeCandidate(
    val modeId: Int,
    val physicalWidth: Int,
    val physicalHeight: Int,
    val refreshRate: Float,
)

internal object HighRefreshRateModeSelector {
    fun select(
        current: DisplayModeCandidate?,
        supported: List<DisplayModeCandidate>,
    ): DisplayModeCandidate? {
        current ?: return null
        return supported
            .asSequence()
            .filter {
                it.physicalWidth == current.physicalWidth &&
                    it.physicalHeight == current.physicalHeight
            }
            .maxWithOrNull(compareBy<DisplayModeCandidate> { it.refreshRate }.thenBy { -it.modeId })
            ?: current
    }
}
```

- [ ] **Step 4: 运行测试并确认通过**

Run Task 2 Step 2 的相同命令。

Expected: PASS，0 failures。

- [ ] **Step 5: 提交纯选择器**

```powershell
git add -- android/app/src/main/kotlin/com/kanyingyin/player/HighRefreshRateModeSelector.kt android/app/src/test/kotlin/com/kanyingyin/player/HighRefreshRateModeSelectorTest.kt
git commit -m '功能：选择Android最高同分辨率刷新率'
```

### Task 3: 接入 Android Window 高刷控制器和生命周期

**Files:**
- Create: `android/app/src/main/kotlin/com/kanyingyin/player/AndroidHighRefreshRateController.kt`
- Modify: `android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt`
- Modify: `test/android_player_media_compatibility_test.dart`

- [ ] **Step 1: 先增加 MainActivity 契约断言**

在 `android_player_media_compatibility_test.dart` 增加：

```dart
test('Android 手机在关键生命周期重新申请最高同分辨率刷新模式', () {
  expect(mainActivity, contains('AndroidHighRefreshRateController(this)'));
  expect(mainActivity, contains('highRefreshRateController.applyPreferredMode()'));
  expect(mainActivity, contains('override fun onResume()'));
  expect(mainActivity, contains('override fun onWindowFocusChanged'));
  expect(mainActivity, contains('override fun onConfigurationChanged'));
});
```

- [ ] **Step 2: 运行契约测试并确认失败**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test\android_player_media_compatibility_test.dart
```

Expected: FAIL，`MainActivity` 尚未创建或调用高刷控制器。

- [ ] **Step 3: 实现 Android 控制器**

控制器输出可供能力通道读取的快照，并跳过 TV 与画中画：

```kotlin
internal data class RefreshRateSnapshot(
    val currentRefreshRate: Float,
    val supportedRefreshRates: List<Float>,
    val preferredModeId: Int,
)

internal class AndroidHighRefreshRateController(
    private val activity: Activity,
) {
    var snapshot = RefreshRateSnapshot(0f, emptyList(), 0)
        private set

    fun applyPreferredMode() {
        val uiMode = activity.resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
        val isTv = activity.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEVISION) ||
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            uiMode == Configuration.UI_MODE_TYPE_TELEVISION
        if (isTv || (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && activity.isInPictureInPictureMode)) return
        val display = activity.display ?: return
        val current = display.mode.toCandidate()
        val supported = display.supportedModes.map { it.toCandidate() }
        val selected = HighRefreshRateModeSelector.select(current, supported) ?: return
        val attributes = activity.window.attributes
        if (attributes.preferredDisplayModeId != selected.modeId) {
            attributes.preferredDisplayModeId = selected.modeId
            activity.window.attributes = attributes
        }
        snapshot = RefreshRateSnapshot(
            currentRefreshRate = display.refreshRate,
            supportedRefreshRates = supported.map { it.refreshRate }.distinct().sorted(),
            preferredModeId = selected.modeId,
        )
    }
}
```

文件内增加私有 `Display.Mode.toCandidate()`；捕获 `RuntimeException` 并保留默认快照，不能阻断启动。

- [ ] **Step 4: 在 MainActivity 生命周期接入**

新增字段：

```kotlin
private val highRefreshRateController by lazy {
    AndroidHighRefreshRateController(this)
}
```

在 `onCreate`、`onResume`、`onWindowFocusChanged(true)`、`onConfigurationChanged` 调用：

```kotlin
highRefreshRateController.applyPreferredMode()
```

保留现有沉浸与平板横屏调用顺序，不删除任何已有行为。

- [ ] **Step 5: 运行 Kotlin 和 Flutter 聚焦测试**

```powershell
Set-Location android
.\gradlew.bat testMobileDebugUnitTest
Set-Location ..
D:\flutter\bin\flutter.bat test --no-pub test\android_player_media_compatibility_test.dart
```

Expected: 全部 PASS。

- [ ] **Step 6: 提交高刷生命周期接入**

```powershell
git add -- android/app/src/main/kotlin/com/kanyingyin/player/AndroidHighRefreshRateController.kt android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt test/android_player_media_compatibility_test.dart
git commit -m '优化：Android界面申请设备最高刷新率'
```

### Task 4: 扩展设备能力并建立 MT6877 性能档位

**Files:**
- Modify: `android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt`
- Modify: `lib/platform/android/android_device_capabilities.dart`
- Create: `lib/platform/android/android_performance_profile.dart`
- Modify: `lib/platform/app_platform.dart`
- Modify: `lib/platform/app_platform_io.dart`
- Modify: `lib/utils/diagnostic_log_exporter.dart`
- Modify: `test/android_platform_channel_test.dart`
- Modify: `test/android_tv_capability_test.dart`
- Create: `test/android_performance_profile_test.dart`

- [ ] **Step 1: 写入 Dart 失败测试**

新测试必须包含：

```dart
expect(
  AndroidPerformanceProfileResolver.resolve(
    manufacturer: 'vivo',
    model: 'V2219A',
    hardware: 'mt6877',
    socModel: 'MT6877V/TTZA',
  ),
  AndroidPerformanceProfile.mt6877,
);
expect(
  AndroidPerformanceProfileResolver.resolve(
    manufacturer: 'vivo',
    model: 'PD2219',
    hardware: 'unknown',
    socModel: '',
  ),
  AndroidPerformanceProfile.mt6877,
);
expect(
  AndroidPerformanceProfileResolver.resolve(
    manufacturer: 'xiaomi',
    model: '17 Pro',
    hardware: 'qcom',
    socModel: 'SM8850',
  ),
  AndroidPerformanceProfile.standard,
);
```

能力解析测试使用 `manufacturer/model/hardware/socModel/currentRefreshRate/supportedRefreshRates/preferredDisplayModeId`，并验证畸形数字和列表安全回退。

- [ ] **Step 2: 运行测试并确认失败**

```powershell
D:\flutter\bin\flutter.bat test --no-pub `
  test\android_platform_channel_test.dart `
  test\android_tv_capability_test.dart `
  test\android_performance_profile_test.dart
```

Expected: FAIL，缺少新字段、枚举或解析器。

- [ ] **Step 3: 扩展原生 capability Map**

在 `deviceCapabilities()` 增加：

```kotlin
"manufacturer" to Build.MANUFACTURER,
"model" to Build.MODEL,
"hardware" to Build.HARDWARE,
"socModel" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MODEL else "",
"currentRefreshRate" to highRefreshRateController.snapshot.currentRefreshRate.toDouble(),
"supportedRefreshRates" to highRefreshRateController.snapshot.supportedRefreshRates.map { it.toDouble() },
"preferredDisplayModeId" to highRefreshRateController.snapshot.preferredModeId,
```

- [ ] **Step 4: 实现强类型性能档位**

`android_performance_profile.dart` 使用：

```dart
enum AndroidPerformanceProfile { standard, mt6877 }

abstract final class AndroidPerformanceProfileResolver {
  static AndroidPerformanceProfile resolve({
    required String manufacturer,
    required String model,
    required String hardware,
    required String socModel,
  }) {
    final chip = '$hardware $socModel'.toLowerCase();
    if (chip.contains('mt6877')) return AndroidPerformanceProfile.mt6877;
    final maker = manufacturer.trim().toLowerCase();
    final device = model.trim().toLowerCase();
    if (maker == 'vivo' && device.contains('pd2219')) {
      return AndroidPerformanceProfile.mt6877;
    }
    return AndroidPerformanceProfile.standard;
  }
}
```

`AndroidDeviceCapabilities` 添加强类型字段和 `performanceProfile` getter；`unknown` 使用空字符串、0 和空列表。

- [ ] **Step 5: 把能力安装到 AppPlatformCapabilities 并记录日志**

`AppPlatformCapabilities` 增加 `androidPerformanceProfile`、设备标识和刷新率字段，Windows/未知值使用标准档与空值。`loadAppPlatformCapabilities()` 安装后记录：

```dart
AppLogger().i(
  'AndroidPerformance: manufacturer=${device.manufacturer} '
  'model=${device.model} soc=${device.socModel} '
  'refresh=${device.currentRefreshRate} '
  'supported=${device.supportedRefreshRates.join(',')} '
  'preferredMode=${device.preferredDisplayModeId} '
  'profile=${device.performanceProfile.name}',
  forceLog: true,
);
```

仅记录系统公开标识；不记录 Android ID、账号或网盘信息。诊断摘要增加相同的只读字段。

- [ ] **Step 6: 运行聚焦测试并确认通过**

Run Task 4 Step 2 的相同命令。

Expected: PASS，未知/畸形数据使用标准档。

- [ ] **Step 7: 提交设备能力与档位**

```powershell
git add -- android/app/src/main/kotlin/com/kanyingyin/player/MainActivity.kt lib/platform/android/android_device_capabilities.dart lib/platform/android/android_performance_profile.dart lib/platform/app_platform.dart lib/platform/app_platform_io.dart lib/utils/diagnostic_log_exporter.dart test/android_platform_channel_test.dart test/android_tv_capability_test.dart test/android_performance_profile_test.dart
git commit -m '功能：识别天玑930安卓性能档位'
```

### Task 5: 用 TDD 增加天玑 930 夸克专项参数

**Files:**
- Modify: `lib/services/cloud/range/cloud_range_relay_session.dart`
- Modify: `lib/services/cloud/range/cloud_range_relay_service.dart`
- Modify: `lib/services/cloud/quark/quark_range_remote_reader.dart`
- Modify: `test/cloud_range_relay_service_test.dart`
- Modify: `test/cloud_range_relay_session_test.dart`
- Modify: `test/quark_range_remote_reader_test.dart`

- [ ] **Step 1: 写入专项参数和设备隔离失败测试**

构造 MT6877 手机能力：

```dart
final mt6877 = AppPlatformCapabilities.android.copyWith(
  androidPerformanceProfile: AndroidPerformanceProfile.mt6877,
);
final tuning = CloudRangeRelayService.tuningFor(
  capabilities: mt6877,
  providerType: CloudSourceType.quark,
);
expect(tuning.chunkSize, 2 * 1024 * 1024);
expect(tuning.maxChunks, 64);
expect(tuning.maxConcurrentReads, 8);
expect(tuning.maxConcurrentPrefetch, 7);
expect(tuning.prefetchAheadChunks, 14);
expect(tuning.adaptivePolicy?.maxConcurrentReads, 10);
expect(tuning.adaptivePolicy?.maxConcurrentPrefetch, 9);
expect(tuning.adaptivePolicy?.prefetchAheadChunks, 18);
```

同一测试继续断言标准 Android 夸克为原有 `4 MiB、6/5→8/7`，Android TV 为保守档，百度/迅雷/Windows 不变。

- [ ] **Step 2: 写入 10 路升降档失败测试**

复用 `_AdaptiveRangeReader` 创建 `androidQuarkMt6877` 会话，断言：

```dart
expect(session.currentMaxConcurrentReads, 8);
// 前台请求未缓存分段后
expect(session.adaptiveMode, CloudRangeRelayAdaptiveMode.boosted);
expect(session.currentMaxConcurrentReads, 10);
expect(session.currentMaxConcurrentPrefetch, 9);
expect(reader.maxActiveReads, lessThanOrEqualTo(10));
reader.emit(CloudRangeReaderEvent.reconnecting);
expect(session.currentMaxConcurrentReads, 8);
```

- [ ] **Step 3: 运行聚焦测试并确认失败**

```powershell
D:\flutter\bin\flutter.bat test --no-pub `
  test\cloud_range_relay_service_test.dart `
  test\cloud_range_relay_session_test.dart `
  test\quark_range_remote_reader_test.dart
```

Expected: FAIL，缺少专项 tuning，仍返回通用 4 MiB/6/8 档。

- [ ] **Step 4: 实现 MT6877 tuning 和选择逻辑**

在 `CloudRangeRelayTuning` 增加：

```dart
static const androidQuarkMt6877 = CloudRangeRelayTuning(
  chunkSize: 2 * 1024 * 1024,
  maxChunks: 64,
  maxConcurrentReads: 8,
  maxConcurrentPrefetch: 7,
  prefetchAheadChunks: 14,
  adaptivePolicy: CloudRangeRelayAdaptivePolicy(
    maxConcurrentReads: 10,
    maxConcurrentPrefetch: 9,
    prefetchAheadChunks: 18,
  ),
);
```

`tuningFor` 顺序必须是 TV 优先，然后仅对 `providerType == quark && profile == mt6877` 返回专项档，最后落回现有 switch。

- [ ] **Step 5: 把夸克同主机连接容量提高到 10**

`QuarkRangeRemoteReader` 增加强类型构造参数：

```dart
this.maxConnectionsPerHost = 10,
```

并断言大于 0；共享客户端使用：

```dart
..maxConnectionsPerHost = maxConnectionsPerHost
```

调度器继续控制实际活跃读取，因此标准设备仍受 6/8 路限制。

- [ ] **Step 6: 记录脱敏会话配置**

`CloudRangeRelayService.start` 在创建会话前仅记录：

```dart
AppLogger().i(
  'CloudRangeRelayService: provider=$normalizedProviderName '
  'profile=${_capabilities.androidPerformanceProfile.name} '
  'chunkMiB=${tuning.chunkSize ~/ (1024 * 1024)} '
  'baseReads=${tuning.maxConcurrentReads} '
  'boostReads=${tuning.adaptivePolicy?.maxConcurrentReads ?? tuning.maxConcurrentReads}',
);
```

不得记录 `providerKey`、URI、请求头或缓存路径。

- [ ] **Step 7: 运行聚焦测试并确认通过**

Run Task 5 Step 3 的相同命令。

Expected: PASS；现有通用设备和 TV 契约不变。

- [ ] **Step 8: 提交专项传输档位**

```powershell
git add -- lib/services/cloud/range/cloud_range_relay_session.dart lib/services/cloud/range/cloud_range_relay_service.dart lib/services/cloud/quark/quark_range_remote_reader.dart test/cloud_range_relay_service_test.dart test/cloud_range_relay_session_test.dart test/quark_range_remote_reader_test.dart
git commit -m '优化：天玑930启用夸克专项读取档位'
```

### Task 6: 更新 2.1.159 测试版本和用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `android/app/build.gradle.kts`
- Modify: `tool/android/build_signed_release.ps1`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/release_config_contract_test.dart`
- Modify: `test/android_release_packaging_test.dart`
- Modify: `test/android_tv_release_contract_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1: 先把版本契约测试改为预期 2.1.159**

测试统一使用：

```dart
const expectedVersion = '2.1.159';
const expectedBuildNumber = '20159';
const expectedAndroidVersionCode = 20159;
```

并断言 TV 发布仍暂停，手机 Android 为本轮测试交付范围，Windows 只生成 Inno Setup EXE、不生成 MSIX。

- [ ] **Step 2: 运行版本契约并确认失败**

```powershell
D:\flutter\bin\flutter.bat test --no-pub `
  test\version_consistency_test.dart `
  test\version_history_current_test.dart `
  test\release_config_contract_test.dart `
  test\android_release_packaging_test.dart `
  test\android_tv_release_contract_test.dart `
  test\identity_v2_zero_residue_test.dart
```

Expected: FAIL，当前源码仍为 1.0.8/Android 1.0.4。

- [ ] **Step 3: 同步源码和手机 Android 版本**

使用：

```yaml
version: 2.1.159+20159
```

历史 MSIX 兼容字段为 `2.1.159.0`，但不得构建 MSIX。`AppVersion.current`、Android mobile `versionName/versionCode`、Android 打包脚本前置校验同步到 `2.1.159/20159`；不得修改或运行 TV 发布流程。

- [ ] **Step 4: 写入普通用户可见文案**

2.1.159 更新说明使用易懂表述：

```text
- Android 手机界面会优先使用设备支持的高刷新率，滑动和页面切换更顺畅。
- 优化 vivo Y77 等天玑 930 设备读取夸克原画的分片与并发策略，减少高码率视频等待。
- 诊断日志会显示设备刷新率、处理器档位和夸克读取配置，便于继续排查兼容问题。
- 4K HDR 120 帧视频仍取决于手机硬件解码能力；网络变快不代表设备一定能够流畅解码。
```

`RELEASE_NOTES.md`、`version_history.dart` 和 `UPDATE_DIALOG_COPY.md` 保持含义一致；不得宣称 vivo 真机网速已达标，除非后续确有实测。

- [ ] **Step 5: 运行版本契约并确认通过**

Run Task 6 Step 2 的相同命令。

Expected: PASS，Android TV 暂停契约继续通过。

- [ ] **Step 6: 提交版本与文案**

```powershell
git add -- pubspec.yaml lib/core/app_version.dart android/app/build.gradle.kts tool/android/build_signed_release.ps1 RELEASE_NOTES.md lib/utils/version_history.dart UPDATE_DIALOG_COPY.md test/version_consistency_test.dart test/version_history_current_test.dart test/release_config_contract_test.dart test/android_release_packaging_test.dart test/android_tv_release_contract_test.dart test/identity_v2_zero_residue_test.dart
git commit -m '发布：准备2.1.159安卓性能测试版'
```

### Task 7: 执行聚焦回归、完整测试与静态分析

**Files:**
- Verify: entire repository

- [ ] **Step 1: 运行 Android 高刷与能力聚焦测试**

```powershell
Set-Location android
.\gradlew.bat testMobileDebugUnitTest
Set-Location ..
D:\flutter\bin\flutter.bat test --no-pub `
  test\android_platform_channel_test.dart `
  test\android_tv_capability_test.dart `
  test\android_performance_profile_test.dart `
  test\android_player_media_compatibility_test.dart
```

Expected: PASS。

- [ ] **Step 2: 运行夸克中转聚焦测试**

```powershell
D:\flutter\bin\flutter.bat test --no-pub `
  test\cloud_range_relay_service_test.dart `
  test\cloud_range_relay_session_test.dart `
  test\cloud_range_chunk_cache_test.dart `
  test\quark_range_remote_reader_test.dart `
  test\quark_range_relay_service_test.dart `
  test\cloud_playback_resolver_test.dart
```

Expected: PASS，日志不泄露 URI、Cookie、路径或文件 ID。

- [ ] **Step 3: 运行完整 Flutter 测试**

```powershell
D:\flutter\bin\flutter.bat test --no-pub
```

Expected: 所有测试通过，0 failures。

- [ ] **Step 4: 运行静态分析**

```powershell
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: `No issues found!`

### Task 8: 构建并交付 Windows Inno Setup EXE

**Files:**
- Generate: `build/windows/x64/runner/Release/kanyingyin.exe`
- Generate: `C:\Users\asus\Desktop\看影音-2.1.159-测试版-安装程序.exe`

- [ ] **Step 1: 构建 Windows Release**

```powershell
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: 构建成功；Release 主程序 `ProductVersion` 为 2.1.159。

- [ ] **Step 2: 生成 Inno Setup EXE**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_exe_release.ps1
```

Expected: 不生成 MSIX；桌面存在 `看影音-2.1.159-测试版-安装程序.exe`。

- [ ] **Step 3: 验证安装器与 Release 主程序**

```powershell
$releaseExe = Get-Item -LiteralPath 'build\windows\x64\runner\Release\kanyingyin.exe'
$installer = Get-Item -LiteralPath "$env:USERPROFILE\Desktop\看影音-2.1.159-测试版-安装程序.exe"
$releaseExe | Select-Object FullName, Length, @{N='ProductVersion';E={$_.VersionInfo.ProductVersion}}
$installer | Select-Object FullName, Length, @{N='ProductVersion';E={$_.VersionInfo.ProductVersion}}
Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA256
Get-AuthenticodeSignature -LiteralPath $installer.FullName | Select-Object Status, StatusMessage
```

Expected: 两者版本均为 2.1.159；如签名为 `NotSigned`，必须如实报告。

### Task 9: 构建并验证 Android mobile APK/AAB

**Files:**
- Generate: Android mobile Release APK/AAB
- Generate: desktop copies from `tool/android/build_signed_release.ps1`

- [ ] **Step 1: 恢复锁定的 Full media 依赖**

```powershell
D:\flutter\bin\flutter.bat pub get --offline --enforce-lockfile
Select-String -Path '.dart_tool\package_config.json' -Pattern 'third_party/media_kit_libs_android_video_full'
```

Expected: `package_config.json` 指向仓库内 Full Android 原生媒体包；不得解析到默认包。

- [ ] **Step 2: 运行 Android 手机签名构建脚本**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\android\build_signed_release.ps1
```

Expected: 只构建 mobile APK/AAB；不得运行 `tvTest` 或生成 TV 产物。

- [ ] **Step 3: 独立验证 Full 媒体包与产物**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\android\verify_full_media_bundle.ps1
```

随后使用脚本已配置的 ASCII 构建路径核对 `com.kanyingyin.player`、`versionName=2.1.159`、`versionCode=20159`、minSdk 24、targetSdk 36、APK v2、AAB 严格签名、ABI 和桌面副本 SHA-256。

Expected: 所有包级验证通过；不得据此宣称 vivo 真机网速或 120Hz 已通过。

### Task 10: vivo Y77 真机验收与最终提交审计

**Files:**
- Verify: vivo Y77 runtime
- Verify: Git state

- [ ] **Step 1: 安装前记录设备状态**

只有用户明确同意安装或用户自行安装后执行；记录系统 120Hz、省电模式关闭、应用旧版本和测试网络。不得静默安装。

- [ ] **Step 2: 验证冷启动界面高刷**

```powershell
adb shell dumpsys display | Select-String -Pattern '120|refresh|mode' -CaseSensitive:$false
adb shell dumpsys gfxinfo com.kanyingyin.player reset
```

冷启动、不播放视频，连续滚动媒体库并切换页面后：

```powershell
adb shell dumpsys gfxinfo com.kanyingyin.player
```

Expected: 应用请求并实际使用同分辨率最高模式；若系统仍锁 60Hz，保留日志并报告为系统策略未接受，不能伪报成功。

- [ ] **Step 3: 验证夸克专项吞吐**

用本次日志相同账号、文件和网络连续播放至少 60 秒，记录首帧、五秒窗口速度、平均速度、峰值、缓冲、重连和温度。

Expected: 日志命中 `profile=mt6877`、2 MiB、`8→10`；稳定至少 8 MB/s 且不增加重连。10 MB/s 以上是目标，不是自动化保证。

- [ ] **Step 4: 分离解码验收**

普通 1080p/4K 24-60fps 硬解样本应流畅。4K HDR 120fps 样本若仍回退软件解码，明确标记为天玑 930 解码能力未通过，不影响高刷和网络两项独立结论。

- [ ] **Step 5: 复核 Git 和产物状态**

```powershell
git status --short
git log --oneline --decorate -8
git diff --check HEAD~4..HEAD
```

Expected: 只包含本轮相关提交；无未提交相关改动；桌面存在 Windows EXE、Android APK/AAB；没有 TV 或 MSIX 新产物。
