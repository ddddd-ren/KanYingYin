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
}
