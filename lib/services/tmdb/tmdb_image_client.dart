import 'package:dio/dio.dart';
import 'package:kanyingyin/core/network/dio_factory.dart';
import 'package:kanyingyin/core/network/network_config.dart';
import 'package:kanyingyin/services/tmdb/tmdb_endpoint_policy.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/network_settings_config_factory.dart';
import 'package:kanyingyin/utils/proxy_manager.dart';

typedef TmdbImageDioFactory = Dio Function();
typedef TmdbImageProxyRecovery = Future<bool> Function();

/// 统一加载 TMDB 图片，并在网络路由变化后重建客户端重试一次。
class TmdbImageClient {
  TmdbImageClient({
    Dio? dio,
    TmdbImageDioFactory? dioFactory,
    TmdbImageProxyRecovery? recoverProxy,
  })  : _dioFactory = dioFactory ?? (dio == null ? _createDefaultDio : null),
        _recoverProxy = recoverProxy ??
            (dio == null ? ProxyManager.recoverOnlineResourceProxy : null),
        _dio = dio ?? (dioFactory ?? _createDefaultDio)();

  static final TmdbImageClient shared = TmdbImageClient();

  Dio _dio;
  final TmdbImageDioFactory? _dioFactory;
  final TmdbImageProxyRecovery? _recoverProxy;
  Future<bool>? _recoveringNetwork;
  DateTime? _lastRecoveryAttemptAt;
  var _networkGeneration = 0;
  var _preferOfficialHttp = false;

  static const Duration _recoveryCooldown = Duration(minutes: 1);

  Future<List<int>> downloadBytes(String url) async {
    final officialHttpUrl = _officialHttpFallbackUrl(url);
    if (_preferOfficialHttp && officialHttpUrl != null) {
      try {
        return await _requestBytes(officialHttpUrl);
      } on Object catch (error) {
        _preferOfficialHttp = false;
        AppLogger().w(
          'TMDB 图片: 官方 HTTP 备用地址失效，重新尝试 HTTPS',
          error: error,
        );
      }
    }

    final requestGeneration = _networkGeneration;
    try {
      return await _requestBytes(url);
    } on DioException catch (error, stackTrace) {
      if (!TmdbEndpointPolicy.canTryAnotherEndpoint(error)) {
        _logFailure(url, error);
        Error.throwWithStackTrace(error, stackTrace);
      }

      var lastSecureError = error;
      var lastSecureStackTrace = stackTrace;
      final routeAlreadyRecovered = requestGeneration != _networkGeneration;
      final routeRecovered =
          routeAlreadyRecovered || await _recoverAndRebuildNetwork();

      if (routeRecovered) {
        try {
          return await _requestBytes(url);
        } on DioException catch (retryError, retryStackTrace) {
          if (!TmdbEndpointPolicy.canTryAnotherEndpoint(retryError)) {
            _logFailure(url, retryError);
            Error.throwWithStackTrace(retryError, retryStackTrace);
          }
          lastSecureError = retryError;
          lastSecureStackTrace = retryStackTrace;
        }
      }

      if (officialHttpUrl != null) {
        try {
          final bytes = await _requestBytes(officialHttpUrl);
          _preferOfficialHttp = true;
          AppLogger().w(
            'TMDB 图片: HTTPS 不可用，已切换 TMDB 官方 HTTP 备用地址；请求不含 API Key',
          );
          return bytes;
        } on DioException catch (fallbackError, fallbackStackTrace) {
          _logFailure(officialHttpUrl, fallbackError);
          Error.throwWithStackTrace(fallbackError, fallbackStackTrace);
        }
      }

      _logFailure(url, lastSecureError);
      Error.throwWithStackTrace(lastSecureError, lastSecureStackTrace);
    }
  }

  Future<List<int>> _requestBytes(String url) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('TMDB 图片响应为空');
    }
    return bytes;
  }

  Future<bool> _recoverAndRebuildNetwork() {
    final existing = _recoveringNetwork;
    if (existing != null) return existing;
    final now = DateTime.now();
    final lastAttempt = _lastRecoveryAttemptAt;
    if (lastAttempt != null &&
        now.difference(lastAttempt) < _recoveryCooldown) {
      return Future<bool>.value(false);
    }
    _lastRecoveryAttemptAt = now;
    final task = _recoverAndRebuildNetworkOnce();
    _recoveringNetwork = task;
    return task.whenComplete(() {
      if (identical(_recoveringNetwork, task)) _recoveringNetwork = null;
    });
  }

  Future<bool> _recoverAndRebuildNetworkOnce() async {
    final recoverProxy = _recoverProxy;
    if (recoverProxy == null || !await recoverProxy()) return false;
    final factory = _dioFactory;
    if (factory == null) return false;

    final previous = _dio;
    final replacement = factory();
    _dio = replacement;
    _networkGeneration++;
    if (!identical(previous, replacement)) previous.close(force: true);
    AppLogger().i('TMDB 图片: 网络路由恢复后已重建客户端');
    return true;
  }

  void _logFailure(String url, DioException error) {
    final host = Uri.tryParse(url)?.host ?? 'unknown';
    AppLogger().w(
      'TMDB 图片: 下载失败 host=$host type=${error.type.name}',
      error: error.error ?? error,
    );
  }

  static String? _officialHttpFallbackUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'image.tmdb.org' ||
        uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        !uri.path.startsWith('/t/p/')) {
      return null;
    }
    return uri.replace(scheme: 'http').toString();
  }

  static Dio _createDefaultDio() {
    const connectTimeout = Duration(seconds: 10);
    const receiveTimeout = Duration(seconds: 30);
    try {
      return DioFactory.createForConfig(
        NetworkSettingsConfigFactory.create(
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
        ),
      );
    } on Object {
      // 单元测试或早期初始化阶段没有设置盒时使用安全的直连配置。
      return DioFactory.createForConfig(
        const NetworkConfig(
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
        ),
      );
    }
  }
}
