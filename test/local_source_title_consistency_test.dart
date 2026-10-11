import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';
import 'package:kanyingyin/features/library/application/media_watch_state.dart';
import 'package:kanyingyin/features/player/application/player_bookmark.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/local/local_series_detail_page.dart';
import 'package:kanyingyin/repositories/local_series_title_override_repository.dart';
import 'package:kanyingyin/services/local_media_library_builder.dart';
import 'package:kanyingyin/services/tmdb/tmdb_episode_title_resolver.dart';

void main() {
  test('不同目录的长剧名前缀不能被另一目录的短剧名覆盖', () {
    final short = _item('光阴之外');
    final long = _item('光阴之外续章');
    final controller = LocalController(
      seriesTitleOverrideRepository: _TitleOverrides(),
    )..localLibraryItems.addAll([short, long]);

    expect(controller.localSourceTitlesByMediaId[short.id], '光阴之外 S01');
    expect(controller.localSourceTitlesByMediaId[long.id], '光阴之外续章 S01');
    expect(controller.localMediaLibrary.series.map((item) => item.title).toSet(),
        {'光阴之外 S01', '光阴之外续章 S01'});
  });

  test('同目录不同原始作品共享旧剧名时不自动迁移偏好别名', () {
    LocalMediaIndexItem inSharedDirectory(String title) {
      final item = _item(title);
      return item.copyWith(
        path: 'D:\\Media\\共享目录\\${item.name}',
        parentPath: r'D:\Media\共享目录',
      );
    }
    final first = inSharedDirectory('作品甲');
    final second = inSharedDirectory('作品乙');
    final controller = LocalController(
      seriesTitleOverrideRepository: _TitleOverrides(),
    )..localLibraryItems.addAll([first, second]);
    final aliases = controller.localLegacySeriesTitlesByMediaId;

    expect(aliases[first.id], isNot(contains('TMDB 另一个剧名')));
    expect(aliases[second.id], isNot(contains('TMDB 另一个剧名')));
    expect(aliases[first.id], isNot(contains('索引中的剧名 S01')));
    expect(aliases[second.id], isNot(contains('索引中的剧名 S01')));
    expect(controller.localMediaLibrary.series.single.legacySeriesTitles,
        isEmpty);
    expect(aliases[first.id], isEmpty);
    expect(aliases[second.id], contains('作品乙 S01'));
  });

  test('不同目录中的相同旧剧名仍可分别兼容各自偏好', () {
    final first = _item('作品甲');
    final second = _item('作品乙');
    final controller = LocalController(
      seriesTitleOverrideRepository: _TitleOverrides(),
    )..localLibraryItems.addAll([first, second]);
    final aliases = controller.localLegacySeriesTitlesByMediaId;

    expect(aliases[first.id], contains('TMDB 另一个剧名'));
    expect(aliases[second.id], contains('TMDB 另一个剧名'));
    for (final series in controller.localMediaLibrary.series) {
      expect(series.legacySeriesTitles, contains('TMDB 另一个剧名'));
    }
  });

  test('未进入来源目录时分类媒体库也继承来源剧名，身份保持不变', () {
    final indexed = _item('来源剧名');
    final controller = LocalController(
      seriesTitleOverrideRepository: _TitleOverrides(),
    )..localLibraryItems.add(indexed);
    final original = const LocalMediaLibraryBuilder().buildSeries([indexed]);

    expect(controller.items, isEmpty);
    expect(controller.localSourceTitlesByMediaId[indexed.id], '来源剧名 S01');
    expect(controller.localLibrarySeries.single.title, '来源剧名 S01');
    expect(controller.localLibrarySeries.single.key, original.single.key);
    final series = controller.localMediaLibrary.series.single;
    expect(series.title, '来源剧名 S01');
    expect(series.tmdbTitle, 'TMDB 另一个剧名');
    expect(series.legacySeriesTitles,
        containsAll([original.single.title, 'TMDB 另一个剧名', '来源剧名 S01']));
    expect(series.episodes.single.stableId, indexed.id);
    expect(series.episodes.single.localItem, same(indexed));
  });

  test('来源手工改名和合法季名重启后仍原样继承', () async {
    final indexed = _item('来源剧名', season: 2);
    final overrides = _TitleOverrides();
    await overrides.saveForDirectories([indexed.parentPath], '我的剧名 第 2 季');
    final restored = LocalMediaIndexItem.fromJson(indexed.toJson());
    final controller = LocalController(
      seriesTitleOverrideRepository: overrides,
    )..localLibraryItems.add(restored);

    expect(controller.items, isEmpty);
    expect(controller.localMediaLibrary.series.single.title, '我的剧名 第 2 季');
    expect(controller.localLibrarySeries.single.displayTitle, '我的剧名 第 2 季');
    expect(controller.localMediaLibrary.series.single.episodes.single.stableId,
        indexed.id);
  });

  test('旧索引组含不同来源名称时拆分展示，收藏和进度记录保留', () async {
    final first = _item('作品甲');
    final second = _item('作品乙', episode: 2);
    final old = const LocalMediaLibraryBuilder().buildSeries([first, second]);
    expect(old, hasLength(1));
    final userState = MediaLibraryUserStateRepository(
      storage: MemoryMediaLibraryUserStateStorage(),
    );
    await userState.save(
      'local|${old.single.key}',
      MediaLibraryUserState(favorite: true, mediaIds: [first.id, second.id]),
    );
    final watchState = MediaWatchStateRepository(_WatchStorage());
    await watchState.record(
      mediaWatchKey(localPath: first.path),
      position: const Duration(minutes: 3),
      duration: const Duration(minutes: 20),
      completed: false,
    );
    final controller = LocalController(
      seriesTitleOverrideRepository: _TitleOverrides(),
    )..localLibraryItems.addAll([first, second]);
    final series = controller.localMediaLibrary.series;

    expect(series.map((item) => item.title).toSet(), {'作品甲 S01', '作品乙 S01'});
    expect(series.map((item) => item.key).toSet(), hasLength(2));
    expect(series.expand((item) => item.episodes).map((item) => item.stableId)
        .toSet(), {first.id, second.id});
    final states = await userState.reconcile({
      for (final item in series)
        item.key: item.episodes.map((episode) => episode.stableId).toSet(),
    });
    expect(states['local|${old.single.key}']?.favorite, isTrue);
    final episode = series.expand((item) => item.episodes).firstWhere(
          (item) => item.stableId == first.id,
        );
    expect(watchState.loadAll()[mediaWatchKeyForEpisode(episode)]?.position,
        const Duration(minutes: 3));
  });

  test('选集单独显示季集号和 TMDB 集名', () {
    final indexed = _item('来源剧名');
    expect(indexed.episodeDisplayTitle, 'S01E01  开篇');
    expect(indexed.playbackTitleFor('来源剧名 S01'), '来源剧名 S01E01 开篇');
    expect(indexed.copyWith(episodeNumber: 2).episodeDisplayTitle, 'S01E02');
  });

  test('来源季名不重复追加同季编号，也不剥离合法季名', () {
    const resolver = TmdbEpisodeTitleResolver();
    for (final entry in {
      '来源剧名 S02': '来源剧名 S02E01 开篇.mkv',
      '来源剧名 第 2 季': '来源剧名 第 2 季 S02E01 开篇.mkv',
      'S02 来源剧名': 'S02 来源剧名 S02E01 开篇.mkv',
      '来源剧名 S01': '来源剧名 S01 S02E01 开篇.mkv',
    }.entries) {
      expect(
        resolver.resolveWithExtension(
          seriesTitle: entry.key,
          seasonNumber: 2,
          episodeNumber: 1,
          episodeName: '开篇',
          originalFileName: '01.mkv',
        ),
        entry.value,
      );
    }
  });

  testWidgets('本地详情标题继承来源剧名，选集保留季集和集名', (tester) async {
    final overrides = _TitleOverrides();
    final base = _item('来源剧名');
    final indexed = base.copyWith(
      tmdb: base.tmdb!.copyWith(originalTitle: 'Original title'),
    );
    final controller = LocalController(
      seriesTitleOverrideRepository: overrides,
    )..localLibraryItems.add(indexed);
    await tester.pumpWidget(MaterialApp(
      home: LocalSeriesDetailPage(
        series: controller.localLibrarySeries.single,
        controller: controller,
        onPlay: (_) {},
      ),
    ));

    expect(find.text('来源剧名 S01'), findsNWidgets(2));
    expect(find.text('TMDB 另一个剧名'), findsNothing);
    expect(find.text('S01E01  开篇'), findsOneWidget);
    expect(find.text('原名：Original title'), findsOneWidget);

    await overrides.saveForDirectories([indexed.parentPath], '改名后的剧名');
    controller.localLibraryItems[0] = indexed.copyWith(seriesName: '改名后的剧名');
    await tester.pump();
    expect(find.text('来源剧名 S01'), findsNothing);
    expect(find.text('改名后的剧名'), findsNWidgets(2));
  });
}

LocalMediaIndexItem _item(String sourceTitle, {int season = 1, int episode = 1}) {
  final name = '$sourceTitle S${season.toString().padLeft(2, '0')}'
      'E${episode.toString().padLeft(2, '0')}.mkv';
  return LocalMediaIndexItem(
    path: 'D:\\Media\\$sourceTitle\\$name',
    name: name,
    parentPath: 'D:\\Media\\$sourceTitle',
    sourcePath: r'D:\Media',
    size: 100,
    modified: DateTime(2026),
    seriesName: '索引中的剧名',
    seasonNumber: season,
    episodeNumber: episode,
    indexedAt: DateTime(2026),
    tmdb: TmdbMetadata(
      id: 1,
      mediaType: TmdbMediaType.tv,
      title: 'TMDB 另一个剧名',
      language: 'zh-CN',
      matchedAt: DateTime(2026),
      matchConfidence: 1,
      seasons: const [
        TmdbSeasonMetadata(
          id: 11,
          seasonNumber: 1,
          name: '第一季',
          episodeCount: 1,
          episodes: [
            TmdbEpisodeMetadata(id: 111, episodeNumber: 1, name: '开篇'),
          ],
        ),
      ],
    ),
  );
}

class _TitleOverrides implements ILocalSeriesTitleOverrideRepository {
  final _titles = <String, String>{};

  @override
  String? getForDirectory(String directoryPath) => _titles[directoryPath];

  @override
  Future<void> saveForDirectories(
    Iterable<String> directoryPaths,
    String title,
  ) async {
    for (final path in directoryPaths) {
      _titles[path] = title;
    }
  }
}

class _WatchStorage implements PlayerBookmarkStorage {
  Object? _value;

  @override
  Object? read() => _value;

  @override
  Future<void> write(Object value) async {
    _value = value;
  }
}
