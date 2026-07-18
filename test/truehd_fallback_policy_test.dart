import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/truehd_fallback_policy.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  final policy = TrueHdFallbackPolicy();

  test('大小写 truehd/mlp 音轨可识别', () {
    expect(policy.isTrueHd(const AudioTrack('1', 'TRUEHD', 'en', codec: 'x')),
        isTrue);
    expect(policy.isTrueHd(const AudioTrack('2', 'main', 'en', codec: 'MLP')),
        isTrue);
  });

  test('错误仅在有 TrueHD 音轨时匹配通用音频解码错误', () {
    final tracks = [const AudioTrack('1', 'TrueHD', 'en', codec: 'truehd')];
    expect(policy.isRelatedError('audio decoder failed', tracks), isTrue);
    expect(policy.isRelatedError('audio decoder failed', const []), isFalse);
    expect(policy.isRelatedError('MLP open error', const []), isTrue);
  });

  test('选择首个非 auto/no/当前且非 TrueHD 音轨', () {
    final tracks = [
      const AudioTrack('auto', null, null),
      const AudioTrack('1', 'TrueHD', 'en', codec: 'truehd'),
      const AudioTrack('2', '当前', 'zh'),
      const AudioTrack('3', '兼容', 'zh'),
    ];
    expect(policy.chooseFallback(tracks, currentTrackId: '2')?.id, '3');
    expect(
      policy.chooseFallback(
        tracks.where((track) => track.id != '3'),
        currentTrackId: '2',
      ),
      isNull,
    );
  });
}
