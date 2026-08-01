# Android 夸克与百度高码率读取优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Android 夸克与百度网盘中转使用六路读取和五路后台预取，同时保持 Windows、迅雷、缓存容量和原始文件不变，并交付 2.1.97 双平台测试版。

**Architecture:** 公共中转启动接口分别传递来源缓存键和强类型 `CloudSourceType`。`CloudRangeRelayService` 根据平台与提供方类型选择调优；会话和读取器继续只消费选定的参数，不改变 Range 协议、缓存文件完整性和租约生命周期。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Test、`dart:io` HttpClient、PowerShell 发布脚本、MSIX、APK/AAB。

---

## 文件职责

- `lib/services/cloud/range/cloud_range_relay_session.dart`：定义标准 Android、Android 高吞吐和 Windows 会话参数，并执行读取调度。
- `lib/services/cloud/range/cloud_range_relay_service.dart`：根据平台与 `CloudSourceType` 选择参数，管理缓存目录和会话租约。
- `lib/services/cloud/cloud_playback_resolver.dart`：把 `CloudSource.id` 作为缓存键、把 `CloudSource.type` 作为提供方类型传给中转。
- `lib/services/cloud/quark/quark_range_relay_service.dart`：兼容旧夸克专用入口并显式传递夸克类型。
- `test/cloud_range_relay_service_test.dart`：验证平台/提供方参数矩阵。
- `test/cloud_range_relay_session_test.dart`：验证五路后台预取和六路总并发。
- `test/cloud_playback_resolver_test.dart`：验证来源 ID 与提供方类型不会混用。
- `test/quark_range_relay_service_test.dart`：验证旧入口传递强类型提供方。
- 版本、发布说明和打包文件：同步 2.1.97、普通用户文案和双平台产物规则。

### Task 1: 用失败测试锁定提供方参数矩阵

**Files:**
- Modify: `test/cloud_range_relay_service_test.dart`
- Modify: `test/cloud_range_relay_session_test.dart`
- Modify: `lib/services/cloud/range/cloud_range_relay_session.dart`
- Modify: `lib/services/cloud/range/cloud_range_relay_service.dart`

- [ ] **Step 1: 写参数选择失败测试**

在 `test/cloud_range_relay_service_test.dart` 中导入平台能力、`CloudSourceType` 和会话参数，并加入：

```dart
test('Android 仅为夸克和百度启用六路高吞吐参数', () {
  final quark = CloudRangeRelayService.tuningFor(
    capabilities: AppPlatformCapabilities.android,
    providerType: CloudSourceType.quark,
  );
  final baidu = CloudRangeRelayService.tuningFor(
    capabilities: AppPlatformCapabilities.android,
    providerType: CloudSourceType.baidu,
  );
  final xunlei = CloudRangeRelayService.tuningFor(
    capabilities: AppPlatformCapabilities.android,
    providerType: CloudSourceType.xunlei,
  );

  for (final tuning in <CloudRangeRelayTuning>[quark, baidu]) {
    expect(tuning.maxConcurrentReads, 6);
    expect(tuning.maxConcurrentPrefetch, 5);
    expect(tuning.prefetchAheadChunks, 10);
    expect(tuning.chunkSize * tuning.maxChunks, 128 * 1024 * 1024);
  }
  expect(xunlei, same(CloudRangeRelayTuning.android));
});

test('Windows 所有提供方继续使用原有参数', () {
  for (final providerType in CloudSourceType.values) {
    expect(
      CloudRangeRelayService.tuningFor(
        capabilities: AppPlatformCapabilities.windows,
        providerType: providerType,
      ),
      same(CloudRangeRelayTuning.windows),
    );
  }
});
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_range_relay_service_test.dart`

Expected: 编译失败，提示 `CloudRangeRelayService.tuningFor` 尚未定义。

- [ ] **Step 3: 写最小参数选择实现**

在 `CloudRangeRelayTuning` 中增加：

```dart
static const androidHighThroughput = CloudRangeRelayTuning(
  chunkSize: 4 * 1024 * 1024,
  maxChunks: 32,
  maxConcurrentReads: 6,
  maxConcurrentPrefetch: 5,
  prefetchAheadChunks: 10,
);
```

在 `CloudRangeRelayService` 中导入 `cloud_source.dart`，增加：

```dart
static CloudRangeRelayTuning tuningFor({
  required AppPlatformCapabilities capabilities,
  required CloudSourceType providerType,
}) {
  if (!capabilities.isAndroid) return CloudRangeRelayTuning.windows;
  return switch (providerType) {
    CloudSourceType.quark || CloudSourceType.baidu =>
      CloudRangeRelayTuning.androidHighThroughput,
    _ => CloudRangeRelayTuning.android,
  };
}
```

- [ ] **Step 4: 运行测试并确认 GREEN**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_range_relay_service_test.dart`

Expected: 参数矩阵测试全部通过。

### Task 2: 强类型传递提供方并接入会话

**Files:**
- Modify: `test/cloud_playback_resolver_test.dart`
- Modify: `test/quark_range_relay_service_test.dart`
- Modify: `lib/services/cloud/range/cloud_range_relay_service.dart`
- Modify: `lib/services/cloud/cloud_playback_resolver.dart`
- Modify: `lib/services/cloud/quark/quark_range_relay_service.dart`

- [ ] **Step 1: 写接口链路失败测试**

为 `cloud_playback_resolver_test.dart` 的所有 `relayStarter` 测试闭包增加 `required providerType`。在夸克、百度、迅雷用例中分别加入：

```dart
expect(providerType, CloudSourceType.quark);
expect(providerType, CloudSourceType.baidu);
expect(providerType, CloudSourceType.xunlei);
```

保留既有 `expect(providerKey, source.id)`，证明缓存键没有改成提供方类型。为 `quark_range_relay_service_test.dart` 增加：

```dart
expect(source, contains('providerType: CloudSourceType.quark'));
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_playback_resolver_test.dart test/quark_range_relay_service_test.dart`

Expected: 编译失败或源码断言失败，因为中转启动接口尚未接收 `providerType`。

- [ ] **Step 3: 修改公共中转接口和调用方**

把启动器定义修改为：

```dart
typedef CloudRangeRelayStarter = Future<CloudRangeRelayPlayback> Function({
  required CloudRangeRemoteReader reader,
  required String providerKey,
  required String providerName,
  required CloudSourceType providerType,
});
```

`CloudRangeRelayService` 保存平台能力并在 `start()` 中传入选定参数：

```dart
final AppPlatformCapabilities _capabilities;

// 构造器初始化
_capabilities = capabilities ?? detectAppPlatform();

// 创建会话
tuning: tuningFor(
  capabilities: _capabilities,
  providerType: providerType,
),
```

`CloudPlaybackResolver` 调用中增加：

```dart
providerType: source.type,
```

`QuarkRangeRelayService` 导入 `cloud_source.dart` 并增加：

```dart
providerType: CloudSourceType.quark,
```

- [ ] **Step 4: 运行接口和参数测试并确认 GREEN**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_playback_resolver_test.dart test/quark_range_relay_service_test.dart test/cloud_range_relay_service_test.dart`

Expected: 全部通过，夸克、百度、迅雷类型断言正确。

### Task 3: 验证高吞吐会话确实提高并发

**Files:**
- Modify: `test/cloud_range_relay_session_test.dart`

- [ ] **Step 1: 写五路后台预取行为测试**

沿用 `_DelayedRangeReader`，加入：

```dart
test('Android 夸克百度高吞吐会话连续播放时达到五路后台预取', () async {
  final highThroughputDirectory =
      await Directory.systemTemp.createTemp('cloud-relay-high-throughput-');
  final highThroughputReader = _DelayedRangeReader(
    totalLength: 64,
    delay: const Duration(milliseconds: 100),
  );
  final highThroughputSession = await CloudRangeRelaySession.start(
    reader: highThroughputReader,
    directory: highThroughputDirectory,
    providerName: '测试网盘',
    tuning: CloudRangeRelayTuning.androidHighThroughput,
    chunkSize: 4,
    maxChunks: 16,
  );
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final request = await client.getUrl(highThroughputSession.uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-19');
    await (await request.close()).drain<void>();
    expect(highThroughputReader.maxActiveReads, greaterThanOrEqualTo(5));
    expect(
      highThroughputReader.maxActiveReads,
      lessThanOrEqualTo(
        CloudRangeRelayTuning.androidHighThroughput.maxConcurrentReads,
      ),
    );
  } finally {
    client.close(force: true);
    await highThroughputSession.close();
  }
});
```

- [ ] **Step 2: 证明行为测试能发现旧参数**

临时把测试中的 `tuning` 指向 `CloudRangeRelayTuning.android`，运行：

`D:\flutter\bin\flutter.bat test --no-pub test/cloud_range_relay_session_test.dart --plain-name "Android 夸克百度高吞吐会话连续播放时达到五路后台预取"`

Expected: FAIL，最大并发小于 5。随后恢复 `androidHighThroughput`。

- [ ] **Step 3: 运行行为测试并确认 GREEN**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_range_relay_session_test.dart`

Expected: 原 Android 三路测试和新增五路测试都通过。

- [ ] **Step 4: 检查实现差异并提交性能改动**

Run: `git diff --check`

只暂存 Task 1-3 的代码和测试，确认不包含设置页用户改动，然后提交：

```powershell
git add -- lib/services/cloud/range/cloud_range_relay_session.dart lib/services/cloud/range/cloud_range_relay_service.dart lib/services/cloud/cloud_playback_resolver.dart lib/services/cloud/quark/quark_range_relay_service.dart test/cloud_range_relay_service_test.dart test/cloud_range_relay_session_test.dart test/cloud_playback_resolver_test.dart test/quark_range_relay_service_test.dart
git commit -m "优化：提升安卓夸克百度网盘读取速度"
```

### Task 4: 以 TDD 同步 2.1.97 双平台发布信息

**Files:**
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/release_config_contract_test.dart`
- Modify: `test/android_release_packaging_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `android/app/build.gradle.kts`
- Modify: `tool/android/build_signed_release.ps1`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: 先更新版本和发布文案测试**

把当前版本期望改为：

```dart
const expectedVersion = '2.1.97';
const expectedBuildNumber = '20197';
```

新增本轮版本历史断言，要求普通文案包含：

```dart
for (final text in <String>[
  'Android',
  '夸克',
  '百度',
  '六路',
  '40 MiB',
  '128 MiB',
  'Windows',
  '迅雷',
  '不会修改或删除',
]) {
  expect(changes, contains(text));
}
```

Android 专用弹窗不得包含 `Windows` 和 `迅雷`。

- [ ] **Step 2: 运行版本测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/release_config_contract_test.dart test/android_release_packaging_test.dart test/identity_v2_zero_residue_test.dart`

Expected: FAIL，仓库仍是 2.1.96。

- [ ] **Step 3: 更新全部版本源和用户文案**

统一修改为：

```text
应用版本：2.1.97
构建号：20197
MSIX 版本：2.1.97.0
Android versionName：2.1.97
Android versionCode：20197
```

`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md` 和 `version_history.dart` 使用普通用户文案：Android 夸克与百度启用最多六路读取、40 MiB 前向窗口，缓存仍为 128 MiB；Windows 和迅雷读取策略不变；不会修改或删除原始文件。

- [ ] **Step 4: 运行版本测试并确认 GREEN**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/release_config_contract_test.dart test/android_release_packaging_test.dart test/identity_v2_zero_residue_test.dart`

Expected: 全部通过。

### Task 5: 全量验证、构建、签名与交付

**Files:**
- Verify: all tracked project files
- Output: `%USERPROFILE%\Desktop\看影音-2.1.97.apk`
- Output: `%USERPROFILE%\Desktop\看影音-2.1.97.aab`
- Output: `%USERPROFILE%\Desktop\看影音-2.1.97.msix`
- Output: `%USERPROFILE%\Desktop\看影音-2.1.97-异机安装包.zip`

- [ ] **Step 1: 运行定向和全量质量门**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_range_relay_service_test.dart test/cloud_range_relay_session_test.dart test/cloud_playback_resolver_test.dart test/quark_range_relay_service_test.dart
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: 测试 0 失败，静态分析 0 问题。

- [ ] **Step 2: 构建并验证 Android 签名产物**

Run: `powershell -ExecutionPolicy Bypass -File tool\android\build_signed_release.ps1`

Expected: APK 与 AAB 版本为 `2.1.97 / 20197`；APK `apksigner verify` 成功；AAB `jarsigner -verify -strict` 返回 0；桌面文件存在且非空。

- [ ] **Step 3: 构建并验证 Windows Release 与 MSIX**

Run: `powershell -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1`

Expected: Windows Release 构建成功；MSIX 清单标识为 `com.kanyingyin.player`、版本 `2.1.97.0`、架构 `x64`；签名状态为 Valid；桌面 MSIX 与异机安装 ZIP 存在。

- [ ] **Step 4: 核对交付物和当前安装版本**

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name, Version
Get-FileHash -Algorithm SHA256 "$env:USERPROFILE\Desktop\看影音-2.1.97.msix"
Get-Item "$env:USERPROFILE\Desktop\看影音-2.1.97.apk", "$env:USERPROFILE\Desktop\看影音-2.1.97.aab", "$env:USERPROFILE\Desktop\看影音-2.1.97.msix", "$env:USERPROFILE\Desktop\看影音-2.1.97-异机安装包.zip" | Select-Object Name, Length, LastWriteTime
```

Expected: 不主动安装新版；已安装版本仍按实测记录，四个交付物非空。

- [ ] **Step 5: 最终差异审查和发布提交**

确认 `git status --short` 中两处用户设置页修改仍未暂存。只暂存 2.1.97 版本与文案文件、计划文件和设计纠正，运行 `git diff --cached --check` 后提交：

```powershell
git commit -m "发布：交付2.1.97安卓网盘读取优化"
```

Expected: 本轮文件已提交；`lib/features/settings/presentation/k_settings_tile.dart` 和 `test/settings_presentation_components_test.dart` 仍保留为用户未提交修改，不推送远端。
