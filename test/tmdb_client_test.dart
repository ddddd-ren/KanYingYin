import 'dart:async';
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

  test('首次连接失败后恢复代理并使用新 Dio 重试一次', () async {
    final firstAdapter = _QueueAdapter([
      DioException(
        requestOptions: RequestOptions(path: '/search/movie'),
        type: DioExceptionType.connectionError,
      ),
    ]);
    final secondAdapter = _QueueAdapter([
      ResponseBody.fromString(
        '{"results":[{"id":1,"title":"Avatar"}]}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    ]);
    final firstDio = Dio()..httpClientAdapter = firstAdapter;
    final secondDio = Dio()..httpClientAdapter = secondAdapter;
    var recoveries = 0;
    var rebuilds = 0;
    final client = TmdbClient(
      apiKey: 'key',
      dio: firstDio,
      recoverProxy: () async {
        recoveries += 1;
        return true;
      },
      dioFactory: () {
        rebuilds += 1;
        return secondDio;
      },
    );

    final results = await client.search('Avatar', TmdbMediaType.movie);

    expect(results.single.title, 'Avatar');
    expect(recoveries, 1);
    expect(rebuilds, 1);
    expect(firstAdapter.requestCount, 1);
    expect(secondAdapter.requestCount, 1);
  });

  test('代理恢复失败时保留首次网络异常且不重建 Dio', () async {
    final error = DioException(
      requestOptions: RequestOptions(path: '/search/movie'),
      type: DioExceptionType.connectionTimeout,
    );
    final adapter = _QueueAdapter([error]);
    final dio = Dio()..httpClientAdapter = adapter;
    var recoveries = 0;
    var rebuilds = 0;
    final client = TmdbClient(
      apiKey: 'key',
      dio: dio,
      recoverProxy: () async {
        recoveries += 1;
        return false;
      },
      dioFactory: () {
        rebuilds += 1;
        return Dio();
      },
    );

    await expectLater(
      client.search('Avatar', TmdbMediaType.movie),
      throwsA(same(error)),
    );
    expect(recoveries, 1);
    expect(rebuilds, 0);
    expect(adapter.requestCount, 1);
  });

  test('HTTP 响应错误不恢复代理', () async {
    final requestOptions = RequestOptions(path: '/search/movie');
    final error = DioException.badResponse(
      statusCode: 401,
      requestOptions: requestOptions,
      response: Response<void>(
        requestOptions: requestOptions,
        statusCode: 401,
      ),
    );
    final adapter = _QueueAdapter([error]);
    final dio = Dio()..httpClientAdapter = adapter;
    var recoveries = 0;
    final client = TmdbClient(
      apiKey: 'key',
      dio: dio,
      recoverProxy: () async {
        recoveries += 1;
        return true;
      },
      dioFactory: Dio.new,
    );

    await expectLater(
      client.search('Avatar', TmdbMediaType.movie),
      throwsA(same(error)),
    );
    expect(recoveries, 0);
    expect(adapter.requestCount, 1);
  });

  test('重建后的请求失败时不进行第三次请求', () async {
    DioException failure(String path) => DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.connectionError,
        );
    final firstAdapter = _QueueAdapter([failure('/first')]);
    final secondError = failure('/second');
    final secondAdapter = _QueueAdapter([secondError]);
    final firstDio = Dio()..httpClientAdapter = firstAdapter;
    final secondDio = Dio()..httpClientAdapter = secondAdapter;
    var recoveries = 0;
    final client = TmdbClient(
      apiKey: 'key',
      dio: firstDio,
      recoverProxy: () async {
        recoveries += 1;
        return true;
      },
      dioFactory: () => secondDio,
    );

    await expectLater(
      client.search('Avatar', TmdbMediaType.movie),
      throwsA(same(secondError)),
    );
    expect(recoveries, 1);
    expect(firstAdapter.requestCount, 1);
    expect(secondAdapter.requestCount, 1);
  });

  test('并发网络失败共享一次恢复和 Dio 重建', () async {
    DioException failure(String path) => DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.connectionError,
        );
    ResponseBody success(int id) => ResponseBody.fromString(
          '{"results":[{"id":$id,"title":"Avatar"}]}',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
    final firstAdapter = _QueueAdapter([
      failure('/first'),
      failure('/second'),
    ]);
    final secondAdapter = _QueueAdapter([
      success(1),
      success(2),
    ]);
    final firstDio = Dio()..httpClientAdapter = firstAdapter;
    final secondDio = Dio()..httpClientAdapter = secondAdapter;
    final recoveryGate = Completer<bool>();
    var recoveries = 0;
    var rebuilds = 0;
    final client = TmdbClient(
      apiKey: 'key',
      dio: firstDio,
      recoverProxy: () {
        recoveries += 1;
        return recoveryGate.future;
      },
      dioFactory: () {
        rebuilds += 1;
        return secondDio;
      },
    );

    final searches = [
      client.search('Avatar', TmdbMediaType.movie),
      client.search('Avatar 2', TmdbMediaType.movie),
    ];
    for (var attempt = 0;
        attempt < 20 && firstAdapter.requestCount < 2;
        attempt += 1) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(firstAdapter.requestCount, 2);
    for (var attempt = 0; attempt < 5; attempt += 1) {
      await Future<void>.delayed(Duration.zero);
    }
    final recoveriesBeforeRelease = recoveries;
    recoveryGate.complete(true);
    final results = await Future.wait(searches);

    expect(results.expand((items) => items), hasLength(2));
    expect(recoveriesBeforeRelease, 1);
    expect(recoveries, recoveriesBeforeRelease);
    expect(rebuilds, 1);
    expect(firstAdapter.requestCount, 2);
    expect(secondAdapter.requestCount, 2);
  });
}

class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this.outcomes);

  final List<Object> outcomes;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final outcome = outcomes[requestCount++];
    if (outcome is DioException) throw outcome;
    return outcome as ResponseBody;
  }

  @override
  void close({bool force = false}) {}
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
