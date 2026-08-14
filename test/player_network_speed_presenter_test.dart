import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/presentation/player_network_speed_presenter.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';

void main() {
  test('就绪的有效中转速度格式化为 MB 每秒', () {
    final result = PlayerNetworkSpeedPresenter.present(
      const CloudRangeRelayStatus(
        providerName: '测试网盘',
        phase: CloudRangeRelayPhase.ready,
        bytesPerSecond: 4.3 * 1024 * 1024,
      ),
    );

    expect(result, '网速 4.3 MB/s');
  });

  test('无效中转速度不展示', () {
    expect(PlayerNetworkSpeedPresenter.present(null), isNull);

    for (final speed in <double>[
      0,
      -1,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      final status = CloudRangeRelayStatus(
        providerName: '测试网盘',
        phase: CloudRangeRelayPhase.ready,
        bytesPerSecond: speed,
      );
      expect(
        PlayerNetworkSpeedPresenter.present(status),
        isNull,
        reason: '$speed 不应生成网速文字',
      );
    }
  });
}
