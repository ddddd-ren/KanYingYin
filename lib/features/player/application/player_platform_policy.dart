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

  String? normalizeRenderer(String? value) {
    if (!capabilities.isAndroid) return null;
    return value != null && capabilities.videoRenderers.contains(value)
        ? value
        : 'auto';
  }

  bool supportsAnime4k(String? renderer) {
    if (capabilities.isWindows) return true;
    return capabilities.supportsAnime4k(normalizeRenderer(renderer) ?? 'auto');
  }
}
