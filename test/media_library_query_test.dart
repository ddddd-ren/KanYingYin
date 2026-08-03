import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_library_query.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';

void main() {
  test('多个类型任一匹配并与来源关键词同时满足', () {
    final result = const MediaLibraryQuery().apply(
      series: <MediaLibrarySeries>[
        _series('local', '星际动画', const <String>['动画', '科幻']),
        _series('openlist', '太空纪录片', const <String>['纪录片']),
        _series('openlist', '科幻电影', const <String>['科幻']),
      ],
      sourceId: 'openlist',
      keyword: '电影',
      selectedGenres: const <String>{'动画', '科幻'},
    );

    expect(result.map((item) => item.title), const <String>['科幻电影']);
  });

  test('可用类型按中文名称排序且切换来源移除失效选择', () {
    const query = MediaLibraryQuery();
    final available = query.availableGenres(
      <MediaLibrarySeries>[
        _series('local', 'A', const <String>['科幻', '动画']),
        _series('openlist', 'B', const <String>['纪录片']),
      ],
      sourceId: 'local',
    );

    expect(available, const <String>['动画', '科幻']);
    expect(
      query.retainAvailableGenres(
        const <String>{'科幻', '纪录片'},
        available,
      ),
      const <String>{'科幻'},
    );
  });
}

MediaLibrarySeries _series(
  String sourceId,
  String title,
  List<String> genres,
) {
  return MediaLibrarySeries(
    key: '$sourceId|$title',
    seriesKey: title,
    title: title,
    sourceKind:
        sourceId == 'local' ? MediaSourceKind.local : MediaSourceKind.cloud,
    sourceId: sourceId,
    sourceName: sourceId == 'local' ? '本地' : '网盘',
    isAvailable: true,
    episodes: const <MediaLibraryEpisode>[],
    genres: genres,
  );
}
