import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/logs/application/diagnostic_log_share_service.dart';
import 'package:kanyingyin/pages/logs/logs_page.dart';
import 'package:kanyingyin/utils/log_archive_reader.dart';
import 'package:kanyingyin/utils/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('logs-page-hive-');
    Hive.init(hiveDirectory.path);
    GStorage.setting = await Hive.openBox<Object?>('logs-page-settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  Future<LogArchiveReader> readerWith(String content) async {
    return _MemoryLogArchiveReader(content);
  }

  Future<void> pumpLogs(
    WidgetTester tester,
    LogArchiveReader reader, {
    double width = 900,
    Future<DiagnosticLogShareOutcome> Function()? shareDiagnosticLogs,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: LogsPage(
          reader: reader,
          shareDiagnosticLogs: shareDiagnosticLogs,
        ),
      ),
    );
    for (var frame = 0; frame < 50; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
  }

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
    await tester.tap(find.widgetWithText(ChoiceChip, '错误'));
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

  testWidgets('清空日志后显示空状态并清除搜索', (tester) async {
    final reader = await readerWith(
      '[2026-07-23T10:00:00.000] INFO\n媒体库扫描完成',
    );
    await pumpLogs(tester, reader);
    await tester.enterText(find.byType(TextField), '扫描');
    await tester.tap(find.byTooltip('清空日志'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('log-state-empty')), findsOneWidget);
    expect(find.text('扫描'), findsNothing);
  });

  testWidgets('读取异常显示失败状态', (tester) async {
    await pumpLogs(tester, _ThrowingLogArchiveReader());
    expect(find.byKey(const ValueKey('log-state-error')), findsOneWidget);
  });

  testWidgets('正常、空白和读取失败状态都能导出诊断日志', (tester) async {
    var calls = 0;
    for (final reader in <LogArchiveReader>[
      await readerWith('[2026-08-03T04:15:42.075] WARNING\nTrueHD 解码失败'),
      await readerWith(''),
      _ThrowingLogArchiveReader(),
    ]) {
      await pumpLogs(
        tester,
        reader,
        shareDiagnosticLogs: () async {
          calls += 1;
          return DiagnosticLogShareOutcome.dismissed;
        },
      );

      expect(find.byTooltip('导出诊断日志'), findsOneWidget);
      await tester.tap(find.byTooltip('导出诊断日志'));
      await tester.pumpAndSettle();
    }
    expect(calls, 3);
  });

  testWidgets('导出期间禁用按钮并阻止重复分享', (tester) async {
    final completer = Completer<DiagnosticLogShareOutcome>();
    var calls = 0;
    await pumpLogs(
      tester,
      await readerWith('[2026-08-03T04:15:42.075] ERROR\n播放器失败'),
      shareDiagnosticLogs: () {
        calls += 1;
        return completer.future;
      },
    );

    await tester.tap(find.byTooltip('导出诊断日志'));
    await tester.pump();

    expect(calls, 1);
    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('export-diagnostic-logs')),
    );
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('export-diagnostic-logs')));
    await tester.pump();
    expect(calls, 1);

    completer.complete(DiagnosticLogShareOutcome.dismissed);
    await tester.pumpAndSettle();
    expect(find.text('导出诊断日志失败，请稍后重试'), findsNothing);
  });

  testWidgets('导出异常显示明确提示', (tester) async {
    await pumpLogs(
      tester,
      await readerWith(''),
      shareDiagnosticLogs: () async => throw StateError('fixture'),
    );

    await tester.tap(find.byTooltip('导出诊断日志'));
    await tester.pump();

    expect(find.text('导出诊断日志失败，请稍后重试'), findsOneWidget);
  });
}

class _ThrowingLogArchiveReader extends LogArchiveReader {
  @override
  Future<String> readAll() async => throw const FileSystemException('fixture');
}

class _MemoryLogArchiveReader extends LogArchiveReader {
  _MemoryLogArchiveReader(this.content);

  String content;

  @override
  Future<String> readAll() async => content;

  @override
  Future<void> clear() async => content = '';
}
