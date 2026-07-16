import 'package:kanyingyin/utils/storage.dart';
import 'package:path/path.dart' as p;

abstract class ILocalSeriesTitleOverrideRepository {
  String? getForDirectory(String directoryPath);

  Future<void> saveForDirectories(
    Iterable<String> directoryPaths,
    String title,
  );
}

class LocalSeriesTitleOverrideRepository
    implements ILocalSeriesTitleOverrideRepository {
  @override
  String? getForDirectory(String directoryPath) {
    final title = _read()[_idForPath(directoryPath)]?.trim();
    return title == null || title.isEmpty ? null : title;
  }

  @override
  Future<void> saveForDirectories(
    Iterable<String> directoryPaths,
    String title,
  ) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) return;

    final next = _read();
    for (final directoryPath in directoryPaths) {
      next[_idForPath(directoryPath)] = normalizedTitle;
    }
    await GStorage.setting.put(SettingBoxKey.localSeriesTitleOverrides, next);
  }

  Map<String, String> _read() {
    try {
      final value = GStorage.setting.get(
        SettingBoxKey.localSeriesTitleOverrides,
        defaultValue: const <String, String>{},
      );
      if (value is! Map) return <String, String>{};
      return value.map(
        (key, title) => MapEntry(key.toString(), title.toString()),
      );
    } catch (_) {
      return <String, String>{};
    }
  }

  String _idForPath(String path) => p.normalize(path).toLowerCase();
}
