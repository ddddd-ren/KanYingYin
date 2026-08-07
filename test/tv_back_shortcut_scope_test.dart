import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/tv/presentation/tv_back_shortcut_scope.dart';

void main() {
  testWidgets('TV 遥控器返回键可以退出非点击遮罩弹窗', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TvBackShortcutScope(
          enabled: true,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (context) => FilledButton(
            autofocus: true,
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('测试弹窗'),
                actions: [
                  TextButton(
                    autofocus: true,
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('测试弹窗'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('测试弹窗'), findsNothing);
  });

  testWidgets('TV 输入框首次返回只退出编辑状态', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TvBackShortcutScope(
          enabled: true,
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: TextField(focusNode: focusNode, autofocus: true),
        ),
      ),
    );
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(focusNode.hasFocus, isFalse);
  });
}
