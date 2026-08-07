import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/tv/presentation/tv_focus_surface.dart';
import 'package:kanyingyin/features/tv/presentation/tv_layout_policy.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  testWidgets('TV 卡片焦点显示状态且中心键触发主动作', (tester) async {
    var activated = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusSurface(
            autofocus: true,
            onPressed: () => activated++,
            child: const SizedBox(width: 320, height: 180),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('tv-focused-surface')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activated, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(activated, 2);
  });

  testWidgets('禁用的 TV 焦点表面不能获得焦点或触发动作', (tester) async {
    var activated = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusSurface(
            autofocus: true,
            enabled: false,
            onPressed: () => activated++,
            child: const SizedBox(width: 320, height: 180),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('tv-focused-surface')),
      findsNothing,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activated, 0);
  });

  testWidgets('TV 焦点表面支持独立缩放和边框参数', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusSurface(
            autofocus: true,
            focusedScale: 1.02,
            focusBorderWidth: 3,
            reserveFocusSpace: false,
            onPressed: () {},
            child: const SizedBox(width: 320, height: 180),
          ),
        ),
      ),
    );
    await tester.pump();

    final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1.02);
    final surface =
        tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    final decoration = surface.foregroundDecoration as BoxDecoration;
    expect(decoration.border?.top.width, 3);
  });

  test('TV 布局策略缩小海报并保持遥控器安全间距', () {
    final normal = TvLayoutPolicy.forCapabilities(
      AppPlatformCapabilities.android,
    );
    final television = TvLayoutPolicy.forCapabilities(
      AppPlatformCapabilities.android.copyWith(television: true),
    );

    expect(normal.posterMaxCrossAxisExtent(300), 300);
    expect(normal.gridSpacing(12), 12);
    expect(normal.dialogMaxWidth(560), 560);
    expect(television.posterMaxCrossAxisExtent(300), 260);
    expect(television.gridSpacing(12), 16);
    expect(
      television.gridPadding(const EdgeInsets.all(12)),
      const EdgeInsets.fromLTRB(20, 16, 20, 24),
    );
    final delegate = television.posterGridDelegate(
      fallbackMaxCrossAxisExtent: 300,
      fallbackChildAspectRatio: 0.68,
    );
    expect(delegate, isA<SliverGridDelegateWithFixedCrossAxisCount>());
    final tvDelegate = delegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(tvDelegate.crossAxisCount, 5);
    expect(tvDelegate.childAspectRatio, 0.78);
    expect(television.dialogMaxWidth(560), greaterThan(560));
  });
}
