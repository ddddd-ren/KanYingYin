import 'package:kanyingyin/platform/app_platform.dart';

abstract interface class DesktopWindowPort {
  Future<void> initialize({
    required bool showWindowButtons,
    required bool lowResolution,
  });

  Future<void> showStorageFailureWindow();
}

class AppBootstrap {
  const AppBootstrap({
    required this.capabilities,
    required this.desktopWindow,
  });

  final AppPlatformCapabilities capabilities;
  final DesktopWindowPort desktopWindow;

  Future<void> prepareWindow({
    required bool showWindowButtons,
    required bool lowResolution,
  }) {
    if (!capabilities.desktopShell) return Future<void>.value();
    return desktopWindow.initialize(
      showWindowButtons: showWindowButtons,
      lowResolution: lowResolution,
    );
  }

  Future<void> prepareStorageFailureWindow() {
    if (!capabilities.desktopShell) return Future<void>.value();
    return desktopWindow.showStorageFailureWindow();
  }
}
