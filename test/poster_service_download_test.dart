import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/poster_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('poster-download');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  for (final responseData in <List<int>?>[null, <int>[]]) {
    final label = responseData == null ? 'null' : 'empty';

    test('downloadPoster 收到 $label bytes 时失败且不创建封面', () async {
      final service = PosterService(downloadDio: _dioWithData(responseData));
      final video =
          File('${directory.path}${Platform.pathSeparator}S01E01.mkv');
      await video.writeAsBytes(<int>[1]);

      final result = await service.downloadPoster(
        'https://example.com/poster.jpg',
        video.path,
      );

      expect(result, isNull);
      expect(
        directory.listSync().whereType<File>().where(
              (file) => file.path.toLowerCase().endsWith('.jpg'),
            ),
        isEmpty,
      );
    });

    test('downloadPosterTo 收到 $label bytes 时保留旧文件并清理临时文件', () async {
      final service = PosterService(downloadDio: _dioWithData(responseData));
      final target = File(
        '${directory.path}${Platform.pathSeparator}poster.jpg',
      );
      await target.writeAsBytes(<int>[1, 2, 3]);

      final result = await service.downloadPosterTo(
        'https://example.com/poster.jpg',
        target.path,
        overwrite: true,
      );

      expect(result, isNull);
      expect(await target.readAsBytes(), <int>[1, 2, 3]);
      expect(File('${target.path}.download').existsSync(), isFalse);
    });
  }
}

Dio _dioWithData(List<int>? responseData) {
  return Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<List<int>>(
              requestOptions: options,
              data: responseData,
            ),
          );
        },
      ),
    );
}
