import 'package:kanyingyin/utils/windows_shortcut.dart';

enum ShortcutStartupDecision {
  repairDesktop,
  askToCreateDesktop,
  skip,
  reportDetectionFailure,
}

ShortcutStartupDecision decideShortcutStartup({
  required WindowsShortcutEntryState state,
  required bool dialogAlreadyShown,
}) {
  return switch (state) {
    WindowsShortcutEntryState.desktopOnly ||
    WindowsShortcutEntryState.desktopAndStartMenu =>
      ShortcutStartupDecision.repairDesktop,
    WindowsShortcutEntryState.startMenuOnly => ShortcutStartupDecision.skip,
    WindowsShortcutEntryState.none when dialogAlreadyShown =>
      ShortcutStartupDecision.skip,
    WindowsShortcutEntryState.none =>
      ShortcutStartupDecision.askToCreateDesktop,
    WindowsShortcutEntryState.unknown =>
      ShortcutStartupDecision.reportDetectionFailure,
  };
}
