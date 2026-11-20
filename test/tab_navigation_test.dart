import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/pages/menu/menu.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';

void main() {
  testWidgets('连续点击实际替换标签、释放旧模块，待处理点击不打断播放', (tester) async {
    var localDisposals = 0;
    installAppPlatformCapabilities(AppPlatformCapabilities.android);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 820);
    addTearDown(tester.view.reset);
    Modular.setInitialRoute('/tab/local/');
    await tester.pumpWidget(ModularApp(
      module: _NavigationModule(() => localDisposals++),
      child: Builder(
          builder: (_) =>
              MaterialApp.router(routerConfig: Modular.routerConfig)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('本地正文'), findsOneWidget);

    Future<void> tapDestination(String name) async {
      await tester.tap(find.byWidgetPredicate(
        (widget) => widget is NavigationDestination && widget.label == name,
      ));
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(milliseconds: 16));
    }

    final started = tester.binding.clock.now();
    await tapDestination('网盘媒体库');
    expect(Modular.to.path, '/tab/cloud/');
    expect(find.text('网盘正文'), findsOneWidget);
    expect(localDisposals, 1);
    await tapDestination('观看历史');
    expect(Modular.to.path, '/tab/history/');
    expect(find.text('历史正文'), findsOneWidget);
    await tapDestination('媒体库');
    expect(Modular.to.path, '/tab/local/');
    expect(find.text('本地正文').hitTestable(), findsOneWidget);
    expect(tester.binding.clock.now().difference(started),
        lessThan(const Duration(milliseconds: 500)));
    expect(Modular.to.navigateHistory.map((route) => route.uri.path),
        ['/tab', '/tab/local/']);

    await tester.pumpAndSettle();
    expect(find.text('本地正文'), findsOneWidget);

    final select = tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!;
    select(2);
    select(1);
    await tester.pump(Duration.zero);
    expect(Modular.to.path, '/tab/local/');
    expect(localDisposals, 1);

    select(2);
    unawaited(Modular.to.pushNamed<void>('/video'));
    await tester.pumpAndSettle();
    expect(find.text('播放器'), findsOneWidget);
    expect(Modular.to.path, '/video');
    expect(localDisposals, 1);
    Modular.to.pop();
    await tester.pumpAndSettle();
    expect(find.text('本地正文'), findsOneWidget);
    expect(Modular.to.path, '/tab/local/');
  });
}

class _TestSettings extends Fake implements TypedSettings {
  @override
  Object? get(String key, {Object? defaultValue}) => defaultValue;

  @override
  T getTyped<T>(String key, {required T defaultValue}) =>
      key == SettingBoxKey.showWindowButton ? true as T : defaultValue;
}

class _NavigationModule extends Module {
  _NavigationModule(this.onLocalDisposed);
  final VoidCallback onLocalDisposed;

  @override
  void binds(Injector i) =>
      i.addSingleton<TypedSettings>(() => _TestSettings());

  @override
  void routes(r) {
    r.child('/tab', child: (_) => const ScaffoldMenu(), children: [
      ModuleRoute('/local', module: _LocalModule(onLocalDisposed)),
      ChildRoute('/cloud/', child: (_) => const Text('网盘正文')),
      ChildRoute('/history/', child: (_) => const Text('历史正文')),
    ]);
    r.child('/video', child: (_) => const Scaffold(body: Text('播放器')));
  }
}

class _LocalModule extends Module {
  _LocalModule(this.onDisposed);
  final VoidCallback onDisposed;

  @override
  void binds(Injector i) =>
      i.addSingleton<_LocalSession>(() => _LocalSession(onDisposed));

  @override
  void routes(r) {
    r.child('/', child: (_) {
      Modular.get<_LocalSession>();
      return const Text('本地正文');
    });
  }
}

class _LocalSession implements Disposable {
  _LocalSession(this.onDisposed);
  final VoidCallback onDisposed;

  @override
  void dispose() => onDisposed();
}
