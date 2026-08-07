import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/android/android_device_capabilities.dart';
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
    });

    expect(result.sdkInt, 36);
    expect(result.leanback, isTrue);
    expect(result.television, isFalse);
    expect(result.touchscreen, isFalse);
    expect(result.webView, isTrue);
    expect(result.isAndroidTv, isTrue);
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
    });

    expect(result.sdkInt, 0);
    expect(result.isAndroidTv, isFalse);
    expect(result.touchscreen, isFalse);
    expect(result.webView, isFalse);
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
