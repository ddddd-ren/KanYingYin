import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 平台工程使用看影音身份和 API 24/36', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(gradle, contains('namespace = "com.kanyingyin.player"'));
    expect(gradle, contains('applicationId = "com.kanyingyin.player"'));
    expect(gradle, contains('create("tvTest")'));
    expect(gradle, contains('applicationId = "com.kanyingyin.player.tvtest"'));
    expect(gradle, contains('compileSdk = 36'));
    expect(gradle, contains('minSdk = 24'));
    expect(gradle, contains('targetSdk = 36'));
    expect(manifest, contains('android:label="看影音"'));
    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
    expect(Directory('android/app/src/tvTest').existsSync(), isTrue);
  });
}
