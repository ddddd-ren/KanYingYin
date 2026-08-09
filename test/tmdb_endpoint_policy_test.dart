import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/tmdb/tmdb_endpoint_policy.dart';

void main() {
  test('只暴露 TMDB 官方 API 主端点和备用端点', () {
    expect(TmdbEndpointPolicy.apiBaseUrls, <String>[
      'https://api.themoviedb.org/3',
      'https://api.tmdb.org/3',
    ]);
    expect(
      TmdbEndpointPolicy.configurationUris.map((uri) => uri.host),
      <String>['api.themoviedb.org', 'api.tmdb.org'],
    );
  });

  test('连接错误和 5xx 可以切换而 401 不切换', () {
    final options = RequestOptions(path: '/configuration');
    expect(
      TmdbEndpointPolicy.canTryAnotherEndpoint(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      ),
      isTrue,
    );
    expect(
      TmdbEndpointPolicy.canTryAnotherEndpoint(
        DioException.badResponse(
          statusCode: 503,
          requestOptions: options,
          response: Response<void>(requestOptions: options, statusCode: 503),
        ),
      ),
      isTrue,
    );
    expect(
      TmdbEndpointPolicy.canTryAnotherEndpoint(
        DioException.badResponse(
          statusCode: 401,
          requestOptions: options,
          response: Response<void>(requestOptions: options, statusCode: 401),
        ),
      ),
      isFalse,
    );
  });

  test('未知类型中的 TLS 握手异常仍可恢复', () {
    final options = RequestOptions(path: '/poster.jpg');

    expect(
      TmdbEndpointPolicy.canTryAnotherEndpoint(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: const HandshakeException(
            'Connection terminated during handshake',
          ),
        ),
      ),
      isTrue,
    );
  });

  test('代理探测同时要求 TMDB API 和图片域名可用', () {
    expect(
      TmdbEndpointPolicy.requiredResourceProbeGroups.keys,
      <String>['TMDB API', 'TMDB 图片'],
    );
    expect(
      TmdbEndpointPolicy.requiredResourceProbeGroups['TMDB API']!
          .map((uri) => uri.host),
      <String>['api.themoviedb.org', 'api.tmdb.org'],
    );
    expect(
      TmdbEndpointPolicy.requiredResourceProbeGroups['TMDB 图片']!
          .map((uri) => uri.scheme),
      <String>['https', 'http'],
    );
    expect(
      TmdbEndpointPolicy.requiredResourceProbeGroups['TMDB 图片']!
          .map((uri) => uri.host),
      <String>['image.tmdb.org', 'image.tmdb.org'],
    );
  });
}
