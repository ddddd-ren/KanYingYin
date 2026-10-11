import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_watch_state.dart';
import 'package:kanyingyin/features/player/application/player_bookmark.dart';

void main() {
  test('临近末尾不推断已看，真实完播持久保存且重播不清除', () async {
    final storage = _Storage();
    final repo = MediaWatchStateRepository(storage);
    await repo.record('local|a',
        position: const Duration(seconds: 98),
        duration: const Duration(seconds: 100),
        completed: false);
    expect(repo.loadAll()['local|a']!.watched, isFalse);
    await repo.record('local|a',
        position: const Duration(seconds: 100),
        duration: const Duration(seconds: 100),
        completed: true);
    await repo.record('local|a',
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 100),
        completed: false);
    expect(MediaWatchStateRepository(storage).loadAll()['local|a']!.watched,
        isTrue);
    await repo.setWatched(['local|a'], false);
    expect(repo.loadAll()['local|a']!.progress, 0);
    expect(repo.loadAll()['local|a']!.watched, isFalse);
  });
  test('并发手动标记不丢失且不限制为历史的一百项', () async {
    final repo = MediaWatchStateRepository(_Storage());
    await Future.wait(
        List.generate(105, (i) => repo.setWatched(['source|$i'], true)));
    expect(repo.loadAll(), hasLength(105));
    expect(mediaWatchKey(localPath: r'D:\Videos\A.mkv'),
        'local|d:\\videos\\a.mkv');
    expect(mediaWatchKey(sourceId: 'disk', remoteId: 'file'), 'disk|file');
  });
}

class _Storage implements PlayerBookmarkStorage {
  Object? value;
  @override
  Object? read() => value;
  @override
  Future<void> write(Object value) async {
    this.value = value;
  }
}
