import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:kanyingyin/features/player/application/player_timeline_segments.dart';
import 'package:kanyingyin/features/player/presentation/player_timeline_progress_bar.dart';
import 'package:kanyingyin/features/player/presentation/player_timeline_segment_editor.dart';

void main() {
  testWidgets('两侧时间标签下标记仍显示且中点拖动保持时间映射', (tester) async {
    Duration? sought;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 400,
                    child: PlayerTimelineProgressBar(
                        progress: Duration.zero,
                        buffered: null,
                        total: const Duration(seconds: 100),
                        timeLabelLocation: TimeLabelLocation.sides,
                        enablePreview: false,
                        segments: const [
                          PlayerTimelineSegment(
                              kind: PlayerSegmentKind.intro,
                              start: Duration.zero,
                              end: Duration(seconds: 20))
                        ],
                        onSeek: (value) => sought = value,
                        onDragStart: (_) {},
                        onDragUpdate: (_) {},
                        onDragEnd: () {}))))));
    await tester
        .tapAt(tester.getCenter(find.byType(PlayerTimelineProgressBar)));
    await tester.pump();
    expect(find.text('片头'), findsOneWidget);
    expect(sought!.inSeconds, inInclusiveRange(48, 54));
    expect(tester.takeException(), isNull);
  });
  testWidgets('标记不依赖缩略图且不拦截进度条拖动', (tester) async {
    Duration? sought;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 400,
                    child: PlayerTimelineProgressBar(
                      progress: Duration.zero,
                      buffered: null,
                      total: const Duration(seconds: 100),
                      enablePreview: false,
                      segments: const [
                        PlayerTimelineSegment(
                            kind: PlayerSegmentKind.intro,
                            start: Duration.zero,
                            end: Duration(seconds: 20)),
                        PlayerTimelineSegment(
                            kind: PlayerSegmentKind.outro,
                            start: Duration(seconds: 80),
                            end: Duration(seconds: 100))
                      ],
                      onSeek: (value) => sought = value,
                      onDragStart: (_) {},
                      onDragUpdate: (_) {},
                      onDragEnd: () {},
                    ))))));
    expect(find.text('片头'), findsOneWidget);
    expect(find.text('片尾'), findsOneWidget);
    await tester.drag(
        find.byType(PlayerTimelineProgressBar), const Offset(100, 0));
    await tester.pump();
    expect(sought, isNotNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('区间保存失败时保留输入和弹窗', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: PlayerTimelineSegmentEditor(
      duration: const Duration(seconds: 100),
      position: () => const Duration(seconds: 10),
      initial: const [
        PlayerTimelineSegment(
            kind: PlayerSegmentKind.intro,
            start: Duration.zero,
            end: Duration(seconds: 20))
      ],
      onSave: (_) async {
        throw StateError('写入失败');
      },
    )));
    await tester.tap(find.text('保存区间'));
    await tester.pump();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.byType(PlayerTimelineSegmentEditor), findsOneWidget);
    expect(
        (tester.widgetList<TextField>(find.byType(TextField)).last)
            .controller!
            .text,
        '00:00:20');
  });
}
