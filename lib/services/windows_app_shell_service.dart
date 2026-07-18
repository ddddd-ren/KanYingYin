import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kanyingyin/utils/app_identity.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

const Color _fallbackThemeColor = Color(0xFF00D4AA);

Color parseStoredThemeColor(Object? storedValue) {
  if (storedValue == null || storedValue == 'default') {
    return _fallbackThemeColor;
  }

  int? colorValue;
  if (storedValue is int) {
    colorValue = storedValue;
  } else if (storedValue is String) {
    final normalized = storedValue.trim().replaceFirst(
          RegExp(r'^0x', caseSensitive: false),
          '',
        );
    colorValue = int.tryParse(normalized, radix: 16);
  }

  if (colorValue == null || colorValue < 0 || colorValue > 0xFFFFFFFF) {
    return _fallbackThemeColor;
  }
  return Color(colorValue);
}

class TrayMenuEntry {
  const TrayMenuEntry({required this.key, required this.label})
      : isSeparator = false;

  const TrayMenuEntry.separator()
      : key = null,
        label = null,
        isSeparator = true;

  final String? key;
  final String? label;
  final bool isSeparator;

  @override
  bool operator ==(Object other) =>
      other is TrayMenuEntry &&
      other.key == key &&
      other.label == label &&
      other.isSeparator == isSeparator;

  @override
  int get hashCode => Object.hash(key, label, isSeparator);
}

abstract interface class WindowsAppShellPlatform {
  bool get isDesktop;
  bool get isWindows;
  bool get isLinux;

  void addTrayListener(TrayListener listener);
  void removeTrayListener(TrayListener listener);
  void addWindowListener(WindowListener listener);
  void removeWindowListener(WindowListener listener);
  Future<void> setPreventClose();
  Future<void> setTrayIcon(String iconPath);
  Future<void> setTrayTooltip(String tooltip);
  Future<void> setTrayMenu(List<TrayMenuEntry> items);
  Future<void> setBrightness(Brightness brightness);
}

class WindowsAppShellService {
  WindowsAppShellService({WindowsAppShellPlatform? platform})
      : _platform = platform ?? _PluginWindowsAppShellPlatform();

  final WindowsAppShellPlatform _platform;
  Future<void>? _initialization;
  TrayListener? _trayListener;
  WindowListener? _windowListener;
  Brightness? _lastBrightness;
  bool _listenersAttached = false;
  bool _disposed = false;

  Future<void> initialize({
    required TrayListener trayListener,
    required WindowListener windowListener,
  }) {
    if (_disposed || !_platform.isDesktop) return Future<void>.value();
    return _initialization ??= _initialize(trayListener, windowListener);
  }

  Future<void> _initialize(
    TrayListener trayListener,
    WindowListener windowListener,
  ) async {
    _trayListener = trayListener;
    _windowListener = windowListener;
    _platform.addTrayListener(trayListener);
    _platform.addWindowListener(windowListener);
    _listenersAttached = true;

    await _platform.setPreventClose();
    if (_disposed) return;

    final iconPath = _platform.isWindows
        ? 'assets/images/logo/logo_lanczos.ico'
        : Platform.environment.containsKey('FLATPAK_ID') ||
                Platform.environment.containsKey('SNAP')
            ? 'com.kanyingyin.player'
            : 'assets/images/logo/logo_rounded.png';
    await _platform.setTrayIcon(iconPath);
    if (_disposed) return;

    if (!_platform.isLinux) {
      await _platform.setTrayTooltip(AppIdentity.displayName);
      if (_disposed) return;
    }

    await _platform.setTrayMenu(const [
      TrayMenuEntry(key: 'show_window', label: '显示窗口'),
      TrayMenuEntry.separator(),
      TrayMenuEntry(key: 'exit', label: '退出看影音'),
    ]);
  }

  Future<void> syncBrightness(Brightness brightness) async {
    if (_disposed || !_platform.isWindows || _lastBrightness == brightness) {
      return;
    }
    _lastBrightness = brightness;
    await _platform.setBrightness(brightness);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (!_listenersAttached) return;

    _platform.removeTrayListener(_trayListener!);
    _platform.removeWindowListener(_windowListener!);
    _listenersAttached = false;
  }
}

class _PluginWindowsAppShellPlatform implements WindowsAppShellPlatform {
  final TrayManager _trayManager = TrayManager.instance;

  @override
  bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  bool get isWindows => Platform.isWindows;

  @override
  bool get isLinux => Platform.isLinux;

  @override
  void addTrayListener(TrayListener listener) =>
      _trayManager.addListener(listener);

  @override
  void removeTrayListener(TrayListener listener) =>
      _trayManager.removeListener(listener);

  @override
  void addWindowListener(WindowListener listener) =>
      windowManager.addListener(listener);

  @override
  void removeWindowListener(WindowListener listener) =>
      windowManager.removeListener(listener);

  @override
  Future<void> setPreventClose() => windowManager.setPreventClose(true);

  @override
  Future<void> setTrayIcon(String iconPath) => _trayManager.setIcon(iconPath);

  @override
  Future<void> setTrayTooltip(String tooltip) =>
      _trayManager.setToolTip(tooltip);

  @override
  Future<void> setTrayMenu(List<TrayMenuEntry> items) {
    final menu = Menu(
      items: items
          .map(
            (item) => item.isSeparator
                ? MenuItem.separator()
                : MenuItem(key: item.key, label: item.label),
          )
          .toList(),
    );
    return _trayManager.setContextMenu(menu);
  }

  @override
  Future<void> setBrightness(Brightness brightness) =>
      windowManager.setBrightness(brightness);
}
