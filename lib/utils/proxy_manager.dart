import 'dart:async';
import 'dart:io';

import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/proxy_utils.dart';
import 'package:kanyingyin/utils/storage.dart';

/// 代理管理器
/// 统一管理 Dio HTTP 请求的代理设置
/// 注意：WebView 代理在各平台 controller 初始化时单独处理
class ProxyManager {
  ProxyManager._();

  static const List<int> _localProxyPorts = [
    7897,
    7890,
    7891,
    7892,
    10809,
    10808,
    1080,
    8080,
    20171,
  ];
  static const Duration _portTimeout = Duration(milliseconds: 350);
  static const Duration _probeTimeout = Duration(seconds: 5);
  static final List<_ProxyProbeGroup> _probeGroups = [
    _ProxyProbeGroup(
      name: 'TMDB API',
      uris: [
        Uri.parse('https://api.themoviedb.org/3/configuration'),
      ],
    ),
  ];
  static Future<bool>? _recoveringProxy;

  /// 启动时初始化代理。
  ///
  /// 如果用户已经手动配置并启用代理，验证后供新建客户端读取。
  /// 如果在线资源直连正常，不主动改动用户的代理开关。
  /// 如果 Bangumi 直连超时，会自动探测常见本机代理端口并启用。
  static Future<void> initializeProxy() async {
    final setting = GStorage.setting;
    final bool proxyEnable =
        setting.get(SettingBoxKey.proxyEnable, defaultValue: false);
    final String proxyUrl =
        setting.get(SettingBoxKey.proxyUrl, defaultValue: '');

    if (proxyEnable) {
      final parsedProxy = ProxyUtils.parseProxyUrl(proxyUrl);
      if (parsedProxy != null &&
          await _canReachProbeUrls(parsedProxy.$1, parsedProxy.$2)) {
        AppLogger().i('Proxy: 已配置代理可用 $proxyUrl');
        await setting.put(SettingBoxKey.proxyConfigured, true);
        await setting.put(SettingBoxKey.enableSystemProxy, true);
        applyProxy();
        return;
      }
      AppLogger().w('Proxy: 已配置代理不可用，尝试重新探测本机代理');

      final detected = await _detectLocalProxy();
      if (detected != null) {
        await _enableDetectedProxy(detected);
        applyProxy();
        return;
      }
    }

    if (await _canReachProbeUrlsDirectly()) {
      AppLogger().i('Proxy: 在线资源直连可用，跳过本机代理探测');
      await setting.put(SettingBoxKey.proxyEnable, false);
      await setting.put(SettingBoxKey.enableSystemProxy, false);
      applyProxy();
      return;
    }

    final detected = await _detectLocalProxy();
    if (detected != null) {
      await _enableDetectedProxy(detected);
      applyProxy();
      return;
    }

    AppLogger().i('Proxy: 在线资源直连和常见本机代理均不可用');
    await setting.put(SettingBoxKey.proxyEnable, false);
    await setting.put(SettingBoxKey.proxyConfigured, false);
    await setting.put(SettingBoxKey.enableSystemProxy, false);
    applyProxy();
  }

  /// 在线资源请求失败后重新探测代理，并更新后续新建客户端使用的设置。
  ///
  /// 这个入口用于处理启动后网络状态变化、代理稍后启动、旧代理失效等情况。
  static Future<bool> recoverOnlineResourceProxy() {
    _recoveringProxy ??= _recoverOnlineResourceProxy()
        .whenComplete(() => _recoveringProxy = null);
    return _recoveringProxy!;
  }

  /// 应用代理设置
  static void applyProxy() {
    AppLogger().i('Proxy: 代理设置已保存，将对新建网络客户端生效');
  }

  /// 清除代理设置
  static void clearProxy() {
    AppLogger().i('Proxy: 代理清除设置已保存，将对新建网络客户端生效');
  }

  static Future<(String, int)?> _detectLocalProxy() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return null;
    }

    for (final port in _localProxyPorts) {
      final portOpen = await _isPortOpen('127.0.0.1', port);
      if (!portOpen) continue;

      final available = await _canReachProbeUrls('127.0.0.1', port);
      if (available) {
        return ('127.0.0.1', port);
      }
    }
    return null;
  }

  static Future<void> _enableDetectedProxy((String, int) detected) async {
    final setting = GStorage.setting;
    final detectedUrl = 'http://${detected.$1}:${detected.$2}';
    await setting.put(SettingBoxKey.proxyUrl, detectedUrl);
    await setting.put(SettingBoxKey.proxyConfigured, true);
    await setting.put(SettingBoxKey.proxyEnable, true);
    await setting.put(SettingBoxKey.enableSystemProxy, true);
    AppLogger().i('Proxy: 已自动启用本机代理 $detectedUrl');
  }

  static Future<bool> _isPortOpen(String host, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: _portTimeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static Future<bool> _recoverOnlineResourceProxy() async {
    final detected = await _detectLocalProxy();
    if (detected != null) {
      await _enableDetectedProxy(detected);
      applyProxy();
      return true;
    }

    if (await _canReachProbeUrlsDirectly()) {
      final setting = GStorage.setting;
      await setting.put(SettingBoxKey.proxyEnable, false);
      await setting.put(SettingBoxKey.enableSystemProxy, false);
      applyProxy();
      return true;
    }

    return false;
  }

  static Future<bool> _canReachProbeUrls(String host, int port) async {
    for (final group in _probeGroups) {
      var groupReachable = false;
      for (final uri in group.uris) {
        if (await _canReachProbeUrl(uri, host, port)) {
          groupReachable = true;
          break;
        }
      }

      if (!groupReachable) {
        AppLogger()
            .w('Proxy: local proxy $host:$port cannot reach ${group.name}');
        return false;
      }
    }
    return true;
  }

  static Future<bool> _canReachProbeUrl(Uri uri, String host, int port) async {
    final client = HttpClient();
    client.connectionTimeout = _probeTimeout;
    client.badCertificateCallback = (_, __, ___) => true;
    client.findProxy = (_) => 'PROXY $host:$port';

    try {
      final request = await client.getUrl(uri).timeout(_probeTimeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'KanYingYin');
      final response = await request.close().timeout(_probeTimeout);
      await response.drain<void>().timeout(const Duration(seconds: 2));
      return _isReachableStatus(response.statusCode);
    } catch (e) {
      AppLogger().w('Proxy: 本机代理 $host:$port 探测失败 $uri $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<bool> _canReachProbeUrlsDirectly() async {
    for (final group in _probeGroups) {
      var groupReachable = false;
      for (final uri in group.uris) {
        if (await _canReachProbeUrlDirectly(uri)) {
          groupReachable = true;
          break;
        }
      }

      if (!groupReachable) {
        AppLogger().w('Proxy: direct connection cannot reach ${group.name}');
        return false;
      }
    }
    return true;
  }

  static Future<bool> _canReachProbeUrlDirectly(Uri uri) async {
    final client = HttpClient();
    client.connectionTimeout = _probeTimeout;
    client.badCertificateCallback = (_, __, ___) => true;
    client.findProxy = (_) => 'DIRECT';

    try {
      final request = await client.getUrl(uri).timeout(_probeTimeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'KanYingYin');
      final response = await request.close().timeout(_probeTimeout);
      await response.drain<void>().timeout(const Duration(seconds: 2));
      return _isReachableStatus(response.statusCode);
    } catch (e) {
      AppLogger().w('Proxy: 在线资源直连探测失败 $uri $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static bool _isReachableStatus(int statusCode) {
    return statusCode >= 200 &&
        statusCode < 500 &&
        statusCode != HttpStatus.proxyAuthenticationRequired;
  }
}

class _ProxyProbeGroup {
  const _ProxyProbeGroup({
    required this.name,
    required this.uris,
  });

  final String name;
  final List<Uri> uris;
}
