import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/android/android_media_bundle.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  test('Android 诊断摘要标记 Full 原生媒体包', () {
    expect(
      AndroidMediaBundle.diagnosticLines(AppPlatformCapabilities.android),
      equals(const <String>['Android 原生媒体包: full-v1.1.11']),
    );
  });

  test('Windows 诊断摘要不声明 Android 原生媒体包', () {
    expect(
      AndroidMediaBundle.diagnosticLines(AppPlatformCapabilities.windows),
      isEmpty,
    );
  });

  test('诊断导出器接入平台原生媒体包标识', () {
    final exporter = File(
      'lib/utils/diagnostic_log_exporter.dart',
    ).readAsStringSync();

    expect(
      exporter,
      contains('...AndroidMediaBundle.diagnosticLines(platform)'),
    );
  });
}
