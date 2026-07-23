import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('活动源码不再包含非 Windows 平台分支', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized.startsWith('lib/legacy/')) continue;
      final source = entity.readAsStringSync();
      for (final token in const <String>[
        'Platform.isAndroid',
        'Platform.isIOS',
        'Platform.isLinux',
        'Platform.isMacOS',
        'kIsWeb',
        'SystemChrome.',
        'DeviceOrientation.',
        'SaverGallery',
        'ScreenBrightnessPlatform',
      ]) {
        if (source.contains(token)) offenders.add('$normalized: $token');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('pubspec 只声明 Windows 所需插件和覆盖', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final token in const <String>[
      'cupertino_icons:',
      'audio_service_mpris:',
      'dynamic_color:',
      'flutter_displaymode:',
      'saver_gallery:',
      'screen_brightness_android:',
      'screen_brightness_ios:',
      'screen_brightness_ohos:',
      'screen_brightness_platform_interface:',
      'media_kit_libs_linux:',
      'media_kit_libs_ios_video:',
      'media_kit_libs_android_video:',
      'media_kit_libs_macos_video:',
      'media_kit_libs_ohos:',
      'flutter_native_splash:',
    ]) {
      expect(pubspec, isNot(contains(token)), reason: token);
    }
    expect(pubspec, contains('flutter_volume_controller:'));
    expect(pubspec, contains('audio_session:'));
    expect(pubspec, contains('media_kit_libs_windows_video:'));
  });

  test('非 Windows 资产已移除', () {
    for (final path in const <String>[
      'assets/linux',
      'assets/images/logo/logo_android.png',
      'assets/images/logo/logo_ios.png',
      'assets/images/logo/logo_linux.png',
    ]) {
      expect(
        FileSystemEntity.typeSync(path),
        FileSystemEntityType.notFound,
        reason: path,
      );
    }
  });
}
