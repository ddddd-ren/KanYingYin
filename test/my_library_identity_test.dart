import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_user_data.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';

void main() {
  test('同一本地来源内两部同名重拍版有独立稳定的收藏身份', () async {
    final first = localItem('媒体', episode: 1).copyWith(tmdbIdentity: 'tv:11');
    final second = localItem('媒体', episode: 2).copyWith(tmdbIdentity: 'tv:22');
    final together = localLibrary([first, second]).series;
    expect(together, hasLength(2));
    final firstKey = localLibrary([first]).series.single.key;
    final secondKey = localLibrary([second]).series.single.key;
    expect(firstKey, isNot(secondKey));
    for (final order in [
      [first, second],
      [second, first]
    ]) {
      final byId = {
        for (final s in localLibrary(order).series)
          s.episodes.single.stableId: s.key
      };
      expect(byId, {first.id: firstKey, second.id: secondKey});
    }
    final legacy =
        'local|${Uri.encodeComponent(first.sourceLocation.stableId)}|相同作品 s01';
    final repo = MediaLibraryUserStateRepository(
        storage: MemoryMediaLibraryUserStateStorage());
    await repo.save(
        legacy, MediaLibraryUserState(favorite: true, mediaIds: [second.id]));
    final ids = {
      for (final s in together) s.key: s.episodes.map((e) => e.stableId).toSet()
    };
    final states = await repo.reconcile(ids);
    expect(states.keys, [secondKey]);
    expect(states[secondKey]?.favorite, isTrue);
    await repo.save(
        legacy,
        MediaLibraryUserState(
            watchLater: true, mediaIds: [first.id, second.id]));
    expect((await repo.reconcile(ids))[legacy]?.watchLater, isTrue);
  });

  test('未识别剧集不能把两个不同 TMDB 身份的分组合在一起', () {
    final unknown = localItem('媒体');
    final a = localItem('媒体', episode: 2).copyWith(tmdbIdentity: 'tv:11');
    final b = localItem('媒体', episode: 3).copyWith(tmdbIdentity: 'tv:22');
    final series = localLibrary([unknown, a, b]).series;
    expect(series, hasLength(2));
    for (final work in series) {
      final identities = work.episodes
          .map((e) => e.localItem!.effectiveTmdbIdentity)
          .whereType<String>()
          .toSet();
      expect(identities, hasLength(1));
    }
  });

  test('备份换目录后，即使原目录仍在索引中也只关联到所选目录', () async {
    final old = localItem('旧目录').copyWith(tmdbIdentity: 'tv:11');
    final target = localItem('新目录').copyWith(tmdbIdentity: 'tv:11');
    final oldKey = localLibrary([old]).series.single.key;
    final targetKey = localLibrary([target]).series.single.key;
    final backup = PortableUserData(states: {
      oldKey: MediaLibraryUserState(favorite: true, mediaIds: [old.id]),
    });
    final restored =
        backup.remap(localRoots: {old.sourcePath: target.sourcePath});
    final repo = MediaLibraryUserStateRepository(
        storage: MemoryMediaLibraryUserStateStorage());
    await repo.replaceAll(restored.states);
    final states = await repo.reconcile({
      oldKey: {old.id},
      targetKey: {target.id}
    });
    expect(states.keys, [targetKey]);
    expect(states[targetKey]?.favorite, isTrue);
    expect(states[targetKey]?.mediaIds, [target.id]);
    expect(backup.states.keys, [oldKey]);
  });

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
    await restored
        .updateMarks(target.key, favorite: false, mediaIds: [first.id]);
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
