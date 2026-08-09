import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/poster_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_image_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('图片连接失败后恢复代理并使用重建的客户端重试一次', () async {
    final directory = await Directory.systemTemp.createTemp(
      'poster-network-recovery-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final failedDio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              message: '模拟 TLS 握手失败',
            ),
          ),
        ),
      );
    final recoveredDio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<List<int>>(
              requestOptions: options,
              data: <int>[1, 2, 3],
            ),
          ),
        ),
      );
    var recoveryCalls = 0;
    var factoryCalls = 0;
    final service = PosterService(
      apiDio: Dio(),
      downloadDio: failedDio,
      downloadDioFactory: () {
        factoryCalls += 1;
        return recoveredDio;
      },
      recoverProxy: () async {
        recoveryCalls += 1;
        return true;
      },
    );
    final target = File(
      '${directory.path}${Platform.pathSeparator}poster.jpg',
    );

    final result = await service.downloadPosterTo(
      'https://image.tmdb.org/t/p/w780/poster.jpg',
      target.path,
    );

    expect(result, target.path);
    expect(await target.readAsBytes(), <int>[1, 2, 3]);
    expect(recoveryCalls, 1);
    expect(factoryCalls, 1);
  });

  test('海报保存委托注入的统一 TMDB 图片客户端', () async {
    final directory = await Directory.systemTemp.createTemp(
      'poster-unified-image-client-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final imageDio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<List<int>>(
              requestOptions: options,
              data: <int>[7, 8, 9],
            ),
          ),
        ),
      );
    final service = PosterService(
      apiDio: Dio(),
      imageClient: TmdbImageClient(dio: imageDio),
    );
    final target = File(
      '${directory.path}${Platform.pathSeparator}poster.jpg',
    );

    final result = await service.downloadPosterTo(
      'https://image.tmdb.org/t/p/w780/poster.jpg',
      target.path,
    );

    expect(result, target.path);
    expect(await target.readAsBytes(), <int>[7, 8, 9]);
  });
}
