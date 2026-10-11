import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/player_bookmark.dart';

void main() {
  test('书签按媒体稳定键保存、合并并限制数量', () async {
    final store = _MemoryBookmarkStore();
    final repository = PlayerBookmarkRepository(store);

    await repository.add('media-1', const Duration(seconds: 10), label: '开场');
    await repository.add('media-1', const Duration(seconds: 11));
    await repository.add('media-2', const Duration(seconds: 10));

    final bookmarks = repository.load('media-1');
    expect(bookmarks, hasLength(1));
    expect(bookmarks.single.position, const Duration(seconds: 11));
    expect(bookmarks.single.label, '开场');
    expect(repository.load('media-2'), hasLength(1));
  });

  test('书签序列化会丢弃无效记录', () {
    final store = _MemoryBookmarkStore()
      ..value = <Object?, Object?>{
        'media-1': <Object?>[
          <Object?, Object?>{'positionMillis': 1000, 'label': '有效'},
          <Object?, Object?>{'positionMillis': -1},
          'broken',
        ],
      };
    final bookmarks = PlayerBookmarkRepository(store).load('media-1');
    expect(bookmarks, hasLength(1));
    expect(bookmarks.single.label, '有效');
  });
}

class _MemoryBookmarkStore implements PlayerBookmarkStorage {
  Object? value;

  @override
  Object? read() => value;

  @override
  Future<void> write(Object value) async {
    this.value = value;
  }
}
