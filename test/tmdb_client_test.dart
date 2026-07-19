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

  test('电视剧详情解析季度并用英文补齐缺失季度海报', () async {
    final adapter = _SeasonDetailsAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = TmdbClient(apiKey: 'key', dio: dio);

    final metadata = await client.details(42, TmdbMediaType.tv);

    expect(metadata.seasons.map((item) => item.seasonNumber), <int>[1, 2]);
    expect(metadata.seasons.first.name, '第 1 季');
    expect(metadata.seasons.first.episodeCount, 8);
    expect(metadata.seasons.first.posterUrl, '/season-1-zh.jpg');
    expect(metadata.seasons.last.posterUrl, '/season-2-en.jpg');
    expect(
        metadata.seasons.map((item) => item.seasonNumber), isNot(contains(0)));
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

class _SeasonDetailsAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final language = options.queryParameters['language'];
    final body = language == 'en-US'
        ? '''
          {
            "id": 42,
            "name": "The Show",
            "overview": "English overview",
            "poster_path": "/show-en.jpg",
            "backdrop_path": "/show-backdrop-en.jpg",
            "seasons": [
              {
                "id": 100,
                "season_number": 1,
                "name": "Season 1",
                "episode_count": 8,
                "overview": "Season one",
                "air_date": "2020-12-10",
                "poster_path": "/season-1-en.jpg"
              },
              {
                "id": 200,
                "season_number": 2,
                "name": "Season 2",
                "episode_count": 8,
                "overview": "Season two",
                "air_date": "2022-12-22",
                "poster_path": "/season-2-en.jpg"
              }
            ]
          }
        '''
        : '''
          {
            "id": 42,
            "name": "弥留之国的爱丽丝",
            "overview": "中文简介",
            "poster_path": "/show-zh.jpg",
            "backdrop_path": "/show-backdrop-zh.jpg",
            "seasons": [
              {
                "id": 1,
                "season_number": 0,
                "name": "特别篇",
                "episode_count": 1,
                "poster_path": "/special.jpg"
              },
              {
                "id": 100,
                "season_number": 1,
                "name": "第 1 季",
                "episode_count": 8,
                "overview": "第一季简介",
                "air_date": "2020-12-10",
                "poster_path": "/season-1-zh.jpg"
              },
              {
                "id": 200,
                "season_number": 2,
                "name": "第 2 季",
                "episode_count": 8,
                "overview": "第二季简介",
                "air_date": "2022-12-22",
                "poster_path": null
              }
            ]
          }
        ''';
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
