import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/settings/presentation/settings_presentation.dart';

void main() {
  test('设置主页按窗口宽度切换三列两列和单列', () {
    expect(SettingsHubLayout.columnCountFor(1280), 3);
    expect(SettingsHubLayout.columnCountFor(1180), 3);
    expect(SettingsHubLayout.columnCountFor(900), 2);
    expect(SettingsHubLayout.columnCountFor(760), 2);
    expect(SettingsHubLayout.columnCountFor(640), 1);
  });

  testWidgets('设置导航项转发点击并尊重禁用状态', (tester) async {
    var enabledPressed = 0;
    var disabledPressed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KSettingsList(
            sections: [
              KSettingsSection(
                title: const Text('导航'),
                tiles: [
                  KSettingsNavigationTile(
                    title: const Text('可用入口'),
                    onPressed: () => enabledPressed += 1,
                  ),
                  KSettingsNavigationTile(
                    title: const Text('禁用入口'),
                    enabled: false,
                    onPressed: () => disabledPressed += 1,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('可用入口'));
    await tester.tap(find.text('禁用入口'));

    expect(enabledPressed, 1);
    expect(disabledPressed, 0);
  });

  testWidgets('设置开关和单选项保持强类型回调', (tester) async {
    bool? toggled;
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KSettingsList(
            sections: [
              KSettingsSection(
                tiles: [
                  KSettingsSwitchTile(
                    title: const Text('硬件解码'),
                    value: false,
                    onChanged: (value) => toggled = value,
                  ),
                  KSettingsRadioTile<String>(
                    title: const Text('自动'),
                    value: 'auto',
                    groupValue: 'gpu',
                    onChanged: (value) => selected = value,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('硬件解码'));
    await tester.tap(find.text('自动'));

    expect(toggled, isTrue);
    expect(selected, 'auto');
  });

  testWidgets('减少动画时使用不超过八十毫秒的动效', (tester) async {
    late Duration resolved;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              resolved = SettingsMotion.duration(
                context,
                SettingsMotion.hoverDuration,
              );
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(resolved, lessThanOrEqualTo(const Duration(milliseconds: 80)));
  });

  testWidgets('设置项提供按钮和开关语义', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KSettingsList(
            sections: [
              KSettingsSection(
                tiles: [
                  KSettingsNavigationTile(
                    title: const Text('进入播放设置'),
                    onPressed: () {},
                  ),
                  KSettingsSwitchTile(
                    title: const Text('后台播放'),
                    value: true,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.text('进入播放设置')),
      matchesSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('后台播放')),
      matchesSemantics(
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
  });
}
