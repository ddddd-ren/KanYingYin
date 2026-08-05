import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_library_category.dart';
import 'package:kanyingyin/features/library/presentation/media_category_page.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';

void main() {
  testWidgets('电影入口只显示电影并可按来源筛选和打开', (tester) async {
    final localMovie = _series(
      key: 'local|movie',
      title: '本地电影',
      sourceKind: MediaSourceKind.local,
      sourceId: 'local',
      sourceName: '本地',
      mediaType: TmdbMediaType.movie,
    );
    final cloudMovie = _series(
      key: 'quark|movie',
      title: '网盘电影',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'quark',
      sourceName: '夸克网盘',
      mediaType: TmdbMediaType.movie,
    );
    final tv = _series(
      key: 'quark|tv',
      title: '网盘电视剧',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'quark',
      sourceName: '夸克网盘',
      mediaType: TmdbMediaType.tv,
    );
    MediaLibraryEpisode? played;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaCategoryPage(
          category: MediaLibraryCategory.movie,
          initialize: () async {},
          libraryProvider: () => CloudMediaLibrary(
            series: <MediaLibrarySeries>[localMovie, cloudMovie, tv],
            filters: const <MediaLibrarySourceFilter>[
              MediaLibrarySourceFilter('all', '全部', null),
              MediaLibrarySourceFilter(
                'local',
                '本地',
                MediaSourceKind.local,
              ),
              MediaLibrarySourceFilter(
                'quark',
                '夸克网盘',
                MediaSourceKind.cloud,
              ),
            ],
          ),
          onPlayEpisode: (series, episode) async => played = episode,
          observeLibrary: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('media-category-title')),
      findsOneWidget,
    );
    expect(find.text('本地电影'), findsOneWidget);
    expect(find.text('网盘电影'), findsOneWidget);
    expect(find.text('网盘电视剧'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('media-category-source-filter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('夸克网盘').last);
    await tester.pumpAndSettle();

    expect(find.text('本地电影'), findsNothing);
    expect(find.text('网盘电影'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('media-category-card-quark|movie'),
      ),
    );
    await tester.pumpAndSettle();
    expect(played?.stableId, cloudMovie.episodes.single.stableId);
  });

  testWidgets('窄屏下较长的网盘来源名称不会挤出分类页头部', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final cloudMovie = _series(
      key: 'quark|movie',
      title: '网盘电影',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'quark',
      sourceName: '家庭共享夸克网盘媒体资料库',
      mediaType: TmdbMediaType.movie,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaCategoryPage(
          category: MediaLibraryCategory.movie,
          initialize: () async {},
          libraryProvider: () => CloudMediaLibrary(
            series: <MediaLibrarySeries>[cloudMovie],
            filters: const <MediaLibrarySourceFilter>[
              MediaLibrarySourceFilter('all', '全部', null),
              MediaLibrarySourceFilter(
                'quark',
                '家庭共享夸克网盘媒体资料库',
                MediaSourceKind.cloud,
              ),
            ],
          ),
          onPlayEpisode: (_, __) async {},
          observeLibrary: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('media-category-source-filter')),
      findsOneWidget,
    );
  });
}

MediaLibrarySeries _series({
  required String key,
  required String title,
  required MediaSourceKind sourceKind,
  required String sourceId,
  required String sourceName,
  required TmdbMediaType mediaType,
}) {
  final episode = sourceKind == MediaSourceKind.local
      ? MediaLibraryEpisode.local(
          stableId: key,
          name: '$title.mkv',
          localItem: LocalMediaIndexItem(
            path: 'C:\\Media\\$title.mkv',
            name: '$title.mkv',
            parentPath: r'C:\Media',
            sourcePath: r'C:\Media',
            size: 10,
            modified: DateTime.utc(2026, 8, 5),
            seriesName: title,
            indexedAt: DateTime.utc(2026, 8, 5),
            tmdb: TmdbMetadata(
              id: key.hashCode,
              mediaType: mediaType,
              title: title,
              language: 'zh-CN',
              matchedAt: DateTime.utc(2026, 8, 5),
              matchConfidence: 1,
            ),
          ),
        )
      : MediaLibraryEpisode.cloud(
          stableId: '$key-episode',
          name: '$title.mkv',
          sourceId: sourceId,
          sourceName: sourceName,
          isAvailable: true,
          remoteId: '$key-episode',
          remotePath: '/$title.mkv',
        );
  return MediaLibrarySeries(
    key: key,
    seriesKey: title,
    title: title,
    sourceKind: sourceKind,
    sourceId: sourceId,
    sourceName: sourceName,
    isAvailable: true,
    episodes: <MediaLibraryEpisode>[episode],
    mediaType: mediaType,
  );
}
