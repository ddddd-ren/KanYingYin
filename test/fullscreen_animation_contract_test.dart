import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 全屏过渡使用非阻塞原生定时器和缓动', () {
    final source = File('windows/runner/fullscreen_utils.cpp').readAsStringSync();

    expect(source, contains('SetTimer(window, kTransitionTimerId, 16'));
    expect(source, contains('std::pow(-2.0 * linear + 2.0'));
    expect(source, contains('SWP_NOACTIVATE | SWP_NOOWNERZORDER'));
    expect(source, isNot(contains('Sleep(')));
  });
}
