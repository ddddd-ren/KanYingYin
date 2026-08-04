# 项目安全、性能与交付闭环实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 基于项目审查制定安全、性能、架构和交付优化路线；2.1.116 先交付诊断日志隐私保护与双平台版本一致性，其余任务按优先级在后续版本分批落地。

**Architecture:** 安全修复保持本机日志可诊断、对外日志强脱敏；OpenList 公开地址强制 HTTPS，局域网 HTTP 使用独立显式授权。性能优化以不可变派生快照、目录级缓存和局部状态监听替代构建阶段 I/O 与重复全量计算。网盘扫描由单一应用层协调器持有互斥、取消、进度和索引事务，页面控制器只映射状态。

**Tech Stack:** Flutter 3.41.9、Dart、MobX、Flutter Modular、PowerShell、Gradle Kotlin DSL、CMake/CTest、MSIX。

**当前状态：** Task 1、Task 3 和 Task 9 属于 2.1.116 已实施范围；Task 2、Task 4 至 Task 8 是本次项目审查形成的后续优化方案，不计入 2.1.116 更新内容。

**建议顺序：** P0 先完成 Task 2 以及 Task 8 的凭据传递收紧；P1 并行推进 Task 4、Task 5，再推进 Task 6、Task 7；P2 完成 Task 8 其余依赖边界、原生测试和 CI 收口。每个 Task 独立遵循 RED、GREEN、定向回归和提交闭环。

---

### Task 1: 对外诊断日志使用严格脱敏

**Files:**
- Modify: `lib/utils/log_sanitizer.dart`
- Modify: `lib/utils/diagnostic_log_exporter.dart`
- Modify: `test/log_sanitizer_test.dart`
- Modify: `test/diagnostic_log_exporter_test.dart`

- [x] **Step 1: 写入失败测试**

  在 `test/log_sanitizer_test.dart` 增加 `sanitizeForExport` 用例，输入同时包含：

  ```dart
  const input = r'''{"access_token":"json-token","clientSecret":"json-secret"}
cookie=session-value
D:\Users\alice\Videos\私密目录\第 01 集.mkv
\\nas\alice\media\show.mkv''';
  final result = sanitizer.sanitizeForExport(input);
  for (final secret in const <String>[
    'json-token',
    'json-secret',
    'session-value',
    'alice',
    '私密目录',
  ]) {
    expect(result, isNot(contains(secret)));
  }
  expect(result, contains('[REDACTED]'));
  expect(result, contains('[LOCAL_PATH]'));
  ```

  在 `test/diagnostic_log_exporter_test.dart` 导出含上述语料的 ZIP，解包后断言所有文件均不含敏感值。

- [x] **Step 2: 验证测试因 API 和规则缺失而失败**

  Run: `D:\flutter\bin\flutter.bat test test/log_sanitizer_test.dart test/diagnostic_log_exporter_test.dart`

  Expected: FAIL，原因是 `sanitizeForExport` 不存在或外发 ZIP 仍包含敏感语料。

- [x] **Step 3: 实现两级脱敏**

  保留 `sanitize` 的本机路径诊断行为，新增：

  ```dart
  String sanitizeForExport(String input) {
    final sanitized = sanitize(input);
    return _redactLocalPaths(_redactStructuredSecrets(sanitized));
  }
  ```

  结构化凭据规则覆盖带引号 JSON、Map、查询串和 camelCase 的 `accessToken`、`refreshToken`、`clientSecret`、`cookie`、`authorization`、`password`、`apiKey`；完整隐藏多段 Cookie 和 Basic、Digest、AWS4 等 Authorization 值，同时保留同一行后续普通中英文字段。外发路径规则覆盖 Windows 盘符路径、UNC 路径、`/Users/<name>` 和 `/home/<name>`，统一替换为 `[LOCAL_PATH]`。`DiagnosticLogExporter` 的摘要和日志文件全部调用 `sanitizeForExport`。

- [x] **Step 4: 验证并提交**

  Run: `D:\flutter\bin\flutter.bat test test/log_sanitizer_test.dart test/diagnostic_log_exporter_test.dart`

  Commit: `修复诊断日志外发脱敏`

### Task 2: OpenList 凭据传输只允许安全端点

**Files:**
- Modify: `lib/modules/cloud/cloud_source.dart`
- Modify: `lib/services/cloud/openlist/openlist_client.dart`
- Modify: `lib/services/cloud/cloud_provider_registry.dart`
- Modify: `lib/pages/cloud/openlist_source_editor.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `test/openlist_client_test.dart`
- Modify: `test/cloud_provider_registry_test.dart`
- Modify: `test/cloud_source_repository_test.dart`
- Modify: `test/cloud_sources_ui_test.dart`
- Modify: `test/android_manifest_contract_test.dart`
- Modify: `test/android_cloud_platform_contract_test.dart`

- [ ] **Step 1: 写入端点策略失败测试**

  覆盖以下规则：

  ```dart
  expect(
    () => OpenListClient.normalizeBaseUrl('http://drive.example.com'),
    throwsA(isA<CloudDriveException>()),
  );
  expect(
    OpenListClient.normalizeBaseUrl(
      'http://192.168.1.20:5244',
      allowInsecureLocalHttp: true,
    ),
    'http://192.168.1.20:5244',
  );
  expect(
    () => OpenListClient.normalizeBaseUrl(
      'http://8.8.8.8:5244',
      allowInsecureLocalHttp: true,
    ),
    throwsA(isA<CloudDriveException>()),
  );
  ```

  同时覆盖 `CloudSource.allowInsecureLocalHttp` 的 JSON 往返、编辑页显式开关，以及 Android 仅保留支持动态局域网地址所必需的明文传输能力；应用层必须在请求前拒绝未授权或非本地 HTTP 地址。

- [ ] **Step 2: 运行定向测试并确认 RED**

  Run: `D:\flutter\bin\flutter.bat test test/openlist_client_test.dart test/cloud_provider_registry_test.dart test/cloud_sources_ui_test.dart test/android_manifest_contract_test.dart`

- [ ] **Step 3: 实现局域网 HTTP 策略**

  为 `CloudSource` 增加默认 `false` 的 `allowInsecureLocalHttp`。`normalizeBaseUrl` 默认只接受 HTTPS；显式授权时仅接受 localhost、IPv4 回环、RFC1918 IPv4、IPv6 回环、IPv6 ULA 和 link-local 地址。编辑页仅在地址为 HTTP 时显示独立开关和风险确认，不复用“允许自签名证书”。Android Network Security Config 无法对用户运行时填写的局域网 CIDR 地址动态放行，因此清单保留明文传输能力；Dart 端地址策略是请求发出前的强制安全门禁，并由平台契约测试防止旁路。

- [ ] **Step 4: 运行定向测试并提交**

  Commit: `限制 OpenList 明文凭据传输`

### Task 3: Android 测试版本直接跟随 Flutter/Windows 版本

**Files:**
- Modify: `android/app/build.gradle.kts`
- Modify: `tool/android/build_signed_release.ps1`
- Modify: `test/android_release_packaging_test.dart`
- Modify: `test/version_consistency_test.dart`

- [x] **Step 1: 写入失败契约测试**

  测试从根目录 `pubspec.yaml` 解析 `version: 2.1.116+20116`，断言 Gradle 与 PowerShell 都从该字段得到 `versionName=2.1.116`、`versionCode=20116`。发布脚本不再包含 `1.0.5+10005` 或任何固定 Android 版本数字；修改测试 fixture 中的 pubspec version 后，两端解析结果必须同步变化。

- [x] **Step 2: 运行测试并确认 RED**

  Run: `D:\flutter\bin\flutter.bat test test/android_release_packaging_test.dart test/version_consistency_test.dart`

- [x] **Step 3: 实现单一版本源**

  Gradle 从 `rootProject.file("../pubspec.yaml")` 读取唯一 `version:` 行，以严格正则解析语义版本和 build number，并分别赋给 `versionName` 与 `versionCode`。PowerShell 复用同一严格解析结果，将 `$androidVersion` 和 `$androidVersionCode` 直接设为 pubspec 值。删除 Android 对 Windows 历史版本的交叉守卫，保留包名、签名和产物版本验证。

- [x] **Step 4: 验证并提交**

  Commit: `统一 Android 发布版本配置`

### Task 4: 缩小毛玻璃范围并限制海报解码尺寸

**Files:**
- Modify: `lib/pages/menu/adaptive_navigation_shell.dart`
- Modify: `lib/features/settings/presentation/k_settings_section.dart`
- Modify: `lib/features/library/presentation/library_media_grid.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`
- Modify: `lib/pages/local/local_series_detail_page.dart`
- Modify: `test/desktop_shell_test.dart`
- Modify: `test/settings_presentation_components_test.dart`
- Modify: `test/library_presentation_components_test.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 写入失败 Widget 测试**

  桌面内容 `navigation-content-surface` 仍使用 `GlassSurface` 的边框和半透明颜色，但断言 `blurSigma == 0`。海报测试断言本地和网络图片 provider 使用目标解码宽度，网盘海报构建不依赖预先同步判断文件存在。

- [ ] **Step 2: 运行定向测试并确认 RED**

  Run: `D:\flutter\bin\flutter.bat test test/desktop_shell_test.dart test/settings_presentation_components_test.dart test/library_presentation_components_test.dart test/cloud_resources_page_test.dart`

- [ ] **Step 3: 实现渲染优化**

  主内容与设置分区使用 `blurSigma: 0`；导航、标题栏、对话框和 `ImmersiveMediaCard` 底部信息面板继续使用局部模糊。图片组件通过 `ResizeImage.resizeIfNeeded` 或 `cacheWidth` 将解码宽度限制为卡片最大宽度乘设备 DPR。删除 Widget build 路径中的 `existsSync`，直接用 `Image.file` 与 `errorBuilder` 回退网络图片或占位图。

- [ ] **Step 4: 验证并提交**

  Commit: `优化毛玻璃和海报渲染性能`

### Task 5: 缓存本地媒体派生视图

**Files:**
- Modify: `lib/pages/local/local_controller.dart`
- Regenerate: `lib/pages/local/local_controller.g.dart`
- Modify: `lib/pages/local/local_page.dart`
- Modify: `test/local_controller_test.dart`
- Modify: `test/library_presentation_components_test.dart`

- [ ] **Step 1: 写入失败缓存测试**

  连续读取 `currentDirectoryGroups`、`localMediaLibrary`、`combinedMediaLibrary` 和 `localLibraryItemsById` 时断言结果对象相同；修改对应 ObservableList 后断言生成新快照。为 `tmdbPosterUrlForPaths` 使用 5,000 条索引和分组路径，断言只通过路径映射访问匹配条目。

- [ ] **Step 2: 运行测试并确认 RED**

  Run: `D:\flutter\bin\flutter.bat test test/local_controller_test.dart test/library_presentation_components_test.dart`

- [ ] **Step 3: 实现 MobX computed 快照**

  新增 `@computed` 的不可变 `currentDirectoryGroups`、`localLibraryItemsById`、`localMediaLibrary`、`combinedMediaLibrary` 和 `visibleMediaLibrarySeries`。`localLibrarySeriesCount` 复用 `localLibrarySeries.length`。`LocalPage` 在一次 Observer 构建中只读取一次分组快照，搜索仅过滤该快照；`tmdbPosterUrlForPaths` 按规范化路径从 map 取值。

- [ ] **Step 4: 重新生成 MobX 并验证**

  Run: `D:\flutter\bin\dart.bat run build_runner build --delete-conflicting-outputs`

  Run: `D:\flutter\bin\flutter.bat test test/local_controller_test.dart test/library_presentation_components_test.dart`

  Commit: `缓存本地媒体派生视图`

### Task 6: 目录级复用封面和字幕快照

**Files:**
- Modify: `lib/services/local_cover_finder.dart`
- Modify: `lib/services/local_thumbnail_cache.dart`
- Modify: `lib/services/local_subtitle_matcher.dart`
- Modify: `lib/services/local_media_scanner.dart`
- Modify: `lib/services/local_media_indexer.dart`
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `test/local_cover_finder_test.dart`
- Modify: `test/local_subtitle_matcher_test.dart`
- Modify: `test/local_media_scanner_test.dart`

- [ ] **Step 1: 写入失败目录枚举测试**

  使用计数型目录/条目提供器建立同一目录 100 个视频、3 个字幕和 2 张封面。扫描完成后断言主目录仅枚举一次、字幕子目录仅枚举一次，并且所有视频得到相同目录封面或各自匹配字幕。源码契约断言扫描热路径不再包含 `listSync`、`existsSync`、`renameSync`。

- [ ] **Step 2: 运行测试并确认 RED**

  Run: `D:\flutter\bin\flutter.bat test test/local_cover_finder_test.dart test/local_subtitle_matcher_test.dart test/local_media_scanner_test.dart`

- [ ] **Step 3: 实现目录快照**

  `LocalSubtitleMatcher` 暴露不可变 `LocalSubtitleDirectorySnapshot`，每目录异步构建一次并为多个视频评分。`LocalCoverFinder` 优先使用 `findForEntry(video, siblings)`；文件系统 fallback 全部改为异步 API并缓存 Future，遗留海报迁移使用 `exists/create/rename` 的异步版本。Scanner 在处理目录前构建一次字幕快照，并复用当前 `entries` 匹配封面。Controller 回写循环复用注入的 finder，不再逐项 `LocalCoverFinder()`。

- [ ] **Step 4: 验证并提交**

  Commit: `批量复用本地目录媒体快照`

### Task 7: 网盘扫描使用单一协调器并局部刷新进度

**Files:**
- Create: `lib/features/cloud/application/cloud_media_scan_coordinator.dart`
- Modify: `lib/providers/cloud_library_controller.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_controller.dart`
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `lib/app/bindings/cloud_bindings.dart`
- Create: `test/cloud_media_scan_coordinator_test.dart`
- Modify: `test/cloud_library_controller_test.dart`
- Modify: `test/cloud_resources_controller_test.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 写入失败事务测试**

  证明同一时刻只能存在一个来源扫描；两个控制器请求同一来源时复用同一 Future；取消、异常、dispose 后结果不会提交陈旧进度；扫描完成只写一次索引和来源摘要。页面测试统计仅进度变化时海报墙 build 次数保持不变。

- [ ] **Step 2: 运行测试并确认 RED**

  Run: `D:\flutter\bin\flutter.bat test test/cloud_media_scan_coordinator_test.dart test/cloud_library_controller_test.dart test/cloud_resources_controller_test.dart test/cloud_resources_page_test.dart`

- [ ] **Step 3: 实现共享协调器**

  `CloudMediaScanCoordinator` 注入来源仓储、凭据存储、provider registry 与 indexer，拥有 active source、token、progress、result 和单飞 Future。两个 Controller 只调用 `scan(sourceId)`、`cancel(sourceId)` 并订阅不可变状态；删除各自重复的 client/indexer/token 生命周期。CloudResources 页面把进度区域拆为独立 `ListenableBuilder`，海报集合仅在索引 revision 变化时刷新；搜索输入 debounce 200ms。

- [ ] **Step 4: 验证并提交**

  Commit: `统一网盘扫描状态所有权`

### Task 8: 收紧播放器依赖、原生测试和发布脚本

**Files:**
- Modify: `lib/pages/player/player_controller.dart`
- Modify: `lib/app/bindings/playback_bindings.dart`
- Modify: `test/architecture_dependency_test.dart`
- Modify: `windows/CMakeLists.txt`
- Modify: `windows/runner/CMakeLists.txt`
- Modify: `.github/workflows/pr.yaml`
- Create: `tool/windows/release_common.ps1`
- Modify: `tool/windows/build_signed_release.ps1`
- Modify: `tool/windows/build_private_release.ps1`
- Modify: `tool/export_xunlei_build_define.dart`
- Modify: `test/release_config_contract_test.dart`

- [ ] **Step 1: 写入失败架构和发布契约测试**

  断言 `PlayerController` 不导入 Flutter Modular 且 `ShadersController` 为 required 构造依赖。断言 CMake 注册 CTest，PR 工作流只运行一次完整 Dart 套件并分别运行 C++、Kotlin 测试。断言两个 Windows wrapper 调用共享脚本、签名含 RFC3161 `/tr` 与 `/td SHA256`、迅雷凭据不出现在进程参数。

- [ ] **Step 2: 运行契约测试并确认 RED**

  Run: `D:\flutter\bin\flutter.bat test test/architecture_dependency_test.dart test/release_config_contract_test.dart`

- [ ] **Step 3: 实现依赖和交付边界**

  Playback binding 显式注入 `ShadersController`。CMake 调用 `enable_testing()` 并为 `kanyingyin_external_player_tests` 注册 `add_test`。CI 增加 concurrency、原生单元测试和超时，将完整 Dart 测试留在 Windows 质量门禁，Android job 只运行 Gradle 单测与 Debug APK 构建。抽取 Windows 公共构建、签名、清单、ZIP、安装版本报告和清理逻辑；公开/私人 wrapper 只选择是否注入 TMDB。迅雷 define 导出工具默认从进程环境读取凭据，脚本命令行仅传输出路径。

- [ ] **Step 4: 验证并提交**

  Run: `D:\flutter\bin\flutter.bat test test/architecture_dependency_test.dart test/release_config_contract_test.dart`

  Commit: `收紧依赖和发布质量门禁`

### Task 9: 版本 2.1.116、完整门禁与 MSIX 交付

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `README.md`
- Modify: `tool/windows/build_signed_release.ps1`
- Modify: `tool/windows/build_private_release.ps1`
- Modify: `test/signed_release_packaging_test.dart`
- Modify: `test/private_release_packaging_test.dart`
- Modify: version contract tests under `test/`

- [x] **Step 1: 恢复被覆盖的历史并写入版本 RED**

  从 Git 提交 `578b9af` 恢复 `2.1.114` 的 `RELEASE_NOTES.md` 与 `version_history.dart` 条目，保持历史只追加。将 Windows 与 Android 测试版期望统一为 `2.1.116+20116`，Android `versionName/versionCode` 为 `2.1.116/20116`，MSIX 为 `2.1.116.0`，先运行确认 RED。

- [x] **Step 2: 同步版本和普通用户文案**

  更新全部版本来源；发布说明仅涵盖本轮实际交付的诊断隐私、双平台统一版本和不删除用户原始媒体。Windows 与 Android 测试版统一显示 `2.1.116`，Flutter build number 与 Android versionCode 统一为 `20116`。

- [x] **Step 3: 执行完整质量门禁**

  Run: `D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed .`

  Run: `D:\flutter\bin\flutter.bat test`

  Run: `D:\flutter\bin\flutter.bat analyze`

  Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

  Run: `D:\flutter\bin\flutter.bat build apk --release --no-pub`

  Run: `D:\flutter\bin\flutter.bat build appbundle --release --no-pub`

- [x] **Step 4: 生成并独立验证签名 MSIX**

  再次记录 `Get-AppxPackage -Name com.kanyingyin.player`。运行项目签名发布脚本，读取 MSIX `AppxManifest.xml`，确认 Identity `com.kanyingyin.player`、Version `2.1.116.0`、签名有效且带时间戳。将最终包复制为 `%USERPROFILE%\Desktop\看影音-2.1.116.msix`，核对修改时间晚于 Release 的 `app.so`。使用 `aapt` 与签名工具确认 APK/AAB 的包名、`versionName=2.1.116`、`versionCode=20116` 和签名，并复制为 `%USERPROFILE%\Desktop\看影音-2.1.116.apk` 与 `%USERPROFILE%\Desktop\看影音-2.1.116.aab`。

- [x] **Step 5: 最终审查与提交**

  检查 `git status --short` 和关键 diff，只暂存本轮文件。最终提交信息：`发布 2.1.116 统一版本并加强诊断隐私`。
