import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';

void main() {
  test('分页搜索保留页码、总页数和候选热度字段', () async {
    final adapter = _CapabilitiesAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = TmdbClient(apiKey: 'key', dio: dio);

    final page = await client.searchPage(
      'Avatar',
      TmdbMediaType.movie,
      page: 2,
    );

    expect(page.page, 2);
    expect(page.totalPages, 3);
    expect(page.results.single.title, 'Avatar');
    expect(page.results.single.popularity, 12.5);
    expect(page.results.single.voteCount, 321);
    expect(adapter.requests.single.queryParameters['page'], 2);
  });

  test('替代标题兼容电视剧响应结构并去重', () async {
    final adapter = _CapabilitiesAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = TmdbClient(apiKey: 'key', dio: dio);

    final aliases = await client.alternativeTitles(42, TmdbMediaType.tv);

    expect(aliases, <String>['The Three-Body Problem', '三体']);
  });

  test('季度详情合并中文集名和英文补充字段', () async {
    final adapter = _CapabilitiesAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = TmdbClient(apiKey: 'key', dio: dio);

    final season = await client.seasonDetails(42, 1);

    expect(season.seasonNumber, 1);
    expect(season.episodes.single.name, '第一个故事');
    expect(season.episodes.single.episodeNumber, 1);
    expect(season.episodes.single.overview, 'English episode overview');
    expect(season.episodes.single.stillUrl, '/episode-1-en.jpg');
  });

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

  test('主端点连接失败后使用官方备用端点并在运行期保持', () async {
    final adapter = _HostAdapter((options) {
      if (options.uri.host == 'api.themoviedb.org') {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      return ResponseBody.fromString(
        '{"results":[{"id":1,"title":"Avatar"}]}',
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      );
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final client = TmdbClient(
      apiKey: 'key',
      dio: dio,
      recoverProxy: () async => false,
      dioFactory: () => dio,
    );

    await client.search('Avatar', TmdbMediaType.movie);
    await client.search('Avatar 2', TmdbMediaType.movie);

    expect(adapter.hosts, <String>[
      'api.themoviedb.org',
      'api.tmdb.org',
      'api.tmdb.org',
    ]);
  });

  test('主端点 401 时不向备用端点重复发送 API Key', () async {
    final adapter = _HostAdapter(
      (_) => ResponseBody.fromString(
        '{"status_code":7}',
        401,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      ),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final client = TmdbClient(apiKey: 'bad-key', dio: dio);

    await expectLater(
      client.search('Avatar', TmdbMediaType.movie),
      throwsA(isA<DioException>()),
    );
    expect(adapter.hosts, <String>['api.themoviedb.org']);
  });

  test('电视剧详情合并中英文类型、季度和季度海报', () async {
    final adapter = _SeasonDetailsAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = TmdbClient(apiKey: 'key', dio: dio);

    final metadata = await client.details(42, TmdbMediaType.tv);

    expect(metadata.seasons.map((item) => item.seasonNumber), <int>[1, 2, 3]);
    expect(metadata.seasons.first.name, '第 1 季');
    expect(metadata.seasons.first.episodeCount, 8);
    expect(metadata.seasons.first.posterUrl, '/season-1-zh.jpg');
    expect(metadata.seasons[1].posterUrl, '/season-2-en.jpg');
    expect(metadata.seasons.last.posterUrl, '/season-3-en.jpg');
    expect(metadata.genres, const <String>['动画', '科幻', 'Drama']);
    expect(
        metadata.seasons.map((item) => item.seasonNumber), isNot(contains(0)));
  });

  test('首次连接失败后恢复代理并使用新 Dio 重试一次', () async {
    final firstAdapter = _QueueAdapter([
      DioException(
        requestOptions: RequestOptions(path: '/primary'),
        type: DioExceptionType.connectionError,
      ),
      DioException(
        requestOptions: RequestOptions(path: '/fallback'),
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
    expect(firstAdapter.requestCount, 2);
    expect(secondAdapter.requestCount, 1);
  });

  test('代理恢复失败时返回备用端点异常且不重建 Dio', () async {
    final primaryError = DioException(
      requestOptions: RequestOptions(path: '/primary'),
      type: DioExceptionType.connectionTimeout,
    );
    final fallbackError = DioException(
      requestOptions: RequestOptions(path: '/fallback'),
      type: DioExceptionType.connectionTimeout,
    );
    final adapter = _QueueAdapter([primaryError, fallbackError]);
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
      throwsA(same(fallbackError)),
    );
    expect(recoveries, 1);
    expect(rebuilds, 0);
    expect(adapter.requestCount, 2);
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

  test('代理重建后的请求失败时不进行第四次请求', () async {
    DioException failure(String path) => DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.connectionError,
        );
    final firstAdapter = _QueueAdapter([
      failure('/primary'),
      failure('/fallback'),
    ]);
    final secondError = failure('/rebuilt-primary');
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
    expect(firstAdapter.requestCount, 2);
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
      failure('/request-1-primary'),
      failure('/request-2-primary'),
      failure('/request-1-fallback'),
      failure('/request-2-fallback'),
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
        attempt < 20 && firstAdapter.requestCount < 4;
        attempt += 1) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(firstAdapter.requestCount, 4);
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
    expect(firstAdapter.requestCount, 4);
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

typedef _HostResponder = ResponseBody Function(RequestOptions options);

class _HostAdapter implements HttpClientAdapter {
  _HostAdapter(this.responder);

  final _HostResponder responder;
  final List<String> hosts = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    hosts.add(options.uri.host);
    return responder(options);
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
            "genres": [
              {"id": 18, "name": "Drama"}
            ],
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
              },
              {
                "id": 300,
                "season_number": 3,
                "name": "Season 3",
                "episode_count": 6,
                "poster_path": "/season-3-en.jpg"
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
            "genres": [
              {"id": 16, "name": "动画"},
              {"id": 878, "name": "科幻"},
              {"id": 999, "name": "动画"}
            ],
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

class _CapabilitiesAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.uri.path;
    String body;
    if (path.endsWith('/search/movie')) {
      body = '''
        {
          "page": 2,
          "total_pages": 3,
          "results": [
            {
              "id": 1,
              "title": "Avatar",
              "popularity": 12.5,
              "vote_count": 321
            }
          ]
        }
      ''';
    } else if (path.endsWith('/tv/42/alternative_titles')) {
      body = '''
        {
          "results": [
            {"title": "The Three-Body Problem"},
            {"title": "三体"},
            {"title": "The Three-Body Problem"},
            {"title": ""}
          ]
        }
      ''';
    } else if (path.endsWith('/tv/42/season/1')) {
      final language = options.queryParameters['language'];
      body = language == 'en-US'
          ? '''
            {
              "id": 100,
              "season_number": 1,
              "name": "Season 1",
              "episode_count": 1,
              "overview": "English season overview",
              "episodes": [
                {
                  "id": 101,
                  "episode_number": 1,
                  "name": "The First Story",
                  "overview": "English episode overview",
                  "air_date": "2023-01-15",
                  "still_path": "/episode-1-en.jpg",
                  "vote_average": 8.5
                }
              ]
            }
          '''
          : '''
            {
              "id": 100,
              "season_number": 1,
              "name": "第 1 季",
              "episode_count": 1,
              "episodes": [
                {
                  "id": 101,
                  "episode_number": 1,
                  "name": "第一个故事",
                  "overview": "",
                  "air_date": "2023-01-15"
                }
              ]
            }
          ''';
    } else {
      throw StateError('未处理的 TMDB 测试请求：$path');
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
