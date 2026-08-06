import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TV flavor 清单声明电视入口和非触摸硬件要求', () async {
    final mainManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final tvManifest = File(
      'android/app/src/tvTest/AndroidManifest.xml',
    ).readAsStringSync();

    expect(mainManifest, contains('android:label="看影音"'));
    expect(tvManifest, contains('android.software.leanback'));
    expect(tvManifest, contains('android.hardware.touchscreen'));
    expect(tvManifest, contains('android.hardware.faketouch'));
    expect(
      tvManifest,
      contains('android.intent.category.LEANBACK_LAUNCHER'),
    );
    expect(tvManifest, contains('android:banner="@drawable/banner"'));
    expect(tvManifest, contains('android:screenOrientation="landscape"'));

    final codec = await ui.instantiateImageCodec(
      File('android/app/src/tvTest/res/drawable-xhdpi/banner.png')
          .readAsBytesSync(),
    );
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 320);
    expect(frame.image.height, 180);
    frame.image.dispose();
    codec.dispose();
  });
}
