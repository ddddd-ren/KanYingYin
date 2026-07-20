# Baidu Dlink Playback Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为百度官方 dlink 请求补齐必需的 User-Agent，使视频能通过现有本机分段中转进入播放器。

**Architecture:** 固定下载 User-Agent 由 `BaiduRequestPolicy` 定义，`BaiduRangeRemoteReader` 在每次初始、Range、完整流和重定向请求中统一应用。凭据仍只附加到官方初始地址；页面只增加不含链接和令牌的阶段日志。

**Tech Stack:** Flutter 3.41.9、Dart `HttpClient`、flutter_test、本机 HTTP Range 中转、MSIX。

---

## 文件结构

- 修改 `lib/services/cloud/baidu/baidu_request_policy.dart`：定义百度下载 UA。
- 修改 `lib/services/cloud/baidu/baidu_range_remote_reader.dart`：发送 UA。
- 修改 `test/baidu_range_remote_reader_test.dart`：验证远程请求和凭据边界。
- 修改 `lib/pages/cloud/resources/cloud_resources_page.dart`：记录脱敏阶段日志。
- 修改版本、发布说明和一致性测试：交付 2.1.29。

### Task 1: 用失败测试复现缺失 User-Agent

**Files:**
- Modify: `test/baidu_range_remote_reader_test.dart`
- Modify: `lib/services/cloud/baidu/baidu_request_policy.dart`
- Modify: `lib/services/cloud/baidu/baidu_range_remote_reader.dart`

- [ ] **Step 1: 扩展重定向测试**

在“百度读取器只向首始官方地址附加 access_token”测试中分别记录初始与重定向请求：

```dart
firstUserAgent = request.headers.value(HttpHeaders.userAgentHeader);
redirectUserAgent = request.headers.value(HttpHeaders.userAgentHeader);
```

增加断言：

```dart
expect(firstUserAgent, 'pan.baidu.com');
expect(redirectUserAgent, 'pan.baidu.com');
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/baidu_range_remote_reader_test.dart --plain-name "百度读取器只向首始官方地址附加 access_token"`

Expected: FAIL，实际 User-Agent 不是 `pan.baidu.com`。

- [ ] **Step 3: 定义并发送固定 UA**

在 `BaiduRequestPolicy` 增加：

```dart
static const String downloadUserAgent = 'pan.baidu.com';
```

在 `_openResponse` 的重定向循环内部、每次 `getUrl` 后增加：

```dart
request.headers.set(
  HttpHeaders.userAgentHeader,
  BaiduRequestPolicy.downloadUserAgent,
);
```

- [ ] **Step 4: 运行测试并确认 GREEN**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/baidu_range_remote_reader_test.dart --plain-name "百度读取器只向首始官方地址附加 access_token"`

Expected: PASS，且重定向无 Access Token、无 Authorization 的原断言继续通过。

- [ ] **Step 5: 验证完整顺序流**

在“探测返回 200 时顺序流只发起一次无 Range 的完整 GET”中记录 `userAgents` 并断言：

```dart
expect(userAgents, <String?>['pan.baidu.com', 'pan.baidu.com']);
```

Run: `D:\flutter\bin\flutter.bat test --no-pub test/baidu_range_remote_reader_test.dart --plain-name "探测返回 200 时顺序流只发起一次无 Range 的完整 GET"`

Expected: PASS。

- [ ] **Step 6: 提交**

```powershell
git add lib/services/cloud/baidu/baidu_request_policy.dart lib/services/cloud/baidu/baidu_range_remote_reader.dart test/baidu_range_remote_reader_test.dart
git commit -m "修复百度网盘原文件请求头"
```

### Task 2: 增加脱敏播放失败日志

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Test: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 运行页面失败提示基线测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_resources_page_test.dart`

Expected: PASS，现有失败场景仍显示“网盘视频解析或加载失败”。

- [ ] **Step 2: 写入不含敏感值的阶段日志**

导入 `utils/logger.dart`，把 `_play` 的捕获改为：

```dart
} on Object catch (error, stackTrace) {
  AppLogger().w(
    'CloudResourcesPage: playback failed '
    'provider=${source.type.name} sourceId=${source.id} '
    'stage=resolve-or-load errorType=${error.runtimeType}',
    stackTrace: stackTrace,
  );
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('网盘视频解析或加载失败')),
  );
}
```

不得记录 `error.toString()`、完整路径、URL、请求头或凭据。

- [ ] **Step 3: 运行页面测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/cloud_resources_page_test.dart`

Expected: PASS。

- [ ] **Step 4: 提交**

```powershell
git add lib/pages/cloud/resources/cloud_resources_page.dart
git commit -m "补充网盘播放失败阶段日志"
```

### Task 3: 百度与公共中转回归

**Files:**
- Verify: `test/baidu_range_remote_reader_test.dart`
- Verify: `test/baidu_drive_client_test.dart`
- Verify: `test/cloud_playback_resolver_test.dart`
- Verify: `test/cloud_range_relay_service_test.dart`
- Verify: `test/quark_range_remote_reader_test.dart`

- [ ] **Step 1: 运行提供方与公共中转测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/baidu_range_remote_reader_test.dart test/baidu_drive_client_test.dart test/cloud_playback_resolver_test.dart test/cloud_range_relay_service_test.dart test/quark_range_remote_reader_test.dart`

Expected: 全部 PASS；百度请求包含 UA，夸克行为不变。

- [ ] **Step 2: 检查敏感信息**

Run: `rg -n "access-fixture|refresh-fixture|secret-fixture" lib`

Expected: `lib` 中无测试凭据。

### Task 4: 更新 2.1.29 版本与用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `README.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1: 先更新版本测试期望**

```dart
const expectedVersion = '2.1.29';
const expectedBuildNumber = '20129';
```

其余当前版本字面量统一改为 `2.1.29`。

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart`

Expected: FAIL，生产版本仍为 2.1.28。

- [ ] **Step 3: 更新生产版本与文案**

使用以下版本：

```text
pubspec version: 2.1.29+20129
MSIX version: 2.1.29.0
AppVersion.current: 2.1.29
```

在版本历史顶部加入：

```dart
VersionHistory(
  version: '2.1.29',
  date: '2026-07-21',
  isPrerelease: true,
  changes: [
    '本测试版修复百度网盘视频在网页端可播放、但看影音提示解析或加载失败的问题，恢复原文件播放、拖动和切集',
    '本地电视剧刮削会按季度使用 TMDB 对应季海报；季度海报缺失时自动使用整部剧海报',
    '本次不会修改百度网盘文件、目录或本地视频；夸克、OpenList、本地扫描和播放器原有功能保持可用',
  ],
),
```

`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md` 使用同义普通用户文案；README 当前版本改为 2.1.29。

- [ ] **Step 4: 运行测试并确认 GREEN**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md README.md test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git commit -m "发布二点一二十九测试版"
```

### Task 5: 全量质量门禁

**Files:**
- Verify: entire repository

- [ ] **Step 1: 格式化本轮 Dart 文件**

Run: `D:\flutter\bin\dart.bat format lib/services/tmdb/local_tmdb_scrape_service.dart test/local_tmdb_integration_test.dart lib/services/cloud/baidu/baidu_request_policy.dart lib/services/cloud/baidu/baidu_range_remote_reader.dart test/baidu_range_remote_reader_test.dart lib/pages/cloud/resources/cloud_resources_page.dart lib/core/app_version.dart lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart`

Expected: 格式化成功且编码不变。

- [ ] **Step 2: 运行全量测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub`

Expected: 全部 PASS。

- [ ] **Step 3: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`。

- [ ] **Step 4: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: `build\windows\x64\runner\Release` 生成成功。

### Task 6: MSIX、桌面交付与最终提交

**Files:**
- Verify: generated MSIX manifest and desktop package

- [ ] **Step 1: 生成 MSIX**

Run: `D:\flutter\bin\dart.bat run msix:create --build-windows false`

Expected: 生成版本 `2.1.29.0`、标识 `com.kanyingyin.player` 的 x64 MSIX。

- [ ] **Step 2: 验证清单和签名**

解包检查 `AppxManifest.xml`：

```text
Identity Name="com.kanyingyin.player"
Version="2.1.29.0"
ProcessorArchitecture="x64"
```

运行 `Get-AuthenticodeSignature`，Expected: `Valid`。

- [ ] **Step 3: 复制到桌面**

复制为 `C:\Users\asus\Desktop\看影音-2.1.29.msix`，确认文件非空且 SHA-256 与生成文件一致。

- [ ] **Step 4: 最终检查与提交**

Run: `git status --short`，再运行 `git diff --check`。只暂存本轮相关文件，不暂存 `.learnings/ERRORS.md` 和 `.learnings/LEARNINGS.md`。若仍有本轮修正，提交信息使用“完成分季海报与百度播放交付”。

- [ ] **Step 5: 实机验收**

运行 2.1.29，验证截图中的百度视频能够进入播放器，并验证本地同一剧两个季度分别显示对应季海报。若当前环境无法完成真实账号或真实媒体实测，最终报告明确标记“待用户实机复核”。
