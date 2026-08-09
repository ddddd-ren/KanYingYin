import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TMDB 图片使用统一客户端且字幕响应读取完成后才关闭原生客户端', () {
    for (final path in <String>[
      'lib/app/bindings/cloud_bindings.dart',
      'lib/pages/local/local_controller.dart',
    ]) {
      final source = File(path).readAsStringSync();

      expect(source, contains('TmdbImageClient.shared.downloadBytes'));
      expect(source, isNot(contains('HttpClient()')));
    }

    final playbackResolver = File(
      'lib/services/cloud/cloud_playback_resolver.dart',
    ).readAsStringSync();
    final responseRead = playbackResolver.indexOf(
      'await response.fold<List<int>>',
    );
    final clientClose =
        playbackResolver.indexOf('httpClient.close(force: true)');
    expect(responseRead, isNonNegative);
    expect(clientClose, greaterThan(responseRead));
  });
}
