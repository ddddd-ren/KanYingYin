import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('桌面窗口控制栏包含完整窗口操作', () {
    final source =
        File('lib/bean/appbar/desktop_window_controls.dart').readAsStringSync();
    for (final label in ['窗口置顶', '最小化', '最大化', '还原', '关闭']) {
      expect(source, contains(label));
    }
    expect(source, contains('setAlwaysOnTop'));
    expect(source, contains('windowManager.minimize'));
    expect(source, contains('windowManager.close'));
  });

  test('我的页面不重复显示桌面窗口控制按钮', () {
    final appBarSource =
        File('lib/bean/appbar/sys_app_bar.dart').readAsStringSync();
    final myPageSource = File('lib/pages/my/my_page.dart').readAsStringSync();

    expect(appBarSource, contains('showDesktopWindowControls'));
    expect(
      myPageSource,
      contains('showDesktopWindowControls: false'),
    );
  });
}
