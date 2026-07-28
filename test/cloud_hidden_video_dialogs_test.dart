import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_hidden_video_dialogs.dart';

void main() {
  const versionA = CloudFileEntry(
    id: 'video-a',
    remotePath: '/影视/示例电影/A.mkv',
    name: '示例电影 [A 版本].mkv',
    size: 2048,
    modifiedAt: null,
    isDirectory: false,
    variantLabel: 'A 版本',
  );
  const versionB = CloudFileEntry(
    id: 'video-b',
    remotePath: '/影视/示例电影/B.mkv',
    name: '示例电影 [B 版本].mkv',
    size: 1024,
    modifiedAt: null,
    isDirectory: false,
    variantLabel: 'B 版本',
  );

  testWidgets('单视频隐藏前明确确认且说明不会删除网盘文件', (tester) async {
    List<CloudFileEntry>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showCloudHideVideoDialog(
                context: context,
                videos: const <CloudFileEntry>[versionA],
              ).then((value) => result = value),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('隐藏视频'), findsOneWidget);
    expect(find.textContaining('不会删除网盘文件'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '隐藏'));
    await tester.pumpAndSettle();
    expect(result, const <CloudFileEntry>[versionA]);
  });

  testWidgets('多版本对话框只返回用户勾选的 B 版本', (tester) async {
    List<CloudFileEntry>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showCloudHideVideoDialog(
                context: context,
                videos: const <CloudFileEntry>[versionA, versionB],
              ).then((value) => result = value),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('选择要隐藏的视频'), findsOneWidget);
    expect(find.textContaining('/影视/示例电影/A.mkv'), findsOneWidget);
    expect(find.textContaining('/影视/示例电影/B.mkv'), findsOneWidget);
    final before = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '隐藏所选'),
    );
    expect(before.onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('hide-video-video-b')),
    );
    await tester.pump();
    final after = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '隐藏所选'),
    );
    expect(after.onPressed, isNotNull);
    await tester.tap(find.widgetWithText(FilledButton, '隐藏所选'));
    await tester.pumpAndSettle();

    expect(result, const <CloudFileEntry>[versionB]);
  });
}
