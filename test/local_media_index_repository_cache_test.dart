import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';

void main() {
  test('重复查询复用不可变索引快照且只读取存储一次', () {
    final storage = _CountingStorage(<String, Object?>{
      SettingBoxKey.localMediaIndex: [_item().toJson()],
    });
    final repository = LocalMediaIndexRepository(storage: storage);

    final first = repository.getAll();
    final second = repository.getAll();

    expect(storage.readCountFor(SettingBoxKey.localMediaIndex), 1);
    expect(identical(first, second), isTrue);
    expect(
      () => first.add(_item(path: r'D:\Media\Other.mkv')),
      throwsUnsupportedError,
    );
  });

  test('更新与清空同步刷新缓存且不会重新读取索引存储', () async {
    final storage = _CountingStorage(<String, Object?>{
      SettingBoxKey.localMediaIndex: [_item().toJson()],
    });
    final repository = LocalMediaIndexRepository(storage: storage);
    repository.getAll();

    await repository.updateItem(_item().copyWith(seriesName: '新标题'));
    expect(repository.getAll().single.seriesName, '新标题');
    expect(storage.readCountFor(SettingBoxKey.localMediaIndex), 1);

    await repository.clear();
    expect(repository.getAll(), isEmpty);
    expect(storage.readCountFor(SettingBoxKey.localMediaIndex), 1);
  });
}

LocalMediaIndexItem _item({String path = r'D:\Media\Movie.mkv'}) {
  return LocalMediaIndexItem(
    path: path,
    name: path.split(r'\').last,
    parentPath: r'D:\Media',
    sourcePath: r'D:\Media',
    size: 100,
    modified: DateTime(2026, 7, 24),
    seriesName: '影片',
    indexedAt: DateTime(2026, 7, 24),
  );
}

class _CountingStorage implements LocalMediaIndexStorage {
  _CountingStorage(this.values);

  final Map<String, Object?> values;
  final Map<String, int> _reads = {};

  int readCountFor(String key) => _reads[key] ?? 0;

  @override
  Object? read(String key, {Object? defaultValue}) {
    _reads.update(key, (count) => count + 1, ifAbsent: () => 1);
    return values[key] ?? defaultValue;
  }

  @override
  Future<void> write(String key, Object? value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
