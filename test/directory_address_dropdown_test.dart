import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/presentation/directory_address_dropdown.dart';

void main() {
  testWidgets('路径框下拉直接子文件夹且保留 Enter 跳转', (tester) async {
    String? selected;
    String? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: DirectoryAddressDropdown(
                currentPath: r'D:\TV',
                enabled: true,
                loadChildren: (_) async => const <DirectoryNavigationItem>[
                  DirectoryNavigationItem(
                    label: '动画',
                    path: r'D:\TV\动画',
                    subtitle: r'D:\TV\动画',
                  ),
                ],
                onChildSelected: (item) => selected = item.path,
                onSubmitted: (path) async {
                  submitted = path;
                  return null;
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('展开子文件夹'));
    await tester.pumpAndSettle();
    expect(find.text('动画'), findsOneWidget);
    expect(find.text(r'D:\TV\动画'), findsOneWidget);

    await tester.tap(find.text('动画'));
    await tester.pumpAndSettle();
    expect(selected, r'D:\TV\动画');

    await tester.enterText(
      find.byKey(const ValueKey<String>('directory-address')),
      r'"E:\Movie"',
    );
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(submitted, r'E:\Movie');
  });

  testWidgets('空目录下拉显示没有子文件夹', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DirectoryAddressDropdown(
            currentPath: '/影视',
            enabled: true,
            loadChildren: (_) async => const <DirectoryNavigationItem>[],
            onChildSelected: (_) {},
            onSubmitted: (_) async => null,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('展开子文件夹'));
    await tester.pumpAndSettle();
    expect(find.text('没有子文件夹'), findsOneWidget);
  });

  testWidgets('子目录加载失败保留当前地址并显示错误', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DirectoryAddressDropdown(
            currentPath: '/影视',
            enabled: true,
            loadChildren: (_) async => throw StateError('offline'),
            onChildSelected: (_) {},
            onSubmitted: (_) async => null,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('展开子文件夹'));
    await tester.pumpAndSettle();
    expect(find.text('目录不存在或无法访问'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('directory-address')),
          )
          .controller
          ?.text,
      '/影视',
    );
  });

  testWidgets('已添加目录与最近访问和子目录共用导航入口', (tester) async {
    final selected = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DirectoryAddressDropdown(
      currentPath: r'D:\TV',
      enabled: true,
      savedDirectories: const [
        DirectoryNavigationItem(label: '电影源', path: r'E:\电影')
      ],
      recentDirectories: const [
        DirectoryNavigationItem(label: '最近动画', path: r'F:\动画')
      ],
      loadChildren: (_) async =>
          const [DirectoryNavigationItem(label: '剧集子目录', path: r'D:\TV\剧集')],
      onChildSelected: (item) => selected.add(item.path),
      onSubmitted: (_) async => null,
    ))));
    for (final label in ['电影源', '最近动画', '剧集子目录']) {
      await tester.tap(find.byTooltip('选择目录与子文件夹'));
      await tester.pumpAndSettle();
      expect(find.text('已添加目录'), findsOneWidget);
      expect(find.text('最近访问'), findsOneWidget);
      expect(find.text('当前目录的子文件夹'), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(selected, [r'E:\电影', r'F:\动画', r'D:\TV\剧集']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('当前目录不可访问时仍能从下拉切换已添加目录', (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DirectoryAddressDropdown(
      currentPath: r'Z:\已断开',
      enabled: true,
      savedDirectories: const [
        DirectoryNavigationItem(label: '可用目录', path: r'D:\TV')
      ],
      loadChildren: (_) async => throw StateError('offline'),
      onChildSelected: (item) => selected = item.path,
      onSubmitted: (_) async => null,
    ))));
    await tester.tap(find.byTooltip('选择目录与子文件夹'));
    await tester.pumpAndSettle();
    expect(find.text('目录不存在或无法访问'), findsOneWidget);
    await tester.tap(find.text('可用目录'));
    await tester.pumpAndSettle();
    expect(selected, r'D:\TV');
    expect(tester.takeException(), isNull);
  });

  testWidgets('目录切换后忽略尚未完成的旧子目录请求', (tester) async {
    final request = Completer<List<DirectoryNavigationItem>>();
    Widget page(String path) => MaterialApp(
            home: Scaffold(
                body: DirectoryAddressDropdown(
          currentPath: path,
          enabled: true,
          loadChildren: (_) => request.future,
          onChildSelected: (_) {},
          onSubmitted: (_) async => null,
        )));
    await tester.pumpWidget(page(r'D:\旧目录'));
    await tester.tap(find.byTooltip('展开子文件夹'));
    await tester.pump();
    await tester.pumpWidget(page(r'E:\新目录'));
    request.complete(
        const [DirectoryNavigationItem(label: '旧子目录', path: r'D:\旧目录\子')]);
    await tester.pumpAndSettle();
    expect(find.text('旧子目录'), findsNothing);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('directory-address')))
            .controller!
            .text,
        r'E:\新目录');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('directory-address')))
            .enabled,
        isTrue);
    expect(tester.takeException(), isNull);
  });
}
