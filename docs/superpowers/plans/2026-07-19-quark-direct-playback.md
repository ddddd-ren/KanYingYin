# 夸克网盘专属直连播放 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让夸克播放地址解析和 MPV 媒体读取都走直连，并在链接打不开时只自动刷新一次。

**Architecture:** 在网盘播放资源中加入强类型网络路由，默认继承应用代理，夸克显式选择直连。路由经解析器和本地视频控制器传到播放器，由播放器纯函数决定是否设置 MPV `http-proxy`；现有刷新守卫扩展识别 MPV 的 `Failed to open`。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、MobX、media_kit、flutter_test、Windows MSIX

---

## 文件结构

- `lib/services/cloud/cloud_drive_client.dart`：定义网盘播放网络路由并承载提供方返回的路由。
- `lib/services/cloud/cloud_playback_resolver.dart`：将路由和提供方名称传入播放器解析结果，并识别打不开的云链接。
- `lib/services/cloud/quark/quark_drive_client.dart`：把夸克播放资源标记为直连。
- `lib/pages/video/local_video_controller.dart`：把解析结果的网络路由和提供方名称传入播放器参数。
- `lib/pages/player/player_controller.dart`：根据路由决定是否设置 MPV 代理，并生成明确的失败提示。
- `test/cloud_playback_resolver_test.dart`：覆盖路由透传、刷新识别、参数合并和播放策略。
- `test/quark_drive_client_test.dart`：覆盖夸克资源直连标记。
- `test/openlist_client_test.dart`：覆盖 OpenList 默认继承代理。
- `pubspec.yaml`、`lib/core/app_version.dart`、`RELEASE_NOTES.md`、`lib/utils/version_history.dart`：2.1.8 交付信息。

### Task 1: 定义并透传强类型网络路由

**Files:**
- Modify: `lib/services/cloud/cloud_drive_client.dart`
- Modify: `lib/services/cloud/cloud_playback_resolver.dart`
- Test: `test/cloud_playback_resolver_test.dart`

- [ ] **Step 1: 写入失败测试**

在 `test/cloud_playback_resolver_test.dart` 的“点击解析”测试中构造直连资源并断言解析结果：

```dart
resource: CloudPlaybackResource(
  uri: Uri.parse('https://cdn.example.com/live-token'),
  headers: const {'Authorization': 'Bearer token'},
  networkRoute: PlaybackNetworkRoute.direct,
),
// ...
expect(result.networkRoute, PlaybackNetworkRoute.direct);
expect(result.cloudProviderName, 'OpenList');
```

- [ ] **Step 2: 运行测试确认因缺少类型而失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_playback_resolver_test.dart`

Expected: FAIL，提示 `PlaybackNetworkRoute` 或 `networkRoute` 未定义。

- [ ] **Step 3: 最小实现模型和透传**

在 `cloud_drive_client.dart` 增加：

```dart
enum PlaybackNetworkRoute { inheritProxy, direct }

class CloudPlaybackResource {
  const CloudPlaybackResource({
    required this.uri,
    this.headers = const <String, String>{},
    this.expiresAt,
    this.networkRoute = PlaybackNetworkRoute.inheritProxy,
  });

  final PlaybackNetworkRoute networkRoute;
}
```

在 `CloudResolvedPlayback` 增加默认路由和可空提供方名称，并在 `resolve` 返回时传入：

```dart
final PlaybackNetworkRoute networkRoute;
final String? cloudProviderName;

networkRoute: resource.networkRoute,
cloudProviderName: switch (source.type) {
  CloudSourceType.quark => '夸克',
  CloudSourceType.openList => 'OpenList',
},
```

- [ ] **Step 4: 运行测试确认通过**

Run: `D:\flutter\bin\flutter.bat test test\cloud_playback_resolver_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交模型改动**

```powershell
git add -- lib/services/cloud/cloud_drive_client.dart lib/services/cloud/cloud_playback_resolver.dart test/cloud_playback_resolver_test.dart
git commit -m "功能：透传网盘播放网络路由"
```

### Task 2: 夸克选择直连且 OpenList 保持默认

**Files:**
- Modify: `lib/services/cloud/quark/quark_drive_client.dart`
- Test: `test/quark_drive_client_test.dart`
- Test: `test/openlist_client_test.dart`

- [ ] **Step 1: 写入提供方失败测试**

在夸克播放解析测试增加：

```dart
expect(resource.networkRoute, PlaybackNetworkRoute.direct);
```

在 OpenList 播放解析测试增加：

```dart
expect(playback.networkRoute, PlaybackNetworkRoute.inheritProxy);
```

- [ ] **Step 2: 运行测试确认夸克断言失败**

Run: `D:\flutter\bin\flutter.bat test test\quark_drive_client_test.dart test\openlist_client_test.dart`

Expected: FAIL，夸克实际值为 `inheritProxy`。

- [ ] **Step 3: 为夸克资源设置直连**

在 `QuarkDriveClient.resolvePlayback` 返回值中加入：

```dart
networkRoute: PlaybackNetworkRoute.direct,
```

- [ ] **Step 4: 运行提供方测试确认通过**

Run: `D:\flutter\bin\flutter.bat test test\quark_drive_client_test.dart test\openlist_client_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交提供方路由改动**

```powershell
git add -- lib/services/cloud/quark/quark_drive_client.dart test/quark_drive_client_test.dart test/openlist_client_test.dart
git commit -m "修复：夸克播放固定使用直连"
```

### Task 3: 播放器消费路由并保留刷新状态

**Files:**
- Modify: `lib/pages/video/local_video_controller.dart`
- Modify: `lib/pages/player/player_controller.dart`
- Test: `test/cloud_playback_resolver_test.dart`

- [ ] **Step 1: 写入播放器参数失败测试**

在云播放首次解析测试中让解析结果使用 `direct`，并断言初始化参数；在刷新合并测试中断言使用刷新后的路由：

```dart
expect(initialized.single.networkRoute, PlaybackNetworkRoute.direct);
expect(merged.networkRoute, PlaybackNetworkRoute.direct);
expect(
  shouldApplyPlayerProxy(
    proxyEnabled: true,
    networkRoute: PlaybackNetworkRoute.direct,
  ),
  isFalse,
);
expect(
  shouldApplyPlayerProxy(
    proxyEnabled: true,
    networkRoute: PlaybackNetworkRoute.inheritProxy,
  ),
  isTrue,
);
```

- [ ] **Step 2: 运行测试确认参数和纯函数缺失**

Run: `D:\flutter\bin\flutter.bat test test\cloud_playback_resolver_test.dart`

Expected: FAIL，提示 `PlaybackInitParams.networkRoute` 或 `shouldApplyPlayerProxy` 未定义。

- [ ] **Step 3: 最小实现播放器路由**

在 `PlaybackInitParams` 增加：

```dart
final PlaybackNetworkRoute networkRoute;
final String? cloudProviderName;

this.networkRoute = PlaybackNetworkRoute.inheritProxy,
this.cloudProviderName,
```

在 `withOffset`、`mergeRefreshedCloudPlayback` 和 `_cloudParams` 中完整复制这两个字段。增加纯函数：

```dart
bool shouldApplyPlayerProxy({
  required bool proxyEnabled,
  required PlaybackNetworkRoute networkRoute,
}) =>
    proxyEnabled && networkRoute == PlaybackNetworkRoute.inheritProxy;
```

把播放器代理条件改为：

```dart
if (shouldApplyPlayerProxy(
  proxyEnabled: proxyEnable,
  networkRoute: initParams.networkRoute,
)) {
```

- [ ] **Step 4: 运行测试确认通过**

Run: `D:\flutter\bin\flutter.bat test test\cloud_playback_resolver_test.dart test\local_video_controller_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交播放器路由改动**

```powershell
git add -- lib/pages/video/local_video_controller.dart lib/pages/player/player_controller.dart test/cloud_playback_resolver_test.dart test/local_video_controller_test.dart
git commit -m "修复：播放器遵循网盘直连策略"
```

### Task 4: 失败时只刷新一次并显示明确提示

**Files:**
- Modify: `lib/services/cloud/cloud_playback_resolver.dart`
- Modify: `lib/pages/player/player_controller.dart`
- Test: `test/cloud_playback_resolver_test.dart`

- [ ] **Step 1: 写入失败识别与提示测试**

```dart
expect(shouldRefreshCloudLink('Failed to open https://cdn.example.com'), isTrue);
expect(shouldRefreshCloudLink('decoder initialization failed'), isFalse);
expect(
  cloudPlaybackFailureMessage('夸克'),
  '夸克播放地址不可用，请重新登录或稍后重试',
);
expect(
  cloudPlaybackFailureMessage(null),
  '网盘播放地址不可用，请重新登录或稍后重试',
);
```

继续使用现有 `CloudLinkRefreshGuard` 测试，断言同一会话第二次 `Failed to open` 返回 `false`。

- [ ] **Step 2: 运行测试确认新行为失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_playback_resolver_test.dart`

Expected: FAIL，`Failed to open` 尚未识别且提示函数不存在。

- [ ] **Step 3: 最小实现刷新识别和提示**

在 `shouldRefreshCloudLink` 的字符串判断中增加大小写不敏感的 `failed to open`。在播放器文件增加：

```dart
String cloudPlaybackFailureMessage(String? providerName) {
  final label = providerName?.trim();
  return '${label == null || label.isEmpty ? '网盘' : label}播放地址不可用，请重新登录或稍后重试';
}
```

刷新失败提示改为调用该函数；刷新后的第二次错误也使用同一明确提示，刷新守卫仍限制每个媒体会话一次。

- [ ] **Step 4: 运行云播放测试确认通过**

Run: `D:\flutter\bin\flutter.bat test test\cloud_playback_resolver_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交失败恢复改动**

```powershell
git add -- lib/services/cloud/cloud_playback_resolver.dart lib/pages/player/player_controller.dart test/cloud_playback_resolver_test.dart
git commit -m "修复：刷新打不开的夸克播放链接"
```

### Task 5: 更新 2.1.8 交付信息

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: 更新版本号**

```yaml
version: 2.1.8+20108
msix_version: 2.1.8.0
```

并把 `AppVersion.current` 更新为 `2.1.8`。

- [ ] **Step 2: 添加普通用户发布文案**

在发布说明和版本历史顶部加入：夸克播放固定直连、链接打不开时自动刷新一次、明确错误提示、OpenList/TMDB/本地播放不受影响。

- [ ] **Step 3: 格式化并检查交付 diff**

Run: `D:\flutter\bin\dart.bat format lib test`

Run: `git diff --check`

Expected: 格式化成功且 diff 检查无输出。

- [ ] **Step 4: 提交版本信息**

```powershell
git add -- pubspec.yaml lib/core/app_version.dart RELEASE_NOTES.md lib/utils/version_history.dart
git commit -m "发布：准备夸克直连播放 2.1.8"
```

### Task 6: 全量验证、Windows Release 与签名 MSIX

**Files:**
- Verify: `build/windows/x64/runner/Release/kanyingyin.exe`
- Verify: `build/windows/x64/runner/Release/data/app.so`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.8.msix`

- [ ] **Step 1: 执行全量测试与静态分析**

Run: `D:\flutter\bin\flutter.bat test`

Run: `D:\flutter\bin\flutter.bat analyze`

Expected: 测试 0 失败，分析无错误。

- [ ] **Step 2: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: exit code 0，`kanyingyin.exe` 与 `data/app.so` 修改时间属于本轮构建。

- [ ] **Step 3: 生成签名 MSIX**

用 `apply_patch` 临时将 `pubspec.yaml` 的 `sign_msix` 改为 `true`。从 `%USERPROFILE%\.kanyingyin\signing\certificate-password.clixml` 读取 DPAPI 加密密码，仅在当前 PowerShell 进程内解密，然后运行：

```powershell
D:\flutter\bin\dart.bat run msix:create --build-windows false --certificate-path "$env:USERPROFILE\.kanyingyin\signing\certificate.pfx" --certificate-password $plainPassword
```

命令结束后立即用 `apply_patch` 恢复 `sign_msix: false`。

Expected: exit code 0，并在 Release 目录生成新的签名 `.msix`。

- [ ] **Step 4: 验证清单并复制桌面**

解压最终 MSIX，确认 `AppxManifest.xml` 的包标识为 `com.kanyingyin.player`、发布者为 `CN=KanYingYin`、架构为 `x64`、版本为 `2.1.8.0`，且 `AppxSignature.p7x` 存在。用 `Get-AuthenticodeSignature` 确认状态为 `Valid`，随后复制为：

```powershell
$msix = Get-ChildItem -LiteralPath 'build\windows\x64\runner\Release' -Filter '*.msix' -File |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
Copy-Item -LiteralPath $msix.FullName -Destination "$env:USERPROFILE\Desktop\看影音-2.1.8.msix" -Force
```

再次验证桌面包签名为 `Valid`，并确认源包与桌面包 SHA-256 一致。

- [ ] **Step 5: 检查状态并提交遗漏的本轮文件**

Run: `git status --short`

Expected: 只剩用户已有的 `.learnings/ERRORS.md` 与 `.learnings/LEARNINGS.md` 修改；不得暂存或提交它们。
