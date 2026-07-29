import 'package:flutter/services.dart';

class AndroidPlatformChannel {
  const AndroidPlatformChannel({
    MethodChannel channel =
        const MethodChannel('com.kanyingyin.player/android'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<bool> enterPictureInPicture({
    required int width,
    required int height,
  }) {
    return _invokeBool('enterPictureInPicture', <String, int>{
      'width': width > 0 ? width : 16,
      'height': height > 0 ? height : 9,
    });
  }

  Future<void> setImmersive(bool enabled) {
    return _channel.invokeMethod<void>('setImmersive', enabled);
  }

  Future<void> setBrightness(double value) {
    return _channel.invokeMethod<void>(
      'setBrightness',
      value.clamp(0.01, 1.0).toDouble(),
    );
  }

  Future<String?> saveScreenshot(Uint8List bytes) {
    return _channel.invokeMethod<String>('saveScreenshot', bytes);
  }

  Future<bool> openWithMime(String uri, String mimeType) {
    return _invokeBool(
      'openWithMime',
      <String, String>{'url': uri, 'mimeType': mimeType},
    );
  }

  Future<bool> _invokeBool(String method, [Object? arguments]) async {
    return await _channel.invokeMethod<bool>(method, arguments) ?? false;
  }
}
