import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kanyingyin/utils/app_identity.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

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
  Future<void>? _brightnessDrain;
  _BrightnessRequest? _pendingBrightness;
  TrayListener? _trayListener;
  WindowListener? _windowListener;
  Brightness? _appliedBrightness;
  int? _appliedBrightnessGeneration;
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

  Future<void> syncBrightness(Brightness brightness) {
    if (_disposed || !_platform.isWindows) return Future<void>.value();
    if (_brightnessDrain == null &&
        _appliedBrightness == brightness &&
        _appliedBrightnessGeneration == _generation) {
      return Future<void>.value();
    }

    _pendingBrightness = _BrightnessRequest(brightness, _generation);
    return _brightnessDrain ??= _drainBrightness();
  }

  Future<void> _drainBrightness() async {
    try {
      while (!_disposed) {
        final request = _pendingBrightness;
        if (request == null) return;
        if (request.generation != _generation) {
          if (identical(_pendingBrightness, request)) {
            _pendingBrightness = null;
          }
          continue;
        }
        if (_appliedBrightness == request.brightness &&
            _appliedBrightnessGeneration == request.generation) {
          if (identical(_pendingBrightness, request)) {
            _pendingBrightness = null;
          }
          continue;
        }

        try {
          await _platform.setBrightness(request.brightness);
          if (!_disposed && request.generation == _generation) {
            _appliedBrightness = request.brightness;
            _appliedBrightnessGeneration = request.generation;
          }
        } catch (error, stackTrace) {
          _onError(error, stackTrace);
        }

        if (identical(_pendingBrightness, request)) {
          _pendingBrightness = null;
        }
      }
    } finally {
      _brightnessDrain = null;
    }
  }

  bool _attachListeners(
    TrayListener trayListener,
    WindowListener windowListener,
  ) {
    var succeeded = true;
    if (_trayListenerAttached && !identical(_trayListener, trayListener)) {
      succeeded &= _removeTrayListener();
    }
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
    if (_windowListenerAttached &&
        !identical(_windowListener, windowListener)) {
      succeeded &= _removeWindowListener();
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
    _pendingBrightness = null;
    _appliedBrightness = null;
    _appliedBrightnessGeneration = null;

    _removeTrayListener();
    _removeWindowListener();
  }

  bool _removeTrayListener() {
    if (!_trayListenerAttached) return true;
    try {
      _platform.removeTrayListener(_trayListener!);
      _trayListenerAttached = false;
      _trayListener = null;
      return true;
    } catch (error, stackTrace) {
      _onError(error, stackTrace);
      return false;
    }
  }

  bool _removeWindowListener() {
    if (!_windowListenerAttached) return true;
    try {
      _platform.removeWindowListener(_windowListener!);
      _windowListenerAttached = false;
      _windowListener = null;
      return true;
    } catch (error, stackTrace) {
      _onError(error, stackTrace);
      return false;
    }
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

class _BrightnessRequest {
  const _BrightnessRequest(this.brightness, this.generation);

  final Brightness brightness;
  final int generation;
}

class _PluginWindowsAppShellPlatform implements WindowsAppShellPlatform {
  final TrayManager _trayManager = TrayManager.instance;

  @override
  bool get isDesktop => true;

  @override
  bool get isWindows => true;

  @override
  bool get isLinux => false;

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
