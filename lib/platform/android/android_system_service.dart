import 'dart:typed_data';

import 'package:kanyingyin/platform/android/android_platform_channel.dart';

class AndroidSystemService {
  const AndroidSystemService({
    AndroidPlatformChannel channel = const AndroidPlatformChannel(),
  }) : _channel = channel;

  final AndroidPlatformChannel _channel;

  Future<bool> enterPictureInPicture({
    required int width,
    required int height,
  }) =>
      _channel.enterPictureInPicture(width: width, height: height);

  Future<void> setImmersive(bool enabled) => _channel.setImmersive(enabled);

  Future<void> setBrightness(double value) => _channel.setBrightness(value);

  Future<String?> saveScreenshot(Uint8List bytes) =>
      _channel.saveScreenshot(bytes);

  Future<bool> openWithMime(String uri, String mimeType) =>
      _channel.openWithMime(uri, mimeType);

  Future<bool> requestNotificationPermission() =>
      _channel.requestNotificationPermission();
}
