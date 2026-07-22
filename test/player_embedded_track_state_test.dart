import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';

void main() {
  test('轨道语言确认只接受当前媒体 revision', () {
    final state = TrackLanguageConfirmationState();
    final first = state.begin('media-a', const []);
    final second = state.begin('media-b', const []);
    expect(state.canApply(first, 'media-a'), isFalse);
    expect(state.canApply(second, 'media-b'), isTrue);
    state.reset();
    expect(state.canApply(second, 'media-b'), isFalse);
  });

  test('自动选择每个媒体只执行一次', () {
    final state = EmbeddedTrackSelectionState();
    expect(state.beginAutomaticSelection(hasAudioTracks: true), isTrue);
    expect(state.beginAutomaticSelection(hasAudioTracks: true), isFalse);
  });

  test('用户手动选择音轨后自动事件不得覆盖', () {
    final state = EmbeddedTrackSelectionState()..markAudioSelectedManually();
    expect(state.canAutomaticallySelectAudio, isFalse);
  });

  test('切换媒体后清理选择锁并重新允许自动选择', () {
    final state = EmbeddedTrackSelectionState()
      ..beginAutomaticSelection(hasAudioTracks: true)
      ..markAudioSelectedManually()
      ..reset();
    expect(state.canAutomaticallySelectAudio, isTrue);
    expect(state.beginAutomaticSelection(hasAudioTracks: true), isTrue);
  });

  test('用户选择字幕后使尚未完成的自动字幕选择失效', () {
    final state = SubtitleTrackSelectionState();
    final automaticSelection = state.beginAutomaticSelection();

    state.markManualSelection();

    expect(state.canApplyAutomaticSelection(automaticSelection), isFalse);
  });

  test('切换媒体后允许新的自动字幕选择生效', () {
    final state = SubtitleTrackSelectionState();
    final previousSelection = state.beginAutomaticSelection();
    state.markManualSelection();

    state.reset();
    final currentSelection = state.beginAutomaticSelection();

    expect(state.canApplyAutomaticSelection(previousSelection), isFalse);
    expect(state.canApplyAutomaticSelection(currentSelection), isTrue);
  });
}
