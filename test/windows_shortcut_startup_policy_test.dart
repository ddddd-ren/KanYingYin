import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/windows_shortcut_startup_policy.dart';
import 'package:kanyingyin/utils/windows_shortcut.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.kanyingyin.player/shortcut.test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('桌面快捷方式存在时修复且不重复询问', () {
    for (final state in <WindowsShortcutEntryState>[
      WindowsShortcutEntryState.desktopOnly,
      WindowsShortcutEntryState.desktopAndStartMenu,
    ]) {
      expect(
        decideShortcutStartup(
          state: state,
          dialogAlreadyShown: false,
        ),
        ShortcutStartupDecision.repairDesktop,
      );
    }
  });

  test('仅开始菜单入口时首次询问且已询问后跳过', () {
    expect(
      decideShortcutStartup(
        state: WindowsShortcutEntryState.startMenuOnly,
        dialogAlreadyShown: false,
      ),
      ShortcutStartupDecision.askToCreateDesktop,
    );
    expect(
      decideShortcutStartup(
        state: WindowsShortcutEntryState.startMenuOnly,
        dialogAlreadyShown: true,
      ),
      ShortcutStartupDecision.skip,
    );
  });

  test('两个入口都不存在且尚未询问时询问创建桌面快捷方式', () {
    expect(
      decideShortcutStartup(
        state: WindowsShortcutEntryState.none,
        dialogAlreadyShown: false,
      ),
      ShortcutStartupDecision.askToCreateDesktop,
    );
    expect(
      decideShortcutStartup(
        state: WindowsShortcutEntryState.none,
        dialogAlreadyShown: true,
      ),
      ShortcutStartupDecision.skip,
    );
  });

  test('入口检测失败时报告错误并保留重试机会', () {
    expect(
      decideShortcutStartup(
        state: WindowsShortcutEntryState.unknown,
        dialogAlreadyShown: false,
      ),
      ShortcutStartupDecision.reportDetectionFailure,
    );
  });

  test('原生组合值映射为强类型入口状态', () async {
    final client = WindowsShortcutClient(channel: channel);
    final expectations = <int, WindowsShortcutEntryState>{
      0: WindowsShortcutEntryState.none,
      1: WindowsShortcutEntryState.desktopOnly,
      2: WindowsShortcutEntryState.startMenuOnly,
      3: WindowsShortcutEntryState.desktopAndStartMenu,
    };

    for (final entry in expectations.entries) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => entry.key);
      expect(await client.inspectShortcutEntries(), entry.value);
    }
  });

  test('原生检测异常不会误判为两个入口都不存在', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'ShortcutInspectionFailed');
    });
    final client = WindowsShortcutClient(channel: channel);

    expect(
      await client.inspectShortcutEntries(),
      WindowsShortcutEntryState.unknown,
    );
  });
}
