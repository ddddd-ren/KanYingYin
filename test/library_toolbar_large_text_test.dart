import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/presentation/library_toolbar.dart';

void main() {
  for (final width in [640.0, 1280.0]) {
    testWidgets('Windows 工具栏在 $width 宽和两倍文字下可搜索和清空', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var keyword = '';
      var refreshed = false;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            return Column(children: [
              LibraryToolbar(
                title: '网盘媒体库',
                icon: Icons.video_library_outlined,
                count: 10000,
                searchController: controller,
                onSearchChanged: (value) => setState(() => keyword = value),
                onClearSearch: () => setState(() {
                  controller.clear();
                  keyword = '';
                }),
                refresh: IconButton(
                  tooltip: '刷新已有资料',
                  onPressed: () => refreshed = true,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ]);
          }),
        ),
      ));
      await tester.enterText(find.byType(TextField), '原始片名');
      await tester.pump();
      expect(keyword, '原始片名');
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      expect(editable.size.height,
          greaterThanOrEqualTo(editable.preferredLineHeight),
          reason: '放大文字后的输入行不能被固定高度裁剪');
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pump();
      expect(keyword, isEmpty);
      expect(controller.text, isEmpty);
      await tester.tap(find.byTooltip('刷新已有资料'));
      expect(refreshed, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
