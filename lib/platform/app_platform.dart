import 'package:kanyingyin/platform/android/android_performance_profile.dart';

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
    this.television = false,
    this.touchscreen = false,
    this.androidSdkInt = 0,
    this.webViewAvailable = false,
    this.androidPerformanceProfile = AndroidPerformanceProfile.standard,
    this.androidManufacturer = '',
    this.androidModel = '',
    this.androidHardware = '',
    this.androidSocModel = '',
    this.androidCurrentRefreshRate = 0,
    this.androidSupportedRefreshRates = const <double>[],
    this.androidPreferredDisplayModeId = 0,
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
  final bool television;
  final bool touchscreen;
  final int androidSdkInt;
  final bool webViewAvailable;
  final AndroidPerformanceProfile androidPerformanceProfile;
  final String androidManufacturer;
  final String androidModel;
  final String androidHardware;
  final String androidSocModel;
  final double androidCurrentRefreshRate;
  final List<double> androidSupportedRefreshRates;
  final int androidPreferredDisplayModeId;

  bool get isWindows => kind == AppPlatformKind.windows;
  bool get isAndroid => kind == AppPlatformKind.android;
  bool get isAndroidTv => isAndroid && television;
  bool get usesMt6877QuarkTuning =>
      androidPerformanceProfile == AndroidPerformanceProfile.mt6877;

  AppPlatformCapabilities copyWith({
    bool? television,
    bool? touchscreen,
    int? androidSdkInt,
    bool? webViewAvailable,
    AndroidPerformanceProfile? androidPerformanceProfile,
    String? androidManufacturer,
    String? androidModel,
    String? androidHardware,
    String? androidSocModel,
    double? androidCurrentRefreshRate,
    List<double>? androidSupportedRefreshRates,
    int? androidPreferredDisplayModeId,
  }) {
    return AppPlatformCapabilities(
      kind: kind,
      desktopShell: desktopShell,
      storageAccessFramework: storageAccessFramework,
      systemPictureInPicture: systemPictureInPicture,
      windowBrightness: windowBrightness,
      hardwareDecoders: hardwareDecoders,
      videoRenderers: videoRenderers,
      television: television ?? this.television,
      touchscreen: touchscreen ?? this.touchscreen,
      androidSdkInt: androidSdkInt ?? this.androidSdkInt,
      webViewAvailable: webViewAvailable ?? this.webViewAvailable,
      androidPerformanceProfile:
          androidPerformanceProfile ?? this.androidPerformanceProfile,
      androidManufacturer: androidManufacturer ?? this.androidManufacturer,
      androidModel: androidModel ?? this.androidModel,
      androidHardware: androidHardware ?? this.androidHardware,
      androidSocModel: androidSocModel ?? this.androidSocModel,
      androidCurrentRefreshRate:
          androidCurrentRefreshRate ?? this.androidCurrentRefreshRate,
      androidSupportedRefreshRates:
          androidSupportedRefreshRates ?? this.androidSupportedRefreshRates,
      androidPreferredDisplayModeId:
          androidPreferredDisplayModeId ?? this.androidPreferredDisplayModeId,
    );
  }

  bool supportsAnime4k(String renderer) {
    if (isWindows) return true;
    // media_kit_video 在 Android 未指定 vo 时默认使用 gpu。
    return renderer == 'auto' || renderer == 'gpu' || renderer == 'gpu-next';
  }
}
