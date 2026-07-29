import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HTTP 图片和字幕响应读取完成后才关闭客户端', () {
    for (final path in <String>[
      'lib/app/bindings/cloud_bindings.dart',
      'lib/pages/local/local_controller.dart',
      'lib/services/cloud/cloud_playback_resolver.dart',
    ]) {
      final source = File(path).readAsStringSync();

      expect(
        source,
        contains('await response.fold<List<int>>'),
        reason: '$path 必须等待响应流读取完成',
      );
    }
  });
}
