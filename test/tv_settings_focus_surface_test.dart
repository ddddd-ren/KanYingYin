import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/settings/presentation/tv_settings_focus_surface.dart';
import 'package:kanyingyin/platform/app_platform.dart';

void main() {
  testWidgets('TV 设置焦点显示 3px 边框、浅色背景、勾选和操作提示', (tester) async {
    var activated = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TvSettingsFocusSurface(
          autofocus: true,
          capabilities:
              AppPlatformCapabilities.android.copyWith(television: true),
          onPressed: () => activated++,
          child: const Text('测试 TMDB 连接'),
        ),
      ),
    ));
    await tester.pump();

    final surface = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('tv-settings-focused-surface')),
    );
    final decoration = surface.decoration as BoxDecoration;
    expect((decoration.border! as Border).top.width, 3);
    expect(decoration.color, isNot(Colors.transparent));
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('当前选中 · 按确认执行'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(activated, 1);
  });

  testWidgets('Windows 设置项不增加 TV 提示且点击行为不变', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TvSettingsFocusSurface(
        capabilities: AppPlatformCapabilities.windows,
        onPressed: () {},
        child: const Text('普通设置项'),
      ),
    ));

    expect(find.text('当前选中 · 按确认执行'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('tv-settings-focused-surface')),
      findsNothing,
    );
  });
}
