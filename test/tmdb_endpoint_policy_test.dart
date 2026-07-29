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
}
