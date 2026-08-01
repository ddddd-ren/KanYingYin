import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android Release 只使用本机环境签名并启用压缩', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    for (final variable in const <String>[
      'KANYINGYIN_ANDROID_KEYSTORE',
      'KANYINGYIN_ANDROID_STORE_PASSWORD',
      'KANYINGYIN_ANDROID_KEY_ALIAS',
      'KANYINGYIN_ANDROID_KEY_PASSWORD',
    ]) {
      expect(gradle, contains('environmentVariable("$variable")'));
    }
    expect(gradle, contains('isMinifyEnabled = true'));
    expect(gradle, contains('isShrinkResources = true'));
    expect(gradle, contains('proguard-rules.pro'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(gradle, contains('val androidVersionName = "2.1.95"'));
    expect(gradle, contains('val androidVersionCode = 20195'));
  });

  test('Android Release 忽略未启用的 Play Core 延迟组件引用', () {
    final rules = File(
      'android/app/proguard-rules.pro',
    ).readAsStringSync();

    expect(rules, contains('-dontwarn com.google.android.play.core.**'));
  });

  test('Android 发布脚本构建、验证并复制 APK 和 AAB', () {
    final script = File(
      'tool/android/build_signed_release.ps1',
    ).readAsStringSync();

    expect(script, contains(r"$flutter = 'D:\flutter\bin\flutter.bat'"));
    expect(script, contains(r'& $flutter build apk --release --no-pub'));
    expect(
      script,
      contains(r'& $flutter build appbundle --release --no-pub'),
    );
    expect(script, contains('apksigner.bat'));
    expect(script, contains('jarsigner.exe'));
    expect(script, contains('-verify -strict -keystore \$keystore'));
    expect(
      script,
      contains('-storepass:env KANYINGYIN_ANDROID_STORE_PASSWORD'),
    );
    expect(script, contains(r'$appName-$androidVersion.apk'));
    expect(script, contains(r'$appName-$androidVersion.aab'));
    expect(script, contains(r"$androidVersion = '2.1.95'"));
    expect(script, contains(r'$androidVersionCode = 20195'));
    expect(script, contains('[char]0x770B'));
    expect(script, contains('com.kanyingyin.player'));
  });

  test('仓库忽略发布密钥且不包含实际密钥文件', () {
    final ignore = File('.gitignore').readAsStringSync();
    expect(ignore, contains('/android/key.properties'));
    expect(ignore, contains('*.jks'));
    expect(ignore, contains('*.keystore'));
    expect(ignore, contains('/tool/android/private-output/'));

    final keys = Directory.current
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) =>
            file.path.endsWith('.jks') || file.path.endsWith('.keystore'));
    expect(keys, isEmpty);
  });
}
