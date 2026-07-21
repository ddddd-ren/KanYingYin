import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/windows_shortcut_startup_policy.dart';
import 'package:kanyingyin/utils/windows_shortcut.dart';

void main() {
  const coordinator = WindowsShortcutStartupCoordinator();

  test('桌面入口存在时只修复一次', () async {
    var askCount = 0;
    var repairCount = 0;

    final result = await coordinator.run(
      state: WindowsShortcutEntryState.desktopOnly,
      dialogAlreadyShown: false,
      askToCreate: () async {
        askCount++;
        return true;
      },
      repairOrCreate: () async {
        repairCount++;
        return true;
      },
    );

    expect(askCount, 0);
    expect(repairCount, 1);
    expect(result.feedback, ShortcutStartupFeedback.none);
    expect(result.markDialogShown, isFalse);
  });

  test('仅开始菜单入口存在时不修复也不询问', () async {
    var callbackCount = 0;

    final result = await coordinator.run(
      state: WindowsShortcutEntryState.startMenuOnly,
      dialogAlreadyShown: false,
      askToCreate: () async {
        callbackCount++;
        return true;
      },
      repairOrCreate: () async {
        callbackCount++;
        return true;
      },
    );

    expect(callbackCount, 0);
    expect(result.feedback, ShortcutStartupFeedback.none);
    expect(result.markDialogShown, isFalse);
  });

  test('两个入口均不存在时按用户确认创建并记住已询问', () async {
    var repairCount = 0;

    final result = await coordinator.run(
      state: WindowsShortcutEntryState.none,
      dialogAlreadyShown: false,
      askToCreate: () async => true,
      repairOrCreate: () async {
        repairCount++;
        return true;
      },
    );

    expect(repairCount, 1);
    expect(result.feedback, ShortcutStartupFeedback.created);
    expect(result.markDialogShown, isTrue);
  });

  test('用户明确拒绝后记住本次安装且不创建', () async {
    var repairCount = 0;

    final result = await coordinator.run(
      state: WindowsShortcutEntryState.none,
      dialogAlreadyShown: false,
      askToCreate: () async => false,
      repairOrCreate: () async {
        repairCount++;
        return true;
      },
    );

    expect(repairCount, 0);
    expect(result.feedback, ShortcutStartupFeedback.none);
    expect(result.markDialogShown, isTrue);
  });

  test('询问流程意外结束时不记住并保留重试', () async {
    final result = await coordinator.run(
      state: WindowsShortcutEntryState.none,
      dialogAlreadyShown: false,
      askToCreate: () async => null,
      repairOrCreate: () async => true,
    );

    expect(result.feedback, ShortcutStartupFeedback.none);
    expect(result.markDialogShown, isFalse);
  });

  test('入口检测失败时报告错误且不写已询问状态', () async {
    var callbackCount = 0;

    final result = await coordinator.run(
      state: WindowsShortcutEntryState.unknown,
      dialogAlreadyShown: false,
      askToCreate: () async {
        callbackCount++;
        return true;
      },
      repairOrCreate: () async {
        callbackCount++;
        return true;
      },
    );

    expect(callbackCount, 0);
    expect(result.reportDetectionFailure, isTrue);
    expect(result.markDialogShown, isFalse);
  });

  test('修复和创建失败返回各自的明确反馈', () async {
    final repairResult = await coordinator.run(
      state: WindowsShortcutEntryState.desktopAndStartMenu,
      dialogAlreadyShown: false,
      askToCreate: () async => true,
      repairOrCreate: () async => false,
    );
    final createResult = await coordinator.run(
      state: WindowsShortcutEntryState.none,
      dialogAlreadyShown: false,
      askToCreate: () async => true,
      repairOrCreate: () async => false,
    );

    expect(repairResult.feedback, ShortcutStartupFeedback.repairFailed);
    expect(createResult.feedback, ShortcutStartupFeedback.creationFailed);
    expect(createResult.markDialogShown, isTrue);
  });
}
