import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/local/local_directory_picker.dart';

void main() {
  test('本地目录地址去除空白和成对双引号', () {
    expect(normalizeLocalDirectoryAddress(r'  D:\a TV  '), r'D:\a TV');
    expect(normalizeLocalDirectoryAddress(r'"D:\a TV"'), r'D:\a TV');
    expect(normalizeLocalDirectoryAddress(r'  "D:\a TV"  '), r'D:\a TV');
    expect(normalizeLocalDirectoryAddress(r'"D:\a TV'), r'"D:\a TV');
    expect(normalizeLocalDirectoryAddress('   '), isEmpty);
  });

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

  testWidgets('地址栏按 Enter 跳转并同步成功路径', (tester) async {
    final loadedPaths = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LocalDirectoryPickerPage(
          initialPath: r'D:\旧目录',
          directoryLoader: (path) async {
            loadedPaths.add(path);
            return switch (path) {
              r'D:\旧目录' => <String>[r'D:\旧目录\原文件夹'],
              r'E:\新目录' => <String>[r'E:\新目录\新文件夹'],
              _ => throw const FileSystemException('不存在'),
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('local-directory-address')),
      r'E:\新目录',
    );
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(loadedPaths.last, r'E:\新目录');
    expect(find.text('新文件夹'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('local-directory-address')),
    );
    expect(field.controller!.text, r'E:\新目录');
  });

  testWidgets('跳转按钮处理带引号地址且空地址返回磁盘列表', (tester) async {
    var driveLoads = 0;
    final loadedPaths = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LocalDirectoryPickerPage(
          initialPath: r'D:\旧目录',
          driveRootsProvider: () async {
            driveLoads++;
            return <String>[r'C:\', r'D:\'];
          },
          directoryLoader: (path) async {
            loadedPaths.add(path);
            return <String>[];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('local-directory-address')),
      r' "E:\媒体" ',
    );
    await tester.tap(find.byKey(const ValueKey('local-directory-go')));
    await tester.pumpAndSettle();
    expect(loadedPaths.last, r'E:\媒体');

    await tester.enterText(
      find.byKey(const ValueKey('local-directory-address')),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('local-directory-go')));
    await tester.pumpAndSettle();
    expect(driveLoads, 1);
    expect(find.text(r'C:\'), findsOneWidget);
  });

  testWidgets('无效手动地址保留当前目录和列表', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LocalDirectoryPickerPage(
          initialPath: r'D:\有效目录',
          directoryLoader: (path) async => switch (path) {
            r'D:\有效目录' => <String>[r'D:\有效目录\仍然可见'],
            _ => throw const FileSystemException('不存在'),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('local-directory-address')),
      r'Z:\不存在',
    );
    await tester.tap(find.byKey(const ValueKey('local-directory-go')));
    await tester.pumpAndSettle();

    expect(find.text('仍然可见'), findsOneWidget);
    expect(find.text('目录不存在或无法访问'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('local-directory-address')),
          )
          .controller!
          .text,
      r'Z:\不存在',
    );
  });

  testWidgets('本地目录选择器使用圆角无直杆的上级图标', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LocalDirectoryPickerPage(
          initialPath: r'D:\',
          directoryLoader: (_) async => <String>[],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
  });
}
