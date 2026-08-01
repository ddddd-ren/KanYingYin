/// 迅雷客户端构建配置。
///
/// 配置只允许在编译时通过 Dart Define 注入，避免把客户端凭据保存在源码中。
final class XunleiClientConfiguration {
  const XunleiClientConfiguration({
    this.clientId = const String.fromEnvironment(
      'KANYINGYIN_XUNLEI_CLIENT_ID',
    ),
    this.clientSecret = const String.fromEnvironment(
      'KANYINGYIN_XUNLEI_CLIENT_SECRET',
    ),
    this.webClientId = const String.fromEnvironment(
      'KANYINGYIN_XUNLEI_WEB_CLIENT_ID',
    ),
    this.appKey = const String.fromEnvironment(
      'KANYINGYIN_XUNLEI_APP_KEY',
    ),
  });

  static const String missingConfigurationMessage = '当前构建未配置迅雷授权';

  final String clientId;
  final String clientSecret;
  final String webClientId;
  final String appKey;

  bool get isConfigured =>
      clientId.trim().isNotEmpty &&
      clientSecret.trim().isNotEmpty &&
      webClientId.trim().isNotEmpty &&
      appKey.trim().isNotEmpty;

  String get requiredClientId => _required(clientId);
  String get requiredClientSecret => _required(clientSecret);
  String get requiredWebClientId => _required(webClientId);
  String get requiredAppKey => _required(appKey);

  void requireConfigured() {
    if (!isConfigured) {
      throw StateError(missingConfigurationMessage);
    }
  }

  String _required(String value) {
    requireConfigured();
    return value.trim();
  }

  @override
  String toString() => 'XunleiClientConfiguration(configured: $isConfigured)';
}
