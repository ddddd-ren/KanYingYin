import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';

void main() {
  test('v3 API Key 使用 api_key 查询参数', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;

    await TmdbClient(apiKey: '1234567890abcdef1234567890abcdef', dio: dio)
        .search('Avatar', TmdbMediaType.movie);

    expect(adapter.lastRequest?.queryParameters['api_key'],
        '1234567890abcdef1234567890abcdef');
    expect(adapter.lastRequest?.headers['Authorization'], isNull);
  });

  test('v4 读取令牌使用 Bearer 请求头', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    const token = 'eyJhbGciOiJIUzI1NiJ9.long.tmdb.read.access.token';

    await TmdbClient(apiKey: token, dio: dio)
        .search('Avatar', TmdbMediaType.movie);

    expect(adapter.lastRequest?.queryParameters['api_key'], isNull);
    expect(adapter.lastRequest?.headers['Authorization'], 'Bearer $token');
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      '{"results":[]}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
