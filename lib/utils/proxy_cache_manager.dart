import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/network_settings_config_factory.dart';
import 'package:kanyingyin/utils/proxy_manager.dart';

class ProxyCacheManager {
  static final CacheManager instance = CacheManager(
    Config(
      'kanyingyinProxyImageCache',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 600,
      fileService: _ProxyAwareFileService(),
    ),
  );

  ProxyCacheManager._();
}

class _ProxyAwareFileService extends FileService {
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      return await _request(url, headers: headers);
    } catch (e) {
      AppLogger().w('ImageCache: image request failed, retry proxy recovery',
          error: e);
      final recovered = await ProxyManager.recoverOnlineResourceProxy();
      if (!recovered) {
        rethrow;
      }
      return _request(url, headers: headers);
    }
  }

  Future<FileServiceResponse> _request(
    String url, {
    Map<String, String>? headers,
  }) async {
    final config = NetworkSettingsConfigFactory.create(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
    );
    final client = HttpClient()
      ..connectionTimeout = config.connectTimeout
      ..idleTimeout = config.receiveTimeout;

    if (config.hasProxy) {
      client.findProxy = (_) => 'PROXY ${config.proxyHost}:${config.proxyPort}';
    }
    if (config.allowBadCertificates) {
      client.badCertificateCallback = (cert, host, port) => true;
    }

    try {
      final request = await client.getUrl(Uri.parse(url));
      headers?.forEach(request.headers.set);
      final response = await request.close().timeout(config.receiveTimeout);
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.accepted) {
        final statusCode = response.statusCode;
        await response.drain<void>().timeout(const Duration(seconds: 2));
        client.close(force: true);
        throw HttpException(
          'Image request failed with status $statusCode',
          uri: Uri.parse(url),
        );
      }
      return _ProxyImageResponse(response, client);
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }
}

class _ProxyImageResponse implements FileServiceResponse {
  _ProxyImageResponse(this._response, this._client)
      : _receivedTime = DateTime.now();

  final HttpClientResponse _response;
  final HttpClient _client;
  final DateTime _receivedTime;

  @override
  Stream<List<int>> get content async* {
    try {
      await for (final chunk in _response) {
        yield chunk;
      }
    } finally {
      _client.close(force: true);
    }
  }

  @override
  int? get contentLength =>
      _response.contentLength >= 0 ? _response.contentLength : null;

  @override
  String? get eTag => null;

  @override
  String get fileExtension {
    final contentType = _response.headers.contentType;
    final mimeType = contentType?.mimeType.toLowerCase();
    return switch (mimeType) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/webp' => '.webp',
      'image/gif' => '.gif',
      'image/avif' => '.avif',
      'image/bmp' => '.bmp',
      _ => '',
    };
  }

  @override
  int get statusCode => _response.statusCode;

  @override
  DateTime get validTill {
    final cacheControl =
        _response.headers.value(HttpHeaders.cacheControlHeader);
    var ageDuration = const Duration(days: 7);

    if (cacheControl != null) {
      for (final setting in cacheControl.split(',')) {
        final sanitizedSetting = setting.trim().toLowerCase();
        if (sanitizedSetting == 'no-cache') {
          ageDuration = Duration.zero;
        } else if (sanitizedSetting.startsWith('max-age=')) {
          final maxAge = int.tryParse(sanitizedSetting.split('=').last);
          if (maxAge != null && maxAge > 0) {
            ageDuration = Duration(seconds: maxAge);
          }
        }
      }
    }

    return _receivedTime.add(ageDuration);
  }
}
