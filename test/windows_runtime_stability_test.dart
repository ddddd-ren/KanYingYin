import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner 使用 Flutter 默认 UI 线程策略', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();

    expect(source, isNot(contains('set_ui_thread_policy')));
    expect(source, isNot(contains('UIThreadPolicy::RunOnSeparateThread')));
  });

  test('Windows MSVC 对应用和插件统一使用 UTF-8 源码编码', () {
    final source = File('windows/CMakeLists.txt').readAsStringSync();

    expect(source, contains('if(MSVC)'));
    expect(source, contains('add_compile_options(/utf-8)'));
  });
}
