import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/core/network/network_config.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/proxy_utils.dart';
import 'package:kanyingyin/utils/storage.dart';

class NetworkSettingsConfigFactory {
  NetworkSettingsConfigFactory._();

  static NetworkConfig create({
    Box<dynamic>? setting,
    Duration connectTimeout = const Duration(seconds: 12),
    Duration receiveTimeout = const Duration(seconds: 12),
    Duration? sendTimeout,
  }) {
    final settings = setting ?? GStorage.setting;
    final proxyEnable =
        settings.get(SettingBoxKey.proxyEnable, defaultValue: false) == true;
    if (!proxyEnable) {
      return NetworkConfig(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        sendTimeout: sendTimeout,
      );
    }

    final rawProxyUrl = settings.get(
      SettingBoxKey.proxyUrl,
      defaultValue: '',
    );
    final proxyUrl = rawProxyUrl is String ? rawProxyUrl : '';
    final parsed = ProxyUtils.parseProxyUrl(proxyUrl);
    if (parsed == null) {
      AppLogger().w('Proxy: 代理地址格式错误或为空');
      return NetworkConfig(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        sendTimeout: sendTimeout,
      );
    }

    return NetworkConfig(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      proxyHost: parsed.$1,
      proxyPort: parsed.$2,
    );
  }
}
