import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/tv/presentation/tv_back_navigation_guard.dart';

void main() {
  testWidgets('TV 返回键先退出输入，再确认，必须点击退出按钮才退出应用', (tester) async {
    final searchFocusNode = FocusNode();
    addTearDown(searchFocusNode.dispose);
    var exitCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TvBackNavigationGuard(
          enabled: true,
          onExit: () => exitCount++,
          child: Scaffold(
            body: TextField(
              focusNode: searchFocusNode,
              autofocus: true,
              decoration: const InputDecoration(hintText: '搜索当前目录'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(searchFocusNode.hasFocus, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(searchFocusNode.hasFocus, isFalse);
    expect(find.text('退出看影音？'), findsNothing);
    expect(exitCount, 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('退出看影音？'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('退出'), findsOneWidget);
    expect(exitCount, 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('退出看影音？'), findsNothing);
    expect(exitCount, 0);
  });

  testWidgets('TV 退出确认可用遥控器按钮取消或退出', (tester) async {
    var exitCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TvBackNavigationGuard(
          enabled: true,
          onExit: () => exitCount++,
          child: const Scaffold(body: Text('内容')),
        ),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(exitCount, 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出'));
    await tester.pumpAndSettle();
    expect(exitCount, 1);
  });
}
