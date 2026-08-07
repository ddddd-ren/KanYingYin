import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';

class CloudPlaybackCachePolicy {
  const CloudPlaybackCachePolicy._(
    this.mpvProperties, {
    this.playerBufferSize,
  });

  static const CloudPlaybackCachePolicy direct =
      CloudPlaybackCachePolicy._(<String, String>{});

  static const CloudPlaybackCachePolicy cloudRangeRelay =
      CloudPlaybackCachePolicy._(<String, String>{
    'stream-buffer-size': '4MiB',
    'cache-pause-initial': 'yes',
    'cache-pause-wait': '5',
    'cache-secs': '30',
    'demuxer-max-bytes': '256MiB',
    'demuxer-max-back-bytes': '32MiB',
  }, playerBufferSize: 256 * 1024 * 1024);

  static const CloudPlaybackCachePolicy androidDirect =
      CloudPlaybackCachePolicy._(
    <String, String>{},
    playerBufferSize: 128 * 1024 * 1024,
  );

  static const CloudPlaybackCachePolicy androidDirectLowMemory =
      CloudPlaybackCachePolicy._(
    <String, String>{},
    playerBufferSize: 64 * 1024 * 1024,
  );

  static const CloudPlaybackCachePolicy androidRangeRelay =
      CloudPlaybackCachePolicy._(<String, String>{
    'stream-buffer-size': '4MiB',
    'cache-pause-initial': 'yes',
    'cache-pause-wait': '5',
    'cache-secs': '45',
    'demuxer-max-bytes': '128MiB',
    'demuxer-max-back-bytes': '16MiB',
  }, playerBufferSize: 128 * 1024 * 1024);

  static const CloudPlaybackCachePolicy androidRangeRelayLowMemory =
      CloudPlaybackCachePolicy._(<String, String>{
    'stream-buffer-size': '4MiB',
    'cache-pause-initial': 'yes',
    'cache-pause-wait': '5',
    'cache-secs': '30',
    'demuxer-max-bytes': '64MiB',
    'demuxer-max-back-bytes': '8MiB',
  }, playerBufferSize: 64 * 1024 * 1024);

  static const CloudPlaybackCachePolicy androidTvRangeRelay =
      CloudPlaybackCachePolicy._(<String, String>{
    'stream-buffer-size': '4MiB',
    'cache-pause-initial': 'yes',
    'cache-pause-wait': '5',
    'cache-secs': '30',
    'demuxer-max-bytes': '48MiB',
    'demuxer-max-back-bytes': '8MiB',
  }, playerBufferSize: 48 * 1024 * 1024);

  static const CloudPlaybackCachePolicy androidTvRangeRelayLowMemory =
      CloudPlaybackCachePolicy._(<String, String>{
    'stream-buffer-size': '4MiB',
    'cache-pause-initial': 'yes',
    'cache-pause-wait': '5',
    'cache-secs': '20',
    'demuxer-max-bytes': '32MiB',
    'demuxer-max-back-bytes': '4MiB',
  }, playerBufferSize: 32 * 1024 * 1024);

  final Map<String, String> mpvProperties;
  final int? playerBufferSize;

  static CloudPlaybackCachePolicy forTransport(
    CloudPlaybackTransport transport, {
    required AppPlatformCapabilities capabilities,
    required bool lowMemoryMode,
  }) {
    if (!capabilities.isAndroid) {
      return switch (transport) {
        CloudPlaybackTransport.direct => direct,
        CloudPlaybackTransport.rangeRelay => cloudRangeRelay,
      };
    }
    if (capabilities.isAndroidTv &&
        transport == CloudPlaybackTransport.rangeRelay) {
      return lowMemoryMode ? androidTvRangeRelayLowMemory : androidTvRangeRelay;
    }
    return switch (transport) {
      CloudPlaybackTransport.direct =>
        lowMemoryMode ? androidDirectLowMemory : androidDirect,
      CloudPlaybackTransport.rangeRelay =>
        lowMemoryMode ? androidRangeRelayLowMemory : androidRangeRelay,
    };
  }
}

class CloudPlaybackLeaseCoordinator {
  CloudPlaybackLease? _active;

  CloudPlaybackLease? get active => _active;

  Future<void> adopt(CloudPlaybackLease? lease) async {
    if (identical(_active, lease)) return;
    final previous = _active;
    _active = lease;
    await previous?.close();
  }

  Future<void> reject(CloudPlaybackLease? lease) async {
    if (lease == null || identical(_active, lease)) return;
    await lease.close();
  }

  Future<void> abortReplacement(CloudPlaybackLease? candidate) async {
    final active = _active;
    _active = null;
    final leases = <CloudPlaybackLease>[
      if (candidate != null && !identical(candidate, active)) candidate,
      if (active != null) active,
    ];
    await Future.wait(leases.map((lease) => lease.close()));
  }

  Future<void> close() async {
    final active = _active;
    _active = null;
    await active?.close();
  }
}
