import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('原生快捷方式会覆盖旧文件并使用当前包与当前图标', () {
    final header = File('windows/runner/shortcut_utils.h').readAsStringSync();
    final source = File('windows/runner/shortcut_utils.cpp').readAsStringSync();

    expect(header, contains('DesktopShortcutExists'));
    expect(source, isNot(contains('INVALID_FILE_ATTRIBUTES) return true')));
    expect(source, contains('GetWindowsDirectoryW'));
    expect(source, contains('SetArguments'));
    expect(source, contains(r'shell:AppsFolder\'));
    expect(source, contains('SetIconLocation(exePath, 0)'));
    expect(source, contains('PKEY_AppUserModel_ID'));
  });

  test('原生通道提供存在性检查并使用看影音文案', () {
    final source =
        File('windows/runner/platform_channels.cpp').readAsStringSync();

    expect(source, contains('desktopShortcutExists'));
    expect(source, contains(r'\x770B\x5F71\x97F3'));
    expect(source, contains(r'\x542F\x52A8\x770B\x5F71\x97F3'));
    expect(source, isNot(contains(r'\x5C31\x770B')));
    expect(source, isNot(contains(r'\x5728\x7EBF')));
  });

  test('启动时只自动修复已有快捷方式', () {
    final shortcutSource =
        File('lib/utils/windows_shortcut.dart').readAsStringSync();
    final initSource = File('lib/pages/init_page.dart').readAsStringSync();

    expect(shortcutSource,
        contains("invokeMethod<bool>('desktopShortcutExists')"));
    expect(
        initSource, contains('await WindowsShortcut.desktopShortcutExists()'));
    expect(initSource, contains('if (shortcutExists)'));

    final methodStart = initSource.indexOf('Future<void> _showShortcutDialog');
    final methodEnd = initSource.indexOf('void _showVersionChangelog');
    final methodSource = initSource.substring(methodStart, methodEnd);
    expect(
      methodSource.indexOf('desktopShortcutExists'),
      lessThan(methodSource.indexOf('shortcutDialogShown')),
    );
    expect(
      methodSource,
      contains('if (shortcutExists) {\n'
          '      await WindowsShortcut.createDesktopShortcut();\n'
          '      return;'),
    );
  });
}
