import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/bean/dialog/async_confirmation_dialog.dart';

void main() {
  Future<void> openDialog(
    WidgetTester tester,
    Future<void> Function() onConfirm,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => AsyncConfirmationDialog(
                title: '移除来源',
                content: const Text('不会删除原始文件'),
                confirmLabel: '移除',
                errorMessage: '移除失败，请重试',
                onConfirm: onConfirm,
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('异步确认处理中保留弹窗并阻止重复提交', (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await openDialog(tester, () {
      calls++;
      return pending.future;
    });

    await tester.tap(find.text('移除'));
    await tester.pump();

    expect(find.text('移除来源'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('async-confirmation-submit')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
          .onPressed,
      isNull,
    );
    expect(calls, 1);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('移除来源'), findsOneWidget);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('移除来源'), findsNothing);
  });

  testWidgets('异步确认失败时保留对象和就地错误', (tester) async {
    await openDialog(tester, () async => throw StateError('failed'));

    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();

    expect(find.text('移除来源'), findsOneWidget);
    expect(find.text('不会删除原始文件'), findsOneWidget);
    expect(find.text('移除失败，请重试'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('async-confirmation-submit')),
          )
          .onPressed,
      isNotNull,
    );
  });
}
