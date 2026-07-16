import 'dart:io';

import 'package:dio/dio.dart';
import 'package:kanyingyin/services/local_cover_finder.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:kanyingyin/modules/local/local_episode_info.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:path/path.dart' as p;

class PosterService {
  static const _baseUrl = 'https://api.themoviedb.org/3';
  static const _imageBaseUrl = 'https://image.tmdb.org/t/p/w780';

  static const _proxies = [
    'https://tmdb.lsmcloud.cc/3',
    'https://api.tmdb.org/3',
  ];

  final Dio _dio;
  final String Function() _apiKeyProvider;
  String? _workingProxy;

  PosterService({String Function()? apiKeyProvider})
      : _apiKeyProvider = apiKeyProvider ?? _readApiKey,
        _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 10),
          ),
        );

  static String _readApiKey() {
    try {
      return GStorage.setting
          .get('tmdbApiKey', defaultValue: '')
          .toString()
          .trim();
    } catch (_) {
      return '';
    }
  }

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
    final apiKey = _apiKeyProvider().trim();
    if (apiKey.isEmpty) return null;

    final baseUrl = await _ensureBaseUrl(apiKey);
    if (baseUrl == null) {
      AppLogger().w('PosterService: all TMDB endpoints unreachable');
      return null;
    }

    try {
      for (final endpoint in ['movie', 'tv']) {
        final response =
            await _dio.get('$baseUrl/search/$endpoint', queryParameters: {
          'api_key': apiKey,
          'query': query,
          'language': 'zh-CN',
        });

        var results = response.data['results'] as List?;
        if (results == null || results.isEmpty) {
          final enResponse =
              await _dio.get('$baseUrl/search/$endpoint', queryParameters: {
            'api_key': apiKey,
            'query': query,
            'language': 'en-US',
          });
          results = enResponse.data['results'] as List?;
        }

        if (results != null && results.isNotEmpty) {
          final posterPath = results.first['poster_path'];
          if (posterPath is String && posterPath.isNotEmpty) {
            return '$_imageBaseUrl$posterPath';
          }
        }
      }
    } catch (e) {
      AppLogger().w('PosterService: TMDB search failed for "$query": $e');
      _workingProxy = null;
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

      final response = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
        ),
      ).get(
        posterUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      final file = File(savePath);
      await file.writeAsBytes(response.data);
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
    try {
      if (!overwrite && File(savePath).existsSync()) {
        AppLogger().i('PosterService: poster already exists: $savePath');
        return savePath;
      }

      await File(savePath).parent.create(recursive: true);

      final response = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
        ),
      ).get(
        posterUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      final target = File(savePath);
      final temporary = File('$savePath.download');
      await temporary.writeAsBytes(response.data, flush: true);
      if (await target.exists()) await target.delete();
      await temporary.rename(savePath);
      AppLogger().i('PosterService: downloaded to $savePath');
      return savePath;
    } catch (e) {
      AppLogger().w('PosterService: download failed for $posterUrl: $e');
      return null;
    }
  }

  Future<String?> _ensureBaseUrl(String apiKey) async {
    if (_workingProxy != null) return _workingProxy;

    try {
      await _dio.get(
        '$_baseUrl/configuration',
        queryParameters: {'api_key': apiKey},
      );
      _workingProxy = _baseUrl;
      return _baseUrl;
    } catch (_) {}

    for (final proxy in _proxies) {
      try {
        await _dio.get(
          '$proxy/configuration',
          queryParameters: {'api_key': apiKey},
        );
        _workingProxy = proxy;
        return proxy;
      } catch (_) {}
    }

    return null;
  }
}
