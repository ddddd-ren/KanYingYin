import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';

void main() {
  test('剧集图片接口解析并按 file_path 去重', () async {
    final adapter = _ImageAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = TmdbClient(apiKey: 'key', dio: dio);

    final images = await client.images(42, TmdbMediaType.tv);

    expect(images.posters, hasLength(1));
    expect(images.posters.single.filePath, '/poster.jpg');
    expect(images.backdrops.single.width, 1920);
    expect(adapter.lastRequest?.uri.path, '/3/tv/42/images');
    expect(adapter.lastRequest?.queryParameters['include_image_language'],
        'zh-CN,en-US,null');
  });

  test('季度和单集图片使用对应 TMDB 路径', () async {
    final adapter = _ImageAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = TmdbClient(apiKey: 'key', dio: dio);

    await client.images(42, TmdbMediaType.tv, seasonNumber: 2);
    expect(adapter.lastRequest?.uri.path, '/3/tv/42/season/2/images');
    await client.images(
      42,
      TmdbMediaType.tv,
      seasonNumber: 2,
      episodeNumber: 3,
    );
    expect(
      adapter.lastRequest?.uri.path,
      '/3/tv/42/season/2/episode/3/images',
    );
  });
}

class _ImageAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      '''
      {
        "posters": [
          {"file_path":"/poster.jpg","width":500,"height":750},
          {"file_path":"/poster.jpg","width":500,"height":750}
        ],
        "backdrops": [
          {"file_path":"/backdrop.jpg","width":1920,"height":1080}
        ],
        "stills": []
      }
      ''',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
