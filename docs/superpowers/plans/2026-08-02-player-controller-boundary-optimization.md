# 播放器控制器边界优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 media-kit 运行时、媒体会话事务和音轨插件副作用从 `PlayerController` 提取，消除 Controller 内服务定位，同时保持播放器公开 API、UI 和运行行为不变。

**Architecture:** `PlayerController` 继续维护 MobX UI 状态并作为页面门面；`PlayerEngineRuntime` 隔离 media-kit/NativePlayer，`PlayerMediaSessionCoordinator` 管理 token、锁和 lease，`PlayerTrackRuntimeCoordinator` 将现有字幕/音轨策略应用到运行时。`LocalVideoController` 通过构造注入播放器端口。

**Tech Stack:** Flutter 3.41.9、Dart、MobX、media_kit、media_kit_video、synchronized、Flutter Modular、flutter_test。

---

## 文件结构

- Create: `lib/features/player/application/player_operation_coordinator.dart`
- Create: `lib/features/player/application/player_engine_runtime.dart`
- Create: `lib/features/player/application/player_media_session_models.dart`
- Create: `lib/features/player/application/player_media_session_coordinator.dart`
- Create: `lib/features/player/application/player_track_runtime_coordinator.dart`
- Create: `lib/features/player/infrastructure/media_kit_player_engine_runtime.dart`
- Modify: `lib/pages/player/player_controller.dart`
- Modify: `lib/pages/video/local_video_controller.dart`
- Modify: `lib/app/bindings/playback_bindings.dart`
- Modify: `test/architecture_dependency_test.dart`
- Add: 对应运行时、会话、音轨和依赖注入测试。

### Task 1: 把播放操作 token 移入播放器应用层

**Files:**
- Create: `lib/features/player/application/player_operation_coordinator.dart`
- Modify: `lib/services/cloud/cloud_playback_resolver.dart:172-230`
- Modify: `lib/pages/player/player_controller.dart:318-321`
- Modify: `lib/pages/video/local_video_controller.dart:36-38`
- Create: `test/player_operation_coordinator_test.dart`

- [ ] **Step 1: 写入失败测试，覆盖生命周期和媒体代际**

```dart
test('新生命周期使旧媒体 token 失效', () {
  final lifecycle = PlayerLifecycleCoordinator();
  final media = PlayerMediaOperationCoordinator();
  final firstLifecycle = lifecycle.activate();
  final firstMedia = media.beginMedia('a');
  final secondLifecycle = lifecycle.activate();
  expect(lifecycle.isCurrent(firstLifecycle), isFalse);
  expect(lifecycle.isCurrent(secondLifecycle), isTrue);
  expect(media.isCurrent(firstMedia), isTrue);
  media.invalidate();
  expect(media.isCurrent(firstMedia), isFalse);
});
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/player_operation_coordinator_test.dart`

Expected: FAIL，新的 application 文件不存在。

- [ ] **Step 3: 将现有纯 Dart 类型原样移动并从旧文件导出兼容符号**

```dart
final class PlayerMediaToken {
  const PlayerMediaToken(this.generation, this.stableMediaKey);
  final int generation;
  final String? stableMediaKey;
}

final class PlayerLifecycleToken {
  const PlayerLifecycleToken(this.generation);
  final int generation;
}

final class PlayerLifecycleCoordinator {
  int _generation = 0;
  PlayerLifecycleToken activate() => PlayerLifecycleToken(++_generation);
  void invalidate() => _generation++;
  bool isCurrent(PlayerLifecycleToken token) =>
      token.generation == _generation;
}

final class PlayerMediaOperationCoordinator {
  int _generation = 0;
  PlayerMediaToken beginMedia(String? stableMediaKey) =>
      PlayerMediaToken(++_generation, stableMediaKey);
  void invalidate() => _generation++;
  bool isCurrent(PlayerMediaToken token) => token.generation == _generation;
}
```

`cloud_playback_resolver.dart` 改为 `export` 新文件，确保尚未迁移的导入不会立即中断；本阶段结束前所有播放器调用方切换到新路径。

- [ ] **Step 4: 运行 token、云播放和播放器生命周期测试并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/player_operation_coordinator_test.dart test/cloud_playback_resolver_test.dart test/player_resource_lifecycle_test.dart test/local_video_controller_test.dart`

Expected: PASS。

```powershell
git add lib/features/player/application/player_operation_coordinator.dart lib/services/cloud/cloud_playback_resolver.dart lib/pages/player/player_controller.dart lib/pages/video/local_video_controller.dart test/player_operation_coordinator_test.dart
git commit -m "重构：归并播放器操作代际边界"
```

### Task 2: 定义播放器运行时端口和强类型事件

**Files:**
- Create: `lib/features/player/application/player_engine_runtime.dart`
- Create: `test/player_engine_runtime_contract_test.dart`
- Modify: `lib/pages/player/player_controller.dart:47-65,314-427`

- [ ] **Step 1: 写入 Fake Runtime 契约测试**

```dart
test('运行时命令与状态事件不暴露 Player 或 NativePlayer', () async {
  final runtime = FakePlayerEngineRuntime();
  final events = <PlayerEngineEvent>[];
  final subscription = runtime.events.listen(events.add);
  await runtime.open(_request('file:///A.mp4'));
  await runtime.seek(const Duration(seconds: 20));
  await runtime.setVolume(45);
  expect(runtime.commands, ['open:file:///A.mp4', 'seek:20', 'volume:45.0']);
  expect(events.last.snapshot.position, const Duration(seconds: 20));
  await subscription.cancel();
});
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/player_engine_runtime_contract_test.dart`

Expected: FAIL。

- [ ] **Step 3: 定义运行时请求、快照、事件和端口**

```dart
final class PlayerEngineOpenRequest {
  const PlayerEngineOpenRequest({
    required this.uri,
    required this.httpHeaders,
    required this.start,
    required this.bufferSize,
    required this.videoRenderer,
    required this.hardwareDecoder,
  });
  final Uri uri;
  final Map<String, String> httpHeaders;
  final Duration start;
  final int bufferSize;
  final String? videoRenderer;
  final String hardwareDecoder;
}

final class PlayerEngineSnapshot {
  const PlayerEngineSnapshot({
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.volume = 100,
    this.position = Duration.zero,
    this.buffer = Duration.zero,
    this.duration = Duration.zero,
    this.width = 0,
    this.height = 0,
  });
  final bool playing, buffering, completed;
  final double volume;
  final Duration position, buffer, duration;
  final int width, height;
}

sealed class PlayerEngineEvent {
  const PlayerEngineEvent(this.snapshot);
  final PlayerEngineSnapshot snapshot;
}
final class PlayerEngineStateChanged extends PlayerEngineEvent {
  const PlayerEngineStateChanged(super.snapshot);
}
final class PlayerEngineFailure extends PlayerEngineEvent {
  const PlayerEngineFailure(super.snapshot, this.message);
  final String message;
}

abstract interface class PlayerEngineRuntime {
  bool get hasActiveMedia;
  VideoController? get videoController;
  PlayerEngineSnapshot get snapshot;
  Stream<PlayerEngineEvent> get events;
  Future<void> open(PlayerEngineOpenRequest request);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double value);
  Future<void> setRate(double value);
  Future<Uint8List?> screenshot({required String format});
  Future<void> stop();
  Future<void> dispose();
}
```

为保持 Flutter 页面类型安全，实际端口增加 `VideoController? get videoController`，该类型只作为渲染句柄；端口不得暴露 `Player` 或 `NativePlayer`。

- [ ] **Step 4: 让 `PlayerController.readRuntimeSnapshot` 从端口快照读取**

```dart
PlayerRuntimeSnapshot? readRuntimeSnapshot() {
  if (!_engineRuntime.hasActiveMedia) return null;
  final value = _engineRuntime.snapshot;
  return PlayerRuntimeSnapshot(
    playing: value.playing,
    buffering: value.buffering,
    completed: value.completed,
    volume: value.volume,
    position: value.position,
    buffer: value.buffer,
    duration: value.duration,
  );
}
```

端口必须同时声明 `bool get hasActiveMedia`；Fake 和 media-kit 实现均以是否已有活动媒体判断。

- [ ] **Step 5: 运行端口契约和现有快照测试并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/player_engine_runtime_contract_test.dart test/player_resource_lifecycle_test.dart`

Expected: PASS。

```powershell
git add lib/features/player/application/player_engine_runtime.dart lib/pages/player/player_controller.dart test/player_engine_runtime_contract_test.dart test/player_resource_lifecycle_test.dart
git commit -m "重构：定义播放器运行时端口"
```

### Task 3: 实现 media-kit 运行时生命周期

**Files:**
- Create: `lib/features/player/infrastructure/media_kit_player_engine_runtime.dart`
- Create: `test/media_kit_player_engine_runtime_test.dart`
- Modify: `lib/pages/player/player_controller.dart:653-920,1883-1979`

- [ ] **Step 1: 写入可注入 Player 工厂的生命周期测试**

```dart
test('重新打开媒体前释放旧订阅并只发布当前播放器事件', () async {
  final first = FakeMediaKitPlayer();
  final second = FakeMediaKitPlayer();
  final runtime = MediaKitPlayerEngineRuntime(
    playerFactory: _QueuePlayerFactory([first, second]).create,
    videoControllerFactory: FakeVideoController.new,
  );
  final events = <PlayerEngineEvent>[];
  runtime.events.listen(events.add);
  await runtime.open(_request('file:///A.mp4'));
  await runtime.open(_request('file:///B.mp4'));
  first.emitPosition(const Duration(seconds: 99));
  second.emitPosition(const Duration(seconds: 3));
  expect(first.disposed, isTrue);
  expect(events.last.snapshot.position, const Duration(seconds: 3));
});
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/media_kit_player_engine_runtime_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现 runtime 的拥有权、事件订阅和幂等释放**

```dart
typedef MediaKitPlayerFactory = Player Function(PlayerConfiguration configuration);
typedef MediaKitVideoControllerFactory = VideoController Function(
  Player player,
  VideoControllerConfiguration configuration,
);

final class MediaKitPlayerEngineRuntime implements PlayerEngineRuntime {
  MediaKitPlayerEngineRuntime({
    required MediaKitPlayerFactory playerFactory,
    required MediaKitVideoControllerFactory videoControllerFactory,
  })  : _playerFactory = playerFactory,
        _videoControllerFactory = videoControllerFactory;

  final MediaKitPlayerFactory _playerFactory;
  final MediaKitVideoControllerFactory _videoControllerFactory;
  final StreamController<PlayerEngineEvent> _events = StreamController.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Player? _player;
  VideoController? _videoController;
  PlayerEngineSnapshot _snapshot = const PlayerEngineSnapshot();
  int _generation = 0;

  @override
  VideoController? get videoController => _videoController;
  @override
  bool get hasActiveMedia => _player != null;
  @override
  PlayerEngineSnapshot get snapshot => _snapshot;
  @override
  Stream<PlayerEngineEvent> get events => _events.stream;

  @override
  Future<void> open(PlayerEngineOpenRequest request) async {
    final generation = ++_generation;
    await _disposeOwnedPlayer();
    final player = _playerFactory(PlayerConfiguration(
      bufferSize: request.bufferSize,
      osc: false,
      libass: true,
      libassAndroidFont: 'assets/fonts/MiSans-Regular.ttf',
      libassAndroidFontName: 'MiSans',
      logLevel: MPVLogLevel.v,
    ));
    _player = player;
    _videoController = _videoControllerFactory(
      player,
      VideoControllerConfiguration(vo: request.videoRenderer),
    );
    _listen(player, generation);
    await player.open(
      Media(request.uri.toString(), httpHeaders: request.httpHeaders),
      play: true,
    );
    if (request.start > Duration.zero) await player.seek(request.start);
  }
}
```

`_listen` 必须订阅 playing、buffering、completed、volume、position、buffer、duration、width、height 和 error，并在每个回调检查 generation；`_disposeOwnedPlayer` 先取消全部订阅，再释放 VideoController 引用并 dispose Player。原 `createVideoController` 中的代理、缓存、解码器、字幕和事件策略先通过配置回调注入，下一任务再移除 NativePlayer 泄漏。

- [ ] **Step 4: 将播放命令和资源释放委托 runtime**

```dart
Future<void> setPlaybackSpeed(double value) => _engineRuntime.setRate(value);
Future<void> setVolume(double value) => _engineRuntime.setVolume(value);
Future<void> seek(Duration value, {bool enableSync = true}) =>
    _engineRuntime.seek(value);
Future<void> stop() => _engineRuntime.stop();
Future<Uint8List?> screenshot({String format = 'image/jpeg'}) =>
    _engineRuntime.screenshot(format: format);
```

- [ ] **Step 5: 运行生命周期、播放器控制和资源测试并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/media_kit_player_engine_runtime_test.dart test/player_resource_lifecycle_test.dart test/player_resource_disposer_test.dart test/anime4k_player_controller_test.dart`

Expected: PASS。

```powershell
git add lib/features/player/infrastructure lib/pages/player/player_controller.dart test/media_kit_player_engine_runtime_test.dart test/player_resource_lifecycle_test.dart
git commit -m "重构：隔离media-kit播放器运行时"
```

### Task 4: 提取媒体会话事务

**Files:**
- Create: `lib/features/player/application/player_media_session_models.dart`
- Create: `lib/features/player/application/player_media_session_coordinator.dart`
- Create: `test/player_media_session_coordinator_test.dart`
- Modify: `lib/pages/player/player_controller.dart:496-652,1599-1654,1875-1911`

- [ ] **Step 1: 写入失败测试，覆盖串行初始化和过期 lease**

```dart
test('后发媒体使旧初始化失效并关闭旧 lease', () async {
  final runtime = _BlockingRuntime();
  final firstLease = _RecordingLease();
  final coordinator = PlayerMediaSessionCoordinator(runtime: runtime);
  final lifecycle = coordinator.activateLifecycle();
  final first = coordinator.open(
    _params('A', lease: firstLease),
    lifecycleToken: lifecycle,
  );
  final second = coordinator.open(
    _params('B'),
    lifecycleToken: lifecycle,
  );
  runtime.complete('B');
  await second;
  runtime.complete('A');
  await first;
  expect(firstLease.closed, isTrue);
  expect(coordinator.current?.stableMediaKey, 'B');
});
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/player_media_session_coordinator_test.dart`

Expected: FAIL。

- [ ] **Step 3: 实现锁、token、lease 采用和刷新事务**

```dart
final class PlayerMediaSessionCoordinator {
  PlayerMediaSessionCoordinator({required PlayerEngineRuntime runtime})
      : _runtime = runtime;
  final PlayerEngineRuntime _runtime;
  final Lock _lock = Lock();
  final PlayerLifecycleCoordinator _lifecycles = PlayerLifecycleCoordinator();
  final PlayerMediaOperationCoordinator _media = PlayerMediaOperationCoordinator();
  final CloudPlaybackLeaseCoordinator _leases = CloudPlaybackLeaseCoordinator();
  PlaybackInitParams? _current;

  PlaybackInitParams? get current => _current;
  PlayerLifecycleToken activateLifecycle() => _lifecycles.activate();

  Future<void> open(
    PlaybackInitParams params, {
    required PlayerLifecycleToken lifecycleToken,
  }) => _lock.synchronized(() async {
    if (!_lifecycles.isCurrent(lifecycleToken)) {
      await _leases.reject(params.lease);
      return;
    }
    final token = _media.beginMedia(params.stableMediaKey);
    try {
      await _runtime.open(params.toEngineRequest());
      if (!_lifecycles.isCurrent(lifecycleToken) || !_media.isCurrent(token)) {
        await _leases.reject(params.lease);
        return;
      }
      await _leases.adopt(params.lease);
      _current = params;
    } on Object {
      await _leases.reject(params.lease);
      rethrow;
    }
  });
}
```

把 `PlaybackInitParams`、`mergeRefreshedCloudPlayback` 和 `CloudPlaybackRefreshTransaction` 从 `player_controller.dart:93-216` 原样移动到 `player_media_session_models.dart`，并在该文件实现 `PlaybackInitParams.toEngineRequest()`。`refreshCloudPlayback` 继续使用现有 position、wasPlaying 和 subtitle fallback 合并规则，不保留 Controller 内的重复声明。

- [ ] **Step 4: PlayerController 的 `init/dispose` 委托会话协调器**

```dart
PlayerLifecycleToken activatePlaybackLifecycle() =>
    _sessionCoordinator.activateLifecycle();

Future<void> init(PlaybackInitParams params, {
  required PlayerLifecycleToken lifecycleToken,
}) => _sessionCoordinator.open(params, lifecycleToken: lifecycleToken);
```

Controller 继续在 runtime 事件中更新 loading、playing、position、duration、错误文本和已有字幕/Anime4K 状态。

- [ ] **Step 5: 运行云链接刷新、lease 和初始化测试并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/player_media_session_coordinator_test.dart test/cloud_playback_resolver_test.dart test/player_resource_lifecycle_test.dart test/http_stream_completion_contract_test.dart`

Expected: PASS。

```powershell
git add lib/features/player/application/player_media_session_coordinator.dart lib/pages/player/player_controller.dart test/player_media_session_coordinator_test.dart test/player_resource_lifecycle_test.dart
git commit -m "重构：提取播放器媒体会话事务"
```

### Task 5: 提取字幕与音轨运行时副作用

**Files:**
- Create: `lib/features/player/application/player_track_runtime_coordinator.dart`
- Create: `test/player_track_runtime_coordinator_test.dart`
- Modify: `lib/features/player/application/player_engine_runtime.dart`
- Modify: `lib/features/player/infrastructure/media_kit_player_engine_runtime.dart`
- Modify: `lib/pages/player/player_controller.dart:991-1582,1655-1711`

- [ ] **Step 1: 写入失败测试，覆盖外部字幕、内嵌轨道和延迟**

```dart
test('字幕切换按清理、加载、样式、延迟顺序调用运行时', () async {
  final runtime = FakePlayerEngineRuntime();
  final coordinator = PlayerTrackRuntimeCoordinator(runtime: runtime);
  await coordinator.selectExternalSubtitle(
    path: 'A.ass',
    style: const SubtitleStyleSettings.defaults(),
    delaySeconds: 1.25,
  );
  expect(runtime.commands, [
    'subtitle:clear',
    'subtitle:external:A.ass',
    'subtitle:style',
    'subtitle:delay:1.25',
  ]);
});
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/player_track_runtime_coordinator_test.dart`

Expected: FAIL。

- [ ] **Step 3: 扩展端口并实现协调器**

```dart
abstract interface class PlayerTrackRuntime {
  Future<void> clearSubtitleTrack();
  Future<void> loadExternalSubtitle(String path);
  Future<void> selectEmbeddedSubtitle(String id);
  Future<void> selectAudioTrack(String id);
  Future<void> applySubtitleStyle(SubtitleStyleSettings style);
  Future<void> setSubtitleDelay(double seconds);
  Future<List<EmbeddedTrackInfo>> readEmbeddedTracks();
}

final class PlayerTrackRuntimeCoordinator {
  const PlayerTrackRuntimeCoordinator({required PlayerTrackRuntime runtime})
      : _runtime = runtime;
  final PlayerTrackRuntime _runtime;

  Future<void> selectExternalSubtitle({
    required String path,
    required SubtitleStyleSettings style,
    required double delaySeconds,
  }) async {
    await _runtime.clearSubtitleTrack();
    await _runtime.loadExternalSubtitle(path);
    await _runtime.applySubtitleStyle(style);
    await _runtime.setSubtitleDelay(delaySeconds);
  }
}
```

把 `player_controller.dart:1035-1582,1655-1711` 中所有 NativePlayer `setProperty`、subtitle track 和 audio track 调用替换为 `PlayerTrackRuntime` 方法；对应 media-kit 调用只实现在 `MediaKitPlayerEngineRuntime`。PlayerController 只保留偏好读取、语言确认状态和 Observable 映射。

- [ ] **Step 4: 运行字幕、音轨、TrueHD 和 Anime4K 回归并提交**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/player_track_runtime_coordinator_test.dart test/player_subtitle_coordinator_test.dart test/player_embedded_track_state_test.dart test/embedded_track_controls_test.dart test/truehd_fallback_policy_test.dart test/anime4k_player_controller_test.dart
```

Expected: PASS。

```powershell
git add lib/features/player/application lib/features/player/infrastructure lib/pages/player/player_controller.dart test/player_track_runtime_coordinator_test.dart test/player_subtitle_coordinator_test.dart test/player_embedded_track_state_test.dart
git commit -m "重构：隔离播放器字幕音轨副作用"
```

### Task 6: 移除 Controller 服务定位并锁定架构

**Files:**
- Modify: `lib/pages/video/local_video_controller.dart:22-31,154-168`
- Modify: `lib/pages/player/player_controller.dart:10,222-260`
- Modify: `lib/app/bindings/playback_bindings.dart:12-35`
- Modify: `test/architecture_dependency_test.dart`
- Modify: `test/local_video_controller_test.dart`

- [ ] **Step 1: 添加失败架构测试**

```dart
test('播放器控制器不使用 Modular 服务定位且插件拥有权归运行时', () {
  final files = [
    File('${libDirectory.path}/pages/player/player_controller.dart'),
    File('${libDirectory.path}/pages/video/local_video_controller.dart'),
  ];
  for (final file in files) {
    expect(file.readAsStringSync(), isNot(contains('Modular.get<')),
        reason: file.path);
  }
  final controller = files.first.readAsStringSync();
  expect(controller, isNot(contains('Player(')));
  expect(controller, isNot(contains('as NativePlayer')));
});
```

- [ ] **Step 2: 运行架构测试并确认 RED**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/architecture_dependency_test.dart`

Expected: FAIL。

- [ ] **Step 3: 通过绑定注入运行时、会话和生命周期端口**

```dart
i.addSingleton<PlayerEngineRuntime>(() => MediaKitPlayerEngineRuntime(
  playerFactory: (configuration) => Player(configuration: configuration),
  videoControllerFactory: (player, configuration) =>
      VideoController(player, configuration: configuration),
));
i.addSingleton<PlayerMediaSessionCoordinator>(() =>
    PlayerMediaSessionCoordinator(runtime: Modular.get<PlayerEngineRuntime>()));
i.addSingleton<LocalVideoController>(() => LocalVideoController(
  activatePlayerLifecycle: Modular.get<PlayerController>().activatePlaybackLifecycle,
  initializePlayer: (params, token) =>
      Modular.get<PlayerController>().init(params, lifecycleToken: token),
));
```

`LocalVideoController` 构造函数接收上述两个强类型回调；内部不得再导入 Flutter Modular。

- [ ] **Step 4: 运行播放器全域测试、分析并提交阶段三**

```powershell
D:\flutter\bin\dart.bat format lib/features/player lib/pages/player/player_controller.dart lib/pages/video/local_video_controller.dart lib/app/bindings/playback_bindings.dart test/player_*_test.dart test/local_video_controller_test.dart test/architecture_dependency_test.dart
D:\flutter\bin\flutter.bat test --no-pub test/architecture_dependency_test.dart test/local_video_controller_test.dart test/player_resource_lifecycle_test.dart test/player_embedded_track_state_test.dart test/anime4k_player_controller_test.dart test/player_exit_lifecycle_test.dart
D:\flutter\bin\flutter.bat analyze --no-pub
git add lib/features/player lib/pages/player/player_controller.dart lib/pages/video/local_video_controller.dart lib/app/bindings/playback_bindings.dart test
git commit -m "重构：完成播放器控制器边界优化"
```

Expected: 测试 PASS，analyze 输出 `No issues found!`。
