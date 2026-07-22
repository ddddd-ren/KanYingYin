# 日志展示与媒体库工具栏轻量优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将原始日志列表升级为可搜索、可筛选、可展开原文的运行记录页面，并在不改变功能顺序和回调的前提下轻量优化媒体库路径工具栏。

**Architecture:** 在 `features/logs/presentation` 中新增纯 Dart 日志事件模型、解析/查询逻辑和小型表现组件，`LogsPage` 只负责读取、分页、搜索筛选状态以及现有复制/清理编排。`LibraryPathBar` 保持现有 ViewData、回调和三行结构，只调整 Material 表面、按钮状态、路径裁切、排序胶囊与搜索框样式。

**Tech Stack:** Flutter 3.41.9、Dart、Material 3、Flutter Modular、flutter_test、Windows MSIX。

---

## 文件结构

- `lib/features/logs/presentation/log_event_view_data.dart`：日志事件模型、等级分类、解析、排序与关键词/等级过滤。
- `lib/features/logs/presentation/log_motion.dart`：日志页展开与状态动画时序及减少动画适配。
- `lib/features/logs/presentation/log_overview_panel.dart`：健康结论和全部/提醒/错误计数。
- `lib/features/logs/presentation/log_filter_bar.dart`：关键词搜索、清空搜索、等级筛选和结果数量。
- `lib/features/logs/presentation/log_event_tile.dart`：可展开的单条事件与完整原文。
- `lib/features/logs/presentation/log_state_panel.dart`：加载、空数据、无搜索结果和读取失败状态。
- `lib/features/logs/presentation/logs_presentation.dart`：日志表现组件统一导出。
- `lib/pages/logs/logs_page.dart`：日志读取、分页、筛选状态、复制和清理动作编排。
- `lib/features/library/presentation/library_path_bar.dart`：保持原结构的工具栏轻量视觉调整。
- `test/log_event_view_data_test.dart`：解析、分类、排序、原文保留和搜索过滤纯 Dart 测试。
- `test/log_presentation_components_test.dart`：健康摘要、筛选、事件展开与减少动画 Widget 测试。
- `test/logs_page_test.dart`：日志页异步状态、搜索、复制/清空、分页和多宽度测试。
- `test/library_presentation_components_test.dart`：工具栏视觉契约、多宽度布局和动作转发回归。
- 版本文件：`pubspec.yaml`、`lib/core/app_version.dart`、`README.md`、`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`lib/utils/version_history.dart`、`test/version_consistency_test.dart`、`test/identity_v2_zero_residue_test.dart`。

### Task 1: 日志事件解析、分类和搜索

**Files:**
- Create: `test/log_event_view_data_test.dart`
- Create: `lib/features/logs/presentation/log_event_view_data.dart`

- [ ] **Step 1: 编写解析与查询失败测试**

创建 `test/log_event_view_data_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/logs/presentation/log_event_view_data.dart';

void main() {
  const content = '''
[2026-07-23T10:00:00.000] INFO
[i] 10:00:00 INFO    媒体库扫描完成
[2026-07-23T10:01:00.000] WARNING
┌────────────────
│ 海报请求超时
└────────────────
[2026-07-23T10:02:00.000] ERROR
│ Player failed to open file
│ stack line
[2026-07-23T10:03:00.000] PLAYER
播放器资源已释放
''';

  test('按头部解析、分类并按时间倒序', () {
    final events = LogEventParser.parse(content);

    expect(events, hasLength(4));
    expect(events.map((event) => event.level), [
      'PLAYER',
      'ERROR',
      'WARNING',
      'INFO',
    ]);
    expect(events[0].category, LogEventCategory.normal);
    expect(events[1].category, LogEventCategory.error);
    expect(events[2].category, LogEventCategory.warning);
    expect(events[3].summary, '媒体库扫描完成');
  });

  test('多行事件保留完整脱敏原文', () {
    final warning = LogEventParser.parse(content)[2];

    expect(warning.summary, '海报请求超时');
    expect(warning.rawText, contains('[2026-07-23T10:01:00.000] WARNING'));
    expect(warning.rawText, contains('┌────────────────'));
    expect(warning.rawText, contains('│ 海报请求超时'));
  });

  test('未知格式形成其他记录且不丢失原文', () {
    final events = LogEventParser.parse('孤立记录\n第二行');

    expect(events, hasLength(1));
    expect(events.single.category, LogEventCategory.other);
    expect(events.single.summary, '孤立记录');
    expect(events.single.rawText, '孤立记录\n第二行');
  });

  test('无效时间保留原始相对顺序', () {
    const invalid = '''
[invalid-one] INFO
第一条
[invalid-two] ERROR
第二条
''';
    final events = LogEventParser.parse(invalid);

    expect(events.map((event) => event.summary), ['第一条', '第二条']);
  });

  test('关键词搜索摘要和原文且英文不区分大小写', () {
    final events = LogEventParser.parse(content);

    expect(
      LogEventQuery.apply(events, query: 'player'),
      hasLength(2),
    );
    expect(
      LogEventQuery.apply(events, query: ' 海报请求 '),
      hasLength(1),
    );
  });

  test('等级筛选与关键词搜索叠加', () {
    final events = LogEventParser.parse(content);

    expect(
      LogEventQuery.apply(
        events,
        filter: LogEventFilter.errors,
        query: 'open file',
      ).single.category,
      LogEventCategory.error,
    );
    expect(
      LogEventQuery.apply(
        events,
        filter: LogEventFilter.warnings,
        query: 'open file',
      ),
      isEmpty,
    );
  });
}
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\log_event_view_data_test.dart
```

Expected: FAIL，提示 `log_event_view_data.dart` 或类型不存在；失败不能来自依赖缓存或语法错误。

- [ ] **Step 3: 实现日志事件模型、解析和查询**

创建 `lib/features/logs/presentation/log_event_view_data.dart`，使用以下公开 API：

```dart
import 'dart:collection';

enum LogEventCategory { normal, warning, error, other }

enum LogEventFilter { all, warnings, errors }

class LogEventViewData {
  const LogEventViewData({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.category,
    required this.summary,
    required this.rawText,
    required this.sourceIndex,
  });

  final int id;
  final DateTime? timestamp;
  final String level;
  final LogEventCategory category;
  final String summary;
  final String rawText;
  final int sourceIndex;
}

abstract final class LogEventParser {
  static final RegExp _header = RegExp(
    r'^\[([^\]]+)\]\s+(TRACE|DEBUG|INFO|WARNING|ERROR|FATAL|PLAYER)\s*$',
  );
  static final RegExp _compactLine = RegExp(
    r'^\[[^\]]+\]\s+.*?\b(?:TRACE|DEBUG|INFO|WARNING|ERROR|FATAL)\s+(.*)$',
  );
  static final RegExp _frameOnly = RegExp(r'^[┌┐└┘├┤┄─│╡═\s]+$');
  static final RegExp _framePrefix = RegExp(r'^[┌┐└┘├┤┄─│╡═\s]+');

  static List<LogEventViewData> parse(String content) {
    if (content.trim().isEmpty) return const [];
    final chunks = <_LogChunk>[];
    _LogChunk? current;
    for (final line in content.split('\n')) {
      final match = _header.firstMatch(line.trimRight());
      if (match != null) {
        if (current != null) chunks.add(current);
        current = _LogChunk(
          header: line,
          timestampText: match.group(1)!,
          level: match.group(2)!,
          lines: <String>[],
          sourceIndex: chunks.length,
        );
      } else if (current == null) {
        if (line.trim().isEmpty) continue;
        current = _LogChunk(
          header: '',
          timestampText: '',
          level: 'OTHER',
          lines: <String>[line],
          sourceIndex: chunks.length,
        );
      } else {
        current.lines.add(line);
      }
    }
    if (current != null) chunks.add(current);

    final events = chunks.map(_toViewData).toList()
      ..sort((left, right) {
        if (left.timestamp != null && right.timestamp != null) {
          return right.timestamp!.compareTo(left.timestamp!);
        }
        if (left.timestamp == null && right.timestamp == null) {
          return left.sourceIndex.compareTo(right.sourceIndex);
        }
        return left.timestamp == null ? 1 : -1;
      });
    return UnmodifiableListView(events);
  }

  static LogEventViewData _toViewData(_LogChunk chunk) {
    final rawLines = <String>[
      if (chunk.header.isNotEmpty) chunk.header,
      ...chunk.lines,
    ];
    return LogEventViewData(
      id: chunk.sourceIndex,
      timestamp: DateTime.tryParse(chunk.timestampText),
      level: chunk.level,
      category: _categoryFor(chunk.level),
      summary: _summaryFor(chunk.lines, chunk.level),
      rawText: rawLines.join('\n').trimRight(),
      sourceIndex: chunk.sourceIndex,
    );
  }

  static LogEventCategory _categoryFor(String level) => switch (level) {
        'WARNING' => LogEventCategory.warning,
        'ERROR' || 'FATAL' => LogEventCategory.error,
        'TRACE' || 'DEBUG' || 'INFO' || 'PLAYER' => LogEventCategory.normal,
        _ => LogEventCategory.other,
      };

  static String _summaryFor(List<String> lines, String level) {
    for (final line in lines) {
      final compact = _compactLine.firstMatch(line.trim())?.group(1)?.trim();
      if (compact?.isNotEmpty == true) return compact!;
      if (_frameOnly.hasMatch(line)) continue;
      final cleaned = line.replaceFirst(_framePrefix, '').trim();
      if (cleaned.isNotEmpty) return cleaned;
    }
    return level == 'OTHER' ? '其他记录' : '$level 记录';
  }
}

abstract final class LogEventQuery {
  static List<LogEventViewData> apply(
    Iterable<LogEventViewData> events, {
    LogEventFilter filter = LogEventFilter.all,
    String query = '',
  }) {
    final needle = query.trim().toLowerCase();
    return List<LogEventViewData>.unmodifiable(
      events.where((event) {
        final categoryMatches = switch (filter) {
          LogEventFilter.all => true,
          LogEventFilter.warnings =>
            event.category == LogEventCategory.warning,
          LogEventFilter.errors => event.category == LogEventCategory.error,
        };
        if (!categoryMatches) return false;
        if (needle.isEmpty) return true;
        return '${event.summary}\n${event.rawText}'
            .toLowerCase()
            .contains(needle);
      }),
    );
  }
}

class _LogChunk {
  _LogChunk({
    required this.header,
    required this.timestampText,
    required this.level,
    required this.lines,
    required this.sourceIndex,
  });

  final String header;
  final String timestampText;
  final String level;
  final List<String> lines;
  final int sourceIndex;
}
```

- [ ] **Step 4: 运行解析测试并转绿**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\features\logs\presentation\log_event_view_data.dart test\log_event_view_data_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\log_event_view_data_test.dart
```

Expected: 全部通过。

- [ ] **Step 5: 提交日志解析能力**

```powershell
git add lib\features\logs\presentation\log_event_view_data.dart test\log_event_view_data_test.dart
git commit -m "建立日志事件解析与搜索模型"
```

### Task 2: 日志页表现组件

**Files:**
- Create: `test/log_presentation_components_test.dart`
- Create: `lib/features/logs/presentation/log_motion.dart`
- Create: `lib/features/logs/presentation/log_overview_panel.dart`
- Create: `lib/features/logs/presentation/log_filter_bar.dart`
- Create: `lib/features/logs/presentation/log_event_tile.dart`
- Create: `lib/features/logs/presentation/log_state_panel.dart`
- Create: `lib/features/logs/presentation/logs_presentation.dart`

- [ ] **Step 1: 编写组件失败测试**

创建 `test/log_presentation_components_test.dart`，覆盖以下行为：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/logs/presentation/logs_presentation.dart';

void main() {
  const warning = LogEventViewData(
    id: 1,
    timestamp: null,
    level: 'WARNING',
    category: LogEventCategory.warning,
    summary: '海报请求超时',
    rawText: '[time] WARNING\n海报请求超时',
    sourceIndex: 1,
  );

  testWidgets('健康摘要展示计数与提醒结论', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LogOverviewPanel(total: 8, warnings: 2, errors: 0),
        ),
      ),
    );

    expect(find.text('有少量运行提醒'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('搜索与等级筛选转发用户输入', (tester) async {
    var query = '';
    var filter = LogEventFilter.all;
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LogFilterBar(
            controller: controller,
            filter: filter,
            visibleCount: 3,
            onQueryChanged: (value) => query = value,
            onClearQuery: () => query = '',
            onFilterChanged: (value) => filter = value,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '播放器');
    await tester.tap(find.text('提醒'));
    expect(query, '播放器');
    expect(filter, LogEventFilter.warnings);
  });

  testWidgets('事件点击后展开完整原文', (tester) async {
    var expanded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: LogEventTile(
              event: warning,
              expanded: expanded,
              onToggle: () => setState(() => expanded = !expanded),
            ),
          ),
        ),
      ),
    );

    expect(find.text(warning.rawText), findsNothing);
    await tester.tap(find.text('海报请求超时'));
    await tester.pumpAndSettle();
    expect(find.text(warning.rawText), findsOneWidget);
  });

  testWidgets('减少动画时日志动效不超过八十毫秒', (tester) async {
    late Duration duration;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              duration = LogMotion.duration(context, LogMotion.expandDuration);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(duration, lessThanOrEqualTo(const Duration(milliseconds: 80)));
  });

  testWidgets('状态面板区分加载、空数据和失败', (tester) async {
    for (final state in LogStateKind.values) {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LogStatePanel(kind: state))),
      );
      expect(find.byKey(ValueKey('log-state-${state.name}')), findsOneWidget);
    }
  });
}
```

- [ ] **Step 2: 运行组件测试并确认 RED**

Run:

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\log_presentation_components_test.dart
```

Expected: FAIL，提示日志表现组件不存在。

- [ ] **Step 3: 实现统一动效和状态面板**

`log_motion.dart` 提供：

```dart
import 'package:flutter/material.dart';

abstract final class LogMotion {
  static const expandDuration = Duration(milliseconds: 180);
  static const stateDuration = Duration(milliseconds: 160);
  static const reducedDuration = Duration(milliseconds: 80);
  static const curve = Curves.easeOutCubic;

  static Duration duration(BuildContext context, Duration normal) =>
      MediaQuery.disableAnimationsOf(context) ? reducedDuration : normal;
}
```

`log_state_panel.dart` 定义 `LogStateKind { loading, empty, noResults, error }`，通过 `ValueKey('log-state-${kind.name}')` 暴露测试契约。`loading` 显示 `CircularProgressIndicator`；`empty`、`noResults`、`error` 的标题依次为“暂无运行记录”“没有匹配的记录”“加载运行记录失败”。组件使用居中、圆角、边框和图标，不包含重试或业务回调。

- [ ] **Step 4: 实现健康摘要、筛选栏和事件卡**

公开构造签名必须保持为：

```dart
const LogOverviewPanel({
  super.key,
  required this.total,
  required this.warnings,
  required this.errors,
});

const LogFilterBar({
  super.key,
  required this.controller,
  required this.filter,
  required this.visibleCount,
  required this.onQueryChanged,
  required this.onClearQuery,
  required this.onFilterChanged,
});

const LogEventTile({
  super.key,
  required this.event,
  required this.expanded,
  required this.onToggle,
});
```

`LogOverviewPanel` 在 `errors > 0` 时显示“发现需要关注的问题”，在 `errors == 0 && warnings > 0` 时显示“有少量运行提醒”，否则显示“运行状态良好”。`LogFilterBar` 使用一个带清空按钮的 `TextField` 和三个 `ChoiceChip`；`LogEventTile` 使用 `Semantics(button: true, expanded: expanded)`、`InkWell` 与 `AnimatedSize(duration: LogMotion.duration(context, LogMotion.expandDuration), curve: LogMotion.curve)`，展开内容使用等宽字体和 `SelectionArea`。

`logs_presentation.dart` 导出本任务和 Task 1 的全部公开文件。

- [ ] **Step 5: 格式化并运行组件测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\features\logs\presentation test\log_presentation_components_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\log_event_view_data_test.dart test\log_presentation_components_test.dart
```

Expected: 全部通过。

- [ ] **Step 6: 提交日志表现组件**

```powershell
git add lib\features\logs\presentation test\log_presentation_components_test.dart
git commit -m "建立运行记录表现组件"
```

### Task 3: 重构 LogsPage 并实装搜索、筛选和展开

**Files:**
- Create: `test/logs_page_test.dart`
- Modify: `lib/pages/logs/logs_page.dart`
- Verify: `test/log_archive_reader_test.dart`

- [ ] **Step 1: 编写页面失败测试**

在 `test/logs_page_test.dart` 使用临时 `RotatingLogWriter` 和真实 `LogArchiveReader` 创建以下辅助函数：

```dart
Future<LogArchiveReader> readerWith(String content) async {
  final root = await Directory.systemTemp.createTemp('logs_page_ui_');
  addTearDown(() => root.delete(recursive: true));
  final writer = RotatingLogWriter(directoryProvider: () async => root);
  await writer.write(content);
  return LogArchiveReader(writer: writer);
}

Future<void> pumpLogs(
  WidgetTester tester,
  LogArchiveReader reader, {
  double width = 900,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: LogsPage(reader: reader)));
  await tester.pumpAndSettle();
}
```

添加测试：

```dart
testWidgets('运行记录展示健康摘要、搜索和等级筛选', (tester) async {
  final reader = await readerWith('''
[2026-07-23T10:00:00.000] INFO
媒体库扫描完成
[2026-07-23T10:01:00.000] WARNING
海报 timeout
[2026-07-23T10:02:00.000] ERROR
播放器 open failed
''');
  await pumpLogs(tester, reader);

  expect(find.text('运行记录'), findsOneWidget);
  expect(find.text('发现需要关注的问题'), findsOneWidget);
  expect(find.byType(TextField), findsOneWidget);

  await tester.enterText(find.byType(TextField), 'timeout');
  await tester.pump();
  expect(find.text('海报 timeout'), findsOneWidget);
  expect(find.text('媒体库扫描完成'), findsNothing);

  await tester.enterText(find.byType(TextField), '');
  await tester.tap(find.text('错误'));
  await tester.pump();
  expect(find.text('播放器 open failed'), findsOneWidget);
  expect(find.text('海报 timeout'), findsNothing);
});

testWidgets('运行记录在三种宽度下无溢出', (tester) async {
  for (final width in <double>[1280, 900, 640]) {
    final reader = await readerWith(
      '[2026-07-23T10:00:00.000] INFO\n媒体库扫描完成',
    );
    await pumpLogs(tester, reader, width: width);
    expect(tester.takeException(), isNull, reason: '窗口宽度 $width');
  }
});
```

增加以下页面状态与动作测试：

```dart
testWidgets('复制全部不受当前搜索过滤影响', (tester) async {
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
''');
  await pumpLogs(tester, reader);
  await tester.enterText(find.byType(TextField), '播放器');
  await tester.tap(find.byTooltip('复制全部'));
  await tester.pump();

  final payload = calls.single.arguments as Map<Object?, Object?>;
  expect(payload['text'], contains('媒体库扫描完成'));
  expect(payload['text'], contains('播放器失败'));
});

testWidgets('清空日志后显示空状态并清除搜索', (tester) async {
  final reader = await readerWith(
    '[2026-07-23T10:00:00.000] INFO\n媒体库扫描完成',
  );
  await pumpLogs(tester, reader);
  await tester.enterText(find.byType(TextField), '扫描');
  await tester.tap(find.byTooltip('清空日志'));
  await tester.pumpAndSettle();

  expect(
    find.byKey(const ValueKey('log-state-empty')),
    findsOneWidget,
  );
  expect(find.text('扫描'), findsNothing);
});

testWidgets('读取异常显示失败状态', (tester) async {
  await pumpLogs(tester, _ThrowingLogArchiveReader());
  expect(
    find.byKey(const ValueKey('log-state-error')),
    findsOneWidget,
  );
});

class _ThrowingLogArchiveReader extends LogArchiveReader {
  @override
  Future<String> readAll() async => throw const FileSystemException('fixture');
}
```

- [ ] **Step 2: 运行页面测试并确认 RED**

Run:

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\logs_page_test.dart
```

Expected: FAIL，因为 `LogsPage` 仍使用原始行列表、没有搜索筛选和新组件。

- [ ] **Step 3: 将页面 State 从行列表迁移为事件列表**

在 `_LogsPageState` 中使用：

```dart
final ScrollController _scrollController = ScrollController();
final TextEditingController _searchController = TextEditingController();
final Set<int> _expandedEventIds = <int>{};
late final LogArchiveReader _reader;

bool _isLoading = true;
bool _hasError = false;
String _fullContent = '';
List<LogEventViewData> _allEvents = const [];
LogEventFilter _filter = LogEventFilter.all;
String _query = '';
int _visibleLimit = 50;

static const int _initialLoadCount = 50;
static const int _loadMoreCount = 100;

List<LogEventViewData> get _filteredEvents => LogEventQuery.apply(
      _allEvents,
      filter: _filter,
      query: _query,
    );

List<LogEventViewData> get _visibleEvents =>
    _filteredEvents.take(_visibleLimit).toList(growable: false);
```

`_loadLogs` 读取成功后设置 `_fullContent = content`、`_allEvents = LogEventParser.parse(content)`、`_visibleLimit = 50`。滚动阈值逻辑比较 `_visibleLimit` 与 `_filteredEvents.length`，每次增加 100。

搜索或筛选变化时清空 `_expandedEventIds` 并把 `_visibleLimit` 重置为 50；清空日志时同时清空搜索控制器、筛选、事件、展开集合和完整内容。

`dispose` 同时释放 `_scrollController` 和 `_searchController`。

- [ ] **Step 4: 用新组件重建页面**

`LogsPage.build` 保留 `SysAppBar`，标题改为“运行记录”，移除 `floatingActionButton`。主体使用最大宽度 1100 的单列布局：

```dart
Scaffold(
  appBar: const SysAppBar(title: Text('运行记录')),
  body: Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: _buildContent(context),
      ),
    ),
  ),
)
```

已加载且有事件时，`_buildContent` 依次构建：

1. `Row`：标题“诊断概览”、`OutlinedButton.icon` 复制全部、`TextButton.icon` 清空；
2. `LogOverviewPanel`；
3. `LogFilterBar`；
4. `Expanded(ListView.builder(... LogEventTile ...))`。

加载、失败、空日志分别使用 `LogStatePanel`。过滤后为空时保留概览与筛选栏，只在列表区域显示 `LogStateKind.noResults`。

- [ ] **Step 5: 运行日志相关测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\pages\logs\logs_page.dart test\logs_page_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\log_event_view_data_test.dart test\log_presentation_components_test.dart test\logs_page_test.dart test\log_archive_reader_test.dart
```

Expected: 全部通过。

- [ ] **Step 6: 提交运行记录页面**

```powershell
git add lib\pages\logs\logs_page.dart test\logs_page_test.dart
git commit -m "重构运行记录展示与搜索"
```

### Task 4: 轻量优化媒体库路径工具栏

**Files:**
- Modify: `test/library_presentation_components_test.dart`
- Modify: `lib/features/library/presentation/library_path_bar.dart`

- [ ] **Step 1: 为视觉契约和多宽度布局编写失败测试**

在现有 `LibraryPathBar` group 中增加以下辅助状态和 `pumpPathBar(width)`：

```dart
final recordedActions = <String>[];
late TextEditingController pathBarSearchController;

setUp(() {
  recordedActions.clear();
  pathBarSearchController = TextEditingController();
});

tearDown(() => pathBarSearchController.dispose());

Future<void> pumpPathBar(
  WidgetTester tester, {
  required double width,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LibraryPathBar(
          data: LibraryPathBarViewData(
            breadcrumbs: const [
              LibraryBreadcrumbViewData(label: 'D:', path: r'D:\'),
              LibraryBreadcrumbViewData(label: 'a TV', path: r'D:\a TV'),
              LibraryBreadcrumbViewData(
                label: '动画',
                path: r'D:\a TV\动画',
                isCurrent: true,
              ),
            ],
            recentPaths: const [],
            sortBy: 'name',
            sortAscending: true,
            status: const LibraryDirectoryStatusViewData(
              kind: LibraryDirectoryStatusKind.idle,
              label: '26 部剧 · 412 个视频',
            ),
          ),
          sourceMenu: const SizedBox(width: 32, height: 32),
          searchController: pathBarSearchController,
          onPickDirectory: () async => recordedActions.add('pick'),
          onRefresh: () async => recordedActions.add('refresh'),
          onSort: (field) async => recordedActions.add('sort:$field'),
          onSearchChanged: (value) => recordedActions.add('search:$value'),
          onClearSearch: () => recordedActions.add('clear-search'),
          onBreadcrumbSelected: (path) async =>
              recordedActions.add('path:$path'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
```

随后添加：

```dart
testWidgets('原工具栏轻量表面在三种宽度下无溢出', (tester) async {
  for (final width in <double>[1280, 900, 640]) {
    await pumpPathBar(tester, width: width);

    expect(
      find.byKey(const ValueKey('library-path-command-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('library-path-breadcrumb-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('library-path-search-surface')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull, reason: '窗口宽度 $width');
  }
});

testWidgets('轻量优化后全部工具动作仍按原参数转发', (tester) async {
  await pumpPathBar(tester, width: 900);
  await tester.tap(find.byTooltip('选择目录'));
  await tester.tap(find.byTooltip('刷新'));
  await tester.tap(find.text('日期'));
  await tester.enterText(find.byType(TextField), '关键字');
  await tester.tap(find.text('D:'));
  expect(recordedActions, [
    'pick',
    'refresh',
    'sort:modified',
    'search:关键字',
    r'path:D:\',
  ]);
});
```

- [ ] **Step 2: 运行工具栏测试并确认 RED**

Run:

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart
```

Expected: FAIL，因为三个视觉契约 key 尚不存在；若同时出现 640px 溢出，也应记录为本任务修复目标。

- [ ] **Step 3: 保持结构和回调，仅调整表现**

在 `LibraryPathBar.build` 中：

- 第一行容器添加 `ValueKey('library-path-command-surface')`、12px 圆角、轻量边框与 `surfaceContainerLow`；
- 在“媒体库”按钮与“最近目录”之间插入固定高度 22px 的 `VerticalDivider`；
- 所有 `_button` / `_busyButton` 使用同一 32×32、8px 圆角的 `IconButton.styleFrom`，统一 hover/focus/pressed overlay；
- “更多媒体操作”按钮使用 `primaryContainer` 的低透明度稳定底板；
- `_breadcrumbs` 外层添加 `ValueKey('library-path-breadcrumb-surface')`、8px 圆角、表面和边框；内部 `SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true)`，确保当前目录优先可见且整行不换行；
- `_sortChip` 改为 `Material + InkWell + AnimatedContainer`，激活态使用 `primaryContainer`，保留原 `onSort(field)`；
- 搜索框外层添加 `ValueKey('library-path-search-surface')`，使用 9px 圆角、outlineVariant 边框与 `surfaceContainerLow`；
- `_status` 继续 `maxLines: 1` 和 `TextOverflow.ellipsis`。

不要改变 `LibraryPathBar` 构造参数、ViewData、动作顺序、Tooltip、菜单内容和回调参数。

- [ ] **Step 4: 运行工具栏与媒体库表现测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\features\library\presentation\library_path_bar.dart test\library_presentation_components_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\library_presentation_components_test.dart test\desktop_shell_test.dart
```

Expected: 全部通过，1280/900/640px 无溢出。

- [ ] **Step 5: 提交工具栏视觉优化**

```powershell
git add lib\features\library\presentation\library_path_bar.dart test\library_presentation_components_test.dart
git commit -m "轻量优化媒体库路径工具栏"
```

### Task 5: 发布 2.1.40

**Files:**
- Modify: `test/version_consistency_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`

- [ ] **Step 1: 查询并记录当前 Windows 已安装版本**

Run:

```powershell
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name, Version, Architecture
```

Expected: 明确记录查询结果；计划编写时为 `2.1.39.0 / X64`，执行时必须以新查询为准。

- [ ] **Step 2: 先更新版本测试并确认 RED**

将 `test/version_consistency_test.dart` 改为：

```dart
const expectedVersion = '2.1.40';
const expectedBuildNumber = '20140';
```

将 `test/identity_v2_zero_residue_test.dart` 的当前版本断言改为 `2.1.40`。运行：

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart
```

Expected: FAIL，实际版本仍为 2.1.39。

- [ ] **Step 3: 更新所有版本源和用户文案**

精确更新：

```text
pubspec.yaml: version: 2.1.40+20140
pubspec.yaml: msix_version: 2.1.40.0
lib/core/app_version.dart: current = '2.1.40'
README.md: | 当前版本 | 2.1.40 |
```

在 `RELEASE_NOTES.md` 顶部和 `UPDATE_DIALOG_COPY.md` 当前正文使用：

```markdown
标题：看影音 2.1.40 测试版

- 日志页面升级为清晰的“运行记录”：默认显示等级、时间和摘要，点击后可展开完整脱敏原文。
- 日志支持关键词搜索和“全部、提醒、错误”筛选，复制全部、清空日志和增量加载行为保持不变。
- 媒体库顶部工具栏保留原有三行结构与全部操作，只统一按钮、路径、排序和搜索框的视觉层级，并改善窄窗口显示。
- 播放器退出卡死修复、本地与网盘经典海报墙及其操作动画继续保留；播放器字幕、选集、硬件解码与 Anime4K 行为不变。
- 没有 TMDB Key 或断网时，应用启动、本地与网盘媒体库和播放器仍可使用；本次不会修改或删除本地原始媒体，也不会修改网盘文件。
```

在 `versionHistoryList` 首位加入：

```dart
VersionHistory(
  version: '2.1.40',
  date: '2026-07-23',
  isPrerelease: true,
  changes: [
    '本测试版将日志页面升级为清晰的“运行记录”：默认显示等级、时间和摘要，点击后可展开完整脱敏原文',
    '日志支持关键词搜索和“全部、提醒、错误”筛选，复制全部、清空日志和增量加载行为保持不变',
    '媒体库顶部工具栏保留原有三行结构与全部操作，只统一按钮、路径、排序和搜索框的视觉层级，并改善窄窗口显示',
    '播放器退出卡死修复、本地与网盘经典海报墙及其操作动画继续保留；播放器字幕、选集、硬件解码与 Anime4K 行为不变',
    '没有 TMDB Key 或断网时，应用启动、本地与网盘媒体库和播放器仍可使用；本次不会修改或删除本地原始媒体，也不会修改网盘文件',
  ],
),
```

同步 `RELEASE_NOTES.md` 的 `## 2.1.40+20140` 和 `MSIX 版本：2.1.40.0`，以及 `UPDATE_DIALOG_COPY.md` 的应用版本、安装包版本与日期。

- [ ] **Step 4: 格式化并运行版本测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\core\app_version.dart lib\utils\version_history.dart test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart
```

Expected: 全部通过。

- [ ] **Step 5: 提交版本更新**

```powershell
git add pubspec.yaml lib\core\app_version.dart README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib\utils\version_history.dart test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart
git commit -m "发布 2.1.40 日志展示优化版"
```

### Task 6: 完整质量门禁和签名交付

**Files:**
- Verify: all tracked project files
- Build: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.40.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.40-异机安装包.zip`

- [ ] **Step 1: 检查格式、残留、动画边界和工作树**

Run:

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed .
git diff --check main...HEAD
git diff --exit-code e6de9a7..HEAD -- lib\pages\player lib\features\library\presentation\immersive_media_card.dart
git status --short
git -C D:\KanYingYin status --short
```

Expected: 格式 0 改动；diff check 通过；播放器和经典海报卡文件无改动；除测试专用 `.dart_appdata` 外无未提交文件；主工作区干净。

- [ ] **Step 2: 串行运行完整测试**

Run:

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat test
```

Expected: 全部测试通过，0 failure。不得与其他 Flutter/Pub 命令并行。

- [ ] **Step 3: 串行运行静态分析**

Run:

```powershell
$env:APPDATA='D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata'
D:\flutter\bin\flutter.bat analyze
```

Expected: `No issues found!`。

- [ ] **Step 4: 安全清理测试 APPDATA**

解析 `D:\KanYingYin\.worktrees\ui-refresh-v1\.dart_appdata` 绝对路径，确认它位于隔离工作树内且末级目录名严格等于 `.dart_appdata` 后删除。再次确认隔离工作树和 `D:\KanYingYin` 均为干净状态。

- [ ] **Step 5: 确认看影音进程已退出并生成签名包**

Run:

```powershell
Get-Process -Name kanyingyin -ErrorAction SilentlyContinue
& .\tool\windows\build_signed_release.ps1
```

Expected: 构建前无运行中的看影音；Windows Release、MSIX 封装和 SignTool 验证成功，0 warning / 0 error，并生成两个桌面文件。

- [ ] **Step 6: 独立验证桌面交付物**

使用 `Get-AuthenticodeSignature` 和 `System.IO.Compression.ZipFile` 验证：

```text
签名状态：Valid
签名者：CN=KanYingYin
证书指纹：A4A2CAA9623FBB8CD27ABC4838D186202EFC1AD6
Identity Name：com.kanyingyin.player
Version：2.1.40.0
ProcessorArchitecture：x64
构建目录 MSIX SHA-256 = 桌面 MSIX SHA-256 = ZIP 内 MSIX SHA-256
ZIP 包含：MSIX、看影音.cer、安装看影音.ps1、安装看影音.cmd、安装说明.txt、SHA256.txt
```

- [ ] **Step 7: 核对最终安装版本和隔离状态**

运行 `Get-AppxPackage -Name com.kanyingyin.player`。若本轮未安装，版本应保持构建前记录；若用户自行安装，则记录实际版本。保留 `codex/ui-refresh-v1` 和 `D:\KanYingYin\.worktrees\ui-refresh-v1`，不合并、不删除。
