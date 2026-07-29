import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/player_decoder_recovery_policy.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  group('PlayerDecoderRecoveryPolicy', () {
    test('用最近的 mpv 前缀区分音频和视频解码错误', () {
      final policy = PlayerDecoderRecoveryPolicy();
      final now = DateTime.utc(2026, 7, 30);

      policy.recordLog(
        const PlayerLog(
          prefix: 'vd',
          level: 'error',
          text: 'Could not open codec.',
        ),
        now: now,
      );
      expect(
        policy.classify('Could not open codec.', now: now),
        PlayerDecoderFailureKind.video,
      );

      policy.recordLog(
        const PlayerLog(
          prefix: 'ad',
          level: 'error',
          text: 'Error decoding audio frame',
        ),
        now: now,
      );
      expect(
        policy.classify('Error decoding audio frame', now: now),
        PlayerDecoderFailureKind.audio,
      );
    });

    test('过期或不相关日志不会错误触发解码降级', () {
      final policy = PlayerDecoderRecoveryPolicy();
      final now = DateTime.utc(2026, 7, 30);
      policy.recordLog(
        const PlayerLog(
          prefix: 'vd',
          level: 'error',
          text: 'Could not open codec.',
        ),
        now: now,
      );

      expect(
        policy.classify(
          'Could not open codec.',
          now: now.add(const Duration(seconds: 3)),
        ),
        PlayerDecoderFailureKind.unknown,
      );
      expect(
        policy.classify('network failed', now: now),
        PlayerDecoderFailureKind.unknown,
      );
    });

    test('同一错误在短时间内只报告一次', () {
      final policy = PlayerDecoderRecoveryPolicy();
      final now = DateTime.utc(2026, 7, 30);

      expect(policy.shouldReport('Could not open codec.', now: now), isTrue);
      expect(
        policy.shouldReport(
          'Could not open codec.',
          now: now.add(const Duration(milliseconds: 200)),
        ),
        isFalse,
      );
      expect(
        policy.shouldReport(
          'Could not open codec.',
          now: now.add(const Duration(seconds: 2)),
        ),
        isTrue,
      );
    });
  });
}
