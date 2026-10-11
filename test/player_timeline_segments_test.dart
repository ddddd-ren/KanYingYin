import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/player_bookmark.dart';
import 'package:kanyingyin/features/player/application/player_timeline_segments.dart';

void main() {
  test('不能保存随后无法读取的超长身份或时长', () async {
    final storage = _Storage();
    final repo = PlayerTimelineSegmentRepository(storage);
    final segments = [
      const PlayerTimelineSegment(
          kind: PlayerSegmentKind.intro,
          start: Duration.zero,
          end: Duration(seconds: 1))
    ];
    await expectLater(
        repo.save('video',
            fingerprint: 'f' * 4097,
            duration: const Duration(seconds: 100),
            segments: segments),
        throwsFormatException);
    await expectLater(
        repo.save('video',
            fingerprint: 'f',
            duration: const Duration(milliseconds: 2147483648),
            segments: segments),
        throwsFormatException);
    expect(storage.value, isNull);
  });
  test('片头片尾按具体视频保存，替换文件后要求重新确认', () async {
    final storage = _Storage();
    final repo = PlayerTimelineSegmentRepository(storage);
    final segments = [
      const PlayerTimelineSegment(
          kind: PlayerSegmentKind.intro,
          start: Duration(seconds: 1),
          end: Duration(seconds: 60)),
      const PlayerTimelineSegment(
          kind: PlayerSegmentKind.outro,
          start: Duration(seconds: 500),
          end: Duration(seconds: 600)),
    ];
    await repo.save('video|version1',
        fingerprint: 'size:time',
        duration: const Duration(seconds: 600),
        segments: segments);
    expect(
        repo.visibleSegments('video|version1',
            fingerprint: 'size:time', duration: const Duration(seconds: 600)),
        hasLength(2));
    expect(
        repo.visibleSegments('video|version2',
            fingerprint: 'size:time', duration: const Duration(seconds: 600)),
        isEmpty);
    expect(
        repo.visibleSegments('video|version1',
            fingerprint: 'changed', duration: const Duration(seconds: 600)),
        isEmpty);
    expect(repo.load('video|version1')!.segments, hasLength(2));
  });
  test('倒置、重叠和超过时长的区间不写入', () async {
    final storage = _Storage();
    final repo = PlayerTimelineSegmentRepository(storage);
    for (final ranges in [
      [(60, 1)],
      [(0, 601)],
      [(0, 100), (99, 600)],
    ]) {
      await expectLater(
          repo.save('video',
              fingerprint: 'f',
              duration: const Duration(seconds: 600),
              segments: [
                for (var i = 0; i < ranges.length; i++)
                  PlayerTimelineSegment(
                      kind: i == 0
                          ? PlayerSegmentKind.intro
                          : PlayerSegmentKind.outro,
                      start: Duration(seconds: ranges[i].$1),
                      end: Duration(seconds: ranges[i].$2)),
              ]),
          throwsFormatException);
    }
    expect(storage.value, isNull);
    expect(parsePlayerTimelineTime('01:02:03'), const Duration(seconds: 3723));
    expect(() => parsePlayerTimelineTime('1:99'), throwsFormatException);
  });
}

class _Storage implements PlayerBookmarkStorage {
  Object? value;
  @override
  Object? read() => value;
  @override
  Future<void> write(Object value) async {
    this.value = value;
  }
}
