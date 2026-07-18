import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/windows_app_shell_service.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  group('WindowsAppShellService', () {
    test('并发重复初始化只配置一次托盘和监听器', () async {
      final platform = _FakeAppShellPlatform();
      final service = WindowsAppShellService(platform: platform);
      final trayListener = _TrayListener();
      final windowListener = _WindowListener();

      await Future.wait([
        service.initialize(
          trayListener: trayListener,
          windowListener: windowListener,
        ),
        service.initialize(
          trayListener: trayListener,
          windowListener: windowListener,
        ),
      ]);

      expect(platform.addTrayListenerCalls, 1);
      expect(platform.addWindowListenerCalls, 1);
      expect(platform.preventCloseCalls, 1);
      expect(platform.trayIcon, 'assets/images/logo/logo_lanczos.ico');
      expect(platform.trayTooltip, '看影音');
      expect(platform.menuItems, const [
        TrayMenuEntry(key: 'show_window', label: '显示窗口'),
        TrayMenuEntry.separator(),
        TrayMenuEntry(key: 'exit', label: '退出看影音'),
      ]);
    });

    test('重复清理只移除一次监听器且清理后不再访问平台', () async {
      final platform = _FakeAppShellPlatform();
      final service = WindowsAppShellService(platform: platform);
      final trayListener = _TrayListener();
      final windowListener = _WindowListener();
      await service.initialize(
        trayListener: trayListener,
        windowListener: windowListener,
      );

      service.dispose();
      service.dispose();
      await service.syncBrightness(Brightness.dark);
      await service.initialize(
        trayListener: trayListener,
        windowListener: windowListener,
      );

      expect(platform.removeTrayListenerCalls, 1);
      expect(platform.removeWindowListenerCalls, 1);
      expect(platform.brightnesses, isEmpty);
      expect(platform.addTrayListenerCalls, 1);
    });

    test('仅在 Windows 同步变化后的窗口亮度', () async {
      final platform = _FakeAppShellPlatform();
      final service = WindowsAppShellService(platform: platform);

      await service.syncBrightness(Brightness.dark);
      await service.syncBrightness(Brightness.dark);
      await service.syncBrightness(Brightness.light);

      expect(
        platform.brightnesses,
        const [Brightness.dark, Brightness.light],
      );

      final nonWindowsPlatform = _FakeAppShellPlatform(isWindows: false);
      final nonWindowsService =
          WindowsAppShellService(platform: nonWindowsPlatform);
      await nonWindowsService.syncBrightness(Brightness.dark);
      expect(nonWindowsPlatform.brightnesses, isEmpty);
    });
  });

  group('parseStoredThemeColor', () {
    const fallback = Color(0xFF00D4AA);

    test('兼容默认值、十六进制字符串和整数', () {
      expect(parseStoredThemeColor(null), fallback);
      expect(parseStoredThemeColor('default'), fallback);
      expect(
        parseStoredThemeColor('ff123456').toARGB32(),
        const Color(0xFF123456).toARGB32(),
      );
      expect(
        parseStoredThemeColor(0xFF654321).toARGB32(),
        const Color(0xFF654321).toARGB32(),
      );
    });

    test('非法或越界旧设置回退默认颜色', () {
      expect(parseStoredThemeColor('not-a-color'), fallback);
      expect(parseStoredThemeColor(-1), fallback);
      expect(parseStoredThemeColor(0x1FFFFFFFF), fallback);
      expect(parseStoredThemeColor(Object()), fallback);
    });
  });

  test('AppWidget.build 不执行应用壳和平台一次性副作用', () {
    final source = File('lib/app_widget.dart').readAsStringSync();
    final buildBody = _methodBody(source, 'Widget build(BuildContext context)');

    expect(buildBody, isNot(contains('setBrightness')));
    expect(buildBody, isNot(contains('setObservers')));
    expect(buildBody, isNot(contains('_handleTray')));
    expect(buildBody, isNot(contains('FlutterDisplayMode.supported')));
  });
}

String _methodBody(String source, String signature) {
  final signatureIndex = source.indexOf(signature);
  expect(signatureIndex, isNonNegative, reason: '找不到方法：$signature');
  final openingBrace = source.indexOf('{', signatureIndex);
  var depth = 0;
  for (var index = openingBrace; index < source.length; index++) {
    if (source[index] == '{') depth++;
    if (source[index] == '}') depth--;
    if (depth == 0) return source.substring(openingBrace, index + 1);
  }
  fail('方法大括号不完整：$signature');
}

class _FakeAppShellPlatform implements WindowsAppShellPlatform {
  _FakeAppShellPlatform({this.isWindows = true});

  @override
  final bool isWindows;

  @override
  bool get isDesktop => true;

  @override
  bool get isLinux => false;

  int addTrayListenerCalls = 0;
  int removeTrayListenerCalls = 0;
  int addWindowListenerCalls = 0;
  int removeWindowListenerCalls = 0;
  int preventCloseCalls = 0;
  String? trayIcon;
  String? trayTooltip;
  List<TrayMenuEntry>? menuItems;
  final List<Brightness> brightnesses = [];

  @override
  void addTrayListener(TrayListener listener) => addTrayListenerCalls++;

  @override
  void removeTrayListener(TrayListener listener) => removeTrayListenerCalls++;

  @override
  void addWindowListener(WindowListener listener) => addWindowListenerCalls++;

  @override
  void removeWindowListener(WindowListener listener) =>
      removeWindowListenerCalls++;

  @override
  Future<void> setPreventClose() async => preventCloseCalls++;

  @override
  Future<void> setTrayIcon(String iconPath) async => trayIcon = iconPath;

  @override
  Future<void> setTrayTooltip(String tooltip) async => trayTooltip = tooltip;

  @override
  Future<void> setTrayMenu(List<TrayMenuEntry> items) async =>
      menuItems = List.of(items);

  @override
  Future<void> setBrightness(Brightness brightness) async =>
      brightnesses.add(brightness);
}

class _TrayListener with TrayListener {}

class _WindowListener with WindowListener {}
