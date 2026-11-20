import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/bean/dialog/dialog_helper.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';
import 'package:kanyingyin/shaders/shaders_controller.dart';
import 'package:kanyingyin/app/startup_landing.dart';
import 'package:kanyingyin/pages/init_page.dart';

void main() {
  test('桌面和手机根入口直达用户首页，显式入站和 TV 预置保留原路由', () {
    var reads = 0;
    String resolve(String route, {bool isTv = false}) => resolveInitialRoute(
          platformRoute: route,
          isAndroidTv: isTv,
          preferredPage: () {
            reads++;
            return '/tab/history/';
          },
        );

    expect(resolve('/video/?source=local'), '/video/?source=local');
    expect(resolve('/', isTv: true), '/');
    expect(reads, 0);
    expect(resolve('/'), '/tab/history/');
    expect(reads, 1);
  });

  testWidgets('启动询问在检测和弹窗两个阶段被路由中断，返回后均可继续', (tester) async {
    const channel = MethodChannel('com.kanyingyin.player/shortcut');
    final inspection = Completer<int>();
    var checks = 0;
    final settings = _FirstRunSettings();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'inspectShortcutEntries');
      checks++;
      if (checks == 1) return inspection.future;
      return 1;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    installAppPlatformCapabilities(AppPlatformCapabilities.windows);
    final route = resolveInitialRoute(
      platformRoute: '/',
      isAndroidTv: false,
      preferredPage: () => '/tab/local/',
    );
    Modular.setInitialRoute(route);
    await tester.pumpWidget(ModularApp(
      module: _LandingModule(settings),
      child: Builder(builder: (_) {
        Modular.setObservers([AppDialog.observer]);
        return MaterialApp.router(routerConfig: Modular.routerConfig);
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.text('默认首页'), findsOneWidget);
    expect(checks, 1);
    Future<void> replaceRoute(String path) async {
      final router = Modular.routerConfig;
      final configuration = await router.routeInformationParser!
          .parseRouteInformation(RouteInformation(uri: Uri.parse(path)));
      await router.routerDelegate.setNewRoutePath(configuration);
      await tester.pumpAndSettle();
    }

    unawaited(Modular.to.pushNamed<void>('/video'));
    await tester.pumpAndSettle();
    expect(Modular.to.path, '/video');
    inspection.complete(1);
    await tester.pumpAndSettle();
    expect(find.text('播放页'), findsOneWidget);
    expect(find.text('创建快捷方式'), findsNothing);

    await replaceRoute('/tab/history/');
    expect(find.text('另一个标签'), findsOneWidget);
    expect(find.text('是否在开始菜单创建看影音的快捷方式？'), findsOneWidget);
    expect(checks, 2);

    await replaceRoute('/video');
    expect(Modular.to.path, '/video');
    expect(settings.asked, isFalse);
    await replaceRoute('/tab/history/');
    expect(find.text('是否在开始菜单创建看影音的快捷方式？'), findsOneWidget);
    await tester.tap(find.text('暂不创建'));
    await tester.pumpAndSettle();
    expect(settings.asked, isTrue);
    expect(checks, 3);
    expect(find.text('创建快捷方式'), findsNothing);
    expect(find.text('版本更新日志'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  test('快捷方式已呈现后切离，返回只继续说明和更新', () async {
    final sequence = StartupPromptSequence();
    var current = true;
    final events = <String>[];
    Future<void> resume() => sequence.resume(
          canPresent: () => current,
          checkShortcut: () async {
            events.add('shortcut');
            current = false;
            return true;
          },
          showVersionChangelog: () async {
            events.add('changelog');
            return true;
          },
          checkForUpdates: () async {
            events.add('update');
            return true;
          },
        );
    await resume();
    current = true;
    await resume();
    expect(events, ['shortcut', 'changelog', 'update']);
  });
}

class _FirstRunSettings extends Fake implements TypedSettings {
  bool asked = false;

  @override
  T getTyped<T>(String key, {required T defaultValue}) =>
      key == SettingBoxKey.shortcutDialogShown ? asked as T : defaultValue;

  @override
  Object? get(String key, {Object? defaultValue}) => defaultValue;

  @override
  Future<void> put<T>(String key, T value) async {
    if (key == SettingBoxKey.shortcutDialogShown) asked = value == true;
  }
}

class _TestShaders extends Fake implements ShadersController {
  @override
  Future<void> copyShadersToExternalDirectory() async {}
}

class _LandingModule extends Module {
  _LandingModule(this.settings);

  final TypedSettings settings;

  @override
  void binds(Injector i) {
    i.addSingleton<TypedSettings>(() => settings);
    i.addSingleton<ShadersController>(() => _TestShaders());
  }

  @override
  void routes(r) {
    r.child('/tab/local/',
        child: (_) => const StartupPrompts(
              child: StartupLanding(child: Scaffold(body: Text('默认首页'))),
            ));
    r.child('/tab/history/',
        child: (_) => const StartupPrompts(
              child: Scaffold(body: Text('另一个标签')),
            ));
    r.child('/video', child: (_) => const Scaffold(body: Text('播放页')));
  }
}
