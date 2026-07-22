import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
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
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: LogsPage(reader: reader)));
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
