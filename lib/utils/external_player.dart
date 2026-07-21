import 'package:flutter/services.dart';
import 'package:kanyingyin/utils/logger.dart';

typedef ExternalPlayerWarningReporter = void Function(String category);

class ExternalPlayerClient {
  const ExternalPlayerClient({
    required MethodChannel channel,
    required ExternalPlayerWarningReporter warningReporter,
  })  : _channel = channel,
        _warningReporter = warningReporter;

  final MethodChannel _channel;
  final ExternalPlayerWarningReporter _warningReporter;

  Future<bool> launchURLWithMIME(String url, String mimeType) async {
    try {
      return await _channel.invokeMethod<bool>(
            'openWithMime',
            <String, String>{'url': url, 'mimeType': mimeType},
          ) ??
          false;
    } on MissingPluginException {
      _warningReporter('PlatformUnavailable');
      return false;
    } on PlatformException catch (error) {
      _warningReporter(_normalizeErrorCode(error.code));
      return false;
    }
  }

  Future<bool> launchURLWithReferer(String url, String referer) async {
    try {
      return await _channel.invokeMethod<bool>(
            'openWithReferer',
            <String, String>{'url': url, 'referer': referer},
          ) ??
          false;
    } on MissingPluginException {
      _warningReporter('PlatformUnavailable');
      return false;
    } on PlatformException catch (error) {
      _warningReporter(_normalizeErrorCode(error.code));
      return false;
    }
  }

  String _normalizeErrorCode(String code) {
    return switch (code) {
      'UnsupportedHeaders' => 'UnsupportedHeaders',
      'InvalidInput' => 'InvalidInput',
      'PlatformUnavailable' => 'PlatformUnavailable',
      _ => 'LaunchFailed',
    };
  }
}

class ExternalPlayer {
  // 注意：仍需开发 iOS/Linux 设备的外部播放功能。
  // Windows 外部播放不支持附带 Referer 等额外请求头。
  static const platform = MethodChannel('com.kanyingyin.player/intent');

  static final ExternalPlayerClient _client = ExternalPlayerClient(
    channel: platform,
    warningReporter: (category) {
      AppLogger().e('ExternalPlayer: $category');
    },
  );

  static Future<bool> launchURLWithMIME(String url, String mimeType) {
    return _client.launchURLWithMIME(url, mimeType);
  }

  static Future<bool> launchURLWithReferer(String url, String referer) {
    return _client.launchURLWithReferer(url, referer);
  }
}
