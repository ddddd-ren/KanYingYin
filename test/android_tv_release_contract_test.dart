import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android mobile 与 pubspec 版本一致并仅保留 tvTest 源码 flavor', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final agents = File('AGENTS.md').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\d+\.\d+\.\d+)\+([1-9]\d*)\s*$',
      multiLine: true,
    ).firstMatch(pubspec)!;

    expect(
      gradle,
      contains('val windowsVersionName = pubspecVersionMatch.groupValues[1]'),
    );
    expect(
      gradle,
      contains(
          'val windowsVersionCode = pubspecVersionMatch.groupValues[2].toInt()'),
    );
    expect(
      gradle,
      contains('val androidVersionName = "${version.group(1)}"'),
    );
    expect(
      gradle,
      contains('val androidVersionCode = ${version.group(2)}'),
    );
    expect(gradle, contains('versionName = androidVersionName'));
    expect(gradle, contains('versionCode = androidVersionCode'));
    expect(gradle, contains('create("tvTest")'));
    expect(agents, contains('Android TV 版发布无限期暂停'));
    expect(agents, contains('不得运行 `tvTest` 发布流程'));
  });

  test('TV 构建脚本保存并验证独立包记录', () {
    final script = File('tool/android/build_tv_test.ps1').readAsStringSync();

    for (final text in <String>[
      'private-output',
      'aapt dump badging',
      'aapt dump xmltree',
      'leanback-launchable-activity',
      'android.hardware.touchscreen',
      'android:banner',
      'apksigner verify --verbose --print-certs',
      'verify_full_media_bundle.ps1',
      'Get-FileHash',
      'SHA256',
    ]) {
      expect(script, contains(text), reason: text);
    }
  });
}
