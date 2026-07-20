enum CloudPlaybackTransport { direct, quarkRangeRelay }

enum QuarkRelayPhase {
  connecting,
  prefetching,
  ready,
  reconnecting,
  degraded,
  failed,
}

class QuarkRelayStatus {
  const QuarkRelayStatus({
    required this.phase,
    this.bytesPerSecond = 0,
    this.receivedBytes = 0,
    this.cachedBytes = 0,
    this.bufferedDuration,
    this.message,
  });

  final QuarkRelayPhase phase;
  final double bytesPerSecond;
  final int receivedBytes;
  final int cachedBytes;
  final Duration? bufferedDuration;
  final String? message;
}

abstract interface class CloudPlaybackLease {
  QuarkRelayStatus get currentStatus;

  Stream<QuarkRelayStatus> get statuses;

  Future<void> close();
}
