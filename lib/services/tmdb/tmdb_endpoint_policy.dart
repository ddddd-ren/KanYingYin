import 'dart:io';

import 'package:dio/dio.dart';

/// 统一定义 TMDB 官方 API 端点及允许故障转移的错误类型。
class TmdbEndpointPolicy {
  const TmdbEndpointPolicy._();

  static const String primaryApiBaseUrl = 'https://api.themoviedb.org/3';
  static const String fallbackApiBaseUrl = 'https://api.tmdb.org/3';
  static const String imageBaseUrl = 'https://image.tmdb.org/t/p/w780';
  static const List<String> apiBaseUrls = <String>[
    primaryApiBaseUrl,
    fallbackApiBaseUrl,
  ];

  static final List<Uri> configurationUris = List<Uri>.unmodifiable(
    apiBaseUrls.map((baseUrl) => Uri.parse('$baseUrl/configuration')),
  );
  static final Map<String, List<Uri>> requiredResourceProbeGroups =
      Map<String, List<Uri>>.unmodifiable(<String, List<Uri>>{
    'TMDB API': configurationUris,
    'TMDB 图片': <Uri>[
      Uri.parse('https://image.tmdb.org'),
      Uri.parse('http://image.tmdb.org'),
    ],
  });

  static bool canTryAnotherEndpoint(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return true;
    }
    final cause = error.error;
    if (cause is HandshakeException || cause is SocketException) {
      return true;
    }
    final statusCode = error.response?.statusCode;
    return error.type == DioExceptionType.badResponse &&
        statusCode != null &&
        statusCode >= 500 &&
        statusCode < 600;
  }
}
