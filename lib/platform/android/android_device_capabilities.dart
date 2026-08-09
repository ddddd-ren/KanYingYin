import 'package:kanyingyin/platform/android/android_platform_channel.dart';
import 'package:kanyingyin/platform/android/android_performance_profile.dart';

class AndroidDeviceCapabilities {
  const AndroidDeviceCapabilities({
    required this.sdkInt,
    required this.leanback,
    required this.television,
    required this.touchscreen,
    required this.webView,
    required this.manufacturer,
    required this.model,
    required this.hardware,
    required this.socModel,
    required this.currentRefreshRate,
    required this.supportedRefreshRates,
    required this.preferredDisplayModeId,
  });

  const AndroidDeviceCapabilities.unknown()
      : sdkInt = 0,
        leanback = false,
        television = false,
        touchscreen = false,
        webView = false,
        manufacturer = '',
        model = '',
        hardware = '',
        socModel = '',
        currentRefreshRate = 0,
        supportedRefreshRates = const <double>[],
        preferredDisplayModeId = 0;

  final int sdkInt;
  final bool leanback;
  final bool television;
  final bool touchscreen;
  final bool webView;
  final String manufacturer;
  final String model;
  final String hardware;
  final String socModel;
  final double currentRefreshRate;
  final List<double> supportedRefreshRates;
  final int preferredDisplayModeId;

  bool get isAndroidTv => leanback || television;
  AndroidPerformanceProfile get performanceProfile =>
      AndroidPerformanceProfileResolver.resolve(
        manufacturer: manufacturer,
        model: model,
        hardware: hardware,
        socModel: socModel,
      );

  static AndroidDeviceCapabilities fromPlatformMap(
    Map<Object?, Object?> values,
  ) {
    return AndroidDeviceCapabilities(
      sdkInt: values['sdkInt'] is int ? values['sdkInt'] as int : 0,
      leanback: values['leanback'] is bool && values['leanback'] as bool,
      television: values['television'] is bool && values['television'] as bool,
      touchscreen:
          values['touchscreen'] is bool && values['touchscreen'] as bool,
      webView: values['webView'] is bool && values['webView'] as bool,
      manufacturer: _string(values['manufacturer']),
      model: _string(values['model']),
      hardware: _string(values['hardware']),
      socModel: _string(values['socModel']),
      currentRefreshRate: _positiveDouble(values['currentRefreshRate']),
      supportedRefreshRates: _refreshRates(values['supportedRefreshRates']),
      preferredDisplayModeId: _positiveInt(values['preferredDisplayModeId']),
    );
  }

  static String _string(Object? value) => value is String ? value.trim() : '';

  static double _positiveDouble(Object? value) {
    if (value is! num) return 0;
    final converted = value.toDouble();
    return converted.isFinite && converted > 0 ? converted : 0;
  }

  static int _positiveInt(Object? value) =>
      value is int && value > 0 ? value : 0;

  static List<double> _refreshRates(Object? value) {
    if (value is! List<Object?>) return const <double>[];
    final rates = value
        .map(_positiveDouble)
        .where((rate) => rate > 0)
        .toSet()
        .toList()
      ..sort();
    return List<double>.unmodifiable(rates);
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
