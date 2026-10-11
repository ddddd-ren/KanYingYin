import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/settings/presentation/k_settings_scaffold.dart';
import 'package:kanyingyin/pages/menu/menu.dart';
import 'package:kanyingyin/utils/constants.dart';

class _NavigationState extends NavigationBarState {
  @override
  int getDefaultSelectedIndex() => 3;
}

double _opacityOf(WidgetTester tester, Finder child) {
  final fades = tester.widgetList<FadeTransition>(
    find.ancestor(of: child, matching: find.byType(FadeTransition)),
  );
  final opacities = tester.widgetList<Opacity>(
    find.ancestor(of: child, matching: find.byType(Opacity)),
  );
  return fades.fold(1.0, (value, fade) => value * fade.opacity.value) *
      opacities.fold(1.0, (value, opacity) => value * opacity.opacity);
}

void main() {
  testWidgets('导航立即更新且连续切换不会被旧延迟覆盖', (tester) async {
    final state = _NavigationState();
    addTearDown(state.dispose);
    state.updateSelectedIndex(4);
    expect(state.selectedIndex, 4);
    state.updateSelectedIndex(3);
    expect(state.selectedIndex, 3);
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.selectedIndex, 3);
  });

  testWidgets('桌面新页面在前半程可见且中途返回保持连续', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    const contentKey = ValueKey('motion-content');
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      theme: ThemeData(
        platform: TargetPlatform.windows,
        pageTransitionsTheme: pageTransitionsTheme2024,
      ),
      home: const Scaffold(body: Text('首页')),
    ));
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('内容', key: contentKey)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final beforePop = _opacityOf(tester, find.byKey(contentKey));
    expect(beforePop, greaterThan(0));
    expect(beforePop, lessThan(1));
    navigator.currentState!.pop();
    await tester.pump();
    expect(
        _opacityOf(tester, find.byKey(contentKey)), closeTo(beforePop, 0.001));
    await tester.pumpAndSettle();
    expect(find.byKey(contentKey), findsNothing);
  });

  testWidgets('设置内容只跟随路由过渡而不额外延迟显示', (tester) async {
    const contentKey = ValueKey('settings-content');
    await tester.pumpWidget(const MaterialApp(
      home: KSettingsScaffold(
        title: '设置',
        body: Text('已加载内容', key: contentKey),
      ),
    ));
    expect(_opacityOf(tester, find.byKey(contentKey)), 1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
