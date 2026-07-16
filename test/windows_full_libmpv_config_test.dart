import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 构建保留 media_kit 自带的零拷贝兼容 libmpv', () {
    final root = File('windows/CMakeLists.txt').readAsStringSync();

    expect(File('windows/cmake/full_libmpv.cmake').existsSync(), isFalse);
    expect(root, isNot(contains('FULL_LIBMPV')));
    expect(root, isNot(contains('libmpv-2\\.dll')));
    expect(root, contains('install(FILES "\${PLUGIN_BUNDLED_LIBRARIES}"'));
  });
}
