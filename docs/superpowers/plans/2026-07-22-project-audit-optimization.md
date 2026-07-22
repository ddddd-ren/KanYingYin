# 项目检查问题闭环优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复代理探测 TLS 与 CI 供应链问题，同步产品约束、更新可安全落地的依赖，并交付 2.1.34 Windows MSIX。

**Architecture:** 网络探测客户端构造从 `ProxyManager` 提取为可行为测试的小型工厂，常规业务客户端与 OpenList 显式自签名选项保持不变。CI、文档和依赖采用独立变更批次；现有结构提取成果通过架构测试复核，不做机械式大文件拆分。

**Tech Stack:** Flutter 3.41.9、Dart 3.11.5、Flutter Modular、MobX、GitHub Actions、Windows/MSIX、PowerShell。

---

### Task 1: 代理探测恢复系统 TLS 校验

**Files:**
- Create: `lib/core/network/proxy_probe_http_client_factory.dart`
- Modify: `lib/utils/proxy_manager.dart`
- Test: `test/network_infrastructure_test.dart`

- [ ] **Step 1: 写入失败测试**

在 `network_infrastructure_test.dart` 增加 `RecordingHttpClient`，记录 `connectionTimeout`、`findProxy` 和 `badCertificateCallback` setter；新增两个测试，分别调用：

```dart
const factory = ProxyProbeHttpClientFactory(
  connectionTimeout: Duration(seconds: 5),
);
final direct = RecordingHttpClient();
factory.createDirect(createClient: () => direct);
expect(direct.proxyFor(Uri.parse('https://api.themoviedb.org')), 'DIRECT');
expect(direct.badCertificateCallbackAssigned, isFalse);

final proxied = RecordingHttpClient();
factory.createProxied(
  host: '127.0.0.1',
  port: 7890,
  createClient: () => proxied,
);
expect(
  proxied.proxyFor(Uri.parse('https://api.themoviedb.org')),
  'PROXY 127.0.0.1:7890',
);
expect(proxied.badCertificateCallbackAssigned, isFalse);
```

- [ ] **Step 2: 验证测试因工厂不存在而失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/network_infrastructure_test.dart`

Expected: FAIL，提示 `ProxyProbeHttpClientFactory` 未定义或导入不存在。

- [ ] **Step 3: 写入最小工厂实现**

新文件提供以下公开边界：

```dart
class ProxyProbeHttpClientFactory {
  const ProxyProbeHttpClientFactory({required this.connectionTimeout});

  final Duration connectionTimeout;

  HttpClient createDirect({HttpClient Function()? createClient}) =>
      _create('DIRECT', createClient);

  HttpClient createProxied({
    required String host,
    required int port,
    HttpClient Function()? createClient,
  }) => _create('PROXY $host:$port', createClient);

  HttpClient _create(
    String proxy,
    HttpClient Function()? createClient,
  ) {
    final client = (createClient ?? HttpClient.new)();
    client.connectionTimeout = connectionTimeout;
    client.findProxy = (_) => proxy;
    return client;
  }
}
```

`ProxyManager` 的 `_canReachProbeUrl` 与 `_canReachProbeUrlDirectly` 改用该工厂，删除两处 `badCertificateCallback`，保留请求头、超时、状态码和关闭逻辑。

- [ ] **Step 4: 验证定向测试通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/network_infrastructure_test.dart`

Expected: PASS，所有网络基础设施测试通过。

- [ ] **Step 5: 提交网络修复**

只暂存上述三个文件并提交：`修复代理探测证书校验`。

### Task 2: 固定 GitHub Actions 供应链版本

**Files:**
- Modify: `.github/workflows/pr.yaml`
- Modify: `.github/workflows/release.yaml`
- Modify: `test/windows_ci_workflow_test.dart`

- [ ] **Step 1: 写入失败契约测试**

增加 `_actionReferences`，使用 `RegExp(r'^\s*uses:\s+([^@\s]+)@([^\s#]+)', multiLine: true)` 读取两个工作流的所有 Action，并断言每个版本满足 `RegExp(r'^[0-9a-f]{40}$')`。将旧的 `contains('actions/upload-artifact@v4')` 与 `softprops/action-gh-release@v2` 断言改为只检查 Action 名称。

- [ ] **Step 2: 验证测试因可变标签而失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/windows_ci_workflow_test.dart`

Expected: FAIL，至少报告 `v4` 不是 40 位 SHA。

- [ ] **Step 3: 固定官方标签当前提交**

将工作流引用替换为：

```yaml
uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
uses: subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2 # v2
uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4
uses: signpath/github-action-submit-signing-request@3c306158facd969ebdb385c6845dee38afc2ebf9 # v1.1
uses: softprops/action-gh-release@3bb12739c298aeb8a4eeaf626c5b8d85266b0e65 # v2
```

- [ ] **Step 4: 验证工作流契约测试通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/windows_ci_workflow_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交 CI 修复**

只暂存两个工作流和测试并提交：`固定发布流水线依赖版本`。

### Task 3: 同步项目产品定位

**Files:**
- Modify: `AGENTS.md`
- Test: `test/app_identity_test.dart`

- [ ] **Step 1: 写入失败文档契约测试**

新增测试读取 `AGENTS.md`，断言包含“本地与个人网盘视频媒体库”和“用户自有媒体入口”，同时继续包含“不包含在线搜索、插件规则、WebView 视频解析或在线评论”。

- [ ] **Step 2: 验证旧定位导致测试失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/app_identity_test.dart`

Expected: FAIL，缺少个人网盘定位。

- [ ] **Step 3: 最小修改 AGENTS.md**

将项目定位更新为：

```markdown
- 项目专注本地与个人网盘视频媒体库，个人网盘仅作为用户自有媒体入口；不包含公共在线影视搜索、插件规则、WebView 视频解析或在线评论。
- 使用 TMDB 为本地与个人网盘媒体刮削中文标题、简介、评分、海报、背景图和季集信息。
```

- [ ] **Step 4: 验证文档契约测试通过并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/app_identity_test.dart`

提交：`同步本地与个人网盘项目定位`。

### Task 4: 更新兼容依赖并逐项评估主要版本

**Files:**
- Modify: `pubspec.yaml`（仅成功升级的直接依赖）
- Modify: `pubspec.lock`

- [ ] **Step 1: 更新兼容约束内依赖**

Run: `D:\flutter\bin\flutter.bat pub upgrade`

Expected: 更新 `flutter_cache_manager`、`safe_local_storage`、`uuid` 与 `wakelock_plus_platform_interface`，Git 固定提交不变。

- [ ] **Step 2: 验证兼容依赖**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/network_infrastructure_test.dart test/windows_runtime_stability_test.dart test/widget_test.dart`

Expected: PASS。

- [ ] **Step 3: 依次升级五个直接依赖**

按以下顺序一次只改一个约束并执行 `flutter pub get`、`flutter analyze --no-pub` 与相关测试；失败时恢复该依赖的约束和锁文件条目，再继续下一项：

```yaml
connectivity_plus: ^7.3.0
file_picker: ^11.0.2
flutter_displaymode: ^0.7.0
flutter_volume_controller: ^2.0.1
flutter_modular: ^7.1.0
```

相关测试分别为 `network_infrastructure_test.dart`、所有 `*_picker_test.dart` 与本地导入测试、`displaymode_settings` 所在组件测试、播放器测试、`navigation_config_test.dart` 与 `architecture_dependency_test.dart`。每项必须通过完整静态分析才保留。

- [ ] **Step 4: 完整验证依赖组合并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub`

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: 973 项以上测试全部通过，静态分析 0 问题。

提交：`更新已验证的项目依赖`。

### Task 5: 复核结构优化边界

**Files:**
- Modify only if needed: `lib/pages/player/player_controller.dart`
- Modify only if needed: `lib/pages/local/local_controller.dart`
- Test: `test/architecture_dependency_test.dart`
- Reference: `docs/superpowers/plans/2026-07-19-project-structure-optimization.md`

- [ ] **Step 1: 对照既有计划确认提取组件均已接线**

检查 `LocalLibraryPreferences`、`LocalLibraryMetadataCoordinator`、`SubtitlePreferences`、`TruehdFallbackPolicy`、`PlayerShortcutHandler`、`PlayerOverlayCoordinator` 的生产引用和测试。

- [ ] **Step 2: 运行架构与相关行为测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/architecture_dependency_test.dart test/local_library_preferences_test.dart test/local_library_metadata_coordinator_test.dart test/subtitle_preferences_test.dart test/truehd_fallback_policy_test.dart test/player_shortcut_handler_test.dart test/player_overlay_coordinator_test.dart`

Expected: PASS。若全部组件已接线且无新的跨层依赖，本任务不修改生产代码；行数本身不作为拆分依据。

### Task 6: 升级 2.1.34 并更新用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 先把版本测试期望改为 2.1.34 并验证失败**

将 `expectedVersion` 改为 `2.1.34`、`expectedBuildNumber` 改为 `20134`，新增版本历史测试，要求文案包含“证书校验”“发布流水线”“依赖”“不会修改”。

Run: `D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart`

Expected: FAIL，因为产品版本仍为 2.1.33。

- [ ] **Step 2: 同步全部版本与用户文案**

设置 `version: 2.1.34+20134`、`msix_version: 2.1.34.0`、`AppVersion.current = '2.1.34'`，更新 README 当前版本、更新弹窗、发布说明和版本历史。当前版本文案必须包含测试版、启动、媒体库、播放器、本地与网盘、TMDB、不会修改原始文件。

- [ ] **Step 3: 验证版本测试通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart`

Expected: PASS。

### Task 7: 完整门禁、MSIX 与提交

**Files:**
- No additional product files unless a verification failure requires an in-scope fix.

- [ ] **Step 1: 执行完整质量门禁**

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed .
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

Expected: 全部退出码为 0。

- [ ] **Step 2: 生成并验证签名 MSIX**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1`

Expected: 清单 Identity 为 `com.kanyingyin.player`、Publisher 为 `CN=KanYingYin`、Version 为 `2.1.34.0`，数字签名有效，桌面存在 `看影音-2.1.34.msix`。若本机签名材料不存在，使用项目允许的未签名生成路径并明确记录签名状态，但仍验证清单与桌面文件哈希。

- [ ] **Step 3: 检查并提交本轮交付文件**

运行 `git status --short` 和关键 diff，只暂存本计划相关文件，排除 `.learnings/ERRORS.md` 与 `.learnings/LEARNINGS.md`，提交：`发布项目安全与维护优化测试版`。
