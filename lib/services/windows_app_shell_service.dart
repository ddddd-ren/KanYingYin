import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kanyingyin/utils/app_identity.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

const Color _fallbackThemeColor = Color(0xFF00D4AA);

/// 解析应用壳持久化的主题配置，不访问平台或存储。
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
  WindowsAppShellService({
    WindowsAppShellPlatform? platform,
    void Function(Object error, StackTrace stackTrace)? onError,
  })  : _platform = platform ?? _PluginWindowsAppShellPlatform(),
        _onError = onError ?? _logError;

  final WindowsAppShellPlatform _platform;
  final void Function(Object error, StackTrace stackTrace) _onError;
  Future<void>? _initialization;
  TrayListener? _trayListener;
  WindowListener? _windowListener;
  Brightness? _lastBrightness;
  bool _trayListenerAttached = false;
  bool _windowListenerAttached = false;
  bool _initialized = false;
  bool _disposed = false;
  int _generation = 0;

  Future<void> initialize({
    required TrayListener trayListener,
    required WindowListener windowListener,
  }) {
    if (_disposed || !_platform.isDesktop) return Future<void>.value();
    if (_initialized) return Future<void>.value();
    final initialization = _initialization;
    if (initialization != null) return initialization;

    final generation = _generation;
    final nextInitialization =
        _initialize(trayListener, windowListener, generation);
    _initialization = nextInitialization;
    return nextInitialization;
  }

  Future<void> _initialize(
    TrayListener trayListener,
    WindowListener windowListener,
    int generation,
  ) async {
    var succeeded = _attachListeners(trayListener, windowListener);

    try {
      succeeded &= await _runCapability(
        generation,
        _platform.setPreventClose,
      );
      if (!_isActive(generation)) return;

      final iconPath = _platform.isWindows
          ? 'assets/images/logo/logo_lanczos.ico'
          : Platform.environment.containsKey('FLATPAK_ID') ||
                  Platform.environment.containsKey('SNAP')
              ? 'com.kanyingyin.player'
              : 'assets/images/logo/logo_rounded.png';
      succeeded &= await _runCapability(
        generation,
        () => _platform.setTrayIcon(iconPath),
      );
      if (!_isActive(generation)) return;

      if (!_platform.isLinux) {
        succeeded &= await _runCapability(
          generation,
          () => _platform.setTrayTooltip(AppIdentity.displayName),
        );
        if (!_isActive(generation)) return;
      }

      succeeded &= await _runCapability(
        generation,
        () => _platform.setTrayMenu(const [
          TrayMenuEntry(key: 'show_window', label: '显示窗口'),
          TrayMenuEntry.separator(),
          TrayMenuEntry(key: 'exit', label: '退出看影音'),
        ]),
      );
      if (_isActive(generation)) _initialized = succeeded;
    } finally {
      if (_generation == generation) _initialization = null;
    }
  }

  Future<void> syncBrightness(Brightness brightness) async {
    if (_disposed || !_platform.isWindows || _lastBrightness == brightness) {
      return;
    }
    try {
      await _platform.setBrightness(brightness);
      if (!_disposed) _lastBrightness = brightness;
    } catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  bool _attachListeners(
    TrayListener trayListener,
    WindowListener windowListener,
  ) {
    var succeeded = true;
    if (!_trayListenerAttached) {
      try {
        _platform.addTrayListener(trayListener);
        _trayListener = trayListener;
        _trayListenerAttached = true;
      } catch (error, stackTrace) {
        succeeded = false;
        _onError(error, stackTrace);
      }
    }
    if (!_windowListenerAttached) {
      try {
        _platform.addWindowListener(windowListener);
        _windowListener = windowListener;
        _windowListenerAttached = true;
      } catch (error, stackTrace) {
        succeeded = false;
        _onError(error, stackTrace);
      }
    }
    return succeeded;
  }

  Future<bool> _runCapability(
    int generation,
    Future<void> Function() capability,
  ) async {
    if (!_isActive(generation)) return false;
    try {
      await capability();
      return _isActive(generation);
    } catch (error, stackTrace) {
      _onError(error, stackTrace);
      return false;
    }
  }

  bool _isActive(int generation) => !_disposed && _generation == generation;

  void detach() {
    _generation++;
    _initialized = false;
    _initialization = null;

    if (_trayListenerAttached) {
      _trayListenerAttached = false;
      try {
        _platform.removeTrayListener(_trayListener!);
      } catch (error, stackTrace) {
        _onError(error, stackTrace);
      }
    }
    if (_windowListenerAttached) {
      _windowListenerAttached = false;
      try {
        _platform.removeWindowListener(_windowListener!);
      } catch (error, stackTrace) {
        _onError(error, stackTrace);
      }
    }
    _trayListener = null;
    _windowListener = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    detach();
  }

  static void _logError(Object error, StackTrace stackTrace) {
    AppLogger().e(
      'Windows app shell capability failed',
      error: error,
      stackTrace: stackTrace,
    );
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
