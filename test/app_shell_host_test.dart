import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_shell_host.dart';

void main() {
  testWidgets('Android 外壳只构建子页面', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppShellHost(
          capabilities: AppPlatformCapabilities.android,
          child: Text('内容'),
        ),
      ),
    );

    expect(find.text('内容'), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-app-shell')), findsNothing);
  });

  test('平台判断集中在运行时选择器', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final offenders = <String>[];
    for (final file in files) {
      if (file.path.endsWith('app_platform_io.dart')) continue;
      final source = file.readAsStringSync();
      if (source.contains('Platform.isWindows') ||
          source.contains('Platform.isAndroid')) {
        offenders.add(file.path);
      }
    }

    expect(offenders, isEmpty);
  });

  test('Android 跳过桌面快捷方式并隐藏打开日志目录', () {
    final initSource = File('lib/pages/init_page.dart').readAsStringSync();
    final playerSettings =
        File('lib/pages/settings/player_settings.dart').readAsStringSync();

    expect(
      initSource,
      contains('if (!detectAppPlatform().desktopShell) return;'),
    );
    expect(
      playerSettings,
      contains('if (platform.desktopShell)'),
    );
    expect(
      playerSettings,
      contains('widget.capabilities ?? detectAppPlatform()'),
    );
  });
}
