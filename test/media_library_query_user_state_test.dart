import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_library_query.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/application/media_watch_state.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';

void main() {
  test('已看筛选要求整部所有媒体已看，部分观看仍在未看', () {
    final done = _series('local|a', '完成');
    final undone = _series('cloud|b', '未完成');
    final states = {
      mediaWatchKeyForEpisode(done.episodes.single): MediaWatchState(
          watched: true,
          position: Duration.zero,
          duration: Duration.zero,
          updatedAt: DateTime(2026))
    };
    const query = MediaLibraryQuery();
    expect(
        query.apply(
            series: [done, undone],
            watchStates: states,
            watched: true).map((e) => e.title),
        ['完成']);
    expect(
        query.apply(
            series: [done, undone],
            watchStates: states,
            watched: false).map((e) => e.title),
        ['未完成']);
  });
  test('媒体库查询支持收藏、待看和合集筛选', () {
    final series = <MediaLibrarySeries>[
      _series('local|a', '收藏作品'),
      _series('cloud|b', '待看作品'),
      _series('cloud|c', '普通作品'),
    ];
    final states = <String, MediaLibraryUserState>{
      'local|a': MediaLibraryUserState(
        favorite: true,
        collections: const <String>['精选'],
      ),
      'cloud|b': const MediaLibraryUserState(watchLater: true),
    };
    const query = MediaLibraryQuery();

    expect(
      query
          .apply(series: series, userStates: states, favoriteOnly: true)
          .map((item) => item.title),
      const <String>['收藏作品'],
    );
    expect(
      query
          .apply(series: series, userStates: states, watchLaterOnly: true)
          .map((item) => item.title),
      const <String>['待看作品'],
    );
    expect(
      query
          .apply(
            series: series,
            userStates: states,
            selectedCollection: '精选',
          )
          .map((item) => item.title),
      const <String>['收藏作品'],
    );
  });
}

MediaLibrarySeries _series(String key, String title) {
  return MediaLibrarySeries(
    key: key,
    seriesKey: title,
    title: title,
    sourceKind: key.startsWith('local|')
        ? MediaSourceKind.local
        : MediaSourceKind.cloud,
    sourceId: key.startsWith('local|') ? 'local' : 'cloud',
    sourceName: key.startsWith('local|') ? '本地' : '网盘',
    isAvailable: true,
    episodes: [
      MediaLibraryEpisode.local(
          stableId: key,
          name: title,
          localItem: LocalMediaIndexItem(
              path: key == 'local|a' ? '/a' : '/b',
              name: title,
              parentPath: '/',
              sourcePath: '/',
              size: 1,
              modified: DateTime(2026),
              indexedAt: DateTime(2026),
              seriesName: title))
    ],
  );
}
