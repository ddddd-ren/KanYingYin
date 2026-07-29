import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/platform/app_platform.dart';

class PlayerPlatformPolicy {
  const PlayerPlatformPolicy(this.capabilities);

  final AppPlatformCapabilities capabilities;

  String get decoderSettingKey => capabilities.isAndroid
      ? SettingBoxKey.androidHardwareDecoder
      : SettingBoxKey.hardwareDecoder;

  String? get rendererSettingKey =>
      capabilities.isAndroid ? SettingBoxKey.androidVideoRenderer : null;

  String normalizeDecoder(String? value) {
    return value != null && capabilities.hardwareDecoders.contains(value)
        ? value
        : 'auto';
  }

  String resolvePlaybackDecoder(String? value) {
    final decoder = normalizeDecoder(value);
    if (!capabilities.isWindows) return decoder;
    return switch (decoder) {
      'd3d11va' => 'd3d11va,d3d11va-copy',
      'dxva2' => 'dxva2,dxva2-copy',
      _ => decoder,
    };
  }

  String? normalizeRenderer(String? value) {
    if (!capabilities.isAndroid) return null;
    // mediacodec_embed 直接输出无法合成字幕，旧设置迁移到通用 GPU 渲染器。
    if (value == 'mediacodec_embed') return 'gpu';
    return value != null && capabilities.videoRenderers.contains(value)
        ? value
        : 'auto';
  }

  bool supportsAnime4k(String? renderer) {
    if (capabilities.isWindows) return true;
    return capabilities.supportsAnime4k(normalizeRenderer(renderer) ?? 'auto');
  }
}
