# Single Log Entry Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为运行记录中的每条日志增加一键复制完整脱敏原文的入口，并保留现有展开和复制全部行为。

**Architecture:** `LogEventTile` 只通过新增的 `onCopy` 回调暴露复制动作；`LogsPage` 继续作为剪贴板和 Toast 编排层。测试先覆盖组件事件隔离，再覆盖页面复制内容，避免表现组件直接依赖平台服务。

**Tech Stack:** Flutter、Dart、Flutter Widget Test、System Clipboard

---

### Task 1: 日志事件卡复制交互

**Files:**
- Modify: `lib/features/logs/presentation/log_event_tile.dart`
- Test: `test/log_presentation_components_test.dart`

- [x] **Step 1: 编写失败的组件测试**

在现有“事件点击后展开完整原文”测试中传入空 `onCopy`，并新增测试：

```dart
testWidgets('事件复制按钮只触发复制而不展开', (tester) async {
  var toggleCount = 0;
  var copyCount = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LogEventTile(
          event: warning,
          expanded: false,
          onToggle: () => toggleCount += 1,
          onCopy: () => copyCount += 1,
        ),
      ),
    ),
  );

  await tester.tap(find.byTooltip('复制此条日志'));
  await tester.pump();

  expect(copyCount, 1);
  expect(toggleCount, 0);
});
```

- [x] **Step 2: 运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test/log_presentation_components_test.dart`

Expected: FAIL，提示 `LogEventTile` 没有 `onCopy` 参数或找不到“复制此条日志”。

- [x] **Step 3: 实现最小组件改动**

给 `LogEventTile` 增加必填的 `VoidCallback onCopy`，并在展开箭头前加入：

```dart
IconButton(
  tooltip: '复制此条日志',
  visualDensity: VisualDensity.compact,
  icon: const Icon(Icons.copy_outlined, size: 18),
  onPressed: onCopy,
),
const SizedBox(width: 2),
```

- [x] **Step 4: 运行组件测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test/log_presentation_components_test.dart`

Expected: PASS。

### Task 2: 页面剪贴板编排与完整原文验证

**Files:**
- Modify: `lib/pages/logs/logs_page.dart`
- Test: `test/logs_page_test.dart`

- [x] **Step 1: 编写失败的页面测试**

新增 Widget 测试，使用现有 `SystemChannels.platform` Mock 捕获剪贴板内容，点击错误事件卡内的复制按钮：

```dart
testWidgets('单条复制只写入对应日志的完整原文', (tester) async {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') calls.add(call);
    return null;
  });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  final reader = await readerWith('''
[2026-07-23T10:00:00.000] INFO
媒体库扫描完成
[2026-07-23T10:01:00.000] ERROR
播放器失败
错误详情第二行
''');
  await pumpLogs(tester, reader);

  final errorTile = find.byKey(const ValueKey('log-event-1'));
  await tester.tap(find.descendant(
    of: errorTile,
    matching: find.byTooltip('复制此条日志'),
  ));
  await tester.pump();

  final payload = calls.single.arguments as Map<Object?, Object?>;
  expect(payload['text'], contains('播放器失败\n错误详情第二行'));
  expect(payload['text'], isNot(contains('媒体库扫描完成')));
});
```

- [x] **Step 2: 运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test/logs_page_test.dart`

Expected: FAIL，页面事件卡尚未提供复制入口。

- [x] **Step 3: 实现页面复制动作**

在 `LogsPage` State 中新增：

```dart
Future<void> _copyEvent(LogEventViewData event) async {
  try {
    await Clipboard.setData(ClipboardData(text: event.rawText));
    if (!mounted) return;
    AppDialog.showToast(message: '日志已复制');
  } on Object {
    if (!mounted) return;
    AppDialog.showToast(message: '复制日志失败，请稍后重试');
  }
}
```

构建事件卡时连接回调：

```dart
onCopy: () => unawaited(_copyEvent(event)),
```

- [x] **Step 4: 运行日志相关测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test test/log_presentation_components_test.dart test/logs_page_test.dart`

Expected: PASS，现有“复制全部”测试同时保持通过。

- [x] **Step 5: 格式化并执行静态检查**

Run: `D:\flutter\bin\dart.bat format lib/features/logs/presentation/log_event_tile.dart lib/pages/logs/logs_page.dart test/log_presentation_components_test.dart test/logs_page_test.dart`

Expected: 四个文件格式化完成且 UTF-8 内容未损坏。

Run: `D:\flutter\bin\flutter.bat analyze`

Expected: `No issues found!`
