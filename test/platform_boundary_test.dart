import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('操作系统探测只存在于平台能力入口', () {
    final offenders = <String>[];
    for (final file in _dartFiles(<String>['lib'])) {
      final path = _normalize(file.path);
      if (path == 'lib/platform/app_platform_io.dart') continue;
      final source = file.readAsStringSync(encoding: utf8);
      for (final token in const <String>[
        'Platform.isWindows',
        'Platform.isAndroid',
      ]) {
        if (source.contains(token)) offenders.add('$path: $token');
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('共享业务层不直接依赖 Windows 或 Android 平台实现', () {
    final offenders = <String>[];
    for (final file in _dartFiles(const <String>[
      'lib/features',
      'lib/modules',
      'lib/repositories',
      'lib/services',
    ])) {
      final path = _normalize(file.path);
      if (path == 'lib/services/windows_app_shell_service.dart') continue;
      if (path.startsWith('lib/services/android_')) continue;
      final source = file.readAsStringSync(encoding: utf8);
      for (final token in const <String>[
        'package:window_manager/',
        'package:tray_manager/',
        'package:kanyingyin/platform/android/',
      ]) {
        if (source.contains(token)) offenders.add('$path: $token');
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('依赖与注册文件同时解析 Android 和 Windows 平台实现', () {
    final pubspec = File('pubspec.yaml').readAsStringSync(encoding: utf8);
    final androidRegistrant = File(
      'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
    ).readAsStringSync(encoding: utf8);
    final windowsRegistrant = File(
      'windows/flutter/generated_plugin_registrant.cc',
    ).readAsStringSync(encoding: utf8);

    for (final dependency in const <String>[
      'flutter_secure_storage:',
      'flutter_inappwebview:',
      'media_kit_libs_video:',
      'media_kit_libs_windows_video:',
      'window_manager:',
      'tray_manager:',
    ]) {
      expect(pubspec, contains(dependency), reason: dependency);
    }
    expect(androidRegistrant, contains('MediaKitLibsAndroidVideoPlugin'));
    expect(androidRegistrant, contains('InAppWebViewFlutterPlugin'));
    expect(androidRegistrant, contains('FlutterSecureStoragePlugin'));
    expect(windowsRegistrant, contains('MediaKitLibsWindowsVideoPlugin'));
    expect(windowsRegistrant, contains('FlutterInappwebviewWindowsPlugin'));
    expect(windowsRegistrant, contains('FlutterSecureStorageWindowsPlugin'));
  });

  test('Android 权限与 Windows 插件注册保持平台边界', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync(encoding: utf8);
    final windowsGenerated = <String>[
      File(
        'windows/flutter/generated_plugin_registrant.cc',
      ).readAsStringSync(encoding: utf8),
      File(
        'windows/flutter/generated_plugins.cmake',
      ).readAsStringSync(encoding: utf8),
    ].join('\n');

    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('READ_MEDIA_VIDEO')));
    for (final token in const <String>[
      'media_kit_libs_android_video',
      'flutter_inappwebview_android',
      'sqflite_android',
      'url_launcher_android',
    ]) {
      expect(windowsGenerated, isNot(contains(token)), reason: token);
    }
  });

  test('迅雷设备验证继续使用受限应用内 WebView', () {
    final editor = File(
      'lib/pages/cloud/xunlei/xunlei_source_editor.dart',
    ).readAsStringSync(encoding: utf8);
    final dialog = File(
      'lib/pages/cloud/xunlei/xunlei_verification_dialog.dart',
    ).readAsStringSync(encoding: utf8);

    expect(editor, isNot(contains('LaunchMode.externalApplication')));
    expect(editor, isNot(contains('launchUrl(')));
    expect(dialog, contains('xunleiVerificationEntryUri'));
    expect(dialog, contains('PermissionResponseAction.DENY'));
    expect(dialog, contains('NavigationActionPolicy.CANCEL'));
    expect(dialog, contains('DebugLoggingSettings(enabled: false)'));
    expect(dialog, contains('DownloadStartResponseAction.CANCEL'));
    expect(dialog, isNot(contains('openDevTools')));
    expect(dialog, isNot(contains('onConsoleMessage')));
  });
}

Iterable<File> _dartFiles(List<String> roots) sync* {
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) continue;
    yield* directory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
  }
}

String _normalize(String path) => path.replaceAll('\\', '/');
