import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/player_color_profile.dart';

void main() {
  test('自动方案不覆盖源视频色彩属性', () {
    final decision = PlayerColorProfilePolicy.resolve(
      PlayerColorProfile.automatic,
      hdrOutputSupported: true,
    );

    expect(decision.effective, PlayerColorProfile.automatic);
    expect(decision.properties, isEmpty);
    expect(decision.isFallback, isFalse);
  });

  test('HDR 直通只在设备报告 HDR 输出时启用', () {
    final supported = PlayerColorProfilePolicy.resolve(
      PlayerColorProfile.hdrPassthrough,
      hdrOutputSupported: true,
    );
    final unsupported = PlayerColorProfilePolicy.resolve(
      PlayerColorProfile.hdrPassthrough,
      hdrOutputSupported: false,
    );

    expect(supported.properties['target-colorspace-hint'], 'yes');
    expect(supported.effective, PlayerColorProfile.hdrPassthrough);
    expect(unsupported.effective, PlayerColorProfile.automatic);
    expect(unsupported.fallbackReason, isNotEmpty);
  });

  test('HDR 转 SDR 使用 BT.709 和 BT.2390 映射', () {
    final decision = PlayerColorProfilePolicy.resolve(
      PlayerColorProfile.hdrToSdr,
      hdrOutputSupported: false,
    );

    expect(decision.effective, PlayerColorProfile.hdrToSdr);
    expect(decision.properties, <String, String>{
      'tone-mapping': 'bt.2390',
      'target-prim': 'bt.709',
      'target-trc': 'bt.1886',
      'target-peak': '100',
    });
  });

  test('无效存储值回退自动方案', () {
    expect(
      PlayerColorProfileParsing.fromStorage('unknown'),
      PlayerColorProfile.automatic,
    );
    expect(
      PlayerColorProfile.hdrToSdr.storageValue,
      'hdrToSdr',
    );
  });

  test('libmpv 属性不受支持时恢复自动方案且不抛出', () async {
    final calls = <String>[];
    final applier = PlayerColorProfileApplier((property, value) async {
      calls.add('$property=$value');
      if (property == 'target-trc' && value == 'bt.1886') {
        throw UnsupportedError(property);
      }
    });

    final decision = await applier.apply(
      PlayerColorProfile.hdrToSdr,
      hdrOutputSupported: false,
    );

    expect(decision.effective, PlayerColorProfile.automatic);
    expect(decision.fallbackReason, contains('UnsupportedError'));
    expect(calls, contains('tone-mapping=auto'));
    expect(calls, contains('target-prim=auto'));
  });
}
