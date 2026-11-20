import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/repositories/local_media_tag_repository.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/services/local_media_library_builder.dart';
import 'package:kanyingyin/utils/storage.dart';

LocalMediaIndexItem _item(String source, {int episode = 1}) =>
    LocalMediaIndexItem(
      path: 'D:\\$source\\相同作品.S01E0$episode.mkv',
      name: '相同作品.S01E0$episode.mkv',
      parentPath: 'D:\\$source',
      sourcePath: 'D:\\$source',
      size: 100,
      modified: DateTime(2026),
      seriesName: '相同作品',
      seasonNumber: 1,
      episodeNumber: episode,
      indexedAt: DateTime(2026),
    );

void main() {
  late Directory hiveDirectory;
  late Box<Object?> box;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('local_media_tags_');
    Hive.init(hiveDirectory.path);
    box = await Hive.openBox<Object?>('settings');
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteFromDisk();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('标签按作品持久化、去重并过滤空值和超长值', () async {
    final repository = LocalMediaTagRepository(box: box);
    await repository.saveForSeries('  动画作品  ', <String>[
      ' 收藏 ',
      '收藏',
      '',
      '待看',
      'x' * 33,
    ]);

    expect(repository.getAll(), <String, List<String>>{
      '动画作品': <String>['收藏', '待看'],
    });
    expect(
      box.get(SettingBoxKey.localMediaLibraryTags),
      <String, List<String>>{
        '动画作品': <String>['收藏', '待看']
      },
    );
  });

  test('旧单来源标签迁移后清除不会复活', () async {
    final repository = LocalMediaTagRepository(box: box);
    final item = _item('A');
    final target = const LocalMediaLibraryBuilder().buildSeries([item]).single;
    final legacyKey = target.legacyTitle!.toLowerCase();

    await repository.saveForSeries(legacyKey, ['旧标签']);
    await repository.reconcileSourceKeys({
      target.key: {item.id}
    });
    expect(repository.getAll(), {
      target.key: ['旧标签']
    });

    await repository.saveForSeries(target.key, const []);
    await repository.reconcileSourceKeys({
      target.key: {item.id}
    });
    expect(repository.getAll(), isEmpty);
  });

  test('带来源的旧标题标签仅迁移到唯一匹配作品', () async {
    final repository = LocalMediaTagRepository(box: box);
    final first = _item('A').copyWith(tmdbIdentity: 'tv:11');
    final second = _item('A', episode: 2).copyWith(tmdbIdentity: 'tv:22');
    final series =
        const LocalMediaLibraryBuilder().buildSeries([first, second]);
    final firstKey =
        series.firstWhere((s) => s.episodes.single.id == first.id).key;
    final oldKey =
        '${Uri.encodeComponent(first.sourceLocation.stableId)}|${series.first.legacyTitle!.toLowerCase()}';
    final unmatched =
        const LocalMediaLibraryBuilder().buildSeries([_item('A')]).single;
    await repository.saveForSeries(unmatched.key, ['匹配前标签']);
    await repository.saveForSeries(oldKey, ['资料']);
    await repository.reconcileSourceKeys({
      for (final work in series) work.key: {work.episodes.single.id},
    });
    expect(repository.getAll(), {
      oldKey: ['资料'],
      unmatched.key: ['匹配前标签']
    });
    await repository.reconcileSourceKeys({
      firstKey: {first.id}
    });
    expect(repository.getAll().keys, [firstKey]);
    expect(repository.getAll()[firstKey], unorderedEquals(['资料', '匹配前标签']));
  });

  test('旧拆分键按成员迁移，成员归属有歧义时保留原记录', () async {
    final repository = LocalMediaTagRepository(box: box);
    final first = _item('A');
    final second = _item('B');
    final series = const LocalMediaLibraryBuilder().buildSeries(
      [first, second],
      sourceTitlesByMediaId: {first.id: '目录甲', second.id: '目录乙'},
    );
    final firstSeries = series.singleWhere(
        (item) => item.episodes.any((episode) => episode.id == first.id));
    final legacyKey = '相同作品|source|${first.id}';

    await repository.saveForSeries(legacyKey, ['成员标签']);
    await repository.reconcileSourceKeys({
      for (final item in series)
        item.key: item.episodes.map((episode) => episode.id).toSet(),
    });
    expect(repository.getAll(), {
      firstSeries.key: ['成员标签']
    });

    await repository.saveForSeries(legacyKey, ['歧义标签']);
    await repository.reconcileSourceKeys({
      firstSeries.key: {first.id},
      'other|same': {first.id, second.id},
    });
    expect(repository.getAll(), {
      legacyKey: ['歧义标签'],
      firstSeries.key: ['成员标签']
    });
  });

  test('同名多来源旧标签与超过合并上限的标签保留原记录', () async {
    final repository = LocalMediaTagRepository(box: box);
    await repository.saveForSeries('同名', ['旧标签']);
    await repository.reconcileSourceKeys({
      'sourceA|同名': {'a'},
      'sourceB|同名': {'b'},
    });
    expect(repository.getAll(), {
      '同名': ['旧标签']
    });
    final tags = List.generate(
        LocalMediaTagRepository.maxTagsPerSeries, (index) => '标签$index');
    await repository.saveForSeries('sourceA|同名', tags);
    await repository.reconcileSourceKeys({
      'sourceA|同名': {'a'}
    });
    expect(repository.getAll(), {
      '同名': ['旧标签'],
      'sourceA|同名': tags
    });
  });

  test('保存空标签会移除作品记录', () async {
    final repository = LocalMediaTagRepository(box: box);
    await repository.saveForSeries('作品', const <String>['收藏']);
    await repository.saveForSeries('作品', const <String>[]);

    expect(repository.getAll(), isEmpty);
  });
}
