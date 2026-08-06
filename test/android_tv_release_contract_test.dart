import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 版本与根工程一致且包含 tvTest flavor', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(pubspec, contains('version: 2.1.138+20138'));
    expect(gradle, contains('versionName = androidVersionName'));
    expect(gradle, contains('versionCode = androidVersionCode'));
    expect(gradle, contains('create("tvTest")'));
  });
}
