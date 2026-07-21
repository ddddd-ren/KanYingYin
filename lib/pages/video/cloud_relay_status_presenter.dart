import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';

class CloudRelayStatusPresentation {
  const CloudRelayStatusPresentation({
    required this.text,
    required this.warning,
    required this.stable,
  });

  final String text;
  final bool warning;
  final bool stable;
}

class CloudRelayStatusPresenter {
  const CloudRelayStatusPresenter._();

  static CloudRelayStatusPresentation present(
    CloudRangeRelayStatus status, {
    int? totalBytes,
    Duration? mediaDuration,
  }) {
    final requiredBytesPerSecond = _requiredBytesPerSecond(
      totalBytes,
      mediaDuration,
    );
    final degraded = status.phase == CloudRangeRelayPhase.degraded ||
        (status.phase == CloudRangeRelayPhase.ready &&
            requiredBytesPerSecond != null &&
            status.bytesPerSecond > 0 &&
            status.bytesPerSecond < requiredBytesPerSecond);
    final speed = _speedText(status.bytesPerSecond);
    final buffered = _bufferedText(
      status.cachedBytes,
      requiredBytesPerSecond,
      status.bufferedDuration,
    );
    final suffix = <String>[
      if (speed != null) speed,
      if (buffered != null) buffered,
    ];
    String withDetails(String label) =>
        suffix.isEmpty ? label : '$label · ${suffix.join(' · ')}';

    if (degraded) {
      return CloudRelayStatusPresentation(
        text: withDetails('当前网盘读取速度不足'),
        warning: true,
        stable: false,
      );
    }
    return switch (status.phase) {
      CloudRangeRelayPhase.connecting => CloudRelayStatusPresentation(
          text: '${status.providerName}正在连接',
          warning: false,
          stable: false,
        ),
      CloudRangeRelayPhase.prefetching => CloudRelayStatusPresentation(
          text: withDetails('${status.providerName}预缓冲中'),
          warning: false,
          stable: false,
        ),
      CloudRangeRelayPhase.ready => CloudRelayStatusPresentation(
          text: speed == null
              ? '${status.providerName}读取已就绪'
              : '${status.providerName}读取 $speed',
          warning: false,
          stable: true,
        ),
      CloudRangeRelayPhase.reconnecting => CloudRelayStatusPresentation(
          text: '${status.providerName}正在重新连接',
          warning: false,
          stable: false,
        ),
      CloudRangeRelayPhase.degraded => throw StateError('已在前置分支处理'),
      CloudRangeRelayPhase.failed => CloudRelayStatusPresentation(
          text: '${status.providerName}分段读取失败',
          warning: true,
          stable: false,
        ),
    };
  }

  static double? _requiredBytesPerSecond(
    int? totalBytes,
    Duration? mediaDuration,
  ) {
    if (totalBytes == null ||
        totalBytes <= 0 ||
        mediaDuration == null ||
        mediaDuration.inMilliseconds <= 0) {
      return null;
    }
    return totalBytes * 1000 / mediaDuration.inMilliseconds;
  }

  static String? _speedText(double bytesPerSecond) {
    if (!bytesPerSecond.isFinite || bytesPerSecond <= 0) return null;
    final megabytes = bytesPerSecond / (1024 * 1024);
    return '${megabytes.toStringAsFixed(1)} MB/s';
  }

  static String? _bufferedText(
    int cachedBytes,
    double? requiredBytesPerSecond,
    Duration? bufferedDuration,
  ) {
    final seconds = bufferedDuration?.inSeconds ??
        (cachedBytes > 0 && requiredBytesPerSecond != null
            ? (cachedBytes / requiredBytesPerSecond).floor()
            : 0);
    return seconds > 0 ? '缓存 $seconds 秒' : null;
  }
}
