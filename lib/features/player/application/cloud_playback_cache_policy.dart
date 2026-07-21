import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';

class CloudPlaybackCachePolicy {
  const CloudPlaybackCachePolicy._(this.mpvProperties);

  static const CloudPlaybackCachePolicy direct =
      CloudPlaybackCachePolicy._(<String, String>{});

  static const CloudPlaybackCachePolicy quarkRelay =
      CloudPlaybackCachePolicy._(<String, String>{
    'stream-buffer-size': '4MiB',
    'cache-pause-initial': 'yes',
    'cache-pause-wait': '5',
    'cache-secs': '30',
    'demuxer-max-bytes': '256MiB',
    'demuxer-max-back-bytes': '32MiB',
  });

  final Map<String, String> mpvProperties;

  static CloudPlaybackCachePolicy forTransport(
    CloudPlaybackTransport transport,
  ) =>
      switch (transport) {
        CloudPlaybackTransport.direct => direct,
        CloudPlaybackTransport.rangeRelay => quarkRelay,
      };
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

  Future<void> close() async {
    final active = _active;
    _active = null;
    await active?.close();
  }
}
