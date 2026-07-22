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
