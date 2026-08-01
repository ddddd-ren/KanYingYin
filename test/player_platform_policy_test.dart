import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/player_platform_policy.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  test('Android 使用独立解码器和渲染器设置', () {
    const policy = PlayerPlatformPolicy(AppPlatformCapabilities.android);

    expect(policy.decoderSettingKey, SettingBoxKey.androidHardwareDecoder);
    expect(policy.rendererSettingKey, SettingBoxKey.androidVideoRenderer);
    expect(policy.normalizeDecoder('d3d11va-copy'), 'auto');
    expect(policy.normalizeRenderer('mediacodec_embed'), 'gpu');
    expect(
      AppPlatformCapabilities.android.videoRenderers,
      isNot(contains('mediacodec_embed')),
    );
    expect(policy.supportsAnime4k('mediacodec_embed'), isTrue);
    expect(policy.supportsAnime4k('auto'), isTrue);
    expect(policy.supportsAnime4k('gpu'), isTrue);
  });

  test('Windows 继续使用原有解码键且不写 Android 渲染器', () {
    const policy = PlayerPlatformPolicy(AppPlatformCapabilities.windows);

    expect(policy.decoderSettingKey, SettingBoxKey.hardwareDecoder);
    expect(policy.rendererSettingKey, isNull);
    expect(policy.normalizeDecoder('d3d11va-copy'), 'd3d11va-copy');
    expect(
      policy.resolvePlaybackDecoder('d3d11va'),
      'd3d11va,d3d11va-copy',
    );
    expect(
      policy.resolvePlaybackDecoder('dxva2'),
      'dxva2,dxva2-copy',
    );
    expect(
      policy.resolvePlaybackDecoder('d3d11va-copy'),
      'd3d11va-copy',
    );
    expect(policy.normalizeRenderer('gpu'), isNull);
    expect(policy.supportsAnime4k(null), isTrue);
  });
}
