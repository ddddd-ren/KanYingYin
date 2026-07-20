enum CloudPlaybackTransport { direct, rangeRelay }

enum CloudRangeRelayPhase {
  connecting,
  prefetching,
  ready,
  reconnecting,
  degraded,
  failed,
}

class CloudRangeRelayStatus {
  const CloudRangeRelayStatus({
    required this.providerName,
    required this.phase,
    this.bytesPerSecond = 0,
    this.receivedBytes = 0,
    this.cachedBytes = 0,
    this.bufferedDuration,
    this.message,
  });

  final String providerName;
  final CloudRangeRelayPhase phase;
  final double bytesPerSecond;
  final int receivedBytes;
  final int cachedBytes;
  final Duration? bufferedDuration;
  final String? message;
}

abstract interface class CloudPlaybackLease {
  CloudRangeRelayStatus get currentStatus;

  Stream<CloudRangeRelayStatus> get statuses;

  Future<void> close();
}
