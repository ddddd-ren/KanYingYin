import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android mobile 二点一六零测试版并仅保留 tvTest 源码 flavor', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final agents = File('AGENTS.md').readAsStringSync();

    expect(pubspec, contains('version: 2.1.160+20160'));
    expect(gradle, contains('val androidVersionName = "2.1.160"'));
    expect(gradle, contains('val androidVersionCode = 20160'));
    expect(gradle, contains('versionName = androidVersionName'));
    expect(gradle, contains('versionCode = androidVersionCode'));
    expect(gradle, contains('create("tvTest")'));
    expect(agents, contains('Android TV 版发布无限期暂停'));
    expect(agents, contains('不得运行 `tvTest` 发布流程'));
  });
}
