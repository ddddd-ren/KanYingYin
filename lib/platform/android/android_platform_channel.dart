import 'package:flutter/services.dart';

class AndroidPickedFile {
  const AndroidPickedFile({
    required this.path,
    required this.name,
    required this.size,
  });

  final String path;
  final String name;
  final int size;
}

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

  Future<bool> requestNotificationPermission() {
    return _invokeBool('requestNotificationPermission');
  }

  Future<Map<Object?, Object?>?> getDeviceCapabilities() {
    return _channel.invokeMapMethod<Object?, Object?>(
      'getDeviceCapabilities',
    );
  }

  Future<Map<Object?, Object?>?> pickDocumentDirectory() {
    return _channel.invokeMapMethod<Object?, Object?>('pickDirectory');
  }

  Future<AndroidPickedFile?> pickFile({
    required String title,
    required List<String> allowedExtensions,
    required int maxBytes,
  }) async {
    if (maxBytes <= 0 || allowedExtensions.isEmpty) {
      throw ArgumentError('文件选择参数无效');
    }
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'pickFile',
      <String, Object>{
        'title': title,
        'allowedExtensions': allowedExtensions,
        'maxBytes': maxBytes,
      },
    );
    if (raw == null) return null;
    final path = raw['path'];
    final name = raw['name'];
    final size = raw['size'];
    if (path is! String ||
        path.isEmpty ||
        name is! String ||
        name.isEmpty ||
        size is! num) {
      throw const FormatException('Android 文件选择响应无效');
    }
    return AndroidPickedFile(
      path: path,
      name: name,
      size: size.toInt(),
    );
  }

  Future<bool> canAccessDocument(String documentUri, String treeUri) {
    return _invokeBool('canAccessDocument', <String, String>{
      'documentUri': documentUri,
      'treeUri': treeUri,
    });
  }

  Future<List<Map<Object?, Object?>>> listDocumentChildren(
    String documentUri,
    String treeUri,
  ) async {
    final values = await _channel.invokeListMethod<Object?>(
      'listDocumentChildren',
      <String, String>{
        'documentUri': documentUri,
        'treeUri': treeUri,
      },
    );
    return (values ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .toList(growable: false);
  }

  Future<Uint8List> readSmallDocument(
    String documentUri,
    int maxBytes,
  ) async {
    return await _channel.invokeMethod<Uint8List>(
          'readSmallDocument',
          <String, Object>{
            'documentUri': documentUri,
            'maxBytes': maxBytes,
          },
        ) ??
        Uint8List(0);
  }

  Future<bool> _invokeBool(String method, [Object? arguments]) async {
    return await _channel.invokeMethod<bool>(method, arguments) ?? false;
  }
}
