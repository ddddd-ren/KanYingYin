import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 清单声明媒体播放与画中画且不申请全盘权限', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final tvManifest =
        File('android/app/src/tvTest/AndroidManifest.xml').readAsStringSync();

    for (final permission in <String>[
      'android.permission.INTERNET',
      'android.permission.WAKE_LOCK',
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
      'android.permission.POST_NOTIFICATIONS',
    ]) {
      expect(manifest, contains(permission), reason: permission);
    }
    expect(manifest, contains('android.permission.WRITE_EXTERNAL_STORAGE'));
    expect(manifest, contains('android:maxSdkVersion="28"'));
    expect(manifest, contains('android:supportsPictureInPicture="true"'));
    expect(
      manifest,
      contains('com.ryanheise.audioservice.AudioService'),
    );
    expect(
      manifest,
      contains('com.ryanheise.audioservice.MediaButtonReceiver'),
    );
    expect(manifest, contains('android:foregroundServiceType="mediaPlayback"'));
    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('READ_MEDIA_VIDEO')));
    expect(tvManifest, contains('android.software.leanback'));
    expect(tvManifest, contains('android.intent.category.LEANBACK_LAUNCHER'));
    expect(tvManifest, contains('android:banner="@drawable/banner"'));
    expect(tvManifest, contains('android.hardware.touchscreen'));
    expect(tvManifest, contains('android:required="false"'));
  });
}
