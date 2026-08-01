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

  test('Windows 在加载插件前为 CMP0175 设置兼容策略', () {
    final source = File('windows/CMakeLists.txt').readAsStringSync();
    const policySetting = 'set(CMAKE_POLICY_DEFAULT_CMP0175 OLD)';
    const generatedPluginsInclude = 'include(flutter/generated_plugins.cmake)';

    final policySettingIndex = source.indexOf(policySetting);
    final generatedPluginsIncludeIndex = source.indexOf(
      generatedPluginsInclude,
    );

    expect(policySettingIndex, isNonNegative);
    expect(generatedPluginsIncludeIndex, isNonNegative);
    expect(policySettingIndex, lessThan(generatedPluginsIncludeIndex));
  });

  test('flutter_inappwebview_windows 仅对插件目标屏蔽参数遮蔽警告', () {
    final topLevelCmake = File(
      'windows/CMakeLists.txt',
    ).readAsStringSync();
    final lifetimePatch = File(
      'windows/cmake/flutter_inappwebview_windows_lifetime_patch.cmake',
    ).readAsStringSync();
    final combinedSource = '$topLevelCmake\n$lifetimePatch';
    final targetScopedOption = RegExp(
      r'target_compile_options\s*\(\s*flutter_inappwebview_windows_plugin\s+'
      r'PRIVATE\s+/wd4458\s*\)',
      multiLine: true,
    );

    expect(lifetimePatch, matches(targetScopedOption));
    expect(RegExp(r'/wd4458').allMatches(combinedSource), hasLength(1));
    expect(combinedSource, isNot(contains('add_compile_options(/wd4458)')));
  });
}
