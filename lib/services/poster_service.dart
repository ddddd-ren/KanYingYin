import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kanyingyin/core/network/dio_factory.dart';
import 'package:kanyingyin/core/network/network_config.dart';
import 'package:kanyingyin/services/local_cover_finder.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';
import 'package:kanyingyin/services/tmdb/tmdb_endpoint_policy.dart';
import 'package:kanyingyin/services/tmdb/tmdb_image_client.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/utils/network_settings_config_factory.dart';
import 'package:kanyingyin/utils/proxy_manager.dart';
import 'package:kanyingyin/modules/local/local_episode_info.dart';
import 'package:path/path.dart' as p;

typedef PosterDioFactory = Dio Function();
typedef PosterProxyRecovery = Future<bool> Function();

class PosterService {
  Dio _dio;
  final TmdbImageClient _imageClient;
  final TmdbApiKeyProvider _apiKeyProvider;
  final PosterDioFactory? _apiDioFactory;
  final PosterProxyRecovery? _recoverProxy;
  Future<bool>? _recoveringNetwork;
  String? _workingBaseUrl;

  PosterService({
    TmdbApiKeyProvider? apiKeyProvider,
    Dio? apiDio,
    Dio? downloadDio,
    PosterDioFactory? apiDioFactory,
    PosterDioFactory? downloadDioFactory,
    PosterProxyRecovery? recoverProxy,
    TmdbImageClient? imageClient,
  })  : _apiKeyProvider =
            apiKeyProvider ?? TmdbApiKeyProvider(userKeyReader: () => ''),
        _apiDioFactory = apiDioFactory ??
            (apiDio == null
                ? () => _createDefaultDio(
                      connectTimeout: const Duration(seconds: 8),
                      receiveTimeout: const Duration(seconds: 10),
                    )
                : null),
        _recoverProxy = recoverProxy ??
            (apiDio == null ? ProxyManager.recoverOnlineResourceProxy : null),
        _dio = apiDio ??
            (apiDioFactory ??
                (() => _createDefaultDio(
                      connectTimeout: const Duration(seconds: 8),
                      receiveTimeout: const Duration(seconds: 10),
                    )))(),
        _imageClient = imageClient ??
            TmdbImageClient(
              dio: downloadDio,
              dioFactory: downloadDioFactory,
              recoverProxy: recoverProxy,
            );

  final Map<String, String?> _searchCache = {};

  String extractMovieName(String filename) {
    var name = p.basenameWithoutExtension(filename);
    name = name.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    name = name.replaceAll(RegExp(r'\([^\)]*\)'), '');

    final filters = [
      RegExp(r'\b\d{3,4}p\b', caseSensitive: false),
      RegExp(r'\b4k\b', caseSensitive: false),
      RegExp(r'\bremux\b', caseSensitive: false),
      RegExp(r'\bbluray\b', caseSensitive: false),
      RegExp(r'\bblu-ray\b', caseSensitive: false),
      RegExp(r'\bhq\b', caseSensitive: false),
      RegExp(r'\b\u9ad8\u7801\b'),
      RegExp(r'\b\u4e2d\u5b57\b'),
      RegExp(r'\b\u4e2d\u6587\u5b57\u5e55\b'),
      RegExp(r'\b\u5185\u5c01\b'),
      RegExp(r'\b\u5185\u5d4c\b'),
      RegExp(r'\b\u4e2d\u82f1\b'),
      RegExp(r'\b\u53cc\u8bed\b'),
      RegExp(r'\b\u56fd\u82f1\b'),
      RegExp(r'\b\u56fd\u914d\b'),
      RegExp(r'\b\u53f0\u914d\b'),
      RegExp(r'\b\u7ca4\u8bed\b'),
      RegExp(r'\bhevc\b', caseSensitive: false),
      RegExp(r'\bh265\b', caseSensitive: false),
      RegExp(r'\bh264\b', caseSensitive: false),
      RegExp(r'\bx265\b', caseSensitive: false),
      RegExp(r'\bx264\b', caseSensitive: false),
      RegExp(r'\bhdr\b', caseSensitive: false),
      RegExp(r'\bdv\b', caseSensitive: false),
      RegExp(r'\bsdr\b', caseSensitive: false),
      RegExp(r'\batmos\b', caseSensitive: false),
      RegExp(r'\bdts\b', caseSensitive: false),
      RegExp(r'\btruehd\b', caseSensitive: false),
      RegExp(r'\bweb-dl\b', caseSensitive: false),
      RegExp(r'\bwebdl\b', caseSensitive: false),
      RegExp(r'\bwebrip\b', caseSensitive: false),
      RegExp(r'\bhdrip\b', caseSensitive: false),
      RegExp(r'\bbdrip\b', caseSensitive: false),
      RegExp(r'\bdvdrip\b', caseSensitive: false),
      RegExp(r'\bbrrip\b', caseSensitive: false),
      RegExp(r'\bu?hd\b', caseSensitive: false),
    ];

    for (final filter in filters) {
      name = name.replaceAll(filter, ' ');
    }

    name = name.replaceFirst(RegExp(r'^[A-Za-z]\s+'), '');
    name = name.replaceAll(RegExp(r'\d+\.?\d*\s*[Gg][Bb]?'), ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return name;
  }

  Future<String?> searchPoster({
    String? rawFilename,
    LocalEpisodeInfo? episodeInfo,
    String? seriesName,
  }) async {
    final queries = _buildPosterQueries(
      rawFilename: rawFilename,
      episodeInfo: episodeInfo,
      seriesName: seriesName,
    );
    if (queries.isEmpty) return null;

    final cacheKey = queries.join('|').toLowerCase();
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey];
    }

    String? result;
    for (final query in queries) {
      result = await _searchTmdb(query);
      if (result != null) break;
    }
    _searchCache[cacheKey] = result;
    return result;
  }

  List<String> _buildPosterQueries({
    String? rawFilename,
    LocalEpisodeInfo? episodeInfo,
    String? seriesName,
  }) {
    final queries = <String>[];

    void addQuery(String? value) {
      final text = value?.trim();
      if (text == null || text.isEmpty) return;
      final normalized = text.replaceAll(RegExp(r'\s+'), ' ');
      if (queries
          .any((item) => item.toLowerCase() == normalized.toLowerCase())) {
        return;
      }
      queries.add(normalized);
    }

    addQuery(seriesName);
    addQuery(_stripSeasonMarkers(seriesName ?? ''));
    addQuery(episodeInfo?.seriesName);
    addQuery(_stripSeasonMarkers(episodeInfo?.seriesName ?? ''));
    addQuery(extractMovieName(rawFilename ?? ''));
    addQuery(_stripSeasonMarkers(extractMovieName(rawFilename ?? '')));

    return queries;
  }

  String _stripSeasonMarkers(String value) {
    var result = value.trim();
    if (result.isEmpty) return result;

    result = result.replaceAll(
      RegExp(r'[\s]*第[一二三四五六七八九十\d]+[季部期]', unicode: true),
      '',
    );
    result = result.replaceAll(
      RegExp(r'\s+\d+(?:st|nd|rd|th)\s+Season', caseSensitive: false),
      '',
    );
    result = result.replaceAll(
      RegExp(r'[\s._-]*S\d{1,2}', caseSensitive: false),
      '',
    );
    result = result.replaceAll(
      RegExp(r'[\s._-]*Season\s*\d{1,2}', caseSensitive: false),
      '',
    );
    result = result.replaceAll(
      RegExp(r'[\s._-]*Part\s*\d{1,2}', caseSensitive: false),
      '',
    );
    result = result.replaceAll(RegExp(r'[\(（][^\)）]*[\)）]'), '');
    return result.trim();
  }

  Future<String?> _searchTmdb(String query) async {
    if (query.isEmpty) return null;
    final apiKey = _apiKeyProvider.read();
    if (apiKey.isEmpty) return null;

    final baseUrl = await _ensureBaseUrl(apiKey);
    if (baseUrl == null) {
      AppLogger().w('PosterService: all TMDB endpoints unreachable');
      return null;
    }

    try {
      for (final endpoint in ['movie', 'tv']) {
        final response = await _dio.get<Map<String, dynamic>>(
            '$baseUrl/search/$endpoint',
            queryParameters: {
              'api_key': apiKey,
              'query': query,
              'language': 'zh-CN',
            });

        var results = response.data?['results'] as List?;
        if (results == null || results.isEmpty) {
          final enResponse = await _dio.get<Map<String, dynamic>>(
              '$baseUrl/search/$endpoint',
              queryParameters: {
                'api_key': apiKey,
                'query': query,
                'language': 'en-US',
              });
          results = enResponse.data?['results'] as List?;
        }

        if (results != null && results.isNotEmpty) {
          final posterPath = results.first['poster_path'];
          if (posterPath is String && posterPath.isNotEmpty) {
            return '${TmdbEndpointPolicy.imageBaseUrl}$posterPath';
          }
        }
      }
    } catch (e) {
      AppLogger().w('PosterService: TMDB search failed for "$query": $e');
      _workingBaseUrl = null;
    }
    return null;
  }

  Future<String?> downloadPoster(String posterUrl, String videoPath) async {
    try {
      final dir = p.dirname(videoPath);
      final savePath = p.join(
        dir,
        '${LocalCoverFinder.seriesCoverBaseNameForVideo(videoPath)}.jpg',
      );

      if (File(savePath).existsSync()) {
        AppLogger().i('PosterService: poster already exists: $savePath');
        return savePath;
      }

      final bytes = await _downloadBytes(posterUrl);
      if (bytes.isEmpty) {
        throw const FormatException('海报响应为空');
      }

      final file = File(savePath);
      await file.writeAsBytes(bytes);
      AppLogger().i('PosterService: downloaded poster to $savePath');
      return savePath;
    } catch (e) {
      AppLogger().w('PosterService: download failed for $posterUrl: $e');
      return null;
    }
  }

  /// Download a poster to a specific file path.
  Future<String?> downloadPosterTo(
    String posterUrl,
    String savePath, {
    bool overwrite = false,
  }) async {
    final temporary = File('$savePath.download');
    try {
      if (!overwrite && File(savePath).existsSync()) {
        AppLogger().i('PosterService: poster already exists: $savePath');
        return savePath;
      }

      await File(savePath).parent.create(recursive: true);

      final bytes = await _downloadBytes(posterUrl);
      if (bytes.isEmpty) {
        throw const FormatException('海报响应为空');
      }

      final target = File(savePath);
      await temporary.writeAsBytes(
        bytes,
        flush: true,
      );
      if (await target.exists()) await target.delete();
      await temporary.rename(savePath);
      AppLogger().i('PosterService: downloaded to $savePath');
      return savePath;
    } catch (e) {
      try {
        if (await temporary.exists()) {
          await temporary.delete();
        }
      } catch (cleanupError) {
        AppLogger().w(
          'PosterService: failed to clean temporary poster: $cleanupError',
        );
      }
      AppLogger().w('PosterService: download failed for $posterUrl: $e');
      return null;
    }
  }

  Future<String?> _ensureBaseUrl(String apiKey) async {
    if (_workingBaseUrl != null) return _workingBaseUrl;

    for (final baseUrl in TmdbEndpointPolicy.apiBaseUrls) {
      try {
        await _dio.get<Object?>(
          '$baseUrl/configuration',
          queryParameters: <String, String>{'api_key': apiKey},
        );
        _workingBaseUrl = baseUrl;
        return baseUrl;
      } on DioException catch (error) {
        if (!TmdbEndpointPolicy.canTryAnotherEndpoint(error)) return null;
      }
    }

    if (await _recoverAndRebuildNetwork()) {
      for (final baseUrl in TmdbEndpointPolicy.apiBaseUrls) {
        try {
          await _dio.get<Object?>(
            '$baseUrl/configuration',
            queryParameters: <String, String>{'api_key': apiKey},
          );
          _workingBaseUrl = baseUrl;
          AppLogger()
              .i('PosterService: TMDB 代理恢复后已连接 ${Uri.parse(baseUrl).host}');
          return baseUrl;
        } on DioException catch (error) {
          if (!TmdbEndpointPolicy.canTryAnotherEndpoint(error)) return null;
        }
      }
    }

    return null;
  }

  Future<List<int>> _downloadBytes(String posterUrl) =>
      _imageClient.downloadBytes(posterUrl);

  Future<bool> _recoverAndRebuildNetwork() {
    final existing = _recoveringNetwork;
    if (existing != null) return existing;
    final task = _recoverAndRebuildNetworkOnce();
    _recoveringNetwork = task;
    return task.whenComplete(() {
      if (identical(_recoveringNetwork, task)) _recoveringNetwork = null;
    });
  }

  Future<bool> _recoverAndRebuildNetworkOnce() async {
    final recoverProxy = _recoverProxy;
    if (recoverProxy == null || !await recoverProxy()) return false;

    final apiFactory = _apiDioFactory;
    if (apiFactory != null) {
      final previous = _dio;
      final replacement = apiFactory();
      _dio = replacement;
      if (!identical(previous, replacement)) previous.close(force: true);
    }
    _workingBaseUrl = null;
    return true;
  }

  static Dio _createDefaultDio({
    required Duration connectTimeout,
    required Duration receiveTimeout,
  }) {
    try {
      final config = NetworkSettingsConfigFactory.create(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
      );
      return DioFactory.createForConfig(config);
    } on Object {
      // 单元测试或早期初始化阶段没有设置盒时仍使用默认网络配置。
      return DioFactory.createForConfig(
        NetworkConfig(
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
        ),
      );
    }
  }
}
