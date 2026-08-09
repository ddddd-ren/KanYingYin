# TMDB 图片网络恢复与 2.1.158 交付 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复部分 Windows 电脑上 TMDB API 可用但 `image.tmdb.org` TLS 握手失败时，本地、网盘和手动匹配候选均无法显示海报的问题，并交付看影音 2.1.158 Windows 测试版 Inno Setup EXE。

**Architecture:** 由 `TmdbEndpointPolicy` 统一判定可恢复传输异常和必须探测的 TMDB API/图片资源组；新增专用 `TmdbImageClient`，复用项目 Dio、代理设置、恢复冷却和会话线路。优先使用 HTTPS；没有可用代理且 HTTPS 仍失败时，仅把不含查询参数的 `image.tmdb.org/t/p/` 公开图片切换到 TMDB 官方 HTTP 备用地址，API 与其他请求不降级。所有 TMDB 图片下载及界面预览均通过该客户端，不使用裸 `HttpClient` 或 `Image.network` 直连；本地和网盘元数据在图片失败时继续保留。

**Tech Stack:** Flutter 3.41.9、Dart、Dio、Flutter Modular、Hive CE、flutter_test、Windows Release、Inno Setup 6。

---

### Task 1: 固定可恢复异常与资源探测策略

**Files:**
- Modify: `test/tmdb_endpoint_policy_test.dart`
- Modify: `lib/services/tmdb/tmdb_endpoint_policy.dart`
- Modify: `lib/utils/proxy_manager.dart`

- [ ] **Step 1: 写失败测试**

在端点策略测试中加入真实日志对应的 `DioExceptionType.unknown + HandshakeException`，并要求代理资源组同时包含 API 主/备域名和图片域名：

```dart
expect(
  TmdbEndpointPolicy.canTryAnotherEndpoint(
    DioException(
      requestOptions: RequestOptions(path: '/poster.jpg'),
      type: DioExceptionType.unknown,
      error: const HandshakeException('Connection terminated during handshake'),
    ),
  ),
  isTrue,
);
expect(
  TmdbEndpointPolicy.requiredResourceProbeGroups['TMDB 图片']!.single.host,
  'image.tmdb.org',
);
```

- [ ] **Step 2: 验证测试因缺少行为而失败**

Run: `D:\flutter\bin\flutter.bat test test\tmdb_endpoint_policy_test.dart`

Expected: FAIL，握手异常未被识别或资源组 API 尚不存在。

- [ ] **Step 3: 最小实现策略**

在 `TmdbEndpointPolicy` 中检查 `HandshakeException`、`SocketException` 和既有 Dio 连接错误；新增只含官方域名的资源探测组。让 `ProxyManager` 直接从该策略建立探测组：

```dart
static final Map<String, List<Uri>> requiredResourceProbeGroups =
    Map<String, List<Uri>>.unmodifiable(<String, List<Uri>>{
  'TMDB API': configurationUris,
  'TMDB 图片': <Uri>[Uri.parse('https://image.tmdb.org')],
});
```

不得关闭系统 TLS 证书校验，不得加入第三方镜像。

- [ ] **Step 4: 运行定向测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test\tmdb_endpoint_policy_test.dart test\network_infrastructure_test.dart`

Expected: PASS。

### Task 2: 建立统一 TMDB 图片客户端

**Files:**
- Create: `lib/services/tmdb/tmdb_image_client.dart`
- Create: `test/tmdb_image_client_test.dart`
- Modify: `lib/services/poster_service.dart`
- Modify: `test/poster_service_test.dart`

- [ ] **Step 1: 写握手恢复失败测试**

注入首次抛出真实 `HandshakeException` 的 Dio、恢复回调和恢复后成功的 Dio 工厂：

```dart
final client = TmdbImageClient(
  dio: failedDio,
  dioFactory: () => recoveredDio,
  recoverProxy: () async => true,
);
expect(await client.downloadBytes(posterUrl), <int>[1, 2, 3]);
expect(recoveryCalls, 1);
expect(factoryCalls, 1);
```

同时验证恢复失败时不循环重试，并保留原始异常。

- [ ] **Step 2: 验证测试因类型不存在而失败**

Run: `D:\flutter\bin\flutter.bat test test\tmdb_image_client_test.dart`

Expected: FAIL，`TmdbImageClient` 尚不存在。

- [ ] **Step 3: 实现最小图片客户端**

客户端通过 `DioFactory` 和 `NetworkSettingsConfigFactory` 创建默认 Dio；单次请求失败后仅在可恢复传输异常时调用一次 `ProxyManager.recoverOnlineResourceProxy()`、重建 Dio 并重试一次。并发恢复复用同一个 Future；日志只记录域名、异常类型和是否恢复，不记录完整图片路径。

- [ ] **Step 4: 让 PosterService 委托统一客户端**

保留现有可注入构造参数兼容测试，将 `_downloadBytes` 的实现收口到 `TmdbImageClient.downloadBytes`，不得改变临时文件、原子替换和旧封面保护行为。

- [ ] **Step 5: 运行图片和海报测试**

Run: `D:\flutter\bin\flutter.bat test test\tmdb_image_client_test.dart test\poster_service_test.dart test\poster_service_download_test.dart`

Expected: PASS。

### Task 3: 接入网盘海报缓存

**Files:**
- Modify: `lib/app/bindings/cloud_bindings.dart`
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `test/network_infrastructure_test.dart`
- Modify: `test/cloud_library_integration_test.dart`

- [ ] **Step 1: 写失败接线契约**

要求两个生产网盘缓存入口都委托 `TmdbImageClient.shared.downloadBytes`，并禁止在对应海报下载函数中创建裸 `HttpClient`。

- [ ] **Step 2: 验证契约失败**

Run: `D:\flutter\bin\flutter.bat test test\network_infrastructure_test.dart`

Expected: FAIL，生产接线仍使用裸 `HttpClient`。

- [ ] **Step 3: 替换生产接线**

```dart
downloader: TmdbImageClient.shared.downloadBytes,
```

保留 `CloudPosterCache` 的锁、临时文件、回滚和来源隔离语义。

- [ ] **Step 4: 运行网盘缓存回归**

Run: `D:\flutter\bin\flutter.bat test test\network_infrastructure_test.dart test\cloud_library_integration_test.dart test\cloud_resource_tmdb_service_test.dart test\cloud_work_tmdb_service_test.dart`

Expected: PASS。

### Task 4: 让手动候选和海报墙使用统一图片加载

**Files:**
- Create: `lib/widgets/tmdb_network_image.dart`
- Create: `test/tmdb_network_image_test.dart`
- Create: `test/tmdb_image_network_contract_test.dart`
- Modify: `lib/pages/tmdb_match_dialog.dart`
- Modify: `lib/pages/local/tmdb_match_sheet.dart`
- Modify: `lib/pages/local/library_sheet.dart`
- Modify: `lib/pages/local/local_series_detail_page.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_episode_sheet.dart`
- Modify: `lib/features/library/presentation/media_category_page.dart`
- Modify: `lib/features/library/presentation/library_media_grid.dart`
- Modify: `lib/features/history/presentation/history_page.dart`

- [ ] **Step 1: 写组件失败测试**

注入返回一像素 PNG 的加载器，要求组件最终使用内存图片；注入异常时要求显示调用方提供的错误占位。再加入源码契约，要求列出的 TMDB 图片界面不再包含 `Image.network(`。

- [ ] **Step 2: 验证测试失败**

Run: `D:\flutter\bin\flutter.bat test test\tmdb_network_image_test.dart test\tmdb_image_network_contract_test.dart`

Expected: FAIL，组件不存在且现有界面仍直连。

- [ ] **Step 3: 实现可注入组件并替换调用点**

`TmdbNetworkImage` 以 URL 为状态键，通过 `TmdbImageClient.shared.downloadBytes` 加载字节并交给 `Image.memory`；URL 变化时刷新 Future，卸载后不更新状态。保留各调用点原有尺寸、裁剪、`BoxFit`、加载占位和破图占位。

- [ ] **Step 4: 运行 UI 回归**

Run: `D:\flutter\bin\flutter.bat test test\tmdb_network_image_test.dart test\tmdb_image_network_contract_test.dart test\tmdb_match_dialog_test.dart test\cloud_tmdb_match_dialog_test.dart test\library_presentation_components_test.dart`

Expected: PASS。

### Task 5: 更新 2.1.158 版本与用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `README.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/release_config_contract_test.dart`

- [ ] **Step 1: 先把版本契约改为 2.1.158**

测试要求 `version: 2.1.158+20158`、历史兼容 `msix_version: 2.1.158.0`、`AppVersion.current = '2.1.158'`，并要求当前用户文案包含“TMDB 海报”“手动匹配”“代理/网络恢复”和“不修改或删除原始视频”。Android 手机当前版本继续保持 1.0.4，但本轮不构建、不打包、不交付 APK/AAB，也不得产生 TV 产物。

- [ ] **Step 2: 验证版本测试失败**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart test\release_config_contract_test.dart`

Expected: FAIL，生产版本仍为 1.0.7。

- [ ] **Step 3: 更新生产版本和普通用户文案**

新增 Windows 2.1.158 测试版条目，说明本地、网盘与手动候选海报在受限网络下会统一恢复代理；必要时只对不含密钥的 TMDB 官方公开图片使用 HTTP 备用地址，并限制重复代理探测；图片失败不影响扫描、匹配和播放。同步 README 当前版本和更新弹窗。

- [ ] **Step 4: 运行版本与安装器契约测试**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart test\release_config_contract_test.dart test\windows_installer_contract_test.dart`

Expected: PASS。

### Task 6: 全量验证和 Windows EXE 交付

**Files:**
- Verify: `build/windows/x64/runner/Release/kanyingyin.exe`
- Output: `%USERPROFILE%/Desktop/看影音-2.1.158-测试版-安装程序.exe`

- [ ] **Step 1: 运行全量测试**

Run: `D:\flutter\bin\flutter.bat test`

Expected: 0 failures。

- [ ] **Step 2: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze`

Expected: No issues found。

- [ ] **Step 3: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release`

Expected: Exit 0，Release 目录包含 `kanyingyin.exe`；本轮不运行任何 Android 构建命令。

- [ ] **Step 4: 核对 Release 主程序版本**

读取 `build/windows/x64/runner/Release/kanyingyin.exe` 的 ProductVersion 和 FileVersion，均必须以 `2.1.158` 开头。

- [ ] **Step 5: 构建并验证 Inno Setup 安装器**

Run: `powershell -ExecutionPolicy Bypass -File tool\windows\installer\build_inno_setup.ps1 -Version 2.1.158`

Expected: 桌面生成且仅生成一个 `看影音-2.1.158-测试版-安装程序.exe`；安装器 ProductVersion 以 2.1.158 开头，并记录长度、SHA-256 和签名状态。不生成 MSIX，不运行 `tvTest`。

- [ ] **Step 6: 再次核对安装状态**

重新查询传统安装记录、已安装 `kanyingyin.exe` 产品版本和旧 MSIX/AppX。除非用户明确要求执行安装，否则不运行安装器；记录现有安装仍为 2.1.157 和未发现旧 MSIX。

### Task 7: 差异审查与提交

**Files:**
- Review: 本计划涉及的全部源文件、测试和发布文案

- [ ] **Step 1: 检查仓库状态和关键差异**

Run: `git status --short`、`git diff --check`、按文件检查关键 diff。

Expected: 只包含本轮 TMDB 图片网络修复、2.1.158 版本和计划/学习记录。

- [ ] **Step 2: 暂存并提交**

Run: `git add <本轮相关文件>`，然后 `git commit -m "修复 TMDB 海报网络并发布 2.1.158"`。

Expected: 提交成功；不包含诊断 ZIP、构建目录、安装器或用户媒体文件。

---

## 开始前安装状态记录

- 查询时间：2026-08-09（Asia/Shanghai）
- 传统安装：`看影音 version 2.1.157`
- 安装目录：`D:\看影音\`
- 已安装主程序：`D:\看影音\kanyingyin.exe`
- ProductVersion / FileVersion：`2.1.157 / 2.1.157`
- 旧 MSIX/AppX：未发现
- 仓库基线：`flutter test` 1884 项通过，0 失败

## 计划自审

- 诊断中的两条失败路径均覆盖：`PosterService` 的未知 TLS 异常、手动候选和网盘缓存绕过代理。
- 所有生产图片域名保持 TMDB 官方域名，不接受无效 HTTPS 证书，不引入第三方转发；HTTP 备用仅限不含密钥和查询参数的公开海报路径。
- 图片失败与元数据、扫描和播放解耦；不会删除或改名本地/网盘原始文件。
- 版本、发布文案、Windows Release、Inno EXE、桌面复制和自动提交均有明确步骤。
- Android TV 发布保持无限期暂停，不构建、不打包、不打标签。
