import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_collection.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/local/library_sheet.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/repositories/local_media_tag_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_media_tree_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_tmdb_metadata_service.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:path/path.dart' as p;

void main() {
  group('CloudMediaLibraryAggregator', () {
    final local = LocalMediaIndexItem(
      path: r'D:\Media\Show\Show S01E01.mkv',
      name: 'Show S01E01.mkv',
      parentPath: r'D:\Media\Show',
      sourcePath: r'D:\Media',
      size: 10,
      modified: DateTime(2026),
      seriesName: 'Show',
      seasonNumber: 1,
      episodeNumber: 1,
      indexedAt: DateTime(2026),
    );
    final openList = _cloud('openlist', '/Show/Show S01E01.mkv');
    final quark = _cloud('quark', '/Show/Show S01E01.mkv');
    final xunlei = _cloud('xunlei', '/Show/Show S01E01.mkv');
    final sources = <CloudSource>[
      _source('openlist', '家庭网盘', enabled: true),
      _source('quark', '夸克归档', enabled: false, type: CloudSourceType.quark),
      _source(
        'xunlei',
        '迅雷归档',
        enabled: true,
        type: CloudSourceType.xunlei,
      ),
    ];

    test('聚合本地和已启用远程来源且不显示停用来源', () {
      final library = const CloudMediaLibraryAggregator().build(
        localItems: [local],
        cloudItems: [openList, quark, xunlei],
        cloudSources: sources,
      );

      expect(library.series, hasLength(3));
      expect(library.series.map((item) => item.sourceId).toSet(),
          {'local', 'openlist', 'xunlei'});
      expect(library.series.map((item) => item.key).toSet(), hasLength(3));
      final remote = library.series
          .firstWhere((item) => item.sourceId == 'openlist')
          .episodes
          .single;
      expect(remote.sourceKind, MediaSourceKind.cloud);
      expect(remote.localItem, isNull);
      expect(remote.remotePath, '/Show/Show S01E01.mkv');
      expect(remote.isAvailable, isTrue);
      expect(
        library.series.any((item) => item.sourceId == 'quark'),
        isFalse,
      );
    });

    test('逐集 TMDB 标题只改变展示名称并保留本地播放路径', () {
      final metadata = TmdbMetadata(
        id: 9,
        mediaType: TmdbMediaType.tv,
        title: 'Show',
        language: 'zh-CN',
        matchedAt: DateTime(2026),
        matchConfidence: 1,
        seasons: const <TmdbSeasonMetadata>[
          TmdbSeasonMetadata(
            id: 91,
            seasonNumber: 1,
            name: '第一季',
            episodeCount: 1,
            episodes: <TmdbEpisodeMetadata>[
              TmdbEpisodeMetadata(
                id: 911,
                episodeNumber: 1,
                name: '试播集',
              ),
            ],
          ),
        ],
      );
      final indexed = local.copyWith(tmdb: metadata);
      final library = const CloudMediaLibraryAggregator().build(
        localItems: [indexed],
        cloudItems: const <CloudMediaIndexItem>[],
        cloudSources: const <CloudSource>[],
      );

      final episode = library.series.single.episodes.single;
      expect(episode.name, 'Show S01E01 试播集.mkv');
      expect(episode.localItem?.path, local.path);
      expect(episode.localItem?.subtitlePath, local.subtitlePath);
    });

    test('来源筛选保留全部、本地和启用网盘来源', () {
      final library = const CloudMediaLibraryAggregator().build(
        localItems: [local],
        cloudItems: [openList, quark, xunlei],
        cloudSources: sources,
      );

      expect(library.filters.map((item) => item.id),
          ['all', 'local', 'openlist', 'xunlei']);
      expect(library.filterBySource('openlist'), hasLength(1));
      expect(library.filterBySource('local').single.sourceKind,
          MediaSourceKind.local);
    });

    test('本地和网盘系列聚合稳定去重的 TMDB 类型', () {
      final localWithGenres = local.copyWith(
        tmdb: TmdbMetadata(
          id: 7,
          mediaType: TmdbMediaType.tv,
          title: 'Show',
          language: 'zh-CN',
          matchedAt: DateTime(2026),
          matchConfidence: 1,
          genres: const <String>['剧情', '科幻'],
        ),
      );
      final cloudWithGenres = openList.replaceTmdb(
        tmdbId: 42,
        tmdbTitle: '中文片名',
        tmdbGenres: const <String>['动画', '科幻', '动画'],
      );

      final library = const CloudMediaLibraryAggregator().build(
        localItems: <LocalMediaIndexItem>[localWithGenres],
        cloudItems: <CloudMediaIndexItem>[cloudWithGenres],
        cloudSources: sources,
      );

      expect(
        library.series.firstWhere((item) => item.sourceId == 'local').genres,
        const <String>['剧情', '科幻'],
      );
      expect(
        library.series.firstWhere((item) => item.sourceId == 'openlist').genres,
        const <String>['动画', '科幻'],
      );
    });

    test('同一云来源沿用季度和特别篇拆分', () {
      final library = const CloudMediaLibraryAggregator().build(
        localItems: const [],
        cloudItems: [
          _cloud('openlist', '/Show/Show S01E01.mkv'),
          _cloud('openlist', '/Show/Show S02E01.mkv', season: 2),
          _cloud('openlist', '/Show/Show Special.mkv',
              type: CloudMediaType.special, episode: null),
        ],
        cloudSources: sources,
      );
      expect(library.series.map((item) => item.title),
          ['Show S01', 'Show S02', 'Show 特别篇']);
    });

    test('云系列保留原始分组键但向界面提供 TMDB 信息', () {
      final enriched = openList.replaceTmdb(
        tmdbId: 42,
        tmdbTitle: '中文片名',
        tmdbOverview: '这是用户可见的简介',
        tmdbRating: 8.8,
        tmdbPosterUrl: '/poster.jpg',
        posterCachePath: r'C:\cache\poster.jpg',
      );

      final series = const CloudMediaLibraryAggregator()
          .build(
            localItems: const [],
            cloudItems: [enriched],
            cloudSources: sources,
          )
          .series
          .single;

      expect(series.seriesKey, 'Show');
      expect(series.title, '中文片名 S01');
      expect(series.tmdbRating, 8.8);
      expect(series.tmdbOverview, '这是用户可见的简介');
      expect(series.tmdbPosterUrl, '/poster.jpg');
      expect(series.posterCachePath, r'C:\cache\poster.jpg');
    });

    test('作品级刮削记录为分类入口提供媒体类型和季度海报', () {
      final indexed = _cloud(
        'openlist',
        '/Show/Show S02E01.mkv',
        season: 2,
        workKey: 'openlist|work|show-s2',
      );
      final record = CloudWorkTmdbRecord.matched(
        sourceId: 'openlist',
        workKey: 'openlist|work|show-s2',
        workRootId: 'show-s2',
        workRootPath: '/Show',
        remoteName: 'Show S02',
        metadata: TmdbMetadata(
          id: 42,
          mediaType: TmdbMediaType.tv,
          title: '中文剧名',
          genres: const <String>['动画', '剧情'],
          language: 'zh-CN',
          matchedAt: DateTime.utc(2026, 8, 5),
          matchConfidence: 1,
          seasons: const <TmdbSeasonMetadata>[
            TmdbSeasonMetadata(
              id: 2,
              seasonNumber: 2,
              name: '第 2 季',
              episodeCount: 12,
              posterUrl: '/season-2.jpg',
              posterCachePath: r'C:\cache\season-2.jpg',
            ),
          ],
        ),
        posterCachePath: r'C:\cache\work.jpg',
        checkedAt: DateTime.utc(2026, 8, 5),
        tmdbMatchOrigin: TmdbMatchOrigin.manual,
      );

      final series = const CloudMediaLibraryAggregator()
          .build(
            localItems: const <LocalMediaIndexItem>[],
            cloudItems: <CloudMediaIndexItem>[indexed],
            cloudSources: sources,
            workRecordsByKey: <String, CloudWorkTmdbRecord>{
              record.workKey: record,
            },
          )
          .series
          .single;

      expect(series.title, '中文剧名 S02');
      expect(series.mediaType, TmdbMediaType.tv);
      expect(series.genres, const <String>['动画', '剧情']);
      expect(series.tmdbPosterUrl, '/season-2.jpg');
      expect(series.posterCachePath, r'C:\cache\season-2.jpg');
    });

    test('手动剧名覆盖时逐集标题使用当前剧名和 TMDB 集名', () {
      const workKey = 'openlist|work|resurrected';
      final indexed = _cloud(
        'openlist',
        '/回魂计/死而复生 S01E01 死刑日.mkv',
        workKey: workKey,
        seriesName: '回魂计',
      );
      final record = CloudWorkTmdbRecord.matched(
        sourceId: 'openlist',
        workKey: workKey,
        workRootId: 'resurrected',
        workRootPath: '/回魂计',
        remoteName: '回魂计',
        scrapeTitleOverride: '回魂计',
        metadata: TmdbMetadata(
          id: 196285,
          mediaType: TmdbMediaType.tv,
          title: '死而复生',
          language: 'zh-CN',
          matchedAt: DateTime.utc(2026, 8, 6),
          matchConfidence: 1,
          seasons: const <TmdbSeasonMetadata>[
            TmdbSeasonMetadata(
              id: 1962851,
              seasonNumber: 1,
              name: '第一季',
              episodeCount: 1,
              episodes: <TmdbEpisodeMetadata>[
                TmdbEpisodeMetadata(
                  id: 196285101,
                  episodeNumber: 1,
                  name: '死而复生',
                ),
              ],
            ),
          ],
        ),
        checkedAt: DateTime.utc(2026, 8, 6),
        tmdbMatchOrigin: TmdbMatchOrigin.manual,
      );

      final series = const CloudMediaLibraryAggregator()
          .build(
            localItems: const <LocalMediaIndexItem>[],
            cloudItems: <CloudMediaIndexItem>[indexed],
            cloudSources: sources,
            workRecordsByKey: <String, CloudWorkTmdbRecord>{
              workKey: record,
            },
          )
          .series
          .single;

      expect(series.title, '回魂计 S01');
      expect(series.episodes.single.name, '回魂计 S01E01 死而复生.mkv');
      expect(series.episodes.single.name, isNot(contains('死刑日')));
    });

    test('同来源不同目录手动匹配到同一 TMDB 作品后分类入口只保留一张卡片', () {
      final first = _cloud(
        'openlist',
        '/版本一/Show S01E01.mkv',
        workKey: 'openlist|work|version-1',
        seriesName: '版本一',
      );
      final second = _cloud(
        'openlist',
        '/版本二/Show S01E02.mkv',
        episode: 2,
        workKey: 'openlist|work|version-2',
        seriesName: '版本二',
      );
      CloudWorkTmdbRecord record(String workKey, String remoteName) {
        return CloudWorkTmdbRecord.matched(
          sourceId: 'openlist',
          workKey: workKey,
          workRootId: workKey,
          workRootPath: '/$remoteName',
          remoteName: remoteName,
          metadata: TmdbMetadata(
            id: 42,
            mediaType: TmdbMediaType.tv,
            title: '同一部剧',
            language: 'zh-CN',
            matchedAt: DateTime.utc(2026, 8, 5),
            matchConfidence: 1,
          ),
          checkedAt: DateTime.utc(2026, 8, 5),
          tmdbMatchOrigin: TmdbMatchOrigin.manual,
        );
      }

      final firstRecord = record(first.workKey!, '版本一');
      final secondRecord = record(second.workKey!, '版本二');
      final library = const CloudMediaLibraryAggregator().build(
        localItems: const <LocalMediaIndexItem>[],
        cloudItems: <CloudMediaIndexItem>[first, second],
        cloudSources: sources,
        workRecordsByKey: <String, CloudWorkTmdbRecord>{
          firstRecord.workKey: firstRecord,
          secondRecord.workKey: secondRecord,
        },
      );

      expect(library.series, hasLength(1));
      expect(library.series.single.title, '同一部剧 S01');
      expect(library.series.single.episodes, hasLength(2));
    });

    test('未刮削的同名网盘作品按作品键分组与网盘媒体库一致', () {
      final first = _cloud(
        'openlist',
        '/版本一/Show S01E01.mkv',
        workKey: 'openlist|work|version-1',
        seriesName: '同名作品',
      );
      final second = _cloud(
        'openlist',
        '/版本二/Show S01E01.mkv',
        workKey: 'openlist|work|version-2',
        seriesName: '同名作品',
      );

      final library = const CloudMediaLibraryAggregator().build(
        localItems: const <LocalMediaIndexItem>[],
        cloudItems: <CloudMediaIndexItem>[first, second],
        cloudSources: sources,
      );

      expect(library.series, hasLength(2));
      expect(library.series.map((item) => item.episodes.single.remotePath), {
        '/版本一/Show S01E01.mkv',
        '/版本二/Show S01E01.mkv',
      });
    });

    test('同季度未匹配资源只对应一个同名 TMDB 作品时继承其分类卡片', () {
      const title = '无职转生～到了异世界就拿出真本事～';
      final matched = _cloud(
        'openlist',
        '/无职转生第二季/无职转生 S02E01.mkv',
        season: 2,
        workKey: 'openlist|work|mushoku-s2-matched',
        seriesName: '无职转生 第二季',
      );
      final unmatchedSpecial = _cloud(
        'openlist',
        '/来自：BT磁力链下载/无职转生 S02E00.mkv',
        season: 2,
        episode: 0,
        workKey: 'openlist|work|mushoku-s2-special',
        seriesName: title,
      );
      final record = CloudWorkTmdbRecord.matched(
        sourceId: 'openlist',
        workKey: matched.workKey!,
        workRootId: 'mushoku-s2-matched',
        workRootPath: '/无职转生第二季',
        remoteName: '无职转生 第二季',
        metadata: TmdbMetadata(
          id: 94664,
          mediaType: TmdbMediaType.tv,
          title: title,
          language: 'zh-CN',
          matchedAt: DateTime.utc(2026, 8, 5),
          matchConfidence: 1,
          seasons: const <TmdbSeasonMetadata>[
            TmdbSeasonMetadata(
              id: 345790,
              seasonNumber: 2,
              name: '第 2 季',
              episodeCount: 13,
              posterUrl: '/mushoku-season-2.jpg',
            ),
          ],
        ),
        checkedAt: DateTime.utc(2026, 8, 5),
        tmdbMatchOrigin: TmdbMatchOrigin.manual,
      );

      final library = const CloudMediaLibraryAggregator().build(
        localItems: const <LocalMediaIndexItem>[],
        cloudItems: <CloudMediaIndexItem>[matched, unmatchedSpecial],
        cloudSources: sources,
        workRecordsByKey: <String, CloudWorkTmdbRecord>{
          record.workKey: record,
        },
      );

      expect(library.series, hasLength(1));
      expect(library.series.single.title, '$title S02');
      expect(library.series.single.tmdbPosterUrl, '/mushoku-season-2.jpg');
      expect(
        library.series.single.episodes.map((episode) => episode.remotePath),
        containsAll(<String>[
          '/无职转生第二季/无职转生 S02E01.mkv',
          '/来自：BT磁力链下载/无职转生 S02E00.mkv',
        ]),
      );
    });

    test('匹配电视剧的 S02E00 独立索引资源按路径季号并入第二季', () {
      const title = '规则标题';
      final matched = _cloud(
        'openlist',
        '/规则标题第二季/规则标题 S02E01.mkv',
        season: 2,
        workKey: 'openlist|work|matched-s2',
        seriesName: title,
      );
      final standalone = CloudMediaIndexItem(
        sourceId: 'openlist',
        remoteId: 'standalone-s2e0',
        remotePath: '/来自其他目录/规则标题 S02E00.mkv',
        name: '规则标题 S02E00.mkv',
        workKey: 'openlist|movie|standalone-s2e0',
        size: 10,
        modifiedAt: DateTime(2026),
        seriesName: title,
        mediaType: CloudMediaType.movie,
      );
      final record = CloudWorkTmdbRecord.matched(
        sourceId: 'openlist',
        workKey: matched.workKey!,
        workRootId: 'matched-s2',
        workRootPath: '/规则标题第二季',
        remoteName: title,
        metadata: TmdbMetadata(
          id: 94664,
          mediaType: TmdbMediaType.tv,
          title: title,
          language: 'zh-CN',
          matchedAt: DateTime(2026),
          matchConfidence: 1,
          genres: const <String>['动画'],
          seasons: const <TmdbSeasonMetadata>[
            TmdbSeasonMetadata(
              id: 2,
              seasonNumber: 2,
              name: '第 2 季',
              episodeCount: 12,
              posterUrl: '/season-2.jpg',
            ),
          ],
        ),
        checkedAt: DateTime(2026),
        tmdbMatchOrigin: TmdbMatchOrigin.manual,
      );

      final library = const CloudMediaLibraryAggregator().build(
        localItems: const <LocalMediaIndexItem>[],
        cloudItems: <CloudMediaIndexItem>[matched, standalone],
        cloudSources: sources,
        workRecordsByKey: <String, CloudWorkTmdbRecord>{
          record.workKey: record,
        },
      );

      expect(library.series, hasLength(1));
      expect(library.series.single.title, '$title S02');
      expect(library.series.single.episodes, hasLength(2));
      expect(
        library.series.single.episodes
            .firstWhere(
                (episode) => episode.remotePath == standalone.remotePath)
            .seasonNumber,
        2,
      );
    });

    test('同名标题对应多个 TMDB 作品时未匹配资源保持独立', () {
      CloudWorkTmdbRecord record(CloudMediaIndexItem item, int tmdbId) {
        return CloudWorkTmdbRecord.matched(
          sourceId: item.sourceId,
          workKey: item.workKey!,
          workRootId: item.workKey!,
          workRootPath: item.remotePath,
          remoteName: item.seriesName,
          metadata: TmdbMetadata(
            id: tmdbId,
            mediaType: TmdbMediaType.tv,
            title: '同名作品',
            language: 'zh-CN',
            matchedAt: DateTime.utc(2026, 8, 5),
            matchConfidence: 1,
          ),
          checkedAt: DateTime.utc(2026, 8, 5),
          tmdbMatchOrigin: TmdbMatchOrigin.manual,
        );
      }

      final first = _cloud(
        'openlist',
        '/版本一/同名作品 S02E01.mkv',
        season: 2,
        workKey: 'openlist|work|same-title-1',
        seriesName: '版本一',
      );
      final second = _cloud(
        'openlist',
        '/版本二/同名作品 S02E01.mkv',
        season: 2,
        workKey: 'openlist|work|same-title-2',
        seriesName: '版本二',
      );
      final unmatched = _cloud(
        'openlist',
        '/未匹配/同名作品 S02E00.mkv',
        season: 2,
        episode: 0,
        workKey: 'openlist|work|same-title-unmatched',
        seriesName: '同名作品',
      );
      final firstRecord = record(first, 101);
      final secondRecord = record(second, 202);

      final library = const CloudMediaLibraryAggregator().build(
        localItems: const <LocalMediaIndexItem>[],
        cloudItems: <CloudMediaIndexItem>[first, second, unmatched],
        cloudSources: sources,
        workRecordsByKey: <String, CloudWorkTmdbRecord>{
          firstRecord.workKey: firstRecord,
          secondRecord.workKey: secondRecord,
        },
      );

      expect(library.series, hasLength(3));
      expect(
        library.series
            .singleWhere(
              (series) => series.episodes.any(
                (episode) => episode.remotePath == unmatched.remotePath,
              ),
            )
            .episodes,
        hasLength(1),
      );
    });

    test('未刮削的本地单片和剧集仍能进入电影或电视剧分类', () {
      final standalone = LocalMediaIndexItem(
        path: r'D:\Media\Movie\Movie.mkv',
        name: 'Movie.mkv',
        parentPath: r'D:\Media\Movie',
        sourcePath: r'D:\Media',
        size: 10,
        modified: DateTime(2026),
        seriesName: 'Movie',
        indexedAt: DateTime(2026),
      );
      final library = const CloudMediaLibraryAggregator().build(
        localItems: <LocalMediaIndexItem>[local, standalone],
        cloudItems: const <CloudMediaIndexItem>[],
        cloudSources: const <CloudSource>[],
      );

      expect(
        library.series
            .firstWhere(
              (item) => item.episodes.any(
                (episode) => episode.localItem?.path == local.path,
              ),
            )
            .mediaType,
        TmdbMediaType.tv,
      );
      expect(
        library.series
            .firstWhere(
              (item) => item.episodes.any(
                (episode) => episode.localItem?.path == standalone.path,
              ),
            )
            .mediaType,
        TmdbMediaType.movie,
      );
    });
  });

  group('CloudPosterCache', () {
    late Directory root;
    setUp(() async =>
        root = await Directory.systemTemp.createTemp('cloud-poster-'));
    tearDown(() async => root.delete(recursive: true));

    test('缓存路径只位于 cloud_posters 哈希目录且 URL 变化会更新', () async {
      var payload = <int>[1, 2, 3];
      final cache = CloudPosterCache(
        cacheRoot: root,
        downloader: (_) async => payload,
      );
      final first = await cache.resolve(
          sourceId: 'source/with/slash',
          stableId: '../remote',
          url: 'https://a/1.jpg');
      payload = <int>[4, 5];
      final second = await cache.resolve(
          sourceId: 'source/with/slash',
          stableId: '../remote',
          url: 'https://a/2.jpg');

      expect(first, second);
      expect(first,
          startsWith('${root.path}${Platform.pathSeparator}cloud_posters'));
      expect(await File(second).readAsBytes(), [4, 5]);
      expect(second, isNot(contains('remote')));
      expect(await File(first).exists(), isTrue);
    });

    test('跨实例单飞且下载失败回退旧缓存或网络 URL', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      Future<List<int>> download(String _) async {
        calls++;
        started.complete();
        await release.future;
        return [7];
      }

      final a = CloudPosterCache(cacheRoot: root, downloader: download);
      final b = CloudPosterCache(cacheRoot: root, downloader: download);
      final one = a.resolve(sourceId: 's', stableId: 'id', url: 'https://a/1');
      await started.future;
      final two = b.resolve(sourceId: 's', stableId: 'id', url: 'https://a/1');
      release.complete();
      expect(await Future.wait([one, two]), everyElement(isA<String>()));
      expect(calls, 1);

      final failing = CloudPosterCache(
          cacheRoot: root,
          downloader: (_) async => throw const SocketException('down'));
      expect(
          await failing.resolve(
              sourceId: 's', stableId: 'id', url: 'https://a/2'),
          endsWith('.jpg'));
      expect(
          await failing.resolve(
              sourceId: 'new', stableId: 'id', url: 'https://a/2'),
          'https://a/2');
    });

    test('同一海报不同 URL 并发仍只返回存在的单一版本', () async {
      final release = Completer<void>();
      var calls = 0;
      final cache = CloudPosterCache(
        cacheRoot: root,
        downloader: (_) async {
          calls++;
          await release.future;
          return [calls];
        },
      );
      final first =
          cache.resolve(sourceId: 's', stableId: 'same', url: 'https://a/1');
      final second =
          cache.resolve(sourceId: 's', stableId: 'same', url: 'https://a/2');
      release.complete();
      final paths = await Future.wait([first, second]);
      expect(paths[0], paths[1]);
      expect(await File(paths[0]).exists(), isTrue);
      expect(calls, 2);
      expect(await File(paths[0]).readAsBytes(), [2]);
      final files = await root
          .list(recursive: true)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      expect(files.where((file) => file.path.endsWith('.jpg')), hasLength(1));
      expect(files.where((file) => file.path.endsWith('.tmp')), isEmpty);
    });

    test('安装新版本失败会恢复旧图片和 sidecar 且无临时备份', () async {
      final initial =
          CloudPosterCache(cacheRoot: root, downloader: (_) async => [1, 2, 3]);
      final path = await initial.resolve(
          sourceId: 's', stableId: 'rollback', url: 'https://a/old');
      final sidecar = File('${p.withoutExtension(path)}.url');
      final oldVersion = await sidecar.readAsString();
      final failing = CloudPosterCache(
        cacheRoot: root,
        downloader: (_) async => [9, 9],
        beforeInstall: (_) async => throw const FileSystemException('install'),
      );

      expect(
          await failing.resolve(
              sourceId: 's', stableId: 'rollback', url: 'https://a/new'),
          path);
      expect(await File(path).readAsBytes(), [1, 2, 3]);
      expect(await sidecar.readAsString(), oldVersion);
      final residue = await root
          .list(recursive: true)
          .where((entity) =>
              entity.path.endsWith('.tmp') || entity.path.endsWith('.bak'))
          .toList();
      expect(residue, isEmpty);
    });

    test('图片备份后 sidecar 备份失败仍独立恢复两份旧文件', () async {
      final initial =
          CloudPosterCache(cacheRoot: root, downloader: (_) async => [3, 2, 1]);
      final path = await initial.resolve(
          sourceId: 's', stableId: 'backup-fail', url: 'https://a/old');
      final sidecar = File('${p.withoutExtension(path)}.url');
      final oldVersion = await sidecar.readAsString();
      final failing = CloudPosterCache(
        cacheRoot: root,
        downloader: (_) async => [8, 8],
        beforeMetadataBackup: (_) async =>
            throw const FileSystemException('metadata backup'),
      );

      expect(
          await failing.resolve(
              sourceId: 's', stableId: 'backup-fail', url: 'https://a/new'),
          path);
      expect(await File(path).readAsBytes(), [3, 2, 1]);
      expect(await sidecar.readAsString(), oldVersion);
      final residue = await root
          .list(recursive: true)
          .where((entity) =>
              entity.path.endsWith('.tmp') || entity.path.endsWith('.bak'))
          .toList();
      expect(residue, isEmpty);
    });

    test('提交后第二个备份清理失败不会回滚新图片和 sidecar', () async {
      final initial =
          CloudPosterCache(cacheRoot: root, downloader: (_) async => [1]);
      final path = await initial.resolve(
          sourceId: 's', stableId: 'cleanup-fail', url: 'https://a/old');
      final sidecar = File('${p.withoutExtension(path)}.url');
      final oldVersion = await sidecar.readAsString();
      final updating = CloudPosterCache(
        cacheRoot: root,
        downloader: (_) async => [7, 7],
        beforeBackupCleanup: (backupPath) async {
          if (backupPath.contains('.url.')) {
            throw const FileSystemException('cleanup');
          }
        },
      );

      expect(
          await updating.resolve(
              sourceId: 's', stableId: 'cleanup-fail', url: 'https://a/new'),
          path);
      expect(await File(path).readAsBytes(), [7, 7]);
      expect(await sidecar.readAsString(), isNot(oldVersion));
      expect(await File(path).exists(), isTrue);
      expect(await sidecar.exists(), isTrue);
    });

    test('大量不同海报完成后锁池归零', () async {
      final cache =
          CloudPosterCache(cacheRoot: root, downloader: (_) async => [1]);
      await Future.wait(List.generate(
        100,
        (index) => cache.resolve(
            sourceId: 's', stableId: 'id-$index', url: 'https://a/$index'),
      ));
      expect(CloudPosterCache.debugLockCount, 0);
    });
  });

  test('媒体条目工厂在 release 语义下拒绝非法云字段', () {
    expect(
      () => MediaLibraryEpisode.cloud(
        stableId: 'id',
        name: 'bad',
        sourceId: '',
        sourceName: 'bad',
        isAvailable: true,
        remoteId: 'id',
        remotePath: '',
      ),
      throwsArgumentError,
    );
  });

  test('LocalController 从仓库读取旧云索引并按来源筛选', () async {
    final sourceStorage = MemoryCloudSourceStorage();
    final sourceRepository = CloudSourceRepository(storage: sourceStorage);
    await sourceRepository.save(_source('openlist', '家庭网盘', enabled: false));
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await indexRepository.replaceSource(
      'openlist',
      [_cloud('openlist', '/Show/Show S01E01.mkv')],
      const {},
      const {},
      const ['/'],
    );
    final controller = LocalController(
      cloudSourceRepository: sourceRepository,
      cloudMediaIndexRepository: indexRepository,
    );

    await controller.reloadCloudLibraryIndex();

    expect(controller.combinedMediaLibrary.series, isEmpty);
    controller.selectLibrarySource('openlist');
    expect(controller.visibleMediaLibrarySeries, isEmpty);
  });

  test('LocalController 网盘资源不能启用本地媒体库入口', () async {
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await sourceRepository.save(_source('openlist', '家庭网盘', enabled: true));
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await indexRepository.replaceSource(
      'openlist',
      <CloudMediaIndexItem>[_cloud('openlist', '/Show/E01.mkv')],
      const {},
      const {},
      const ['/'],
    );
    final controller = LocalController(
      cloudSourceRepository: sourceRepository,
      cloudMediaIndexRepository: indexRepository,
    );

    await controller.revealCloudLibrarySource('openlist');

    expect(controller.mediaLibraryVideoCount, 0);
    expect(controller.selectedLibrarySourceId, 'openlist');
    final page = File('lib/pages/local/local_page.dart').readAsStringSync();
    expect(page, contains('LibraryPathBar('));
    expect(
      page,
      contains('canOpenLibrary: localController.mediaLibraryVideoCount > 0'),
    );
  });

  test('云索引完整持久化 TMDB 元数据和海报缓存路径', () async {
    final repository =
        CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
    final item = _cloud('openlist', '/Show/E01.mkv').copyWith(
      tmdbId: 42,
      tmdbTitle: '中文名',
      tmdbOriginalTitle: 'Original',
      tmdbOverview: '简介',
      tmdbRating: 8.8,
      tmdbPosterUrl: '/poster.jpg',
      tmdbBackdropUrl: '/backdrop.jpg',
      posterCachePath: r'C:\cache\poster.jpg',
    );
    await repository
        .replaceSource('openlist', [item], const {}, const {}, const ['/']);

    final restored = (await repository.getBySource('openlist')).single;
    expect(restored.tmdbOriginalTitle, 'Original');
    expect(restored.tmdbOverview, '简介');
    expect(restored.posterCachePath, r'C:\cache\poster.jpg');
  });

  test('原子 TMDB 更新保留扫描新增条目并能清除旧可空字段', () async {
    final repository =
        CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
    final old = _cloud('openlist', '/Show/E01.mkv').replaceTmdb(
      tmdbId: 1,
      tmdbTitle: '旧标题',
      tmdbOverview: '旧简介',
      posterCachePath: 'old.jpg',
    );
    final added = _cloud('openlist', '/Other/E01.mkv');
    await repository.replaceSource(
        'openlist', [old, added], const {}, const {}, const ['/']);
    final count = await repository.updateMatching(
      'openlist',
      (item) => item.remotePath == '/Show/E01.mkv',
      (item) => item.replaceTmdb(tmdbId: 2, tmdbTitle: '新标题'),
    );
    final items = await repository.getBySource('openlist');
    expect(count, 1);
    expect(items, hasLength(2));
    final updated =
        items.firstWhere((item) => item.remotePath.contains('Show'));
    expect(updated.tmdbOverview, isNull);
    expect(updated.posterCachePath, isNull);
  });

  test('LocalController 按来源调用真实扫描后重读索引', () async {
    final sourceRepository =
        CloudSourceRepository(storage: MemoryCloudSourceStorage());
    await sourceRepository.save(_source('openlist', '家庭网盘', enabled: true));
    final indexRepository =
        CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
    final calls = <String>[];
    final controller = LocalController(
      cloudSourceRepository: sourceRepository,
      cloudMediaIndexRepository: indexRepository,
      scanCloudSource: (sourceId) async {
        calls.add(sourceId);
        await indexRepository.replaceSource(
            sourceId,
            [_cloud(sourceId, '/New/E01.mkv')],
            const {},
            const {},
            const ['/']);
      },
    );
    expect(await controller.refreshCloudLibrarySource('openlist'), isTrue);
    expect(calls, ['openlist']);
    expect(controller.cloudLibraryItems.single.remotePath, '/New/E01.mkv');
  });

  test('海报下载失败不会遗留临时文件', () async {
    final root = await Directory.systemTemp.createTemp('cloud-poster-fail-');
    addTearDown(() => root.delete(recursive: true));
    final cache = CloudPosterCache(
        cacheRoot: root,
        downloader: (_) async => throw const FileSystemException('partial'));
    await cache.resolve(sourceId: 's', stableId: 'id', url: 'https://a/1');
    final files =
        await root.list(recursive: true).where((e) => e is File).toList();
    expect(files.where((e) => e.path.endsWith('.tmp')), isEmpty);
  });

  test('云 TMDB 自动匹配和手动候选只更新云索引', () async {
    final repository =
        CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
    await repository.replaceSource('openlist',
        [_cloud('openlist', '/Show/E01.mkv')], const {}, const {}, const ['/']);
    final candidate = TmdbMetadata(
      id: 7,
      mediaType: TmdbMediaType.tv,
      title: 'Show',
      language: 'zh-CN',
      matchedAt: DateTime(2026),
      matchConfidence: 1,
      posterUrl: '/p.jpg',
    );
    final service = CloudTmdbMetadataService(
        repository: repository, client: _FakeTmdbClient(candidate));
    final outcome =
        await service.match(sourceId: 'openlist', seriesName: 'Show');
    expect(outcome.selected?.id, 7);
    expect((await repository.getBySource('openlist')).single.tmdbId, 7);
    expect(Directory('/Show').existsSync(), isFalse);
  });

  test('真实多季度目录从扫描到刮削只请求一次详情并保留真实播放引用', () async {
    const source = CloudSource(
      id: 'quark-e2e',
      type: CloudSourceType.quark,
      name: '夸克测试库',
      baseUrl: 'https://drive.example.com',
      rootPaths: <String>['/影视'],
    );
    const workName = '154332_《边界测试剧3》(2025) 4K 全6集 内附第一二季';
    const workPath = '/影视/$workName';
    const season1Path = '$workPath/第一季';
    const season2Path = '$workPath/第二季';
    const season3FirstPath =
        '$workPath/第 3 季 - 2160p WEB-DL H265 DDP 5.1 Atmos';
    const season3SecondPath = '$workPath/第三季（2025）4K DV&HDR';
    final drive = _EndToEndCloudClient(<String, List<CloudFileEntry>>{
      '/影视': <CloudFileEntry>[_directory('work', workPath)],
      workPath: <CloudFileEntry>[
        _directory('season-1', season1Path),
        _directory('season-2', season2Path),
        _directory('season-3-a', season3FirstPath),
        _directory('season-3-b', season3SecondPath),
        _directory('advertisement', '$workPath/0001更多资源请访问'),
      ],
      season1Path: <CloudFileEntry>[
        _remoteVideo('s1e1', '$season1Path/01.mkv'),
      ],
      season2Path: <CloudFileEntry>[
        _remoteVideo('s2e1', '$season2Path/01.mkv'),
      ],
      season3FirstPath: <CloudFileEntry>[
        _remoteVideo('s3e1', '$season3FirstPath/01.mkv'),
        _remoteVideo('s3e2', '$season3FirstPath/02.mkv'),
        _remoteVideo('promotion', '$season3FirstPath/更多【神秘入口】.png'),
      ],
      season3SecondPath: <CloudFileEntry>[
        _remoteVideo('s3e3', '$season3SecondPath/03.mkv'),
      ],
    });
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    final scan = await CloudMediaIndexer(
      repository: indexRepository,
      minRecognizedVideoSizeBytesProvider: () => 100,
    ).scan(source: source, client: drive);
    final snapshot = await indexRepository.snapshot(source.id);
    final tree = const CloudMediaTreeResolver().resolve(
      sourceId: source.id,
      configuredRoots: source.rootPaths,
      directoryEntries: snapshot.directoryEntries,
      minSizeBytes: 100,
    );
    final workRepository = CloudWorkTmdbRepository(
      storage: MemoryCloudWorkTmdbStorage(),
    );
    final tmdb = _EndToEndTmdbClient();
    final coordinator = CloudWorkTmdbCoordinator(
      repository: workRepository,
      legacyRepository: CloudResourceTmdbRepository(
        storage: MemoryCloudResourceTmdbStorage(),
      ),
      indexRepository: indexRepository,
      serviceFactory: (_) => CloudWorkTmdbService(
        repository: workRepository,
        indexRepository: indexRepository,
        client: tmdb,
        posterCache: _EndToEndPosterCache(),
        now: () => DateTime.utc(2026, 7, 20),
      ),
      apiKeyProvider: () => 'test-key',
      now: () => DateTime.utc(2026, 7, 20),
    );

    await coordinator.loadAndSchedule(tree);
    final collection = CloudResourceCollectionGrouper().group(
      items: await indexRepository.getBySource(source.id),
      works: tree.works,
      recordsByWorkKey: coordinator.recordsByWorkKey,
      query: '',
    );

    expect(scan.videoCount, 5);
    expect(tree.ignored.map((entry) => entry.id), contains('promotion'));
    expect(collection.groups, hasLength(3));
    expect(tmdb.searchCalls, 1);
    expect(tmdb.detailCalls, 1);
    expect(
      collection.groups.map((group) => group.seasonMetadata?.seasonNumber),
      <int?>[1, 2, 3],
    );
    expect(
      collection.groups.map((group) => group.seasonMetadata?.posterUrl),
      <String?>['/season-1.jpg', '/season-2.jpg', '/season-3.jpg'],
    );
    final episode = collection.groups.last.videos.first;
    expect(episode.name, 'TMDB 中文标题 S03E01.mkv');
    expect(episode.id, 's3e1');
    expect(episode.remotePath, '$season3FirstPath/01.mkv');
    await drive.resolvePlayback(
      CloudRemoteRef(id: episode.id, path: episode.remotePath),
    );
    expect(drive.lastPlaybackRef?.id, 's3e1');
    expect(drive.lastPlaybackRef?.path, '$season3FirstPath/01.mkv');
  });

  testWidgets('本地媒体库不显示网盘资源和网盘来源入口', (tester) async {
    final controller = LocalController();
    controller.localLibraryItems.add(
      _genreLocal('local-movie', '本地作品', const <String>['剧情']),
    );
    controller.cloudLibrarySources
        .add(_source('openlist', '家庭网盘', enabled: true));
    controller.cloudLibraryItems.add(
      _genreCloud('cloud-movie', '网盘作品', const <String>['网盘独有']),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibrarySheetContent(
          controller: controller,
          onPlay: (_, __) {},
          onRefresh: () {},
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('本地作品'), findsOneWidget);
    expect(find.text('网盘作品'), findsNothing);
    expect(find.text('家庭网盘'), findsNothing);
    expect(find.byTooltip('筛选媒体来源'), findsNothing);
    expect(find.byTooltip('网盘系列操作'), findsNothing);
  });

  testWidgets('只有网盘资源时本地媒体库仍显示本地空状态', (tester) async {
    final controller = LocalController();
    controller.cloudLibrarySources.add(CloudSource(
      id: 'openlist',
      type: CloudSourceType.openList,
      name: '家庭网盘',
      baseUrl: 'https://drive.example.com',
      rootPaths: const <String>['/动漫'],
      scanStatus: CloudScanStatus.completed,
      lastScannedAt: DateTime(2026, 7, 15),
    ));
    controller.cloudLibraryItems.add(
      _genreCloud('cloud-only', '网盘作品', const <String>['科幻']),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibrarySheetContent(
          controller: controller,
          onPlay: (_, __) {},
          onRefresh: () {},
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('媒体库还没有内容'), findsOneWidget);
    expect(find.text('扫描已添加的本地媒体源后，可以按系列查看视频。'), findsOneWidget);
    expect(find.text('重新扫描网盘'), findsNothing);
    expect(find.text('网盘作品'), findsNothing);
  });

  testWidgets('本地类型菜单支持多选且不包含网盘独有标签', (tester) async {
    final controller = LocalController();
    controller.localLibraryItems.addAll(<LocalMediaIndexItem>[
      _genreLocal('animation', '动画作品', const <String>['动画']),
      _genreLocal('science-fiction', '科幻作品', const <String>['科幻']),
      _genreLocal('documentary', '纪录片作品', const <String>['纪录片']),
    ]);
    controller.cloudLibrarySources
        .add(_source('openlist', '家庭网盘', enabled: true));
    controller.cloudLibraryItems.add(
      _genreCloud('cloud-only', '网盘作品', const <String>['网盘独有']),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibrarySheetContent(
          controller: controller,
          onPlay: (_, __) {},
          onRefresh: () {},
        ),
      ),
    ));

    await tester.tap(find.byTooltip('筛选 TMDB 类型'));
    await tester.pumpAndSettle();
    expect(find.text('网盘独有'), findsNothing);
    await tester.tap(_checkedGenreItem('动画'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('筛选 TMDB 类型'));
    await tester.pumpAndSettle();
    await tester.tap(_checkedGenreItem('科幻'));
    await tester.pumpAndSettle();

    expect(find.text('类型 2'), findsOneWidget);
    expect(find.text('动画作品'), findsOneWidget);
    expect(find.text('科幻作品'), findsOneWidget);
    expect(find.text('纪录片作品'), findsNothing);

    await tester.tap(find.byTooltip('筛选 TMDB 类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(find.text('纪录片作品'), findsOneWidget);
  });

  testWidgets('类型补齐失败时保留轻量重试入口', (tester) async {
    final controller = LocalController();
    controller.localLibraryItems.add(
      _genreLocal('animation', '动画作品', const <String>['动画']),
    );
    controller.libraryGenreRefreshError = '1 个作品暂时无法更新';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibrarySheetContent(
          controller: controller,
          onPlay: (_, __) {},
          onRefresh: () {},
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('1 个作品暂时无法更新'), findsOneWidget);
    expect(find.byTooltip('刷新类型标签'), findsOneWidget);
  });

  testWidgets('本地标签入口显示分类并支持保存自定义标签', (tester) async {
    final controller = LocalController();
    controller.localLibraryItems.add(
      _genreLocal('custom-tag', '自定义作品', const <String>['动画']),
    );
    final tagRepository = _MemoryLocalMediaTagRepository();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LibrarySheetContent(
          controller: controller,
          tagRepository: tagRepository,
          onPlay: (_, __) {},
          onRefresh: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('筛选 TMDB 类型'));
    await tester.pumpAndSettle();
    expect(find.text('分类'), findsOneWidget);
    expect(find.text('动漫'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('播放选项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理标签'));
    await tester.pumpAndSettle();
    final tagInput = find.byType(TextField).last;
    await tester.enterText(tagInput, '收藏');
    await tester.tap(find.byTooltip('添加标签'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('收藏'), findsOneWidget);
    await tester.tap(find.byTooltip('筛选 TMDB 类型'));
    await tester.pumpAndSettle();
    expect(find.text('自定义标签'), findsOneWidget);
    await tester.tap(_checkedGenreItem('收藏'));
    await tester.pumpAndSettle();
    expect(find.text('自定义作品'), findsOneWidget);
  });
}

class _FakeTmdbClient implements ITmdbClient {
  const _FakeTmdbClient(this.metadata);
  final TmdbMetadata metadata;
  @override
  Future<TmdbMetadata> details(int id, TmdbMediaType mediaType,
          {String language = 'zh-CN'}) async =>
      metadata;
  @override
  Future<List<TmdbMetadata>> search(String query, TmdbMediaType mediaType,
          {String language = 'zh-CN'}) async =>
      [metadata];
}

class _EndToEndCloudClient implements CloudDriveClient {
  _EndToEndCloudClient(this.directories);

  final Map<String, List<CloudFileEntry>> directories;
  CloudRemoteRef? lastPlaybackRef;

  @override
  Future<void> authenticate(
    CloudSource source,
    CloudCredential credential,
  ) async {}

  @override
  Future<void> close() async {}

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) async =>
      throw UnimplementedError();

  @override
  Future<List<CloudFileEntry>> listDirectory(CloudRemoteRef directory) async =>
      directories[directory.path] ?? const <CloudFileEntry>[];

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) async {
    lastPlaybackRef = file;
    return CloudPlaybackResource(
      uri: Uri.parse('https://download.example.com/video'),
    );
  }
}

class _EndToEndTmdbClient implements ITmdbClient {
  int searchCalls = 0;
  int detailCalls = 0;

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    searchCalls++;
    return <TmdbMetadata>[
      TmdbMetadata(
        id: 42,
        mediaType: mediaType,
        title: query,
        language: language,
        matchedAt: DateTime.utc(2026, 7, 20),
        matchConfidence: 1,
      ),
    ];
  }

  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    detailCalls++;
    return TmdbMetadata(
      id: id,
      mediaType: mediaType,
      title: 'TMDB 中文标题',
      posterUrl: '/poster.jpg',
      language: language,
      matchedAt: DateTime.utc(2026, 7, 20),
      matchConfidence: 1,
      seasons: <TmdbSeasonMetadata>[
        for (var season = 1; season <= 3; season++)
          TmdbSeasonMetadata(
            id: season * 100,
            seasonNumber: season,
            name: '第 $season 季',
            episodeCount: season == 3 ? 3 : 1,
            posterUrl: '/season-$season.jpg',
          ),
      ],
    );
  }
}

class _EndToEndPosterCache extends CloudPosterCache {
  _EndToEndPosterCache()
      : super(
          cacheRoot: Directory.systemTemp,
          downloader: (_) async => const <int>[1],
        );

  @override
  Future<String> resolve({
    required String sourceId,
    required String stableId,
    required String url,
  }) async =>
      'C:/cache/${stableId.hashCode}.jpg';
}

CloudFileEntry _directory(String id, String path) => CloudFileEntry(
      id: id,
      remotePath: path,
      name: path.split('/').last,
      size: 0,
      modifiedAt: DateTime.utc(2026, 7, 20),
      isDirectory: true,
    );

CloudFileEntry _remoteVideo(String id, String path) => CloudFileEntry(
      id: id,
      remotePath: path,
      name: path.split('/').last,
      size: 200,
      modifiedAt: DateTime.utc(2026, 7, 20),
      isDirectory: false,
    );

CloudMediaIndexItem _cloud(String sourceId, String path,
    {int season = 1,
    int? episode = 1,
    String? workKey,
    String seriesName = 'Show',
    CloudMediaType type = CloudMediaType.episode}) {
  return CloudMediaIndexItem(
    sourceId: sourceId,
    remoteId: path,
    remotePath: path,
    name: path.split('/').last,
    workKey: workKey,
    size: 10,
    modifiedAt: DateTime(2026),
    seriesName: seriesName,
    seasonNumber: season,
    episodeNumber: episode,
    mediaType: type,
  );
}

CloudMediaIndexItem _genreCloud(
  String id,
  String title,
  List<String> genres,
) {
  return CloudMediaIndexItem(
    sourceId: 'openlist',
    remoteId: id,
    remotePath: '/$id.mkv',
    name: '$id.mkv',
    size: 10,
    modifiedAt: DateTime(2026),
    seriesName: title,
    mediaType: CloudMediaType.movie,
    tmdbId: id.hashCode,
    tmdbTitle: title,
    tmdbGenres: genres,
  );
}

LocalMediaIndexItem _genreLocal(
  String id,
  String title,
  List<String> genres,
) {
  return LocalMediaIndexItem(
    path: 'C:\\Media\\$id\\$id.mkv',
    name: '$id.mkv',
    parentPath: 'C:\\Media\\$id',
    sourcePath: r'C:\Media',
    size: 10,
    modified: DateTime.utc(2026, 8, 4),
    seriesName: title,
    indexedAt: DateTime.utc(2026, 8, 4),
    tmdb: TmdbMetadata(
      id: id.hashCode,
      mediaType: TmdbMediaType.movie,
      title: title,
      genres: genres,
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 8, 4),
      matchConfidence: 1,
    ),
  );
}

Finder _checkedGenreItem(String value) {
  return find.byWidgetPredicate(
    (widget) => widget is CheckedPopupMenuItem<String> && widget.value == value,
  );
}

class _MemoryLocalMediaTagRepository implements ILocalMediaTagRepository {
  final Map<String, List<String>> values = <String, List<String>>{};

  @override
  Map<String, List<String>> getAll() {
    return values.map(
      (key, tags) => MapEntry(key, List<String>.unmodifiable(tags)),
    );
  }

  @override
  Future<void> saveForSeries(String seriesKey, Iterable<String> tags) async {
    final normalized = tags.toList(growable: false);
    if (normalized.isEmpty) {
      values.remove(seriesKey);
    } else {
      values[seriesKey] = normalized;
    }
  }
}

CloudSource _source(String id, String name,
    {required bool enabled, CloudSourceType type = CloudSourceType.openList}) {
  return CloudSource(
    id: id,
    type: type,
    name: name,
    baseUrl: 'https://example.com',
    rootPaths: const ['/'],
    enabled: enabled,
  );
}
