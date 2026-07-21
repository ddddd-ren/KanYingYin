import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum WindowsShortcutEntryState {
  none,
  desktopOnly,
  startMenuOnly,
  desktopAndStartMenu,
  unknown,
}

class WindowsShortcutClient {
  const WindowsShortcutClient({required MethodChannel channel})
      : _channel = channel;

  final MethodChannel _channel;

  Future<WindowsShortcutEntryState> inspectShortcutEntries() async {
    try {
      final value = await _channel.invokeMethod<int>('inspectShortcutEntries');
      return switch (value) {
        0 => WindowsShortcutEntryState.none,
        1 => WindowsShortcutEntryState.desktopOnly,
        2 => WindowsShortcutEntryState.startMenuOnly,
        3 => WindowsShortcutEntryState.desktopAndStartMenu,
        _ => WindowsShortcutEntryState.unknown,
      };
    } catch (_) {
      debugPrint('快捷方式状态检测失败');
      return WindowsShortcutEntryState.unknown;
    }
  }

  Future<bool> createDesktopShortcut() async {
    try {
      return await _channel.invokeMethod<bool>('createDesktopShortcut') ??
          false;
    } catch (_) {
      debugPrint('桌面快捷方式创建失败');
      return false;
    }
  }
}

class WindowsShortcut {
  static const _channel = MethodChannel('com.kanyingyin.player/shortcut');
  static const _client = WindowsShortcutClient(channel: _channel);

  static Future<WindowsShortcutEntryState> inspectShortcutEntries() {
    if (!Platform.isWindows) {
      return Future<WindowsShortcutEntryState>.value(
        WindowsShortcutEntryState.unknown,
      );
    }
    return _client.inspectShortcutEntries();
  }

  static Future<bool> desktopShortcutExists() async {
    final state = await inspectShortcutEntries();
    return state == WindowsShortcutEntryState.desktopOnly ||
        state == WindowsShortcutEntryState.desktopAndStartMenu;
  }

  static Future<bool> createDesktopShortcut() {
    if (!Platform.isWindows) return Future<bool>.value(false);
    return _client.createDesktopShortcut();
  }
}
