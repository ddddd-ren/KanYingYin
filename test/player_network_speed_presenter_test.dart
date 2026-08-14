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
    final invalidStatuses = <CloudRangeRelayStatus?>[
      null,
      const CloudRangeRelayStatus(
        providerName: '测试网盘',
        phase: CloudRangeRelayPhase.ready,
      ),
      const CloudRangeRelayStatus(
        providerName: '测试网盘',
        phase: CloudRangeRelayPhase.ready,
        bytesPerSecond: -1,
      ),
      CloudRangeRelayStatus(
        providerName: '测试网盘',
        phase: CloudRangeRelayPhase.ready,
        bytesPerSecond: double.nan,
      ),
      CloudRangeRelayStatus(
        providerName: '测试网盘',
        phase: CloudRangeRelayPhase.ready,
        bytesPerSecond: double.infinity,
      ),
      CloudRangeRelayStatus(
        providerName: '测试网盘',
        phase: CloudRangeRelayPhase.ready,
        bytesPerSecond: double.negativeInfinity,
      ),
    ];

    for (final status in invalidStatuses) {
      expect(PlayerNetworkSpeedPresenter.present(status), isNull);
    }
  });
}
