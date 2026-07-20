import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/cloud_playback_cache_policy.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';

void main() {
  test('夸克中转使用独立 MPV 网络缓存参数', () {
    expect(
      CloudPlaybackCachePolicy.forTransport(
        CloudPlaybackTransport.quarkRangeRelay,
      ).mpvProperties,
      const <String, String>{
        'stream-buffer-size': '4MiB',
        'cache-pause-initial': 'yes',
        'cache-pause-wait': '5',
        'cache-secs': '30',
        'demuxer-max-bytes': '256MiB',
        'demuxer-max-back-bytes': '32MiB',
      },
    );
    expect(
      CloudPlaybackCachePolicy.forTransport(CloudPlaybackTransport.direct)
          .mpvProperties,
      isEmpty,
    );
  });

  test('租约协调器在新媒体接管后释放旧租约', () async {
    final coordinator = CloudPlaybackLeaseCoordinator();
    final first = _FakeLease();
    final second = _FakeLease();
    final rejected = _FakeLease();

    await coordinator.adopt(first);
    await coordinator.adopt(second);
    await coordinator.reject(rejected);

    expect(first.closeCalls, 1);
    expect(second.closeCalls, 0);
    expect(rejected.closeCalls, 1);

    await coordinator.close();
    await coordinator.close();
    expect(second.closeCalls, 1);
  });
}

class _FakeLease implements CloudPlaybackLease {
  var closeCalls = 0;

  @override
  QuarkRelayStatus get currentStatus =>
      const QuarkRelayStatus(phase: QuarkRelayPhase.ready);

  @override
  Stream<QuarkRelayStatus> get statuses =>
      const Stream<QuarkRelayStatus>.empty();

  @override
  Future<void> close() async => closeCalls++;
}
