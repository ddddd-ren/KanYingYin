import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/media_library_category.dart';
import 'package:kanyingyin/features/library/application/media_library_query.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/features/library/presentation/media_category_page.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/local_series_grouper.dart';

void main() {
  final metadata = TmdbMetadata(
    id: 42,
    mediaType: TmdbMediaType.movie,
    title: '中文电影',
    originalTitle: 'Original Movie',
    aliases: ['别名', '别名'],
    genres: const ['剧情'],
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026),
    matchConfidence: 1,
  );
  final local = LocalMediaIndexItem(
    path: 'D:/Movies/来源名称.mkv',
    name: '来源名称.mkv',
    parentPath: 'D:/Movies',
    sourcePath: 'D:/Movies',
    size: 100000000,
    modified: DateTime.utc(2026),
    indexedAt: DateTime.utc(2026),
    seriesName: '显示名称',
    originalNames: const ['最初文件名.mkv'],
    tmdb: metadata,
  );
  const query = MediaLibraryQuery();

  test('搜索保留单集独有元数据与名称，不因作品元数据存在而跳过', () {
    final episodeItem = local.copyWith(tmdb: metadata.copyWith(
      originalTitle: 'Episode Original', aliases: ['单集别名']));
    final series = MediaLibrarySeries(
      key: 'local|one', seriesKey: 'one', title: '作品显示名',
      sourceKind: MediaSourceKind.local, sourceId: 'local', sourceName: '来源标签',
      isAvailable: true, tmdbMetadata: metadata,
      legacySeriesTitles: const ['历史作品名'],
      episodes: [MediaLibraryEpisode.local(
        stableId: episodeItem.id, name: '单集显示名', localItem: episodeItem)],
    );
    for (final keyword in ['episode original', '单集别名', '单集显示名',
      '来源标签', '历史作品名', '来源名称', 'original movie', '中文电影', '别名']) {
      expect(query.matchesSeries(series, keyword), isTrue, reason: keyword);
      expect(query.apply(series: [series], keyword: keyword), [series], reason: keyword);
    }
    expect(query.matchesSeries(series, '不存在'), isFalse);
  });

  testWidgets('分类页输入原名别名不扫描或刷新且只显示一张卡', (tester) async {
    final library = const CloudMediaLibraryAggregator().build(
      localItems: [local], cloudItems: [], cloudSources: [],
    );
    var initializations = 0;
    var refreshes = 0;
    await tester.pumpWidget(MaterialApp(home: MediaCategoryPage(
      category: MediaLibraryCategory.movie,
      initialize: () async { initializations++; },
      refresh: () async { refreshes++; },
      libraryProvider: () => library,
      onPlayEpisode: (_, __) async {}, observeLibrary: false,
    )));
    await tester.pumpAndSettle();
    for (final keyword in [' original MOVIE ', '别名', '来源名称']) {
      await tester.enterText(find.byKey(const ValueKey('media-category-search')), keyword);
      await tester.pumpAndSettle();
      expect(find.byType(ImmersiveMediaCard), findsOneWidget);
    }
    expect(initializations, 1);
    expect(refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  test('分类聚合保留网盘原始作品名且不依赖显示名', () {
    final library = const CloudMediaLibraryAggregator().build(
      localItems: [],
      cloudItems: [CloudMediaIndexItem(
        sourceId: 'cloud', remoteId: 'one', remotePath: '/目录/来源文件名.mkv',
        name: '规则显示名.mkv', remoteName: '来源文件名.mkv',
        displayName: '虚拟显示名.mkv', seriesName: '原始作品名',
        size: 100000000, modifiedAt: null,
        mediaType: CloudMediaType.movie, tmdbTitle: '中文电影',
        tmdbOriginalTitle: 'Original Movie',
      )],
      cloudSources: const [CloudSource(
        id: 'cloud', type: CloudSourceType.quark, name: '我的网盘',
        baseUrl: '', rootPaths: ['/'],
      )],
    );
    for (final keyword in ['原始作品名', '来源文件名', '中文电影', ' original MOVIE ']) {
      expect(query.apply(series: library.series, keyword: keyword),
          [same(library.series.single)], reason: keyword);
    }
  });

  test('分类与本地库按来源名称、中文名、原名及别名命中同一作品且不复制结果', () {
    final library = const CloudMediaLibraryAggregator().build(
      localItems: [local],
      cloudItems: [],
      cloudSources: [],
    );
    for (final keyword in ['来源名称', '中文电影', ' original MOVIE ', '别名', '最初文件名']) {
      final result = query.apply(series: library.series, keyword: keyword);
      expect(result, hasLength(1), reason: keyword);
      expect(result.single, same(library.series.single));
      expect(result.single.episodes.single.localItem?.path, local.path);
    }
    expect(query.apply(series: library.series, keyword: '不相关'), isEmpty);
    expect(
        query.apply(series: library.series, keyword: '别名', sourceId: 'other'),
        isEmpty);
    expect(
        query.apply(
            series: library.series, keyword: '别名', selectedGenres: {'喜剧'}),
        isEmpty);
    expect(query.apply(series: library.series, keyword: '  '), library.series);
  });

  test('本地目录搜索复用相同匹配并保留原始文件身份', () {
    final groups = const LocalSeriesGrouper().group([
      LocalFileItem(
          path: local.path,
          name: local.name,
          size: local.size,
          modified: local.modified,
          isDirectory: false,
          isVideo: true,
          originalNames: local.originalNames),
    ]);
    for (final keyword in ['来源名称', '中文电影', ' ORIGINAL MOVIE ', '别名', '最初文件名']) {
      final result = groups
          .where((group) => group.matches(keyword, extraTitles: [
                metadata.title,
                metadata.originalTitle,
                ...metadata.aliases
              ]))
          .toList();
      expect(result, hasLength(1), reason: keyword);
      expect(result.single.episodes.single.path, local.path);
    }
  });

  test('网盘旧记录入口按中文原名及重复别名只返回同一作品', () {
    const entry = CloudFileEntry(
        id: 'one',
        remotePath: '/来源名称.mkv',
        name: '来源名称.mkv',
        size: 100000000,
        modifiedAt: null,
        isDirectory: false);
    final record = CloudResourceTmdbRecord.matched(
      sourceId: 'cloud',
      remoteId: entry.id,
      remotePath: entry.remotePath,
      displayName: entry.name,
      resourceKind: CloudResourceKind.standaloneVideo,
      metadata: metadata,
      checkedAt: DateTime.utc(2026),
      customTitle: '人工显示名',
    );
    for (final keyword in ['来源名称', '中文电影', ' ORIGINAL MOVIE ', '别名']) {
      final result = CloudResourceCollectionGrouper().group(
        sourceId: 'cloud',
        entries: [entry],
        records: {record.stableKey: record},
        query: keyword,
      );
      expect(result.groups, hasLength(1), reason: keyword);
      expect(result.groups.single.videos.single.id, entry.id);
      expect(result.groups.single.videos.single.remotePath, entry.remotePath);
    }
  });
}
