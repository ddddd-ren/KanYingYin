import 'package:flutter/material.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/windows/windows_app_shell_host.dart';

class AppShellHost extends StatelessWidget {
  const AppShellHost({
    super.key,
    required this.capabilities,
    required this.child,
  });

  final AppPlatformCapabilities capabilities;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!capabilities.desktopShell) return child;
    return WindowsAppShellHost(
      key: const ValueKey('desktop-app-shell'),
      child: child,
    );
  }
}
