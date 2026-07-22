# 播放器退出与经典海报墙实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复播放器退出时资源先释放而界面回调仍运行的竞态，并恢复提交 `1585d82` 前的本地与网盘海报墙，交付签名的看影音 2.1.37。

**Architecture:** `VideoPage` 持有同步、幂等的 `PlayerExitCoordinator`，并在真正弹出播放路由前通知 `PlayerItem` 停止计时器与输入。`PlayerController` 使用可空运行时快照和幂等释放保护资源边界。海报墙通过精确恢复 `1585d82` 涉及的三个生产文件实现，不回退主题、导航或工具栏。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、MobX、media_kit、flutter_test、Windows MSIX、SignTool

---

## 文件结构

- Create: `lib/features/player/presentation/player_exit_coordinator.dart`
  - 保存一次性退出状态，并同步通知播放器界面停止工作
- Modify: `lib/pages/video/video_page.dart`
  - 区分退出全屏与退出路由，在路由弹出前发出退出信号
- Modify: `lib/pages/player/player_item.dart`
  - 监听退出信号，统一停止计时器和拒绝输入，周期任务使用单次状态快照
- Modify: `lib/pages/player/player_controller.dart`
  - 提供播放器可用状态、运行时快照、空播放器安全控制和幂等释放
- Create: `test/player_exit_lifecycle_test.dart`
  - 验证退出协调器、空播放器操作、重复释放和集成顺序
- Modify: `lib/features/library/presentation/immersive_media_card.dart`
  - 恢复覆盖式海报和悬停信息层
- Modify: `lib/features/library/presentation/library_media_grid.dart`
  - 恢复本地网格尺寸
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
  - 恢复网盘网格尺寸
- Modify: `test/library_presentation_components_test.dart`
  - 恢复经典卡片和本地网格断言
- Modify: `test/cloud_resources_page_test.dart`
  - 恢复网盘网格断言
- Modify: `pubspec.yaml`, `lib/core/app_version.dart`, `lib/utils/version_history.dart`
  - 将应用和 MSIX 版本升级到 2.1.37
- Modify: `README.md`, `RELEASE_NOTES.md`, `UPDATE_DIALOG_COPY.md`
  - 记录播放器返回修复和经典海报墙恢复
- Modify: `test/version_consistency_test.dart`, `test/identity_v2_zero_residue_test.dart`
  - 锁定 2.1.37 版本一致性

### Task 1: 建立播放器退出协调器

**Files:**
- Create: `lib/features/player/presentation/player_exit_coordinator.dart`
- Create: `test/player_exit_lifecycle_test.dart`

- [ ] **Step 1: 写退出协调器失败测试**

```dart
test('播放器退出协调器只同步通知一次', () {
  final coordinator = PlayerExitCoordinator();
  var notifications = 0;
  coordinator.addListener(() => notifications++);

  expect(coordinator.beginExit(), isTrue);
  expect(coordinator.beginExit(), isFalse);
  expect(coordinator.exitRequested, isTrue);
  expect(notifications, 1);

  coordinator.dispose();
});
```

- [ ] **Step 2: 运行测试并确认按预期失败**

Run: `D:\flutter\bin\flutter.bat test test\player_exit_lifecycle_test.dart`

Expected: FAIL，提示 `player_exit_coordinator.dart` 或 `PlayerExitCoordinator` 不存在。

- [ ] **Step 3: 实现最小退出协调器**

```dart
import 'package:flutter/foundation.dart';

class PlayerExitCoordinator extends ChangeNotifier {
  bool _exitRequested = false;

  bool get exitRequested => _exitRequested;

  bool beginExit() {
    if (_exitRequested) return false;
    _exitRequested = true;
    notifyListeners();
    return true;
  }
}
```

- [ ] **Step 4: 运行协调器测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test\player_exit_lifecycle_test.dart`

Expected: PASS，退出通知次数为 1。

### Task 2: 让播放器资源读取和控制具备退出安全性

**Files:**
- Modify: `lib/pages/player/player_controller.dart`
- Modify: `test/player_exit_lifecycle_test.dart`

- [ ] **Step 1: 添加空播放器与重复释放失败测试**

在 `PlayerController` 构造函数增加可注入的 `ShadersController` 后，测试使用真实控制器但不创建 media_kit 播放器：

```dart
test('播放器不存在时状态读取和控制操作安全结束', () async {
  final controller = PlayerController(
    shadersController: ShadersController(),
  );

  expect(controller.hasActivePlayer, isFalse);
  expect(controller.readRuntimeSnapshot(), isNull);
  await expectLater(controller.playOrPause(), completes);
  await expectLater(controller.pause(), completes);
  await expectLater(controller.play(), completes);
  await expectLater(controller.seek(Duration.zero), completes);
});

test('播放器重复释放共享同一个清理任务', () async {
  final controller = PlayerController(
    shadersController: ShadersController(),
  );

  final first = controller.dispose();
  final second = controller.dispose();
  expect(identical(first, second), isTrue);
  await first;
});
```

- [ ] **Step 2: 运行测试并确认缺少接口而失败**

Run: `D:\flutter\bin\flutter.bat test test\player_exit_lifecycle_test.dart`

Expected: FAIL，提示构造参数、`hasActivePlayer` 或 `readRuntimeSnapshot` 不存在，或空播放器控制触发空值异常。

- [ ] **Step 3: 增加运行时快照与可用状态**

在 `player_controller.dart` 中加入不可变快照：

```dart
class PlayerRuntimeSnapshot {
  const PlayerRuntimeSnapshot({
    required this.playing,
    required this.buffering,
    required this.completed,
    required this.volume,
    required this.position,
    required this.buffer,
    required this.duration,
  });

  final bool playing;
  final bool buffering;
  final bool completed;
  final double volume;
  final Duration position;
  final Duration buffer;
  final Duration duration;
}
```

构造函数接收 `ShadersController? shadersController`，并将字段初始化为传入实例或 `Modular.get<ShadersController>()`。新增：

```dart
bool get hasActivePlayer => !_disposeRequested && mediaPlayer != null;

PlayerRuntimeSnapshot? readRuntimeSnapshot() {
  final player = mediaPlayer;
  if (_disposeRequested || player == null) return null;
  final state = player.state;
  return PlayerRuntimeSnapshot(
    playing: state.playing,
    buffering: state.buffering,
    completed: state.completed,
    volume: state.volume,
    position: state.position,
    buffer: state.buffer,
    duration: state.duration,
  );
}
```

- [ ] **Step 4: 移除控制入口的空值断言**

`playOrPause`、`pause`、`play`、`seek`、`setVolume` 和 `setPlaybackSpeed` 先捕获局部播放器引用：

```dart
Future<void> playOrPause() async {
  final player = mediaPlayer;
  if (_disposeRequested || player == null) return;
  if (player.state.playing) {
    await pause();
  } else {
    await play();
  }
}
```

其他入口使用相同的局部引用与退出检查。播放器正常操作失败时沿用现有日志策略，退出导致的空播放器不写错误日志。

- [ ] **Step 5: 让释放流程幂等并可在下一播放生命周期重置**

新增 `Future<void>? _disposeFuture`。`dispose()` 首次调用设置 `_disposeRequested`、失效令牌并保存清理 Future；重复调用返回同一 Future。`activatePlaybackLifecycle()` 在创建新令牌前清除已经完成的退出任务引用。

在资源释放开始和完成时写入不含媒体地址的 INFO 日志。异常继续记录错误与堆栈。

- [ ] **Step 6: 运行播放器安全测试**

Run: `D:\flutter\bin\flutter.bat test test\player_exit_lifecycle_test.dart`

Expected: PASS，空播放器操作和重复释放均不抛异常。

### Task 3: 在路由退出前停止 PlayerItem

**Files:**
- Modify: `lib/pages/video/video_page.dart`
- Modify: `lib/pages/player/player_item.dart`
- Modify: `test/player_exit_lifecycle_test.dart`
- Modify: `test/local_video_controller_test.dart`

- [ ] **Step 1: 添加退出顺序和输入门禁失败测试**

添加源码集成断言，锁定关键调用顺序：

```dart
test('播放页在弹出路由前同步发出退出信号', () {
  final source = File('lib/pages/video/video_page.dart').readAsStringSync();
  final beginExit = source.indexOf('_exitCoordinator.beginExit()');
  final popRoute = source.indexOf('Navigator.of(context).pop()');

  expect(beginExit, greaterThanOrEqualTo(0));
  expect(popRoute, greaterThan(beginExit));
});

test('播放器界面收到退出信号后停止计时器和输入', () {
  final source = File('lib/pages/player/player_item.dart').readAsStringSync();

  expect(source, contains('_exitCoordinator.addListener'));
  expect(source, contains('playerTimer?.cancel()'));
  expect(source, contains('_acceptingInput = false'));
  expect(source, contains('readRuntimeSnapshot()'));
});
```

- [ ] **Step 2: 运行测试并确认缺少退出接线而失败**

Run: `D:\flutter\bin\flutter.bat test test\player_exit_lifecycle_test.dart test\local_video_controller_test.dart`

Expected: FAIL，找不到退出协调器调用或输入门禁。

- [ ] **Step 3: VideoPage 只在真正退出路由时发出信号**

`VideoPage` 创建并释放 `PlayerExitCoordinator`，将它传入 `PlayerItem`。`onBackPressed` 保持对话框、画中画和全屏分支不变；只有最终路由返回分支执行：

```dart
if (!_exitCoordinator.beginExit()) return;
AppLogger().i('VideoPage: route exit requested');
Navigator.of(context).pop();
```

页面销毁阶段保持播放操作失效和播放器释放，协调器在页面销毁末尾释放。

- [ ] **Step 4: PlayerItem 同步停止任务并拒绝输入**

`PlayerItem` 接收协调器。状态初始化时注册监听器，销毁时注销。抽取幂等方法：

```dart
void _stopInteractiveWorkForExit() {
  if (!_acceptingInput) return;
  _acceptingInput = false;
  playerTimer?.cancel();
  playerTimer = null;
  hideTimer?.cancel();
  hideTimer = null;
  mouseScrollerTimer?.cancel();
  mouseScrollerTimer = null;
  hideVolumeUITimer?.cancel();
  hideVolumeUITimer = null;
  AppLogger().i('PlayerItem: timers and input stopped for route exit');
}
```

点击、双击、滚轮、快捷键和手势入口在 `_acceptingInput` 为 `false` 时直接返回。周期回调一次读取 `readRuntimeSnapshot()`；快照为空时取消自身并返回，不更新 MobX 状态。

- [ ] **Step 5: 所有 await 后续逻辑检查生命周期**

在会更新界面或继续操作播放器的异步回调中，`await` 后检查：

```dart
if (!mounted || !_acceptingInput || !playerController.hasActivePlayer) return;
```

不要改变现有动画时长、曲线或播放器控件层级。

- [ ] **Step 6: 运行播放器相关测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\player_exit_lifecycle_test.dart test\local_video_controller_test.dart test\player_shortcut_handler_test.dart test\player_overlay_coordinator_test.dart`

Expected: PASS。

Commit:

```powershell
git add -- lib/features/player/presentation/player_exit_coordinator.dart lib/pages/video/video_page.dart lib/pages/player/player_item.dart lib/pages/player/player_controller.dart test/player_exit_lifecycle_test.dart test/local_video_controller_test.dart
git commit -m "修复播放器退出生命周期竞态"
```

### Task 4: 精确恢复经典海报墙

**Files:**
- Modify: `lib/features/library/presentation/immersive_media_card.dart`
- Modify: `lib/features/library/presentation/library_media_grid.dart`
- Modify: `lib/pages/cloud/resources/cloud_resource_poster_wall.dart`
- Modify: `test/library_presentation_components_test.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1: 先恢复经典海报墙测试断言**

将本地与网盘网格断言改为：

```dart
expect(delegate.maxCrossAxisExtent, 300);
expect(delegate.childAspectRatio, 0.68);
expect(delegate.crossAxisSpacing, 12);
expect(delegate.mainAxisSpacing, 12);
```

卡片断言恢复为单个覆盖式 `AnimatedOpacity`：初始 `0`，悬停后 `1`，时长 `160 ms`，曲线 `Curves.easeOut`。删除对 `media-card-hover-actions`、常驻信息区、边框抬升和居中播放按钮的新版断言。

- [ ] **Step 2: 运行测试并确认新版卡片导致失败**

Run: `D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart test\cloud_resources_page_test.dart`

Expected: FAIL，实际网格仍为 `220 / 0.5`，卡片结构仍为新版布局。

- [ ] **Step 3: 恢复提交 1585d82 前的三个生产文件行为**

从 `bc0951d` 读取 `immersive_media_card.dart` 的完整经典实现，并只替换当前卡片文件。将两个网格的 `maxCrossAxisExtent` 改为 `300`，`childAspectRatio` 改为 `0.68`，间距保持 `12`。

不要恢复 `1585d82` 之外的文件，也不要改动主题、导航或工具栏。

- [ ] **Step 4: 格式化并运行海报墙测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\features\library\presentation\immersive_media_card.dart lib\features\library\presentation\library_media_grid.dart lib\pages\cloud\resources\cloud_resource_poster_wall.dart test\library_presentation_components_test.dart test\cloud_resources_page_test.dart
D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart test\cloud_resources_page_test.dart
```

Expected: PASS。

- [ ] **Step 5: 提交经典海报墙**

```powershell
git add -- lib/features/library/presentation/immersive_media_card.dart lib/features/library/presentation/library_media_grid.dart lib/pages/cloud/resources/cloud_resource_poster_wall.dart test/library_presentation_components_test.dart test/cloud_resources_page_test.dart
git commit -m "恢复经典海报墙"
```

### Task 5: 升级 2.1.37 并更新用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1: 在版本修改前重新记录已安装版本**

Run:

```powershell
Get-AppxPackage -Name com.kanyingyin.player |
  Select-Object Name, Version, Architecture, PackageFullName
```

Expected: 当前版本 `2.1.36.0`；如果实际结果不同，以命令输出为准并停止版本修改。

- [ ] **Step 2: 先把版本一致性测试改为 2.1.37**

```dart
const expectedVersion = '2.1.37';
const expectedBuildNumber = '20137';
```

`identity_v2_zero_residue_test.dart` 的当前版本断言同步改为 `2.1.37`。

- [ ] **Step 3: 运行版本测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart`

Expected: FAIL，项目配置仍为 2.1.36。

- [ ] **Step 4: 更新版本和普通用户文案**

设置：

```yaml
version: 2.1.37+20137
msix_version: 2.1.37.0
```

发布文案说明两项用户可见变化：从播放页返回不再停留黑屏；本地与网盘海报墙恢复整张海报和悬停信息。同步说明播放器解码、字幕、选集、硬件解码、Anime4K、原始媒体与网盘文件均未改变。

- [ ] **Step 5: 运行版本测试并提交**

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart test\version_history_current_test.dart test\release_config_contract_test.dart test\signed_release_packaging_test.dart`

Expected: PASS。

Commit:

```powershell
git add -- pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md test/version_consistency_test.dart test/identity_v2_zero_residue_test.dart
git commit -m "发布 2.1.37 测试版"
```

### Task 6: 完整验证与签名交付

**Files:**
- Verify only: entire repository
- Generated: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `%USERPROFILE%\Desktop\看影音-2.1.37.msix`
- Deliver: `%USERPROFILE%\Desktop\看影音-2.1.37-异机安装包.zip`

- [ ] **Step 1: 检查提交范围和格式**

Run:

```powershell
git status --short
git diff --check
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed .
```

Expected: 工作树无未提交源码改动，格式检查退出码为 0。

- [ ] **Step 2: 运行完整测试和静态分析**

Run:

```powershell
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
```

Expected: 所有测试通过；`No issues found!`。

- [ ] **Step 3: 运行正式签名发布脚本**

Run: `powershell -ExecutionPolicy Bypass -File tool\windows\build_signed_release.ps1`

Expected: Windows Release 构建成功，MSIX 签名验证成功，桌面生成 MSIX 和异机安装 ZIP。

- [ ] **Step 4: 独立验证最终安装包**

使用 `Get-AuthenticodeSignature` 检查状态为 `Valid`。读取 `AppxManifest.xml`，确认身份 `com.kanyingyin.player`、版本 `2.1.37.0`、架构 `x64`。比较构建产物和桌面 MSIX 的 SHA-256，并确认签名证书指纹与 2.1.36 相同。

- [ ] **Step 5: 核对最终状态**

Run:

```powershell
git status --short --branch
git log -4 --oneline
Get-AppxPackage -Name com.kanyingyin.player |
  Select-Object Name, Version, Architecture
```

Expected: 隔离分支干净，存在三个功能与发布提交，当前已安装版本仍为 2.1.36.0，因为本计划不自动安装 2.1.37。
