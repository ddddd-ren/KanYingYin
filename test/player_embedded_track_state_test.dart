import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';

void main() {
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
}
