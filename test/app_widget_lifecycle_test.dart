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

    test('同色并发亮度请求只访问平台一次', () async {
      final platform = _FakeAppShellPlatform(manualBrightness: true);
      final service = WindowsAppShellService(platform: platform);

      final first = service.syncBrightness(Brightness.dark);
      final second = service.syncBrightness(Brightness.dark);

      expect(platform.brightnesses, const [Brightness.dark]);
      platform.completeBrightness(0);
      await Future.wait([first, second]);
      expect(platform.brightnesses, const [Brightness.dark]);
    });

    test('异色快速请求串行执行且最终缓存最后一次亮度', () async {
      final platform = _FakeAppShellPlatform(manualBrightness: true);
      final service = WindowsAppShellService(platform: platform);

      final dark = service.syncBrightness(Brightness.dark);
      final light = service.syncBrightness(Brightness.light);
      expect(platform.brightnesses, const [Brightness.dark]);

      platform.completeBrightness(0);
      await Future<void>.delayed(Duration.zero);
      expect(
        platform.brightnesses,
        const [Brightness.dark, Brightness.light],
      );

      platform.completeBrightness(1);
      await Future.wait([dark, light]);
      await service.syncBrightness(Brightness.light);
      expect(platform.brightnesses, hasLength(2), reason: '最后完成的亮度应成为缓存值');
    });

    test('解绑后旧亮度 Future 不污染新 generation 的缓存', () async {
      final platform = _FakeAppShellPlatform(manualBrightness: true);
      final service = WindowsAppShellService(platform: platform);

      final stale = service.syncBrightness(Brightness.dark);
      service.detach();
      platform.completeBrightness(0);
      await stale;

      final current = service.syncBrightness(Brightness.dark);
      expect(platform.brightnesses, hasLength(2));
      platform.completeBrightness(1);
      await current;
    });

    test('解绑分别重试失败的监听器移除且不重复清理成功项', () async {
      final capturedErrors = <Object>[];
      final platform = _FakeAppShellPlatform(failedRemoveTrayAttempts: 1);
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

      service.detach();
      expect(platform.removeTrayListenerCalls, 1);
      expect(platform.removeWindowListenerCalls, 1);

      service.detach();
      expect(platform.removeTrayListenerCalls, 2);
      expect(platform.removeWindowListenerCalls, 1);
      expect(capturedErrors, hasLength(1));

      await service.initialize(
        trayListener: trayListener,
        windowListener: windowListener,
      );
      expect(platform.addTrayListenerCalls, 2);
      expect(platform.addWindowListenerCalls, 2);
    });

    test('销毁时某个监听器移除失败不阻断另一个监听器清理', () async {
      final platform = _FakeAppShellPlatform(
        failedRemoveTrayAttempts: 1,
        failedRemoveWindowAttempts: 1,
      );
      final service = WindowsAppShellService(
        platform: platform,
        onError: (error, stackTrace) {},
      );
      await service.initialize(
        trayListener: _TrayListener(),
        windowListener: _WindowListener(),
      );

      service.dispose();

      expect(platform.removeTrayListenerCalls, 1);
      expect(platform.removeWindowListenerCalls, 1);
      await service.initialize(
        trayListener: _TrayListener(),
        windowListener: _WindowListener(),
      );
      expect(platform.addTrayListenerCalls, 1);
      expect(platform.addWindowListenerCalls, 1);
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

    testWidgets('原位替换 owned 服务会销毁旧服务并初始化 borrowed 服务', (tester) async {
      final oldPlatform = _FakeAppShellPlatform();
      final oldService = WindowsAppShellService(platform: oldPlatform);
      final newPlatform = _FakeAppShellPlatform();
      final newService = WindowsAppShellService(platform: newPlatform);

      await tester.pumpWidget(AppShellLifecycle(
        service: oldService,
        trayListener: _TrayListener(),
        windowListener: _WindowListener(),
        ownership: AppShellServiceOwnership.owned,
        child: const SizedBox(),
      ));
      await tester.pumpWidget(AppShellLifecycle(
        service: newService,
        trayListener: _TrayListener(),
        windowListener: _WindowListener(),
        ownership: AppShellServiceOwnership.borrowed,
        child: const SizedBox(),
      ));

      expect(oldPlatform.removeTrayListenerCalls, 1);
      expect(oldPlatform.removeWindowListenerCalls, 1);
      expect(newPlatform.addTrayListenerCalls, 1);
      expect(newPlatform.addWindowListenerCalls, 1);
      await oldService.initialize(
        trayListener: _TrayListener(),
        windowListener: _WindowListener(),
      );
      expect(oldPlatform.addTrayListenerCalls, 1, reason: '旧 owned 服务已经永久销毁');

      await tester.pumpWidget(const SizedBox());
      await newService.initialize(
        trayListener: _TrayListener(),
        windowListener: _WindowListener(),
      );
      expect(newPlatform.addTrayListenerCalls, 2,
          reason: '新 borrowed 服务仅解绑，仍归外部所有');
      newService.dispose();
    });

    testWidgets('原位替换 borrowed 服务会解绑旧服务并接管新 owned 服务', (tester) async {
      final oldPlatform = _FakeAppShellPlatform();
      final oldService = WindowsAppShellService(platform: oldPlatform);
      final newPlatform = _FakeAppShellPlatform();
      final newService = WindowsAppShellService(platform: newPlatform);

      await tester.pumpWidget(AppShellLifecycle(
        service: oldService,
        trayListener: _TrayListener(),
        windowListener: _WindowListener(),
        ownership: AppShellServiceOwnership.borrowed,
        child: const SizedBox(),
      ));
      await tester.pumpWidget(AppShellLifecycle(
        service: newService,
        trayListener: _TrayListener(),
        windowListener: _WindowListener(),
        ownership: AppShellServiceOwnership.owned,
        child: const SizedBox(),
      ));

      expect(oldPlatform.removeTrayListenerCalls, 1);
      expect(newPlatform.addTrayListenerCalls, 1);
      await oldService.initialize(
        trayListener: _TrayListener(),
        windowListener: _WindowListener(),
      );
      expect(oldPlatform.addTrayListenerCalls, 2,
          reason: '旧 borrowed 服务仍归外部所有');

      await tester.pumpWidget(const SizedBox());
      await newService.initialize(
        trayListener: _TrayListener(),
        windowListener: _WindowListener(),
      );
      expect(newPlatform.addTrayListenerCalls, 1, reason: '新 owned 服务随组件永久销毁');
      oldService.dispose();
    });

    testWidgets('同一服务原位替换 listeners 时重试首次失败的解绑', (tester) async {
      final platform = _FakeAppShellPlatform(failedRemoveTrayAttempts: 1);
      final service = WindowsAppShellService(
        platform: platform,
        onError: (error, stackTrace) {},
      );
      final oldTrayListener = _TrayListener();
      final newTrayListener = _TrayListener();

      await tester.pumpWidget(AppShellLifecycle(
        service: service,
        trayListener: oldTrayListener,
        windowListener: _WindowListener(),
        ownership: AppShellServiceOwnership.borrowed,
        child: const SizedBox(),
      ));
      await tester.pumpWidget(AppShellLifecycle(
        service: service,
        trayListener: newTrayListener,
        windowListener: _WindowListener(),
        ownership: AppShellServiceOwnership.borrowed,
        child: const SizedBox(),
      ));

      expect(platform.removeTrayListenerCalls, 2);
      expect(platform.addTrayListenerCalls, 2);
      expect(platform.lastTrayListener, same(newTrayListener));
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    });
  });

  group('parseStoredThemeColor', () {
    const fallback = Color(0xFF78A9D4);

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

  test('持久化主题色转换归属于 AppWidget 而非 Windows 服务', () {
    final appWidgetSource = File('lib/app_widget.dart').readAsStringSync();
    final windowsServiceSource =
        File('lib/services/windows_app_shell_service.dart').readAsStringSync();

    expect(appWidgetSource, contains('Color parseStoredThemeColor('));
    expect(windowsServiceSource, isNot(contains('parseStoredThemeColor')));
  });

  test('AppWidget 通过统一主题工厂构建明暗与 OLED 主题', () {
    final source = File('lib/app_widget.dart').readAsStringSync();

    expect(source, contains('AppTheme.light('));
    expect(source, contains('AppTheme.dark('));
    expect(source, contains('AppTheme.fromColorScheme('));
    expect(source, contains('AppTheme.withOledBackground('));
    expect(source, isNot(contains('Utils.oledDarkTheme(')));
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
    this.failedRemoveTrayAttempts = 0,
    this.failedRemoveWindowAttempts = 0,
    this.preventCloseCompleter,
    this.manualBrightness = false,
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
  int failedRemoveTrayAttempts;
  int failedRemoveWindowAttempts;
  final Completer<void>? preventCloseCompleter;
  final bool manualBrightness;
  String? trayIcon;
  String? trayTooltip;
  List<TrayMenuEntry>? menuItems;
  final List<Brightness> brightnesses = [];
  final List<Completer<void>> brightnessCompleters = [];
  TrayListener? lastTrayListener;

  @override
  void addTrayListener(TrayListener listener) {
    addTrayListenerCalls++;
    lastTrayListener = listener;
  }

  @override
  void removeTrayListener(TrayListener listener) {
    removeTrayListenerCalls++;
    if (failedRemoveTrayAttempts > 0) {
      failedRemoveTrayAttempts--;
      throw StateError('托盘监听器移除失败');
    }
  }

  @override
  void addWindowListener(WindowListener listener) => addWindowListenerCalls++;

  @override
  void removeWindowListener(WindowListener listener) {
    removeWindowListenerCalls++;
    if (failedRemoveWindowAttempts > 0) {
      failedRemoveWindowAttempts--;
      throw StateError('窗口监听器移除失败');
    }
  }

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
  Future<void> setBrightness(Brightness brightness) {
    brightnesses.add(brightness);
    if (!manualBrightness) return Future<void>.value();
    final completer = Completer<void>();
    brightnessCompleters.add(completer);
    return completer.future;
  }

  void completeBrightness(int index) => brightnessCompleters[index].complete();
}

class _TrayListener with TrayListener {}

class _WindowListener with WindowListener {}
