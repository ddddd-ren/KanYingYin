import 'package:kanyingyin/platform/android/android_platform_channel.dart';

class AndroidDeviceCapabilities {
  const AndroidDeviceCapabilities({
    required this.sdkInt,
    required this.leanback,
    required this.television,
    required this.touchscreen,
    required this.webView,
  });

  const AndroidDeviceCapabilities.unknown()
      : sdkInt = 0,
        leanback = false,
        television = false,
        touchscreen = false,
        webView = false;

  final int sdkInt;
  final bool leanback;
  final bool television;
  final bool touchscreen;
  final bool webView;

  bool get isAndroidTv => leanback || television;

  static AndroidDeviceCapabilities fromPlatformMap(
    Map<Object?, Object?> values,
  ) {
    return AndroidDeviceCapabilities(
      sdkInt: values['sdkInt'] is int ? values['sdkInt'] as int : 0,
      leanback: values['leanback'] is bool && values['leanback'] as bool,
      television:
          values['television'] is bool && values['television'] as bool,
      touchscreen:
          values['touchscreen'] is bool && values['touchscreen'] as bool,
      webView: values['webView'] is bool && values['webView'] as bool,
    );
  }

  static Future<AndroidDeviceCapabilities> load({
    AndroidPlatformChannel? channel,
  }) async {
    try {
      final values = await (channel ?? const AndroidPlatformChannel())
          .getDeviceCapabilities();
      if (values == null) return const AndroidDeviceCapabilities.unknown();
      return fromPlatformMap(values);
    } on Object {
      return const AndroidDeviceCapabilities.unknown();
    }
  }
}
