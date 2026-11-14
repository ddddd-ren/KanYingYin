import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';

void main() {
  test('同名跨本地来源保留独立身份及各自集数', () {
    final first = localItem('A');
    final second = localItem('B');
    final library = localLibrary([first, second, localItem('A', episode: 2)]);
    expect(library.series, hasLength(2));
    expect(library.series.map((s) => s.key).toSet(), hasLength(2));
    expect(
        library.series.every((s) =>
            s.episodes.map((e) => e.localItem!.sourcePath).toSet().length == 1),
        isTrue);
    expect(
        library.series.map((s) => s.episodes.length), unorderedEquals([1, 2]));
    expect(library.series.expand((s) => s.episodes).map((e) => e.stableId),
        containsAll([first.id, second.id]));
  });

  test('旧单来源标记按成员迁移，混合来源记录保留待关联且重建仓库后仍在', () async {
    final first = localItem('A');
    final second = localItem('B');
    final storage = MemoryMediaLibraryUserStateStorage();
    final repository = MediaLibraryUserStateRepository(storage: storage);
    await repository.save(
        'old-single',
        MediaLibraryUserState(
            favorite: true,
            watchLater: true,
            collections: const ['周末'],
            mediaIds: [first.id],
            categoryOverride: const ['电视剧']));
    await repository.save('old-mixed',
        MediaLibraryUserState(favorite: true, mediaIds: [first.id, second.id]));
    final series = localLibrary([first, second]).series;
    await repository.reconcile({
      for (final s in series) s.key: s.episodes.map((e) => e.stableId).toSet()
    });
    final restored = MediaLibraryUserStateRepository(storage: storage);
    final all = await restored.getAll();
    final target = series
        .singleWhere((s) => s.episodes.any((e) => e.stableId == first.id));
    expect(all.containsKey('old-single'), isFalse);
    expect(all['old-mixed']?.favorite, isTrue);
    expect(all[target.key]?.watchLater, isTrue);
    expect(all[target.key]?.collections, ['周末']);
    await restored.save(target.key, all[target.key]!.copyWith(favorite: false),
        preserveClassification: true);
    final saved = (await repository.get(target.key))!;
    expect(saved.favorite, isFalse);
    expect(saved.watchLater, isTrue);
    expect(saved.collections, ['周末']);
    expect(saved.categoryOverride, ['电视剧']);
  });
}

LocalMediaIndexItem localItem(String source,
        {int season = 1, int episode = 1}) =>
    LocalMediaIndexItem(
      path: 'D:\\$source\\相同作品.S0${season}E0$episode.mkv',
      name: '相同作品.S0${season}E0$episode.mkv',
      parentPath: 'D:\\$source',
      sourcePath: 'D:\\$source',
      size: 100,
      modified: DateTime(2026),
      indexedAt: DateTime(2026),
      seriesName: '相同作品',
      seasonNumber: season,
      episodeNumber: episode,
    );

CloudMediaLibrary localLibrary(List<LocalMediaIndexItem> items) =>
    const CloudMediaLibraryAggregator()
        .build(localItems: items, cloudItems: [], cloudSources: []);
