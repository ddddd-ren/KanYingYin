import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/local/local_directory_picker.dart';

void main() {
  test('本地目录入口不再调用 Windows 原生文件夹对话框', () {
    final localPage =
        File('lib/pages/local/local_page.dart').readAsStringSync();
    final interfaceSettings =
        File('lib/pages/settings/interface_settings.dart').readAsStringSync();

    expect(localPage, contains('LocalDirectoryPickerPage.pick('));
    expect(interfaceSettings, contains('LocalDirectoryPickerPage.pick('));
    expect(localPage, isNot(contains('FilePicker.platform.getDirectoryPath')));
    expect(interfaceSettings,
        isNot(contains('FilePicker.platform.getDirectoryPath')));
  });

  testWidgets('应用内目录选择器可进入移动硬盘并返回当前目录', (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return FilledButton(
          onPressed: () async {
            selected = await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => LocalDirectoryPickerPage(
                  driveRootsProvider: () async => <String>[r'C:\', r'E:\'],
                  directoryLoader: (path) async => switch (path) {
                    r'E:\' => <String>[r'E:\动漫', r'E:\电影'],
                    _ => <String>[],
                  },
                ),
              ),
            );
          },
          child: const Text('打开'),
        );
      }),
    ));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text(r'E:\'), findsOneWidget);

    await tester.tap(find.text(r'E:\'));
    await tester.pumpAndSettle();
    expect(find.text('动漫'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('select-current')));
    await tester.pumpAndSettle();
    expect(selected, r'E:\');
  });

  testWidgets('应用内目录选择器捕获移动硬盘不可访问错误', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LocalDirectoryPickerPage(
        initialPath: r'E:\',
        driveRootsProvider: () async => <String>[r'E:\'],
        directoryLoader: (_) async => throw const FileSystemException('设备未就绪'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('无法读取该目录，移动硬盘可能已断开'), findsOneWidget);
    expect(find.text('返回磁盘列表'), findsOneWidget);
  });
}
