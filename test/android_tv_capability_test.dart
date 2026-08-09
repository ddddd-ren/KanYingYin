import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/android/android_device_capabilities.dart';
import 'package:kanyingyin/platform/android/android_performance_profile.dart';
import 'package:kanyingyin/platform/android/android_platform_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel =
      MethodChannel('com.kanyingyin.player/android.capability.test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Leanback 设备 Map 解析为 Android TV 能力', () {
    final result = AndroidDeviceCapabilities.fromPlatformMap(const {
      'sdkInt': 36,
      'leanback': true,
      'television': false,
      'touchscreen': false,
      'webView': true,
      'manufacturer': 'vivo',
      'model': 'V2219A',
      'hardware': 'mt6877',
      'socModel': 'MT6877V/TTZA',
      'currentRefreshRate': 60.0,
      'supportedRefreshRates': <Object?>[120, 60.0, 90.0, 120.0],
      'preferredDisplayModeId': 3,
    });

    expect(result.sdkInt, 36);
    expect(result.leanback, isTrue);
    expect(result.television, isFalse);
    expect(result.touchscreen, isFalse);
    expect(result.webView, isTrue);
    expect(result.isAndroidTv, isTrue);
    expect(result.manufacturer, 'vivo');
    expect(result.model, 'V2219A');
    expect(result.hardware, 'mt6877');
    expect(result.socModel, 'MT6877V/TTZA');
    expect(result.currentRefreshRate, 60.0);
    expect(result.supportedRefreshRates, <double>[60.0, 90.0, 120.0]);
    expect(result.preferredDisplayModeId, 3);
    expect(result.performanceProfile, AndroidPerformanceProfile.mt6877);
  });

  test('没有 TV 特性时回退为普通 Android', () {
    final result = AndroidDeviceCapabilities.fromPlatformMap(const {
      'sdkInt': 24,
      'leanback': false,
      'television': false,
      'touchscreen': true,
      'webView': false,
    });

    expect(result.isAndroidTv, isFalse);
    expect(result.sdkInt, 24);
    expect(result.touchscreen, isTrue);
  });

  test('Television 设备在没有 Leanback 时仍识别为 Android TV', () {
    final result = AndroidDeviceCapabilities.fromPlatformMap(const {
      'sdkInt': 28,
      'leanback': false,
      'television': true,
      'touchscreen': false,
      'webView': false,
    });

    expect(result.leanback, isFalse);
    expect(result.television, isTrue);
    expect(result.isAndroidTv, isTrue);
  });

  test('畸形平台 Map 使用安全默认值', () {
    final result = AndroidDeviceCapabilities.fromPlatformMap(const {
      'sdkInt': '36',
      'leanback': 'true',
      'television': null,
      'touchscreen': 1,
      'webView': false,
      'manufacturer': 1,
      'model': null,
      'hardware': true,
      'socModel': <Object?>[],
      'currentRefreshRate': double.nan,
      'supportedRefreshRates': <Object?>[-1, 0, double.infinity, '120'],
      'preferredDisplayModeId': -1,
    });

    expect(result.sdkInt, 0);
    expect(result.isAndroidTv, isFalse);
    expect(result.touchscreen, isFalse);
    expect(result.webView, isFalse);
    expect(result.manufacturer, isEmpty);
    expect(result.model, isEmpty);
    expect(result.hardware, isEmpty);
    expect(result.socModel, isEmpty);
    expect(result.currentRefreshRate, 0);
    expect(result.supportedRefreshRates, isEmpty);
    expect(result.preferredDisplayModeId, 0);
    expect(result.performanceProfile, AndroidPerformanceProfile.standard);
  });

  test('平台通道异常时回退为未知能力', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'CapabilityProbeFailed',
        message: '无法读取 Android 设备能力',
      );
    });

    final result = await AndroidDeviceCapabilities.load(
      channel: const AndroidPlatformChannel(channel: channel),
    );

    expect(result.sdkInt, 0);
    expect(result.isAndroidTv, isFalse);
    expect(result.touchscreen, isFalse);
    expect(result.webView, isFalse);
  });
}
