import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';

abstract final class PlayerNetworkSpeedPresenter {
  static String? present(CloudRangeRelayStatus? status) {
    final bytesPerSecond = status?.bytesPerSecond;
    if (bytesPerSecond == null ||
        !bytesPerSecond.isFinite ||
        bytesPerSecond <= 0) {
      return null;
    }
    return '网速 ${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}
