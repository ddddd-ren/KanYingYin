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
