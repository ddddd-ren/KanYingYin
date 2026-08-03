import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/platform/app_platform.dart';

SystemUiOverlayStyle androidAppSystemUiStyle(Brightness brightness) {
  final iconBrightness =
      brightness == Brightness.light ? Brightness.dark : Brightness.light;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: iconBrightness,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: iconBrightness,
    systemNavigationBarContrastEnforced: false,
  );
}

const SystemUiOverlayStyle androidPlaybackSystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
);

class AndroidSystemUiSurface extends StatelessWidget {
  const AndroidSystemUiSurface({
    super.key,
    required this.capabilities,
    required this.child,
  });

  final AppPlatformCapabilities capabilities;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!capabilities.isAndroid) return child;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      key: const ValueKey('android-app-system-ui'),
      value: androidAppSystemUiStyle(Theme.of(context).brightness),
      child: ColoredBox(
        key: const ValueKey('android-app-system-ui-background'),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: child,
      ),
    );
  }
}

class AndroidPlaybackSystemUiSurface extends StatelessWidget {
  const AndroidPlaybackSystemUiSurface({
    super.key,
    required this.capabilities,
    required this.child,
  });

  final AppPlatformCapabilities capabilities;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!capabilities.isAndroid) return child;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      key: const ValueKey('android-player-system-ui'),
      value: androidPlaybackSystemUiStyle,
      child: ColoredBox(
        key: const ValueKey('android-player-system-ui-background'),
        color: Colors.black,
        child: child,
      ),
    );
  }
}
