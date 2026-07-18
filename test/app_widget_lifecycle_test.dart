import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/app_widget.dart';
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

    test('单个插件能力失败不阻断后续能力且下次可重试', () async {
      final platform = _FakeAppShellPlatform(failedTrayIconAttempts: 1);
      final capturedErrors = <Object>[];
      final service = WindowsAppShellService(
        platform: platform,
        onError: (error, stackTrace) => capturedErrors.add(error),
      );
      final trayListener = _TrayListener();
      final windowListener = _WindowListener();

      await service.initialize(
        trayListener: trayListener,
        windowListener: windowListener,
      );

      expect(platform.preventCloseCalls, 1);
      expect(platform.trayIconCalls, 1);
      expect(platform.trayTooltipCalls, 1);
      expect(platform.trayMenuCalls, 1);

      await service.initialize(
        trayListener: trayListener,
        windowListener: windowListener,
      );

      expect(platform.preventCloseCalls, 2);
      expect(platform.trayIconCalls, 2);
      expect(platform.trayTooltipCalls, 2);
      expect(platform.trayMenuCalls, 2);
      expect(platform.addTrayListenerCalls, 1);
      expect(platform.addWindowListenerCalls, 1);
      expect(capturedErrors, hasLength(1));
    });
  });

  group('AppShellLifecycle', () {
    testWidgets('在首帧子树构建前启动初始化并在销毁时移除监听器', (tester) async {
      final platform = _FakeAppShellPlatform();
      final service = WindowsAppShellService(platform: platform);
      var listenersAttachedDuringBuild = false;

      await tester.pumpWidget(
        AppShellLifecycle(
          service: service,
          trayListener: _TrayListener(),
          windowListener: _WindowListener(),
          ownership: AppShellServiceOwnership.borrowed,
          child: Builder(builder: (context) {
            listenersAttachedDuringBuild = platform.addTrayListenerCalls == 1 &&
                platform.addWindowListenerCalls == 1;
            return const SizedBox();
          }),
        ),
      );

      expect(listenersAttachedDuringBuild, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(platform.removeTrayListenerCalls, 1);
      expect(platform.removeWindowListenerCalls, 1);

      await service.initialize(
        trayListener: _TrayListener(),
        windowListener: _WindowListener(),
      );
      expect(platform.addTrayListenerCalls, 2,
          reason: '借用的服务由外部持有，组件只能解绑本次监听器');
      service.dispose();
    });

    testWidgets('拥有的服务随生命周期销毁', (tester) async {
      final platform = _FakeAppShellPlatform();
      final service = WindowsAppShellService(platform: platform);

      await tester.pumpWidget(
        AppShellLifecycle(
          service: service,
          trayListener: _TrayListener(),
          windowListener: _WindowListener(),
          ownership: AppShellServiceOwnership.owned,
          child: const SizedBox(),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      await service.initialize(
        trayListener: _TrayListener(),
        windowListener: _WindowListener(),
      );

      expect(platform.removeTrayListenerCalls, 1);
      expect(platform.removeWindowListenerCalls, 1);
      expect(platform.addTrayListenerCalls, 1, reason: '生命周期拥有的服务不得在销毁后重新初始化');
    });

    testWidgets('初始化等待期间销毁后不再继续调用平台能力', (tester) async {
      final preventCloseCompleter = Completer<void>();
      final platform = _FakeAppShellPlatform(
        preventCloseCompleter: preventCloseCompleter,
      );
      final service = WindowsAppShellService(platform: platform);

      await tester.pumpWidget(
        AppShellLifecycle(
          service: service,
          trayListener: _TrayListener(),
          windowListener: _WindowListener(),
          ownership: AppShellServiceOwnership.owned,
          child: const SizedBox(),
        ),
      );
      expect(platform.preventCloseCalls, 1);

      await tester.pumpWidget(const SizedBox());
      preventCloseCompleter.complete();
      await tester.pump();

      expect(platform.removeTrayListenerCalls, 1);
      expect(platform.removeWindowListenerCalls, 1);
      expect(platform.trayIconCalls, 0);
      expect(platform.trayTooltipCalls, 0);
      expect(platform.trayMenuCalls, 0);
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
    final buildBody = _methodBody(
      source,
      'Widget build(BuildContext context)',
      after: 'class _AppWidgetState',
    );

    expect(buildBody, isNot(contains('setBrightness')));
    expect(buildBody, isNot(contains('setObservers')));
    expect(buildBody, isNot(contains('_handleTray')));
    expect(buildBody, isNot(contains('FlutterDisplayMode.supported')));
    expect(buildBody, isNot(contains('themeProvider.setTheme(')));
  });
}

String _methodBody(String source, String signature, {String? after}) {
  final searchStart = after == null ? 0 : source.indexOf(after);
  expect(searchStart, isNonNegative, reason: '找不到起始标记：$after');
  final signatureIndex = source.indexOf(signature, searchStart);
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
  _FakeAppShellPlatform({
    this.isWindows = true,
    this.failedTrayIconAttempts = 0,
    this.preventCloseCompleter,
  });

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
  int trayIconCalls = 0;
  int trayTooltipCalls = 0;
  int trayMenuCalls = 0;
  int failedTrayIconAttempts;
  final Completer<void>? preventCloseCompleter;
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
  Future<void> setPreventClose() {
    preventCloseCalls++;
    return preventCloseCompleter?.future ?? Future<void>.value();
  }

  @override
  Future<void> setTrayIcon(String iconPath) async {
    trayIconCalls++;
    if (failedTrayIconAttempts > 0) {
      failedTrayIconAttempts--;
      throw StateError('托盘图标设置失败');
    }
    trayIcon = iconPath;
  }

  @override
  Future<void> setTrayTooltip(String tooltip) async {
    trayTooltipCalls++;
    trayTooltip = tooltip;
  }

  @override
  Future<void> setTrayMenu(List<TrayMenuEntry> items) async {
    trayMenuCalls++;
    menuItems = List.of(items);
  }

  @override
  Future<void> setBrightness(Brightness brightness) async =>
      brightnesses.add(brightness);
}

class _TrayListener with TrayListener {}

class _WindowListener with WindowListener {}
