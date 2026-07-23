import 'package:kanyingyin/utils/windows_shortcut.dart';

enum ShortcutStartupDecision {
  repairDesktop,
  askToCreateDesktop,
  skip,
  reportDetectionFailure,
}

enum ShortcutStartupFeedback {
  none,
  detectionFailed,
  repairFailed,
  created,
  creationFailed,
}

class ShortcutStartupResult {
  const ShortcutStartupResult({
    required this.markDialogShown,
    required this.feedback,
  });

  final bool markDialogShown;
  final ShortcutStartupFeedback feedback;

  bool get reportDetectionFailure =>
      feedback == ShortcutStartupFeedback.detectionFailed;
}

class WindowsShortcutStartupCoordinator {
  const WindowsShortcutStartupCoordinator();

  Future<ShortcutStartupResult> run({
    required WindowsShortcutEntryState state,
    required bool dialogAlreadyShown,
    required Future<bool?> Function() askToCreate,
    required Future<bool> Function() repairOrCreate,
  }) async {
    final decision = decideShortcutStartup(
      state: state,
      dialogAlreadyShown: dialogAlreadyShown,
    );
    switch (decision) {
      case ShortcutStartupDecision.repairDesktop:
        final success = await repairOrCreate();
        return ShortcutStartupResult(
          markDialogShown: false,
          feedback: success
              ? ShortcutStartupFeedback.none
              : ShortcutStartupFeedback.repairFailed,
        );
      case ShortcutStartupDecision.askToCreateDesktop:
        final create = await askToCreate();
        if (create == null) {
          return const ShortcutStartupResult(
            markDialogShown: false,
            feedback: ShortcutStartupFeedback.none,
          );
        }
        if (!create) {
          return const ShortcutStartupResult(
            markDialogShown: true,
            feedback: ShortcutStartupFeedback.none,
          );
        }
        final success = await repairOrCreate();
        return ShortcutStartupResult(
          markDialogShown: true,
          feedback: success
              ? ShortcutStartupFeedback.created
              : ShortcutStartupFeedback.creationFailed,
        );
      case ShortcutStartupDecision.skip:
        return const ShortcutStartupResult(
          markDialogShown: false,
          feedback: ShortcutStartupFeedback.none,
        );
      case ShortcutStartupDecision.reportDetectionFailure:
        return const ShortcutStartupResult(
          markDialogShown: false,
          feedback: ShortcutStartupFeedback.detectionFailed,
        );
    }
  }
}

ShortcutStartupDecision decideShortcutStartup({
  required WindowsShortcutEntryState state,
  required bool dialogAlreadyShown,
}) {
  return switch (state) {
    WindowsShortcutEntryState.desktopOnly ||
    WindowsShortcutEntryState.desktopAndStartMenu =>
      ShortcutStartupDecision.repairDesktop,
    WindowsShortcutEntryState.startMenuOnly ||
    WindowsShortcutEntryState.none when dialogAlreadyShown =>
      ShortcutStartupDecision.skip,
    WindowsShortcutEntryState.startMenuOnly ||
    WindowsShortcutEntryState.none =>
      ShortcutStartupDecision.askToCreateDesktop,
    WindowsShortcutEntryState.unknown =>
      ShortcutStartupDecision.reportDetectionFailure,
  };
}
