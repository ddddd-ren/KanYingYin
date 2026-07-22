import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';
import 'package:kanyingyin/pages/player/widgets/track_language_confirmation_dialog.dart';

void main() {
  const tracks = [
    PendingTrackLanguage(
      fingerprint: 'sub-1',
      type: EmbeddedTrackType.subtitle,
      trackId: '1',
      codecLabel: 'PGS',
      title: '',
    ),
    PendingTrackLanguage(
      fingerprint: 'audio-2',
      type: EmbeddedTrackType.audio,
      trackId: '2',
      codecLabel: 'AAC',
      title: 'Commentary',
    ),
  ];

  testWidgets('所有轨道选择语言后才能保存且不显示未知语种', (tester) async {
    Map<String, TrackLanguageChoice>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackLanguageConfirmationDialog(
            tracks: tracks,
            onConfirm: (values) async {
              submitted = values;
              return null;
            },
          ),
        ),
      ),
    );

    expect(find.text('确认轨道语言'), findsOneWidget);
    expect(find.text('字幕轨道 1'), findsOneWidget);
    expect(find.text('音轨 2'), findsOneWidget);
    expect(find.textContaining('未知语种'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '保存并继续'),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('track-language-input-sub-1')),
      '日语',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('日语').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('track-language-input-audio-2')),
      '精灵语',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '保存并继续'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存并继续'));
    await tester.pumpAndSettle();

    expect(submitted?['sub-1']?.label, '日语');
    expect(submitted?['audio-2']?.label, '精灵语');
    expect(submitted?['audio-2']?.code, startsWith('custom:'));
  });

  testWidgets('可以稍后确认并关闭语言窗口', (tester) async {
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackLanguageConfirmationDialog(
            tracks: [tracks[0]],
            onConfirm: (values) async {
              submitted = true;
              return null;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('稍后确认'));
    await tester.pumpAndSettle();

    expect(submitted, isFalse);
  });
}
