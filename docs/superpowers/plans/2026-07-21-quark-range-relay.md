# 夸克分段预读中转实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为夸克原文件播放增加安全的本机 Range 分段中转，使 MPV 获得稳定吞吐、可恢复跳转和可观察的预缓冲状态。

**Architecture:** `QuarkDriveClient` 标记需要中转的夸克原文件，`CloudPlaybackResolver` 通过单例 `QuarkRangeRelayService` 建立带租约的本机播放会话。会话把 MPV 的 HEAD/GET/Range 请求映射成 16 MiB 远程分段，使用 256 MiB LRU 缓存、有限重试和一次鉴权刷新；播放器负责租约切换、专用 MPV 参数和状态展示。

**Tech Stack:** Flutter 3.41.9、Dart `dart:io` HTTP 服务、Flutter Modular、MobX、media_kit、`flutter_test`

---

## 文件结构

- `lib/services/cloud/cloud_playback_transport.dart`：播放传输类型、租约与无敏感信息的中转状态。
- `lib/services/cloud/cloud_drive_client.dart`：为云播放资源增加传输类型。
- `lib/services/cloud/quark/quark_range_relay_protocol.dart`：解析单区间 HTTP Range，并生成标准响应元数据。
- `lib/services/cloud/quark/quark_range_chunk_cache.dart`：16 MiB 分段、单飞加载、LRU 和幂等清理。
- `lib/services/cloud/quark/quark_range_remote_reader.dart`：可信主机校验、远程 206 校验、刷新和重试。
- `lib/services/cloud/quark/quark_range_relay_session.dart`：本机 loopback HTTP 会话、令牌、输出与预取。
- `lib/services/cloud/quark/quark_range_relay_service.dart`：创建、跟踪会话并清理孤立目录。
- `lib/services/cloud/cloud_playback_resolver.dart`：把夸克远程资源转换成本机 URI，并返回租约。
- `lib/pages/video/local_video_controller.dart`：把传输、租约和状态带入播放器参数。
- `lib/pages/player/player_controller.dart`：租约生命周期和中转专用 MPV 参数。
- `lib/pages/video/video_page.dart`：在现有加载区域显示中转状态。
- `test/quark_range_relay_protocol_test.dart`：Range 协议测试。
- `test/quark_range_chunk_cache_test.dart`：缓存与并发测试。
- `test/quark_range_remote_reader_test.dart`：伪远端、刷新和恢复测试。
- `test/quark_range_relay_session_test.dart`：本机服务、安全、预取和清理测试。
- `test/cloud_playback_resolver_test.dart`、`test/quark_drive_client_test.dart`、`test/local_video_controller_test.dart`：集成与回归测试。

### Task 1: 强类型播放传输与租约契约

**Files:**
- Create: `lib/services/cloud/cloud_playback_transport.dart`
- Modify: `lib/services/cloud/cloud_drive_client.dart`
- Modify: `lib/services/cloud/quark/quark_drive_client.dart`
- Modify: `test/quark_drive_client_test.dart`

- [ ] **Step 1: 写失败测试**

在 `test/quark_drive_client_test.dart` 中断言转码链接仍为 `direct`，原文件为 `quarkRangeRelay`：

```dart
expect(resource.transport, CloudPlaybackTransport.quarkRangeRelay);
```

- [ ] **Step 2: 验证测试失败**

Run: `D:\flutter\bin\flutter.bat test test\quark_drive_client_test.dart`

Expected: FAIL，提示 `CloudPlaybackTransport` 或 `transport` 未定义。

- [ ] **Step 3: 实现最小契约**

在新文件中定义：

```dart
enum CloudPlaybackTransport { direct, quarkRangeRelay }

enum QuarkRelayPhase {
  connecting,
  prefetching,
  ready,
  reconnecting,
  degraded,
  failed,
}

class QuarkRelayStatus {
  const QuarkRelayStatus({
    required this.phase,
    this.bytesPerSecond = 0,
    this.receivedBytes = 0,
    this.cachedBytes = 0,
    this.bufferedDuration,
    this.message,
  });

  final QuarkRelayPhase phase;
  final double bytesPerSecond;
  final int receivedBytes;
  final int cachedBytes;
  final Duration? bufferedDuration;
  final String? message;
}

abstract interface class CloudPlaybackLease {
  Stream<QuarkRelayStatus> get statuses;
  Future<void> close();
}
```

给 `CloudPlaybackResource` 增加默认 `CloudPlaybackTransport.direct`，并让 `QuarkDriveClient` 只对 `originalDownload` 返回 `quarkRangeRelay`。

- [ ] **Step 4: 验证测试通过**

Run: `D:\flutter\bin\flutter.bat test test\quark_drive_client_test.dart`

Expected: PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/services/cloud/cloud_playback_transport.dart lib/services/cloud/cloud_drive_client.dart lib/services/cloud/quark/quark_drive_client.dart test/quark_drive_client_test.dart
git commit -m "增加云播放传输契约"
```

### Task 2: 单区间 HTTP Range 协议

**Files:**
- Create: `lib/services/cloud/quark/quark_range_relay_protocol.dart`
- Create: `test/quark_range_relay_protocol_test.dart`

- [ ] **Step 1: 写失败测试**

覆盖 `bytes=0-15`、`bytes=16-`、`bytes=-16`、越界、倒序和多区间：

```dart
expect(parseSingleHttpRange('bytes=16-', 100), const ByteRange(16, 99));
expect(() => parseSingleHttpRange('bytes=0-1,4-5', 100),
    throwsA(isA<RangeNotSatisfiable>()));
```

- [ ] **Step 2: 验证测试失败**

Run: `D:\flutter\bin\flutter.bat test test\quark_range_relay_protocol_test.dart`

Expected: FAIL，协议类型和函数未定义。

- [ ] **Step 3: 实现协议解析**

定义不可变 `ByteRange(start, endInclusive)`、`length`、`contentRange(totalLength)`，以及 `RangeNotSatisfiable`；`parseSingleHttpRange` 只接受 `bytes=` 的单区间并将后缀区间转换为绝对区间。无 Range 的 GET 由会话走 200，不调用解析器。

- [ ] **Step 4: 验证测试通过**

Run: `D:\flutter\bin\flutter.bat test test\quark_range_relay_protocol_test.dart`

Expected: PASS，且 416 分支可获得 `bytes */总长度`。

- [ ] **Step 5: 提交**

```powershell
git add lib/services/cloud/quark/quark_range_relay_protocol.dart test/quark_range_relay_protocol_test.dart
git commit -m "实现本机 Range 协议解析"
```

### Task 3: 16 MiB 分段 LRU 缓存

**Files:**
- Create: `lib/services/cloud/quark/quark_range_chunk_cache.dart`
- Create: `test/quark_range_chunk_cache_test.dart`

- [ ] **Step 1: 写失败测试**

使用 4 字节测试分段和最多 2 段的小配置，验证对齐、同段并发只加载一次、pin 后不淘汰、LRU 淘汰和重复关闭安全：

```dart
final cache = QuarkRangeChunkCache(
  directory: tempDir,
  totalLength: 20,
  chunkSize: 4,
  maxChunks: 2,
);
final first = await Future.wait([
  cache.acquire(1, loader),
  cache.acquire(3, loader),
]);
expect(loadCalls, 1);
```

- [ ] **Step 2: 验证测试失败**

Run: `D:\flutter\bin\flutter.bat test test\quark_range_chunk_cache_test.dart`

Expected: FAIL，缓存类型未定义。

- [ ] **Step 3: 实现缓存**

默认值固定为 `chunkSize = 16 * 1024 * 1024`、`maxChunks = 16`。每个分段保存为随机会话目录内的编号文件；`acquire` 返回含 `RandomAccessFile`、范围和 `release()` 的句柄；用 `Map<int, Future<_ChunkEntry>>` 做单飞，用访问序号做 LRU，引用计数大于零的段不得淘汰。`close()` 取消新加载、关闭句柄并只删除当前会话目录。

- [ ] **Step 4: 验证缓存测试**

Run: `D:\flutter\bin\flutter.bat test test\quark_range_chunk_cache_test.dart`

Expected: PASS，临时目录在关闭后不存在。

- [ ] **Step 5: 提交**

```powershell
git add lib/services/cloud/quark/quark_range_chunk_cache.dart test/quark_range_chunk_cache_test.dart
git commit -m "实现夸克分段缓存"
```

### Task 4: 远程 Range 读取与有限恢复

**Files:**
- Create: `lib/services/cloud/quark/quark_range_remote_reader.dart`
- Modify: `lib/services/cloud/quark/quark_request_policy.dart`
- Create: `test/quark_range_remote_reader_test.dart`

- [ ] **Step 1: 写失败测试**

用 `HttpServer.bind(InternetAddress.loopbackIPv4, 0)` 构造伪远端，验证请求携带正确 Range、206 和 `Content-Range` 校验、401/403/412 只刷新一次、非零起点收到 200 时失败、连接错误按注入 delay 序列重试：

```dart
expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=16-31');
expect(delays, const [Duration(milliseconds: 500), Duration(seconds: 1)]);
```

- [ ] **Step 2: 验证测试失败**

Run: `D:\flutter\bin\flutter.bat test test\quark_range_remote_reader_test.dart`

Expected: FAIL，读取器未定义。

- [ ] **Step 3: 实现远程读取器**

定义 `QuarkRemoteResource(uri, headers, totalLength, contentType)` 和刷新回调 `Future<QuarkRemoteResource> Function()`。读取器关闭自动跳转，逐次验证重定向目标；只允许 HTTPS `drive.quark.cn`、`*.drive.quark.cn`、`pds.quark.cn`、`*.pds.quark.cn`，不向其他主机发送 Cookie。响应必须为 206 且起止和总长度与请求一致；401/403/412 调用一次刷新，连接、TLS、超时使用 500 ms、1 s、2 s 后最多三次重试。

- [ ] **Step 4: 验证读取器测试**

Run: `D:\flutter\bin\flutter.bat test test\quark_range_remote_reader_test.dart`

Expected: PASS；测试日志与异常文本不含 Cookie、完整 URL、令牌和文件 ID。

- [ ] **Step 5: 提交**

```powershell
git add lib/services/cloud/quark/quark_range_remote_reader.dart lib/services/cloud/quark/quark_request_policy.dart test/quark_range_remote_reader_test.dart
git commit -m "实现夸克远程分段读取"
```

### Task 5: 安全的本机中转会话

**Files:**
- Create: `lib/services/cloud/quark/quark_range_relay_session.dart`
- Create: `test/quark_range_relay_session_test.dart`

- [ ] **Step 1: 写失败测试**

用内存字节源验证：仅绑定 `127.0.0.1`、令牌长度至少 32 个十六进制字符、错误路径或 Host 返回 404、HEAD 返回长度、完整 GET 返回 200、单 Range 返回 206、多 Range 返回 416、跨段内容准确、客户端断开后可幂等清理。

```dart
expect(session.uri.host, '127.0.0.1');
expect(session.uri.pathSegments.last.length, greaterThanOrEqualTo(32));
```

- [ ] **Step 2: 验证测试失败**

Run: `D:\flutter\bin\flutter.bat test test\quark_range_relay_session_test.dart`

Expected: FAIL，会话类型未定义。

- [ ] **Step 3: 实现会话**

会话启动时先验证第 0 段并取得总长度，再返回本机 URI；用 `Random.secure()` 生成 16 字节令牌并只监听 IPv4 loopback 随机端口。请求输出按分段句柄流式写入 `HttpResponse` 并等待背压；前台分段优先，最多同时进行一个前台加载和一个预取；启动时预取头尾，顺序读取时预取后两段，不连续跳转时丢弃未被消费的旧预取。

状态以广播流发布 `connecting/prefetching/ready/reconnecting/degraded/failed`，速度为最近 5 秒滑动窗口；状态和错误只含主机、段号、范围、耗时与速度。

- [ ] **Step 4: 验证会话测试**

Run: `D:\flutter\bin\flutter.bat test test\quark_range_relay_session_test.dart`

Expected: PASS，关闭后三秒内服务器不可访问且缓存目录已删除。

- [ ] **Step 5: 提交**

```powershell
git add lib/services/cloud/quark/quark_range_relay_session.dart test/quark_range_relay_session_test.dart
git commit -m "实现夸克本机中转会话"
```

### Task 6: 中转服务与解析器集成

**Files:**
- Create: `lib/services/cloud/quark/quark_range_relay_service.dart`
- Modify: `lib/services/cloud/cloud_playback_resolver.dart`
- Modify: `lib/services/cloud/cloud_cache_directories.dart`
- Modify: `test/cloud_playback_resolver_test.dart`

- [ ] **Step 1: 写失败测试**

注入伪 `QuarkRangeRelayService`，断言夸克原文件返回 `127.0.0.1` URI、空请求头和非空租约；OpenList/转码仍返回远端 URI、原请求头且不创建会话。断言启动清理只删除专属根目录下名称匹配 `quark-relay-*` 且超过 24 小时的目录。

- [ ] **Step 2: 验证测试失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_playback_resolver_test.dart`

Expected: FAIL，解析结果没有传输和租约。

- [ ] **Step 3: 实现服务和解析器接入**

为 `CloudResolvedPlayback` 增加：

```dart
final CloudPlaybackTransport transport;
final CloudPlaybackLease? lease;
```

`QuarkRangeRelayService.start` 接收远端资源和刷新回调，返回包含本机 URI 与租约的结果。刷新回调重新从仓库取来源、创建客户端、解析同一 `CloudPlaybackTarget` 并关闭客户端。解析器只有在 `resource.transport == quarkRangeRelay` 时启动中转；启动尚未输出数据即失败可回退原直连，已启动后错误交给会话处理。服务首次使用时仅清理看影音专属缓存根下超过 24 小时的匹配目录。

- [ ] **Step 4: 验证解析器测试**

Run: `D:\flutter\bin\flutter.bat test test\cloud_playback_resolver_test.dart test\quark_drive_client_test.dart`

Expected: PASS，OpenList 回归行为不变。

- [ ] **Step 5: 提交**

```powershell
git add lib/services/cloud/quark/quark_range_relay_service.dart lib/services/cloud/cloud_playback_resolver.dart lib/services/cloud/cloud_cache_directories.dart test/cloud_playback_resolver_test.dart
git commit -m "接入夸克播放中转服务"
```

### Task 7: 播放器租约生命周期与 MPV 策略

**Files:**
- Modify: `lib/pages/video/local_video_controller.dart`
- Modify: `lib/pages/player/player_controller.dart`
- Create: `lib/features/player/application/cloud_playback_cache_policy.dart`
- Modify: `test/local_video_controller_test.dart`
- Modify: `test/cloud_playback_resolver_test.dart`

- [ ] **Step 1: 写失败测试**

构造记录关闭次数的伪租约，验证初始化失败释放新租约、切集成功后释放旧租约、乱序结果释放被丢弃租约、页面销毁重复调用只关闭一次；验证中转策略映射为：

```dart
const expected = <String, String>{
  'stream-buffer-size': '4MiB',
  'cache-pause-initial': 'yes',
  'cache-pause-wait': '5',
  'cache-secs': '30',
  'demuxer-max-bytes': '256MiB',
  'demuxer-max-back-bytes': '32MiB',
};
```

- [ ] **Step 2: 验证测试失败**

Run: `D:\flutter\bin\flutter.bat test test\local_video_controller_test.dart test\cloud_playback_resolver_test.dart`

Expected: FAIL，播放参数没有租约或策略。

- [ ] **Step 3: 实现生命周期**

给 `PlaybackInitParams` 增加 `transport`、`lease` 和状态流访问，确保 `withOffset` 与 `CloudPlaybackRefreshTransaction.merge` 保留新资源的租约。`PlayerController` 仅在新媒体已接管后关闭旧租约；初始化失败、无效 token、切集丢弃、控制器销毁均关闭对应租约，关闭方法幂等且不阻塞 UI。

把上述六项 MPV 参数集中到 `CloudPlaybackCachePolicy.quarkRelay`，只对 `quarkRangeRelay` 设置，不改变本地和 OpenList 的现有配置。

- [ ] **Step 4: 验证生命周期测试**

Run: `D:\flutter\bin\flutter.bat test test\local_video_controller_test.dart test\cloud_playback_resolver_test.dart`

Expected: PASS，每个租约关闭一次且现有切集测试全部通过。

- [ ] **Step 5: 提交**

```powershell
git add lib/pages/video/local_video_controller.dart lib/pages/player/player_controller.dart lib/features/player/application/cloud_playback_cache_policy.dart test/local_video_controller_test.dart test/cloud_playback_resolver_test.dart
git commit -m "管理中转租约和播放器缓存"
```

### Task 8: 播放器中转状态展示

**Files:**
- Modify: `lib/pages/video/video_page.dart`
- Modify: `lib/pages/video/video_page_controller_interface.dart`
- Create: `test/quark_relay_status_ui_test.dart`

- [ ] **Step 1: 写失败测试**

验证状态文案映射：预取显示“夸克预缓冲中 · 12.3 MB/s”，重连显示“夸克正在重新连接”，低速显示“当前网盘读取速度不足”，ready 连续五秒后隐藏；断言不新增永久控制栏。

- [ ] **Step 2: 验证测试失败**

Run: `D:\flutter\bin\flutter.bat test test\quark_relay_status_ui_test.dart`

Expected: FAIL，状态映射和组件未定义。

- [ ] **Step 3: 接入现有加载区域**

订阅当前租约状态，在现有加载/错误层中渲染文案和速度；取得文件总字节与有效总时长后用 `总字节 / 总时长` 估算消耗速度，最近 5 秒速度低于该值时显示 degraded。ready 稳定五秒沿用现有动画时长和曲线隐藏，换媒体或销毁时取消订阅和定时器。

- [ ] **Step 4: 验证 UI 测试**

Run: `D:\flutter\bin\flutter.bat test test\quark_relay_status_ui_test.dart test\cloud_resources_page_test.dart`

Expected: PASS，现有播放器控件结构断言不变。

- [ ] **Step 5: 提交**

```powershell
git add lib/pages/video/video_page.dart lib/pages/video/video_page_controller_interface.dart test/quark_relay_status_ui_test.dart
git commit -m "显示夸克中转播放状态"
```

### Task 9: 中转完整回归与安全验证

**Files:**
- Modify: `test/quark_range_relay_session_test.dart`
- Modify: `test/quark_range_remote_reader_test.dart`
- Modify: `test/cloud_playback_resolver_test.dart`

- [ ] **Step 1: 增加端到端失败用例**

将伪夸克远端、真实本机中转和本机客户端串联，覆盖头尾预取、跨段 GET、跳转、401 刷新后从原起点续传、并发上限二、客户端提前断开、恶意相似域、错误 Host、错误令牌和日志脱敏。

- [ ] **Step 2: 运行定向测试并修正实现**

Run: `D:\flutter\bin\flutter.bat test test\quark_range_relay_protocol_test.dart test\quark_range_chunk_cache_test.dart test\quark_range_remote_reader_test.dart test\quark_range_relay_session_test.dart test\cloud_playback_resolver_test.dart test\local_video_controller_test.dart`

Expected: 全部 PASS；若失败，只修改对应中转模块和测试，不放宽安全断言。

- [ ] **Step 3: 运行全量测试和静态分析**

Run: `D:\flutter\bin\flutter.bat test`

Expected: 全部测试 PASS。

Run: `D:\flutter\bin\flutter.bat analyze`

Expected: `No issues found!`。

- [ ] **Step 4: 提交**

```powershell
git add lib test
git commit -m "完善夸克中转回归测试"
```

### Task 10: 2.1.27 版本与 MSIX 交付

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `README.md`

- [ ] **Step 1: 写版本一致性失败测试所需版本**

将应用版本改为 `2.1.27+20127`，MSIX 清单版本改为 `2.1.27.0`；普通用户文案说明“夸克原文件新增分段预读，改善 4K 播放卡顿，并显示预缓冲和重连状态”。

- [ ] **Step 2: 运行版本测试**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart`

Expected: PASS，所有版本源一致。

- [ ] **Step 3: 最终全量验证**

Run: `D:\flutter\bin\flutter.bat test`

Expected: 全部测试 PASS。

Run: `D:\flutter\bin\flutter.bat analyze`

Expected: `No issues found!`。

Run: `D:\flutter\bin\flutter.bat build windows --release`

Expected: `build\windows\x64\runner\Release\kanyingyin.exe` 生成成功。

- [ ] **Step 4: 生成并验证 MSIX**

Run: `D:\flutter\bin\dart.bat run msix:create`

Expected: 生成签名的 `2.1.27.0` MSIX。

使用 `Get-AppPackageManifest`/解包清单或项目现有验证脚本核对 Identity 版本为 `2.1.27.0`，用 `Get-AuthenticodeSignature` 验证签名状态有效，并计算 SHA-256。复制到 `C:\Users\asus\Desktop\看影音-2.1.27.msix`。

- [ ] **Step 5: 核对改动并提交**

```powershell
git status --short
git diff --check
git add pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md README.md
git commit -m "发布二点一二十七测试版"
```

Expected: 不包含 `.learnings/ERRORS.md` 和 `.learnings/LEARNINGS.md`，桌面安装包存在且哈希可读取。

## 自检结果

- 规格覆盖：传输边界、16 MiB/256 MiB 缓存、HEAD/GET/Range、安全令牌、可信域、头尾及顺序预取、地址刷新、三次退避、状态 UI、MPV 参数、生命周期、孤立缓存清理、OpenList/本地绕过和 MSIX 交付均有对应任务。
- 占位符扫描：计划不含 TBD、TODO 或“稍后实现”；每项均给出目标接口、命令和预期结果。
- 类型一致性：统一使用 `CloudPlaybackTransport`、`CloudPlaybackLease`、`QuarkRelayStatus`、`QuarkRangeRelayService` 与 `CloudResolvedPlayback.lease`。
