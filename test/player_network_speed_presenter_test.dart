import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/presentation/player_network_speed_presenter.dart';

void main() {
  test('有效中转速度格式化为 MB 每秒', () {
    final result = PlayerNetworkSpeedPresenter.present(
      4.3 * 1024 * 1024,
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
      expect(
        PlayerNetworkSpeedPresenter.present(speed),
        isNull,
        reason: '$speed 不应生成网速文字',
      );
    }
  });
}
