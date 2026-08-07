import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/cloud_playback_cache_policy.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';

void main() {
  test('Windows 中转保留 256 MiB 播放缓存', () {
    final policy = CloudPlaybackCachePolicy.forTransport(
      CloudPlaybackTransport.rangeRelay,
      capabilities: AppPlatformCapabilities.windows,
      lowMemoryMode: false,
    );
    expect(policy.playerBufferSize, 256 * 1024 * 1024);
    expect(
      policy.mpvProperties,
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
      CloudPlaybackCachePolicy.forTransport(
        CloudPlaybackTransport.direct,
        capabilities: AppPlatformCapabilities.windows,
        lowMemoryMode: false,
      ).mpvProperties,
      isEmpty,
    );
  });

  test('Android 中转扩大预读时长并限制双层缓存占用', () {
    final policy = CloudPlaybackCachePolicy.forTransport(
      CloudPlaybackTransport.rangeRelay,
      capabilities: AppPlatformCapabilities.android,
      lowMemoryMode: false,
    );

    expect(policy.playerBufferSize, 128 * 1024 * 1024);
    expect(
      policy.mpvProperties,
      const <String, String>{
        'stream-buffer-size': '4MiB',
        'cache-pause-initial': 'yes',
        'cache-pause-wait': '5',
        'cache-secs': '45',
        'demuxer-max-bytes': '128MiB',
        'demuxer-max-back-bytes': '16MiB',
      },
    );
  });

  test('Android 低内存模式对中转缓存生效', () {
    final policy = CloudPlaybackCachePolicy.forTransport(
      CloudPlaybackTransport.rangeRelay,
      capabilities: AppPlatformCapabilities.android,
      lowMemoryMode: true,
    );

    expect(policy.playerBufferSize, 64 * 1024 * 1024);
    expect(
      policy.mpvProperties,
      const <String, String>{
        'stream-buffer-size': '4MiB',
        'cache-pause-initial': 'yes',
        'cache-pause-wait': '5',
        'cache-secs': '30',
        'demuxer-max-bytes': '64MiB',
        'demuxer-max-back-bytes': '8MiB',
      },
    );
  });

  test('Android TV 中转使用更低的双层缓存峰值', () {
    final tv = AppPlatformCapabilities.android.copyWith(
      television: true,
      androidSdkInt: 28,
    );
    final normal = CloudPlaybackCachePolicy.forTransport(
      CloudPlaybackTransport.rangeRelay,
      capabilities: tv,
      lowMemoryMode: false,
    );
    final lowMemory = CloudPlaybackCachePolicy.forTransport(
      CloudPlaybackTransport.rangeRelay,
      capabilities: tv,
      lowMemoryMode: true,
    );

    expect(normal.playerBufferSize, 48 * 1024 * 1024);
    expect(
      normal.mpvProperties,
      const <String, String>{
        'stream-buffer-size': '4MiB',
        'cache-pause-initial': 'yes',
        'cache-pause-wait': '5',
        'cache-secs': '30',
        'demuxer-max-bytes': '48MiB',
        'demuxer-max-back-bytes': '8MiB',
      },
    );
    expect(lowMemory.playerBufferSize, 32 * 1024 * 1024);
    expect(
      lowMemory.mpvProperties,
      const <String, String>{
        'stream-buffer-size': '4MiB',
        'cache-pause-initial': 'yes',
        'cache-pause-wait': '5',
        'cache-secs': '20',
        'demuxer-max-bytes': '32MiB',
        'demuxer-max-back-bytes': '4MiB',
      },
    );
    expect(
      CloudPlaybackCachePolicy.forTransport(
        CloudPlaybackTransport.direct,
        capabilities: tv,
        lowMemoryMode: false,
      ),
      same(CloudPlaybackCachePolicy.androidDirect),
    );
  });

  test('Android 直连资源不沿用桌面端 1500 MiB 播放缓存', () {
    final normal = CloudPlaybackCachePolicy.forTransport(
      CloudPlaybackTransport.direct,
      capabilities: AppPlatformCapabilities.android,
      lowMemoryMode: false,
    );
    final lowMemory = CloudPlaybackCachePolicy.forTransport(
      CloudPlaybackTransport.direct,
      capabilities: AppPlatformCapabilities.android,
      lowMemoryMode: true,
    );

    expect(normal.playerBufferSize, 128 * 1024 * 1024);
    expect(lowMemory.playerBufferSize, 64 * 1024 * 1024);
    expect(normal.mpvProperties, isEmpty);
    expect(lowMemory.mpvProperties, isEmpty);
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

  test('播放替换失败时同时释放候选租约和旧租约', () async {
    final coordinator = CloudPlaybackLeaseCoordinator();
    final active = _FakeLease();
    final candidate = _FakeLease();

    await coordinator.adopt(active);
    await coordinator.abortReplacement(candidate);

    expect(active.closeCalls, 1);
    expect(candidate.closeCalls, 1);
    expect(coordinator.active, isNull);
  });
}

class _FakeLease implements CloudPlaybackLease {
  var closeCalls = 0;

  @override
  CloudRangeRelayStatus get currentStatus => const CloudRangeRelayStatus(
        providerName: '测试网盘',
        phase: CloudRangeRelayPhase.ready,
      );

  @override
  Stream<CloudRangeRelayStatus> get statuses =>
      const Stream<CloudRangeRelayStatus>.empty();

  @override
  Future<void> close() async => closeCalls++;
}
