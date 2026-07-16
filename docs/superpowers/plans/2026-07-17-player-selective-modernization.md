# 播放器选择性现代化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变看影音现有播放器外观的前提下，完成快捷键分发、控制栏保持、统一 HUD、截图反馈、字幕滚轮隔离和字幕样式串行同步，并删除失效的断点续播设置。

**Architecture:** 保留 `PlayerController`、`PlayerItemPanel` 和 `SmallestPlayerItemPanel` 的现有业务边界，新增纯状态或局部 Widget 组件承担键盘、hold 和反馈展示。字幕 MPV 写入通过通用的“最新值串行执行器”合并，预览与持久化分离。

**Tech Stack:** Flutter 3.41.9、Dart、MobX、media_kit/libmpv、flutter_test、Windows/MSIX。

---

## 文件结构

- `lib/pages/player/player_keyboard_shortcuts.dart`：键盘按下、重复、松开和阻断判断。
- `lib/pages/player/player_panel_hold.dart`：引用计数式控制栏保持及幂等 lease。
- `lib/pages/player/player_adjustment_hud.dart`：快进快退、音量和临时倍速反馈。
- `lib/pages/player/player_screenshot_feedback_overlay.dart`：截图成功边框反馈。
- `lib/pages/player/latest_value_serial_executor.dart`：通用的单任务、只保留最新值执行器。
- `lib/pages/player/player_item.dart`：组合新组件，仍负责现有播放操作回调。
- `lib/pages/player/player_item_panel.dart`、`smallest_player_item_panel.dart`、`widgets/embedded_track_menus.dart`：获取和释放 hold，不改变视觉层级。
- `lib/pages/player/widgets/subtitle_settings_overlay.dart`：报告鼠标命中，拆分滑块预览和提交。
- `lib/pages/player/player_controller.dart`：字幕样式快照、串行合并写入和持久化。
- `test/player_*_test.dart`：新组件和数据流的单元/Widget 测试。

### Task 1: 删除失效的断点续播设置

**Files:**
- Modify: `lib/pages/settings/player_settings.dart`
- Modify: `lib/utils/storage.dart`
- Modify: `test/history_feature_removal_test.dart`

- [ ] **Step 1: 运行基线测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub --reporter compact`

Expected: 现有 `392` 项或更多测试全部通过。

- [ ] **Step 2: 先写失败断言**

在 `history_feature_removal_test.dart` 的用户界面测试中加入：

```dart
final storage = File('lib/utils/storage.dart').readAsStringSync();

for (final text in [
  'playResume',
  '自动跳转',
  '上次播放位置',
]) {
  expect('$playerSettings\n$storage', isNot(contains(text)), reason: text);
}
expect(playerSettings, contains('autoPlayNext'));
expect(playerSettings, contains('自动连播'));
```

- [ ] **Step 3: 验证测试按预期失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\history_feature_removal_test.dart --plain-name "用户界面不再提供历史记录和隐身模式"`

Expected: FAIL，报告 `playResume` 或“自动跳转”仍存在。

- [ ] **Step 4: 最小实现**

从 `PlayerSettingsPage` 删除 `playResume` 字段、初始化读取和整个“自动跳转” `SettingsTile`，从 `SettingBoxKey` 删除：

```dart
playResume = 'playResume',
```

保留 `autoPlayNext`、“自动连播”及 `PlayerItem` 中的完成后切集逻辑。

- [ ] **Step 5: 验证转绿并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\history_feature_removal_test.dart`

Expected: PASS。

```powershell
git add lib/pages/settings/player_settings.dart lib/utils/storage.dart test/history_feature_removal_test.dart
git commit -m "refactor: 删除失效的断点续播设置"
```

### Task 2: 实现引用计数式面板保持

**Files:**
- Create: `lib/pages/player/player_panel_hold.dart`
- Create: `test/player_panel_hold_test.dart`

- [ ] **Step 1: 写纯 Dart 失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/player/player_panel_hold.dart';

void main() {
  test('只在首次获取和最后释放时通知', () {
    var first = 0;
    var last = 0;
    final hold = PlayerPanelHold(
      onFirstAcquire: () => first++,
      onLastRelease: () => last++,
    );

    final firstLease = hold.acquire();
    final secondLease = hold.acquire();
    expect((first, last, hold.isHeld), (1, 0, true));
    firstLease.release();
    expect((first, last, hold.isHeld), (1, 0, true));
    secondLease.release();
    secondLease.release();
    expect((first, last, hold.isHeld), (1, 1, false));
  });

  test('销毁后释放 lease 不再触发回调', () {
    var last = 0;
    final hold = PlayerPanelHold(
      onFirstAcquire: () {},
      onLastRelease: () => last++,
    );
    final lease = hold.acquire();
    hold.dispose();
    lease.release();
    expect((last, hold.isHeld), (0, false));
  });
}
```

- [ ] **Step 2: 运行并确认缺少类**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\player_panel_hold_test.dart`

Expected: FAIL，`player_panel_hold.dart` 或 `PlayerPanelHold` 不存在。

- [ ] **Step 3: 实现 hold 与幂等 lease**

```dart
import 'package:flutter/foundation.dart';

class PlayerPanelHold {
  PlayerPanelHold({
    required this.onFirstAcquire,
    required this.onLastRelease,
  });

  final VoidCallback onFirstAcquire;
  final VoidCallback onLastRelease;
  int _count = 0;
  bool _disposed = false;

  bool get isHeld => !_disposed && _count > 0;

  PlayerPanelHoldLease acquire() {
    if (_disposed) return PlayerPanelHoldLease._(() {});
    if (_count++ == 0) onFirstAcquire();
    return PlayerPanelHoldLease._(_release);
  }

  void _release() {
    if (_disposed || _count == 0) return;
    _count--;
    if (_count == 0) onLastRelease();
  }

  void dispose() {
    _disposed = true;
    _count = 0;
  }
}

class PlayerPanelHoldLease {
  PlayerPanelHoldLease._(this._onRelease);
  final VoidCallback _onRelease;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _onRelease();
  }
}
```

- [ ] **Step 4: 验证并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\player_panel_hold_test.dart`

Expected: 2 tests PASS。

```powershell
git add lib/pages/player/player_panel_hold.dart test/player_panel_hold_test.dart
git commit -m "feat: 增加播放器面板保持机制"
```

### Task 3: 独立键盘快捷键分发

**Files:**
- Create: `lib/pages/player/player_keyboard_shortcuts.dart`
- Create: `test/player_keyboard_shortcuts_test.dart`
- Modify: `lib/pages/player/player_item.dart`

- [ ] **Step 1: 写 Widget 失败测试**

构建包含 `FocusScope` 和 `PlayerKeyboardShortcuts` 的测试容器，显式传入 `shortcuts`，验证：

```dart
testWidgets('按下重复和松开分发长按动作', (tester) async {
  var down = 0;
  var repeat = 0;
  var release = 0;
  await pumpShortcutHarness(
    tester,
    shortcuts: const {'forward': ['Arrow Right']},
    actions: {'forward': () => down++},
    longPressActions: {
      'forward': PlayerLongPressShortcutActions(
        onRepeat: () => repeat++,
        onRelease: () => release++,
      ),
    },
  );

  await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
  await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
  expect((down, repeat, release), (1, 1, 1));
});
```

再加两个测试：`EditableText` 获得焦点时不分发；`isBlocked` 为 true 时不分发。

```dart
testWidgets('输入框获得焦点时不分发', (tester) async {
  var invoked = 0;
  await pumpShortcutHarness(
    tester,
    shortcuts: const {'playpause': ['Space']},
    actions: {'playpause': () => invoked++},
    includeFocusedTextField: true,
  );
  await tester.sendKeyEvent(LogicalKeyboardKey.space);
  expect(invoked, 0);
});

testWidgets('显式阻断时不分发', (tester) async {
  var invoked = 0;
  await pumpShortcutHarness(
    tester,
    shortcuts: const {'playpause': ['Space']},
    actions: {'playpause': () => invoked++},
    isBlocked: () => true,
  );
  await tester.sendKeyEvent(LogicalKeyboardKey.space);
  expect(invoked, 0);
});
```

- [ ] **Step 2: 验证测试因类缺失而失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\player_keyboard_shortcuts_test.dart`

Expected: FAIL，`PlayerKeyboardShortcuts` 不存在。

- [ ] **Step 3: 实现分发器**

参照 Kazumi `PlayerKeyboardShortcuts` 的事件模型，实现以下公开 API：

```dart
typedef PlayerShortcutAction = FutureOr<void> Function();

class PlayerLongPressShortcutActions {
  const PlayerLongPressShortcutActions({
    required this.onRepeat,
    required this.onRelease,
  });
  final PlayerShortcutAction onRepeat;
  final PlayerShortcutAction onRelease;
}

class PlayerKeyboardShortcuts extends StatefulWidget {
  const PlayerKeyboardShortcuts({
    super.key,
    required this.focusScopeNode,
    required this.actions,
    this.longPressActions = const {},
    this.isBlocked,
    this.shortcuts,
  });
  final FocusNode focusScopeNode;
  final Map<String, PlayerShortcutAction> actions;
  final Map<String, PlayerLongPressShortcutActions> longPressActions;
  final bool Function()? isBlocked;
  final Map<String, List<String>>? shortcuts;
}
```

使用 `FocusManager.instance.addEarlyKeyEventHandler`；只处理当前路由、播放器焦点树中且焦点不在 `EditableText` 的事件。异步动作通过 `FlutterError.reportError` 报告失败。

- [ ] **Step 4: 替换 `PlayerItem` 的手工键盘监听**

保留现有 `handleShortcut*` 动作，删除 `handleShortcutDown`、`handleShortcutLongPress` 和底层 `KeyboardListener.onKeyEvent` 分支。将现有动作映射传给新组件：

同时将 `keyboardActions` 字段类型改为 `Map<String, PlayerShortcutAction>`，使同步和异步动作共用同一映射。

```dart
PlayerKeyboardShortcuts(
  focusScopeNode: playerFocusNode,
  actions: keyboardActions,
  longPressActions: {
    'forward': PlayerLongPressShortcutActions(
      onRepeat: handleShortcutForwardRepeat,
      onRelease: handleShortcutForwardUp,
    ),
  },
  isBlocked: () => showSubtitleOverlay,
),
```

底部弹窗和其他路由由分发器的 `ModalRoute.isCurrent` 判断阻断，不在 `PlayerItem` 中额外保存弹窗布尔值。

- [ ] **Step 5: 验证并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\player_keyboard_shortcuts_test.dart`

Expected: 全部 PASS。

```powershell
git add lib/pages/player/player_keyboard_shortcuts.dart lib/pages/player/player_item.dart test/player_keyboard_shortcuts_test.dart
git commit -m "feat: 统一播放器快捷键分发"
```

### Task 4: 增加统一 HUD 和截图反馈

**Files:**
- Create: `lib/pages/player/player_adjustment_hud.dart`
- Create: `lib/pages/player/player_screenshot_feedback_overlay.dart`
- Create: `test/player_adjustment_hud_test.dart`
- Create: `test/player_screenshot_feedback_overlay_test.dart`

- [ ] **Step 1: 先写反馈 Widget 测试**

```dart
testWidgets('音量 HUD 显示百分比且不拦截点击', (tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: Stack(children: [
      PlayerAdjustmentHud(
        feedback: PlayerAdjustmentFeedback.volume(value: 42, muted: false),
      ),
    ]),
  ));
  expect(find.text('42%'), findsOneWidget);
  expect(find.byType(IgnorePointer), findsWidgets);
});

testWidgets('截图序号变化时显示后自动消失', (tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: PlayerScreenshotFeedbackOverlay(serial: 0),
  ));
  expect(find.byKey(const Key('screenshot-feedback-border')), findsNothing);
  await tester.pumpWidget(const MaterialApp(
    home: PlayerScreenshotFeedbackOverlay(serial: 1),
  ));
  expect(find.byKey(const Key('screenshot-feedback-border')), findsOneWidget);
  await tester.pump(StyleString.animationDuration * 2);
  expect(find.byKey(const Key('screenshot-feedback-border')), findsNothing);
});
```

- [ ] **Step 2: 运行并确认类缺失**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\player_adjustment_hud_test.dart test\player_screenshot_feedback_overlay_test.dart`

Expected: FAIL，新 Widget 不存在。

- [ ] **Step 3: 实现反馈模型与 Widget**

`PlayerAdjustmentFeedback` 使用密封的 `seek`、`volume`、`speed` 工厂，Widget 只读模型并置于 `IgnorePointer` 内。使用现有 `StyleString.animationDuration` 和主题色，不新增颜色常量。

```dart
class PlayerAdjustmentFeedback {
  const PlayerAdjustmentFeedback._(this.kind, this.value, this.label);
  final PlayerAdjustmentKind kind;
  final double value;
  final String label;

  factory PlayerAdjustmentFeedback.volume({
    required double value,
    required bool muted,
  }) => PlayerAdjustmentFeedback._(
        PlayerAdjustmentKind.volume,
        value.clamp(0, 100),
        muted ? '已静音' : '${value.clamp(0, 100).round()}%',
      );
}
```

截图反馈以递增 `serial` 作为触发信号，`didUpdateWidget` 遇到新序号时重启动画；销毁时 dispose controller。

- [ ] **Step 4: 验证并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\player_adjustment_hud_test.dart test\player_screenshot_feedback_overlay_test.dart`

Expected: PASS。

```powershell
git add lib/pages/player/player_adjustment_hud.dart lib/pages/player/player_screenshot_feedback_overlay.dart test/player_adjustment_hud_test.dart test/player_screenshot_feedback_overlay_test.dart
git commit -m "feat: 增加播放器操作反馈"
```

### Task 5: 在播放器面板中接入 hold 与反馈

**Files:**
- Modify: `lib/pages/player/player_item.dart`
- Modify: `lib/pages/player/player_item_panel.dart`
- Modify: `lib/pages/player/smallest_player_item_panel.dart`
- Modify: `lib/pages/player/widgets/embedded_track_menus.dart`
- Create: `test/player_modernization_integration_test.dart`

- [ ] **Step 1: 写接入边界失败测试**

测试读取四个源码文件，保护以下结构：

```dart
test('播放器组合 hold、HUD 和截图反馈', () {
  final item = File('lib/pages/player/player_item.dart').readAsStringSync();
  final panels = [
    File('lib/pages/player/player_item_panel.dart').readAsStringSync(),
    File('lib/pages/player/smallest_player_item_panel.dart').readAsStringSync(),
    File('lib/pages/player/widgets/embedded_track_menus.dart').readAsStringSync(),
  ].join('\n');
  expect(item, contains('PlayerPanelHold('));
  expect(item, contains('PlayerAdjustmentHud('));
  expect(item, contains('PlayerScreenshotFeedbackOverlay('));
  expect(panels, contains('PlayerPanelHoldLease'));
  expect(panels, isNot(contains('playerController.canHidePlayerPanel = false')));
});
```

- [ ] **Step 2: 验证失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\player_modernization_integration_test.dart`

Expected: FAIL，现有面板仍手工切换 `canHidePlayerPanel`。

- [ ] **Step 3: 在 `PlayerItem` 创建单一 hold**

```dart
late final PlayerPanelHold panelHold;
```

在现有 `initState()` 的 `super.initState();` 之后插入：

```dart
panelHold = PlayerPanelHold(
  onFirstAcquire: cancelHideTimer,
  onLastRelease: startHideTimer,
);
```

`startHideTimer` 的回调在隐藏前再检查 `panelHold.isHeld`；`dispose` 先调用 `panelHold.dispose()` 再取消 timer。

- [ ] **Step 4: 菜单使用 lease**

`EmbeddedTrackMenus`、两个面板的倍速/比例/更多菜单在 `onOpen` 获取 lease，`onClose` 释放并置空。每个菜单对应一个独立 lease，不再直接写 `canHidePlayerPanel`。

- [ ] **Step 5: 接入 HUD 和截图序号**

`PlayerItem` 保存当前 `PlayerAdjustmentFeedback?` 和 `_screenshotFeedbackSerial`。快进快退、滚轮音量、快捷键音量及长按倍速成功后更新 feedback；截图写入成功后递增 serial。

在播放器 `Stack` 的控制栏之前、视频画面之后插入：

```dart
PlayerAdjustmentHud(feedback: adjustmentFeedback),
PlayerScreenshotFeedbackOverlay(serial: _screenshotFeedbackSerial),
```

- [ ] **Step 6: 验证并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\player_panel_hold_test.dart test\player_adjustment_hud_test.dart test\player_screenshot_feedback_overlay_test.dart test\player_modernization_integration_test.dart`

Expected: PASS。

```powershell
git add lib/pages/player/player_item.dart lib/pages/player/player_item_panel.dart lib/pages/player/smallest_player_item_panel.dart lib/pages/player/widgets/embedded_track_menus.dart test/player_modernization_integration_test.dart
git commit -m "feat: 接入播放器面板保持与反馈"
```

### Task 6: 隔离字幕面板滚轮与音量滚轮

**Files:**
- Modify: `lib/pages/player/player_item.dart`
- Modify: `lib/pages/player/widgets/subtitle_settings_overlay.dart`
- Create: `test/subtitle_panel_scroll_isolation_test.dart`

- [ ] **Step 1: 写滚轮判断失败测试**

为可单测判断新增顶层函数：

```dart
bool shouldAdjustPlayerVolumeForScroll({
  required bool subtitlePanelOpen,
  required bool pointerOverSubtitlePanel,
}) => !(subtitlePanelOpen && pointerOverSubtitlePanel);
```

测试：

```dart
test('字幕面板实体区域独占滚轮', () {
  expect(shouldAdjustPlayerVolumeForScroll(
    subtitlePanelOpen: true,
    pointerOverSubtitlePanel: true,
  ), isFalse);
  expect(shouldAdjustPlayerVolumeForScroll(
    subtitlePanelOpen: true,
    pointerOverSubtitlePanel: false,
  ), isTrue);
  expect(shouldAdjustPlayerVolumeForScroll(
    subtitlePanelOpen: false,
    pointerOverSubtitlePanel: true,
  ), isTrue);
});
```

- [ ] **Step 2: 验证函数缺失**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\subtitle_panel_scroll_isolation_test.dart`

Expected: FAIL，`shouldAdjustPlayerVolumeForScroll` 不存在。

- [ ] **Step 3: 接入 `MouseRegion` 与 hold**

`SubtitleSettingsOverlay` 新增：

```dart
final ValueChanged<bool> onPointerHoverChanged;
```

仅在可见面板容器外包裹 `MouseRegion`，`onEnter` 报告 true，`onExit` 报告 false。`PlayerItem` 保存 `_isPointerOverSubtitlePanel`，打开字幕面板时获取 hold，关闭时清除指针状态并释放 hold。

- [ ] **Step 4: 在音量滚轮前返回**

```dart
if (!shouldAdjustPlayerVolumeForScroll(
  subtitlePanelOpen: showSubtitleSettingsOverlay,
  pointerOverSubtitlePanel: _isPointerOverSubtitlePanel,
)) {
  return;
}
```

这个判断不读取 `ScrollPosition`，因此面板到达顶部或底部后仍然隔离音量。

- [ ] **Step 5: 验证并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\subtitle_panel_scroll_isolation_test.dart test\player_panel_hold_test.dart`

Expected: PASS。

```powershell
git add lib/pages/player/player_item.dart lib/pages/player/widgets/subtitle_settings_overlay.dart test/subtitle_panel_scroll_isolation_test.dart
git commit -m "fix: 隔离字幕面板滚轮与音量"
```

### Task 7: 串行合并字幕样式预览

**Files:**
- Create: `lib/pages/player/latest_value_serial_executor.dart`
- Create: `test/latest_value_serial_executor_test.dart`
- Modify: `lib/pages/player/player_controller.dart`
- Modify: `lib/pages/player/widgets/subtitle_settings_overlay.dart`
- Modify: `test/local_video_controller_test.dart`
- Regenerate: `lib/pages/player/player_controller.g.dart`

- [ ] **Step 1: 为串行执行器写失败测试**

```dart
test('同步期间只保留最新值且不并发', () async {
  final firstGate = Completer<void>();
  final applied = <int>[];
  var running = 0;
  var maxRunning = 0;
  final executor = LatestValueSerialExecutor<int>((value) async {
    running++;
    maxRunning = math.max(maxRunning, running);
    applied.add(value);
    if (value == 1) await firstGate.future;
    running--;
  });

  final drain = executor.schedule(1);
  executor.schedule(2);
  executor.schedule(3);
  firstGate.complete();
  await drain;
  expect(applied, [1, 3]);
  expect(maxRunning, 1);
});
```

再测试 `dispose()` 后 `schedule` 不启动新任务。

- [ ] **Step 2: 验证类缺失**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\latest_value_serial_executor_test.dart`

Expected: FAIL，`LatestValueSerialExecutor` 不存在。

- [ ] **Step 3: 实现通用执行器**

```dart
class LatestValueSerialExecutor<T> {
  LatestValueSerialExecutor(this._apply);
  final Future<void> Function(T value) _apply;
  T? _pending;
  Future<void>? _drain;
  bool _disposed = false;

  Future<void> schedule(T value) {
    if (_disposed) return Future.value();
    _pending = value;
    return _drain ??= _run();
  }

  Future<void> _run() async {
    try {
      while (!_disposed && _pending != null) {
        final value = _pending as T;
        _pending = null;
        await _apply(value);
      }
    } finally {
      _drain = null;
    }
  }

  void dispose() {
    _disposed = true;
    _pending = null;
  }
}
```

- [ ] **Step 4: 为字幕样式建立不可变快照**

在 `player_controller.dart` 定义 `SubtitleStyleSnapshot`，包含 `fontSize`、`colorValue`、`borderColorValue`、`borderSize`、`shadowEnabled`、`shadowOffset`、`position`、`forceStyle`。将 `_syncSubtitleStyleToPlayer` 改为接收快照，整组 MPV 属性只读该快照。

```dart
Future<void> previewSubtitleStyle({
  double? fontSize,
  int? colorValue,
  int? borderColorValue,
  double? borderSize,
  bool? shadowEnabled,
  double? shadowOffset,
  double? position,
  bool? forceStyle,
}) async {
  _updateSubtitleStyleState(
    fontSize: fontSize,
    colorValue: colorValue,
    borderColorValue: borderColorValue,
    borderSize: borderSize,
    shadowEnabled: shadowEnabled,
    shadowOffset: shadowOffset,
    position: position,
    forceStyle: forceStyle,
  );
  await _subtitleStyleExecutor.schedule(_subtitleStyleSnapshot());
}

Future<void> commitSubtitleStyle() => _saveSubtitleStyleSettings();
```

`latest_value_serial_executor_test.dart` 显式导入 `dart:async` 和 `dart:math` as `math`。`_updateSubtitleStyleState` 复用现有 `applySubtitleStyle` 中的赋值与 clamp 规则，`_subtitleStyleSnapshot()` 一次读取全部字段构建不可变对象。

`dispose()` 中先 dispose executor，防止切集或销毁后排入新同步。离散操作继续通过 `applySubtitleStyle`完成预览和立即保存。

- [ ] **Step 5: 拆分滑块的预览和提交**

`_SubtitleSlider` 新增：

```dart
final ValueChanged<double>? onChangeEnd;
```

字号、位置、描边和阴影滑块的 `onChanged` 调用 `previewSubtitleStyle`，`onChangeEnd` 调用 `commitSubtitleStyle`。强制样式、颜色、阴影开关和恢复默认继续立即保存。

- [ ] **Step 6: 更新界面结构测试并生成 MobX 代码**

`local_video_controller_test.dart` 断言滑块源码同时包含 `previewSubtitleStyle` 和 `commitSubtitleStyle`，离散操作仍包含 `applySubtitleStyle`。

Run: `D:\flutter\bin\cache\dart-sdk\bin\dart.exe run build_runner build --delete-conflicting-outputs`

Expected: `player_controller.g.dart` 与新动作签名一致。

- [ ] **Step 7: 验证并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\latest_value_serial_executor_test.dart test\local_video_controller_test.dart`

Expected: PASS。

```powershell
git add lib/pages/player/latest_value_serial_executor.dart lib/pages/player/player_controller.dart lib/pages/player/player_controller.g.dart lib/pages/player/widgets/subtitle_settings_overlay.dart test/latest_value_serial_executor_test.dart test/local_video_controller_test.dart
git commit -m "fix: 串行合并字幕样式同步"
```

### Task 8: 版本、回归测试与正式 MSIX 交付

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/request/config/api_endpoints.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `README.md`
- Modify: `test/version_consistency_test.dart`

- [ ] **Step 1: 先更新版本测试为 1.0.1**

```dart
const expectedVersion = '1.0.1';
const expectedBuildNumber = '10001';
```

在当前版本文案检查中新增：

```dart
for (final text in [
  '播放器交互',
  '字幕面板',
  '快捷键',
]) {
  expect(currentCopy, contains(text));
}
```

- [ ] **Step 2: 验证版本测试失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\version_consistency_test.dart`

Expected: FAIL，当前仍为 `1.0.0+10000`。

- [ ] **Step 3: 更新版本和用户文案**

- `pubspec.yaml`: `version: 1.0.1+10001`，`msix_version: 1.0.1.0`。
- `api_endpoints.dart`: 版本常量改为 `1.0.1`。
- `README.md`: 当前版本改为 `1.0.1`，保留 Kazumi 来源和网盘未完成说明。
- `RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`version_history.dart`: 面向普通用户说明播放器交互、字幕面板和快捷键稳定性提升，不宣称历史记录、断点续播或隐身模式。

- [ ] **Step 4: 运行格式、定向测试和全量验证**

```powershell
& 'D:\flutter\bin\cache\dart-sdk\bin\dart.exe' format lib test
& 'D:\flutter\bin\flutter.bat' test --no-pub --reporter compact
& 'D:\flutter\bin\flutter.bat' analyze --no-pub
```

Expected: 全量测试 PASS，静态分析输出 `No issues found!`。

- [ ] **Step 5: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: `build\windows\x64\runner\Release\kanyingyin.exe` 和 `data\app.so` 时间戳晚于本轮源码修改。

- [ ] **Step 6: 使用 DPAPI 密码生成 MSIX**

从 `%USERPROFILE%\.kanyingyin\signing\certificate-password.clixml` 读取 `SecureString`，解密值只存在于当前 PowerShell 变量：

```powershell
& 'D:\flutter\bin\cache\dart-sdk\bin\dart.exe' run msix:create --build-windows false --certificate-password $password
```

Expected: 生成 `build\windows\x64\runner\Release\kanyingyin.msix`。

- [ ] **Step 7: 验证清单、签名和桌面文件**

验证 `AppxManifest.xml`:

```text
Identity.Name=com.kanyingyin.player
Identity.Version=1.0.1.0
Publisher=CN=KanYingYin
```

`Get-AuthenticodeSignature` 必须为 `Valid`。复制为：

```powershell
Copy-Item 'build\windows\x64\runner\Release\kanyingyin.msix' "$env:USERPROFILE\Desktop\看影音-1.0.1.msix" -Force
```

- [ ] **Step 8: 审查、提交且不推送 Release**

Run: `git status --short` 和 `git diff --check`，确认 `.learnings/ERRORS.md` 和 `.learnings/LEARNINGS.md` 不在暂存区。

```powershell
git add pubspec.yaml lib/request/config/api_endpoints.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/utils/version_history.dart README.md test/version_consistency_test.dart
git commit -m "release: 发布播放器交互更新 1.0.1"
```

Expected: 本地 `main` 完成交付提交，本计划不覆盖或修改现有 GitHub `v1.0` Release；只在用户后续明确要求发布 GitHub Release 时创建新标签。
