import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const assets = <String, String>{
    'full-arm64-v8a.jar':
        'cdb54c5cf24725623ca717bbbd6d991031d625a377460bd128f19c2dffe189bd',
    'full-armeabi-v7a.jar':
        'b658f2ff91169f8dad0e09e0240ebe200bb3df999da5712f8fab96ad11a4fbec',
    'full-x86.jar':
        '8b3b84e54ec09bb79972095dc04bcaf651294da4e73b1e7c3251055fd8a2b901',
    'full-x86_64.jar':
        '848936cfd7333077f21759adaca4a9e1a5647891da2e42ab211c5bdc30f4535d',
  };

  test('Android 使用仓库内官方 Full v1.1.11 原生包', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final gradle = File(
      'third_party/media_kit_libs_android_video_full/android/build.gradle',
    ).readAsStringSync();

    expect(
      pubspec,
      contains(
        'media_kit_libs_android_video:\n'
        '    path: third_party/media_kit_libs_android_video_full',
      ),
    );
    expect(
      gradle,
      contains(
        'https://github.com/media-kit/libmpv-android-video-build/'
        'releases/download/v1.1.11/',
      ),
    );
    for (final asset in assets.entries) {
      expect(gradle, contains(asset.key));
      expect(gradle, contains(asset.value));
    }
    expect(gradle, isNot(contains('default-')));
  });

  test('本地适配包保持 media-kit Android 插件接口', () {
    final pubspec = File(
      'third_party/media_kit_libs_android_video_full/pubspec.yaml',
    ).readAsStringSync();
    final manifest = File(
      'third_party/media_kit_libs_android_video_full/'
      'android/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final plugin = File(
      'third_party/media_kit_libs_android_video_full/android/src/main/java/'
      'com/alexmercerind/media_kit_libs_android_video/'
      'MediaKitLibsAndroidVideoPlugin.java',
    ).readAsStringSync();
    final helper = File(
      'third_party/media_kit_libs_android_video_full/android/src/main/java/'
      'com/alexmercerind/mediakitandroidhelper/MediaKitAndroidHelper.java',
    ).readAsStringSync();

    expect(pubspec, contains('name: media_kit_libs_android_video'));
    expect(pubspec, contains('pluginClass: MediaKitLibsAndroidVideoPlugin'));
    expect(manifest, contains('android:extractNativeLibs="true"'));
    expect(plugin, contains('System.loadLibrary("mpv")'));
    expect(helper, contains('openFileDescriptorJava'));
  });
}
