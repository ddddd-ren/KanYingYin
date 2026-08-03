# Android 夸克自适应高速读取 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Android 夸克原画播放在前台缓存跟不上时从六路读取自动提升到八路，并在重连或地址刷新时安全退回基础档。

**Architecture:** `CloudRangeChunkCache` 向会话报告完成命中、进行中复用和新缺块；`CloudRangeRelaySession` 只在 Android 夸克提供的自适应策略存在时切换调度上限。夸克仍使用现有可信 URI、Range 校验和缓存文件链路，百度及其他平台保持现状。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Test、`dart:io` HttpClient、现有 Cloud Range Relay。

---

## 文件职责

- `lib/services/cloud/range/cloud_range_chunk_cache.dart`：报告每次分段获取是缓存命中、复用进行中任务还是新建远程读取，继续负责去重和 LRU 淘汰。
- `lib/services/cloud/range/cloud_range_relay_session.dart`：定义夸克基础/高速参数、运行时升降档、动态读取调度和脱敏状态日志。
- `lib/services/cloud/range/cloud_range_relay_service.dart`：只为 Android 夸克选择自适应参数，保持百度和其他来源现状。
- `lib/services/cloud/quark/quark_range_remote_reader.dart`：把夸克单主机连接容量提高到八路，协议与重试不变。
- `test/cloud_range_chunk_cache_test.dart`：验证三种缓存获取结果和同段去重。
- `test/cloud_range_relay_service_test.dart`：验证平台/提供方参数矩阵。
- `test/cloud_range_relay_session_test.dart`：验证升档、降档、再次升档、并发上限和前台优先。
- `test/quark_range_remote_reader_test.dart`：验证夸克读取器八路连接配置不改变请求协议。
- `test/log_sanitizer_test.dart`：沿用现有脱敏测试，不新增秘密格式。

## 执行顺序

本计划必须先于 `2026-08-03-android-edge-to-edge-system-bars.md` 或与其独立执行；两者均完成后才能执行 `2026-08-03-v2.1.103-integration-delivery.md`。

### Task 1: 用 TDD 增加缓存访问结果

**Files:**
- Modify: `test/cloud_range_chunk_cache_test.dart`
- Modify: `lib/services/cloud/range/cloud_range_chunk_cache.dart`

- [ ] **Step 1: 写完成命中与新缺块的失败测试**

在 `test/cloud_range_chunk_cache_test.dart` 增加：

```dart
test('分段获取区分新缺块和完成缓存命中', () async {
  final accesses = <CloudRangeChunkAccess>[];

  final first = await cache.acquire(
    1,
    loader,
    onAccess: accesses.add,
  );
  await first.release();
  final second = await cache.acquire(
    2,
    loader,
    onAccess: accesses.add,
  );
  await second.release();

  expect(
    accesses,
    <CloudRangeChunkAccess>[
      CloudRangeChunkAccess.miss,
      CloudRangeChunkAccess.cached,
    ],
  );
  expect(loadCalls, 1);
});
```

- [ ] **Step 2: 写进行中任务复用的失败测试**

```dart
test('分段获取报告进行中复用且不重复下载', () async {
  final loadStarted = Completer<void>();
  final allowLoad = Completer<void>();
  final accesses = <CloudRangeChunkAccess>[];

  Future<void> delayedLoader(ByteRange range, File destination) async {
    loadCalls++;
    loadStarted.complete();
    await allowLoad.future;
    await destination.writeAsBytes(
      List<int>.generate(range.length, (index) => range.start + index),
      flush: true,
    );
  }

  final firstFuture = cache.acquire(
    1,
    delayedLoader,
    onAccess: accesses.add,
  );
  await loadStarted.future;
  final secondFuture = cache.acquire(
    3,
    delayedLoader,
    onAccess: accesses.add,
  );
  allowLoad.complete();
  final handles = await Future.wait([firstFuture, secondFuture]);

  expect(
    accesses,
    <CloudRangeChunkAccess>[
      CloudRangeChunkAccess.miss,
      CloudRangeChunkAccess.inFlight,
    ],
  );
  expect(loadCalls, 1);
  await handles[0].release();
  await handles[1].release();
});
```

同时在测试文件顶部增加 `import 'dart:async';`。

- [ ] **Step 3: 运行测试并确认 RED**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_range_chunk_cache_test.dart
```

Expected: 编译失败，提示 `CloudRangeChunkAccess` 和 `onAccess` 尚未定义。

- [ ] **Step 4: 写最小缓存访问实现**

在 `cloud_range_chunk_cache.dart` 增加：

```dart
enum CloudRangeChunkAccess { cached, inFlight, miss }

typedef CloudRangeChunkAccessListener = void Function(
  CloudRangeChunkAccess access,
);
```

把 `acquire` 签名改为：

```dart
Future<CloudRangeChunkHandle> acquire(
  int byteOffset,
  CloudRangeChunkLoader loader, {
  CloudRangeChunkAccessListener? onAccess,
}) async {
```

在三个分支开始远程等待前同步报告结果：

```dart
final cached = _entries[chunkIndex];
if (cached != null) {
  onAccess?.call(CloudRangeChunkAccess.cached);
  return _pin(cached);
}

final loading = _inFlight[chunkIndex];
if (loading != null) {
  onAccess?.call(CloudRangeChunkAccess.inFlight);
  return _pin(await loading);
}

onAccess?.call(CloudRangeChunkAccess.miss);
final future = _makeRoomAndLoad(chunkIndex, loader);
```

- [ ] **Step 5: 运行缓存测试并确认 GREEN**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_range_chunk_cache_test.dart
```

Expected: 原有缓存测试和两个新增测试全部通过。

- [ ] **Step 6: 检查并提交缓存信号**

```powershell
git diff --check
git add -- lib/services/cloud/range/cloud_range_chunk_cache.dart test/cloud_range_chunk_cache_test.dart
git commit -m "功能：报告网盘分段缓存压力"
```

Expected: 只提交缓存实现和测试。

### Task 2: 用 TDD 定义 Android 夸克自适应参数

**Files:**
- Modify: `test/cloud_range_relay_service_test.dart`
- Modify: `lib/services/cloud/range/cloud_range_relay_session.dart`
- Modify: `lib/services/cloud/range/cloud_range_relay_service.dart`

- [ ] **Step 1: 把参数矩阵测试改为夸克自适应、百度固定高速**

将现有“Android 仅为夸克和百度启用六路高吞吐参数”替换为：

```dart
test('Android 仅为夸克启用八路自适应上限和192MiB缓存', () {
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

  expect(quark.maxConcurrentReads, 6);
  expect(quark.maxConcurrentPrefetch, 5);
  expect(quark.prefetchAheadChunks, 10);
  expect(quark.chunkSize * quark.maxChunks, 192 * 1024 * 1024);
  expect(quark.adaptivePolicy?.maxConcurrentReads, 8);
  expect(quark.adaptivePolicy?.maxConcurrentPrefetch, 7);
  expect(quark.adaptivePolicy?.prefetchAheadChunks, 14);

  expect(baidu, same(CloudRangeRelayTuning.androidHighThroughput));
  expect(baidu.adaptivePolicy, isNull);
  expect(baidu.chunkSize * baidu.maxChunks, 128 * 1024 * 1024);
  expect(xunlei, same(CloudRangeRelayTuning.android));
});
```

保留 Windows 全提供方使用 `CloudRangeRelayTuning.windows` 的测试。

- [ ] **Step 2: 运行参数测试并确认 RED**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_range_relay_service_test.dart
```

Expected: 编译失败，提示 `adaptivePolicy` 尚未定义。

- [ ] **Step 3: 增加不可变自适应策略类型**

在 `cloud_range_relay_session.dart` 的 `CloudRangeRelayTuning` 前增加：

```dart
class CloudRangeRelayAdaptivePolicy {
  const CloudRangeRelayAdaptivePolicy({
    required this.maxConcurrentReads,
    required this.maxConcurrentPrefetch,
    required this.prefetchAheadChunks,
  })  : assert(maxConcurrentReads > 0),
        assert(maxConcurrentPrefetch > 0),
        assert(maxConcurrentPrefetch < maxConcurrentReads),
        assert(prefetchAheadChunks >= maxConcurrentPrefetch);

  final int maxConcurrentReads;
  final int maxConcurrentPrefetch;
  final int prefetchAheadChunks;
}
```

给 `CloudRangeRelayTuning` 构造器和字段增加：

```dart
this.adaptivePolicy,

final CloudRangeRelayAdaptivePolicy? adaptivePolicy;
```

并定义：

```dart
static const androidQuarkAdaptive = CloudRangeRelayTuning(
  chunkSize: 4 * 1024 * 1024,
  maxChunks: 48,
  maxConcurrentReads: 6,
  maxConcurrentPrefetch: 5,
  prefetchAheadChunks: 10,
  adaptivePolicy: CloudRangeRelayAdaptivePolicy(
    maxConcurrentReads: 8,
    maxConcurrentPrefetch: 7,
    prefetchAheadChunks: 14,
  ),
);
```

- [ ] **Step 4: 只为 Android 夸克选择新参数**

将 `CloudRangeRelayService.tuningFor` 的 Android 分支改为：

```dart
return switch (providerType) {
  CloudSourceType.quark => CloudRangeRelayTuning.androidQuarkAdaptive,
  CloudSourceType.baidu => CloudRangeRelayTuning.androidHighThroughput,
  _ => CloudRangeRelayTuning.android,
};
```

- [ ] **Step 5: 运行参数测试并确认 GREEN**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_range_relay_service_test.dart test/cloud_range_relay_session_test.dart
```

Expected: 参数矩阵通过，现有 Windows、Android 和百度固定高速行为测试不回归。

- [ ] **Step 6: 提交参数选择**

```powershell
git diff --check
git add -- lib/services/cloud/range/cloud_range_relay_session.dart lib/services/cloud/range/cloud_range_relay_service.dart test/cloud_range_relay_service_test.dart
git commit -m "功能：定义安卓夸克自适应读取档位"
```

### Task 3: 用 TDD 实现会话升档、降档与动态调度

**Files:**
- Modify: `test/cloud_range_relay_session_test.dart`
- Modify: `lib/services/cloud/range/cloud_range_relay_session.dart`

- [ ] **Step 1: 为测试读取器增加可控事件流**

在 `cloud_range_relay_session_test.dart` 增加：

```dart
class _AdaptiveRangeReader extends _DelayedRangeReader {
  _AdaptiveRangeReader({
    required super.totalLength,
    required super.delay,
  });

  final StreamController<CloudRangeReaderEvent> eventController =
      StreamController<CloudRangeReaderEvent>.broadcast(sync: true);

  static const secretUri = 'https://secret.example/video?id=private';
  static const secretCookie = 'Cookie: secret-cookie';

  @override
  Stream<CloudRangeReaderEvent> get events => eventController.stream;

  void emit(CloudRangeReaderEvent event) => eventController.add(event);

  @override
  String toString() => '$secretUri $secretCookie chunk-private-path';

  @override
  Future<void> close() async {
    await eventController.close();
  }
}
```

`_DelayedRangeReader` 当前已经可以继承，不修改其余现有行为。覆盖 `toString` 是为了证明状态日志不会间接输出读取器中的资源地址、Cookie 或缓存路径。

- [ ] **Step 2: 写升档和重新连接降档失败测试**

```dart
test('夸克前台未命中升为八路且重连后退回六路', () async {
  final adaptiveDirectory =
      await Directory.systemTemp.createTemp('cloud-relay-adaptive-');
  final adaptiveReader = _AdaptiveRangeReader(
    totalLength: 512,
    delay: const Duration(milliseconds: 100),
  );
  final logs = <String>[];
  final adaptiveSession = await CloudRangeRelaySession.start(
    reader: adaptiveReader,
    directory: adaptiveDirectory,
    providerName: '夸克',
    tuning: CloudRangeRelayTuning.androidQuarkAdaptive,
    chunkSize: 4,
    maxChunks: 48,
    log: logs.add,
  );
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    expect(adaptiveSession.adaptiveMode, CloudRangeRelayAdaptiveMode.base);
    expect(adaptiveSession.currentMaxConcurrentReads, 6);

    final request = await client.getUrl(adaptiveSession.uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=64-95');
    await (await request.close()).drain<void>();

    expect(adaptiveSession.adaptiveMode, CloudRangeRelayAdaptiveMode.boosted);
    expect(adaptiveSession.currentMaxConcurrentReads, 8);
    expect(adaptiveSession.currentMaxConcurrentPrefetch, 7);
    final combined = logs.join('\n');
    expect(combined, contains('foreground_cache_pressure'));
    expect(combined, isNot(contains(_AdaptiveRangeReader.secretUri)));
    expect(combined, isNot(contains(_AdaptiveRangeReader.secretCookie)));
    expect(combined, isNot(contains('chunk-private-path')));

    adaptiveReader.emit(CloudRangeReaderEvent.reconnecting);
    expect(adaptiveSession.adaptiveMode, CloudRangeRelayAdaptiveMode.base);
    expect(adaptiveSession.currentMaxConcurrentReads, 6);
    expect(logs.join('\n'), contains('reconnecting'));
  } finally {
    client.close(force: true);
    await adaptiveSession.close();
  }
});
```

“前台缓存压力”包括 `inFlight` 和 `miss`，但不包括已完成的 `cached`；这样播放器追上仍在预取的分段时也能及时升档。

- [ ] **Step 3: 写再次升档与并发上限失败测试**

```dart
test('夸克降档后再次出现前台缓存压力可以重新升档', () async {
  final adaptiveDirectory =
      await Directory.systemTemp.createTemp('cloud-relay-readaptive-');
  final adaptiveReader = _AdaptiveRangeReader(
    totalLength: 512,
    delay: const Duration(milliseconds: 100),
  );
  final logs = <String>[];
  final adaptiveSession = await CloudRangeRelaySession.start(
    reader: adaptiveReader,
    directory: adaptiveDirectory,
    providerName: '夸克',
    tuning: CloudRangeRelayTuning.androidQuarkAdaptive,
    chunkSize: 4,
    maxChunks: 48,
    log: logs.add,
  );
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final first = await client.getUrl(adaptiveSession.uri);
    first.headers.set(HttpHeaders.rangeHeader, 'bytes=64-95');
    await (await first.close()).drain<void>();
    expect(adaptiveSession.adaptiveMode, CloudRangeRelayAdaptiveMode.boosted);

    adaptiveReader.emit(CloudRangeReaderEvent.refreshing);
    expect(adaptiveSession.adaptiveMode, CloudRangeRelayAdaptiveMode.base);

    final second = await client.getUrl(adaptiveSession.uri);
    second.headers.set(HttpHeaders.rangeHeader, 'bytes=256-287');
    await (await second.close()).drain<void>();

    expect(adaptiveSession.adaptiveMode, CloudRangeRelayAdaptiveMode.boosted);
    expect(adaptiveSession.currentMaxConcurrentReads, 8);
    expect(adaptiveReader.maxActiveReads, lessThanOrEqualTo(8));
    expect(logs.join('\n'), contains('refreshing'));
  } finally {
    client.close(force: true);
    await adaptiveSession.close();
  }
});
```

第二次 Range 使用远离首次请求及其前向预取区间的中部分段，不能使用启动时已预取的首段或尾段。

- [ ] **Step 4: 运行会话测试并确认 RED**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_range_relay_session_test.dart
```

Expected: 编译失败，提示自适应模式、动态并发 getter 和 `log` 参数尚未定义。

- [ ] **Step 5: 增加会话模式与可注入日志**

在 `cloud_range_relay_session.dart` 增加：

```dart
import 'package:kanyingyin/utils/logger.dart';

enum CloudRangeRelayAdaptiveMode { base, boosted }

typedef CloudRangeRelayLog = void Function(String message);
```

给 `start` 增加可选日志，并在创建私有会话时注入默认实现：

```dart
CloudRangeRelayLog? log,

final session = CloudRangeRelaySession._(
  reader: reader,
  directory: directory,
  providerName: providerName,
  tuning: tuning,
  chunkSize: chunkSize ?? tuning.chunkSize,
  maxChunks: maxChunks ?? tuning.maxChunks,
  log: log ?? ((message) => AppLogger().i(message)),
);
```

私有构造器增加 `required CloudRangeRelayLog log`，并在初始化列表和字段中保存：

```dart
_log = log,

final CloudRangeRelayLog _log;
```

增加可观测但只读的当前状态：

```dart
var _adaptiveMode = CloudRangeRelayAdaptiveMode.base;

CloudRangeRelayAdaptiveMode get adaptiveMode => _adaptiveMode;
int get currentMaxConcurrentReads => _scheduler.maxConcurrent;
int get currentMaxConcurrentPrefetch => _scheduler.maxConcurrentPrefetch;
```

- [ ] **Step 6: 让读取调度器支持运行时更新上限**

把 `_ReadScheduler` 的构造器和上限改为私有可变字段与只读 getter：

```dart
_ReadScheduler({
  required int maxConcurrent,
  required int maxConcurrentPrefetch,
})  : assert(maxConcurrent > 0),
      assert(maxConcurrentPrefetch >= 0),
      assert(maxConcurrentPrefetch < maxConcurrent),
      _maxConcurrent = maxConcurrent,
      _maxConcurrentPrefetch = maxConcurrentPrefetch;

int _maxConcurrent;
int _maxConcurrentPrefetch;

int get maxConcurrent => _maxConcurrent;
int get maxConcurrentPrefetch => _maxConcurrentPrefetch;

void updateLimits({
  required int maxConcurrent,
  required int maxConcurrentPrefetch,
}) {
  if (_closed) return;
  if (maxConcurrent <= 0 ||
      maxConcurrentPrefetch < 0 ||
      maxConcurrentPrefetch >= maxConcurrent) {
    throw ArgumentError('读取并发参数无效');
  }
  _maxConcurrent = maxConcurrent;
  _maxConcurrentPrefetch = maxConcurrentPrefetch;
  _drain();
}
```

`_drain` 使用 getter 或私有字段。降低上限时不取消活动请求，只阻止新任务启动，直到活动数回到新上限内。

- [ ] **Step 7: 在缓存压力发生前升档**

把 `_acquireChunk` 的缓存调用改为：

```dart
final handle = await cache.acquire(
  offset,
  (range, destination) async {
    await _scheduler.run(priority, () async {
      final stopwatch = Stopwatch()..start();
      await _reader.readTo(range, destination);
      stopwatch.stop();
      _recordTransfer(range.length, stopwatch.elapsed);
    });
  },
  onAccess: (access) {
    if (priority == _ReadPriority.foreground &&
        access != CloudRangeChunkAccess.cached) {
      _boostForForegroundPressure();
    }
  },
);
```

实现升档：

```dart
void _boostForForegroundPressure() {
  final policy = tuning.adaptivePolicy;
  if (policy == null ||
      _adaptiveMode == CloudRangeRelayAdaptiveMode.boosted) {
    return;
  }
  _adaptiveMode = CloudRangeRelayAdaptiveMode.boosted;
  _scheduler.updateLimits(
    maxConcurrent: policy.maxConcurrentReads,
    maxConcurrentPrefetch: policy.maxConcurrentPrefetch,
  );
  _logAdaptiveTransition('foreground_cache_pressure');
}
```

预取距离改为当前模式 getter：

```dart
int get _prefetchAheadChunks =>
    _adaptiveMode == CloudRangeRelayAdaptiveMode.boosted
        ? tuning.adaptivePolicy!.prefetchAheadChunks
        : tuning.prefetchAheadChunks;
```

`_launchSequentialPrefetch` 循环使用 `_prefetchAheadChunks`。

- [ ] **Step 8: 在读取器事件发生时降档**

在 `_reader.events.listen` 中先调用：

```dart
_returnToBase(event.name);
```

实现：

```dart
void _returnToBase(String reason) {
  if (_adaptiveMode == CloudRangeRelayAdaptiveMode.base) return;
  _adaptiveMode = CloudRangeRelayAdaptiveMode.base;
  _scheduler.updateLimits(
    maxConcurrent: tuning.maxConcurrentReads,
    maxConcurrentPrefetch: tuning.maxConcurrentPrefetch,
  );
  _logAdaptiveTransition(reason);
}
```

日志正文固定为不含资源信息的字段：

```dart
void _logAdaptiveTransition(String reason) {
  _log(
    'CloudRangeRelaySession: provider=$providerName '
    'mode=${_adaptiveMode.name} '
    'maxReads=$currentMaxConcurrentReads '
    'maxPrefetch=$currentMaxConcurrentPrefetch reason=$reason',
  );
}
```

在 `_close()` 设置 `_closed = true` 后增加一次仅限自适应会话的关闭日志：

```dart
if (tuning.adaptivePolicy != null) {
  _log(
    'CloudRangeRelaySession: provider=$providerName '
    'event=session_closed receivedBytes=$_receivedBytes '
    'mode=${_adaptiveMode.name}',
  );
}
```

在首个自适应测试的 `finally` 结束后增加：

```dart
expect(logs.join('\n'), contains('event=session_closed'));
expect(logs.join('\n'), contains('receivedBytes='));
```

日志不得拼接 `_reader`、URI、请求头或缓存路径。

- [ ] **Step 9: 运行会话测试并确认 GREEN**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_range_relay_session_test.dart test/cloud_range_chunk_cache_test.dart
```

Expected: 升降档测试通过；现有协议、速度聚合和并发测试全部通过。

- [ ] **Step 10: 提交自适应调度**

```powershell
git diff --check
git add -- lib/services/cloud/range/cloud_range_relay_session.dart test/cloud_range_relay_session_test.dart
git commit -m "优化：自适应提升安卓夸克读取并发"
```

### Task 4: 把夸克连接容量提高到八路并锁定脱敏边界

**Files:**
- Modify: `test/quark_range_remote_reader_test.dart`
- Modify: `lib/services/cloud/quark/quark_range_remote_reader.dart`
- Modify: `test/cloud_range_relay_session_test.dart`

- [ ] **Step 1: 写连接容量失败测试**

在 `quark_range_remote_reader_test.dart` 增加源码契约测试：

```dart
test('夸克读取器允许自适应调度使用八路连接', () {
  final source = File(
    'lib/services/cloud/quark/quark_range_remote_reader.dart',
  ).readAsStringSync();

  expect(source, contains('..maxConnectionsPerHost = 8'));
  expect(source, contains("..findProxy = (_) => 'DIRECT'"));
  expect(source, contains('..autoUncompress = false'));
});
```

如果文件尚未导入 `dart:io`，补充该导入。

- [ ] **Step 2: 锁定日志不包含资源秘密**

确认 Task 3 的首个自适应会话测试包含以下断言：

```dart
final combined = logs.join('\n');
expect(combined, isNot(contains(_AdaptiveRangeReader.secretUri)));
expect(combined, isNot(contains(_AdaptiveRangeReader.secretCookie)));
expect(combined, isNot(contains('chunk-private-path')));
```

假读取器的 `toString` 已包含三项秘密哨兵；日志注入只应收到固定调度字段。

- [ ] **Step 3: 运行定向测试并确认 RED**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/quark_range_remote_reader_test.dart test/cloud_range_relay_session_test.dart
```

Expected: 连接容量测试失败，当前值仍为 6；日志测试应保持通过或暴露任何不当字段。

- [ ] **Step 4: 修改夸克单主机连接容量**

在 `_sharedClient()` 中只改一项：

```dart
..maxConnectionsPerHost = 8
```

保留 `requestTimeout`、`idleTimeout`、`autoUncompress=false` 和 `DIRECT` 代理策略不变。

- [ ] **Step 5: 运行全部夸克与公共中转测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_range_chunk_cache_test.dart test/cloud_range_relay_service_test.dart test/cloud_range_relay_session_test.dart test/quark_range_remote_reader_test.dart test/quark_range_relay_service_test.dart test/cloud_playback_resolver_test.dart
```

Expected: 全部通过，0 失败。

- [ ] **Step 6: 提交夸克连接容量**

```powershell
git diff --check
git add -- lib/services/cloud/quark/quark_range_remote_reader.dart test/quark_range_remote_reader_test.dart test/cloud_range_relay_session_test.dart
git commit -m "优化：开放夸克八路读取容量"
```

### Task 5: 性能子系统完成门

**Files:**
- Verify: all files changed by Tasks 1-4

- [ ] **Step 1: 运行性能子系统全套测试**

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_range_chunk_cache_test.dart test/cloud_range_relay_service_test.dart test/cloud_range_relay_session_test.dart test/quark_range_remote_reader_test.dart test/quark_range_relay_service_test.dart test/cloud_playback_resolver_test.dart test/cloud_range_relay_protocol_test.dart
```

Expected: 0 失败。

- [ ] **Step 2: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`

- [ ] **Step 3: 审查性能差异和提交边界**

```powershell
git status --short
git diff --check
git log -4 --oneline
```

Expected: 本计划代码全部已提交；没有版本号、系统栏或发布文案改动。
