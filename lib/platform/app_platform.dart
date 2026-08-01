enum AppPlatformKind { windows, android }

class AppPlatformCapabilities {
  const AppPlatformCapabilities({
    required this.kind,
    required this.desktopShell,
    required this.storageAccessFramework,
    required this.systemPictureInPicture,
    required this.windowBrightness,
    required this.hardwareDecoders,
    required this.videoRenderers,
  });

  static const windows = AppPlatformCapabilities(
    kind: AppPlatformKind.windows,
    desktopShell: true,
    storageAccessFramework: false,
    systemPictureInPicture: false,
    windowBrightness: false,
    hardwareDecoders: <String>[
      'auto',
      'no',
      'auto-safe',
      'auto-copy',
      'd3d11va-copy',
      'd3d11va',
      'dxva2-copy',
      'dxva2',
    ],
    videoRenderers: <String>[],
  );

  static const android = AppPlatformCapabilities(
    kind: AppPlatformKind.android,
    desktopShell: false,
    storageAccessFramework: true,
    systemPictureInPicture: true,
    windowBrightness: true,
    hardwareDecoders: <String>['auto', 'no'],
    videoRenderers: <String>['auto', 'gpu', 'gpu-next'],
  );

  final AppPlatformKind kind;
  final bool desktopShell;
  final bool storageAccessFramework;
  final bool systemPictureInPicture;
  final bool windowBrightness;
  final List<String> hardwareDecoders;
  final List<String> videoRenderers;

  bool get isWindows => kind == AppPlatformKind.windows;
  bool get isAndroid => kind == AppPlatformKind.android;

  bool supportsAnime4k(String renderer) {
    if (isWindows) return true;
    // media_kit_video 在 Android 未指定 vo 时默认使用 gpu。
    return renderer == 'auto' || renderer == 'gpu' || renderer == 'gpu-next';
  }
}
