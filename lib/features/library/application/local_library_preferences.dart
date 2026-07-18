import 'dart:async';

import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/utils/storage.dart';

abstract interface class ILocalLibraryPreferences {
  String get lastLocalDirectory;
  String get defaultPath;
  List<String> get recentDirectories;

  Future<void> saveLastLocalDirectory(String path);
  Future<void> saveDefaultPath(String path);
  Future<void> saveRecentDirectories(List<String> paths);
}

final class LocalLibraryPreferences implements ILocalLibraryPreferences {
  LocalLibraryPreferences({Box<dynamic>? box}) : _providedBox = box;

  static const int maxRecentDirectories = 10;

  final Box<dynamic>? _providedBox;

  Box<dynamic> get _box => _providedBox ?? GStorage.setting;

  @override
  String get lastLocalDirectory => _readPath(SettingBoxKey.lastLocalDirectory);

  @override
  String get defaultPath => _readPath(SettingBoxKey.localDefaultPath);

  @override
  List<String> get recentDirectories {
    final value = _box.get(
      SettingBoxKey.localRecentDirectories,
      defaultValue: const <String>[],
    );
    return value is List ? normalizeRecentDirectories(value) : const <String>[];
  }

  @override
  Future<void> saveLastLocalDirectory(String path) {
    return _box.put(SettingBoxKey.lastLocalDirectory, path.trim());
  }

  @override
  Future<void> saveDefaultPath(String path) {
    return _box.put(SettingBoxKey.localDefaultPath, path.trim());
  }

  @override
  Future<void> saveRecentDirectories(List<String> paths) {
    return _box.put(
      SettingBoxKey.localRecentDirectories,
      normalizeRecentDirectories(paths),
    );
  }

  String _readPath(String key) {
    final value = _box.get(key, defaultValue: '');
    return value is String ? value.trim() : '';
  }

  static List<String> normalizeRecentDirectories(Iterable<Object?> values) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final value in values) {
      if (value is! String) continue;
      final path = value.trim();
      if (path.isEmpty || !seen.add(path)) continue;
      normalized.add(path);
      if (normalized.length == maxRecentDirectories) break;
    }
    return normalized;
  }
}

/// 为不需要初始化 Hive 的调用方提供强类型适配器。
final class CallbackLocalLibraryPreferences
    implements ILocalLibraryPreferences {
  CallbackLocalLibraryPreferences({
    String Function()? loadLastLocalDirectory,
    String Function()? loadDefaultPath,
    List<String> Function()? loadRecentDirectories,
    FutureOr<void> Function(String path)? saveLastLocalDirectory,
    FutureOr<void> Function(String path)? saveDefaultPath,
    FutureOr<void> Function(List<String> paths)? saveRecentDirectories,
  })  : _loadLastLocalDirectory = loadLastLocalDirectory ?? _emptyPath,
        _loadDefaultPath = loadDefaultPath ?? _emptyPath,
        _loadRecentDirectories =
            loadRecentDirectories ?? _emptyRecentDirectories,
        _saveLastLocalDirectory = saveLastLocalDirectory ?? _ignorePath,
        _saveDefaultPath = saveDefaultPath ?? _ignorePath,
        _saveRecentDirectories =
            saveRecentDirectories ?? _ignoreRecentDirectories;

  final String Function() _loadLastLocalDirectory;
  final String Function() _loadDefaultPath;
  final List<String> Function() _loadRecentDirectories;
  final FutureOr<void> Function(String path) _saveLastLocalDirectory;
  final FutureOr<void> Function(String path) _saveDefaultPath;
  final FutureOr<void> Function(List<String> paths) _saveRecentDirectories;

  @override
  String get lastLocalDirectory => _loadLastLocalDirectory().trim();

  @override
  String get defaultPath => _loadDefaultPath().trim();

  @override
  List<String> get recentDirectories =>
      LocalLibraryPreferences.normalizeRecentDirectories(
        _loadRecentDirectories(),
      );

  @override
  Future<void> saveLastLocalDirectory(String path) async {
    await _saveLastLocalDirectory(path.trim());
  }

  @override
  Future<void> saveDefaultPath(String path) async {
    await _saveDefaultPath(path.trim());
  }

  @override
  Future<void> saveRecentDirectories(List<String> paths) async {
    await _saveRecentDirectories(
      LocalLibraryPreferences.normalizeRecentDirectories(paths),
    );
  }

  static String _emptyPath() => '';
  static List<String> _emptyRecentDirectories() => const <String>[];
  static void _ignorePath(String _) {}
  static void _ignoreRecentDirectories(List<String> _) {}
}
