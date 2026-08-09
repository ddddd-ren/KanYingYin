import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/tmdb/tmdb_image_client.dart';

void main() {
  test('未知类型的 TLS 握手失败后恢复代理并重试一次', () async {
    var failedRequests = 0;
    final failedDio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            failedRequests++;
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.unknown,
                error: const HandshakeException(
                  'Connection terminated during handshake',
                ),
              ),
            );
          },
        ),
      );
    var recoveredRequests = 0;
    final recoveredDio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            recoveredRequests++;
            handler.resolve(
              Response<List<int>>(
                requestOptions: options,
                data: <int>[1, 2, 3],
              ),
            );
          },
        ),
      );
    var recoveryCalls = 0;
    var factoryCalls = 0;
    final client = TmdbImageClient(
      dio: failedDio,
      dioFactory: () {
        factoryCalls++;
        return recoveredDio;
      },
      recoverProxy: () async {
        recoveryCalls++;
        return true;
      },
    );

    final bytes = await client.downloadBytes(
      'https://image.tmdb.org/t/p/w342/poster.jpg',
    );

    expect(bytes, <int>[1, 2, 3]);
    expect(failedRequests, 1);
    expect(recoveredRequests, 1);
    expect(recoveryCalls, 1);
    expect(factoryCalls, 1);
  });

  test('代理无法恢复时只尝试一次 TMDB 官方 HTTP 图片回退', () async {
    var requests = 0;
    final failedDio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: const SocketException('connection reset'),
              ),
            );
          },
        ),
      );
    var recoveryCalls = 0;
    final client = TmdbImageClient(
      dio: failedDio,
      recoverProxy: () async {
        recoveryCalls++;
        return false;
      },
    );

    await expectLater(
      client.downloadBytes(
        'https://image.tmdb.org/t/p/w342/poster.jpg',
      ),
      throwsA(isA<DioException>()),
    );
    expect(requests, 2);
    expect(recoveryCalls, 1);
  });

  test('HTTPS 握手失败且代理不可恢复时使用 TMDB 官方 HTTP 图片地址', () async {
    final requestedUris = <Uri>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestedUris.add(options.uri);
            if (options.uri.scheme == 'https') {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.unknown,
                  error: const HandshakeException(
                    'Connection terminated during handshake',
                  ),
                ),
              );
              return;
            }
            handler.resolve(
              Response<List<int>>(
                requestOptions: options,
                data: <int>[4, 5, 6],
              ),
            );
          },
        ),
      );
    var recoveryCalls = 0;
    final client = TmdbImageClient(
      dio: dio,
      recoverProxy: () async {
        recoveryCalls++;
        return false;
      },
    );

    expect(
      await client.downloadBytes(
        'https://image.tmdb.org/t/p/w342/first.jpg',
      ),
      <int>[4, 5, 6],
    );
    expect(
      await client.downloadBytes(
        'https://image.tmdb.org/t/p/w342/second.jpg',
      ),
      <int>[4, 5, 6],
    );
    expect(
      requestedUris.map((uri) => uri.toString()),
      <String>[
        'https://image.tmdb.org/t/p/w342/first.jpg',
        'http://image.tmdb.org/t/p/w342/first.jpg',
        'http://image.tmdb.org/t/p/w342/second.jpg',
      ],
    );
    expect(recoveryCalls, 1);
  });

  test('非 TMDB 图片地址发生握手错误时禁止降级到 HTTP', () async {
    final requestedUris = <Uri>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestedUris.add(options.uri);
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.unknown,
                error: const HandshakeException(
                  'Connection terminated during handshake',
                ),
              ),
            );
          },
        ),
      );
    final client = TmdbImageClient(
      dio: dio,
      recoverProxy: () async => false,
    );

    await expectLater(
      client.downloadBytes('https://example.com/poster.jpg'),
      throwsA(isA<DioException>()),
    );
    expect(
      requestedUris.map((uri) => uri.toString()),
      <String>['https://example.com/poster.jpg'],
    );
  });

  test('连续下载都失败时代理恢复探测进入冷却', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: const SocketException('connection reset'),
            ),
          ),
        ),
      );
    var recoveryCalls = 0;
    final client = TmdbImageClient(
      dio: dio,
      recoverProxy: () async {
        recoveryCalls++;
        return false;
      },
    );

    for (var index = 0; index < 2; index++) {
      await expectLater(
        client.downloadBytes(
          'https://image.tmdb.org/t/p/w342/poster-$index.jpg',
        ),
        throwsA(isA<DioException>()),
      );
    }
    expect(recoveryCalls, 1);
  });
}
