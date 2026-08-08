import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/services/cloud/cloud_media_tree_resolver.dart';

void main() {
  group('CloudMediaTreeResolver', () {
    const resolver = CloudMediaTreeResolver();

    test('名称含发布站网址的剧集目录仍扫描其中分集', () {
      const releaseName =
          '[高清剧集发布 www.BBHDTV.com] 财阀家的小儿子[全16集][中文字幕].Reborn.Rich.S01.2160p.TVING.WEB-DL.H265.AAC-ColorTV';
      const workPath = '/剧集/$releaseName';
      final directoryEntries = <String, List<CloudFileEntry>>{
        '/剧集': <CloudFileEntry>[
          _dir('reborn-rich', workPath, releaseName),
        ],
        workPath: <CloudFileEntry>[
          _video(
            'reborn-rich-1',
            '$workPath/Reborn.Rich.S01E01.2160p.WEB-DL.H265.AAC.mkv',
            'Reborn.Rich.S01E01.2160p.WEB-DL.H265.AAC.mkv',
          ),
          _video(
            'reborn-rich-2',
            '$workPath/Reborn.Rich.S01E02.2160p.WEB-DL.H265.AAC.mkv',
            'Reborn.Rich.S01E02.2160p.WEB-DL.H265.AAC.mkv',
          ),
        ],
      };

      for (final configuredRoot in <String>['/剧集', workPath]) {
        final tree = resolver.resolve(
          sourceId: 'quark-a',
          configuredRoots: <String>[configuredRoot],
          directoryEntries: directoryEntries,
          minSizeBytes: 100,
        );

        expect(tree.works, hasLength(1), reason: configuredRoot);
        final work = tree.works.single;
        expect(work.seasons, hasLength(1), reason: configuredRoot);
        expect(
          work.seasons.single.episodes.map(
            (episode) => episode.episodeNumber,
          ),
          <int>[1, 2],
          reason: configuredRoot,
        );
        expect(
          work.titleCandidates.any((title) => title.contains('BBHDTV.com')),
          isFalse,
          reason: configuredRoot,
        );
        expect(
          tree.ignored.any(
            (entry) =>
                entry.id == 'reborn-rich-1' || entry.id == 'reborn-rich-2',
          ),
          isFalse,
          reason: configuredRoot,
        );
      }
    });

    test('同目录方括号发布名按共同剧名合并分集', () {
      const workPath = '/动漫/假面骑士OOO';
      final hashes = <String>['9F632FDD', '5A8A1BD9', 'B3F01416'];
      final tree = resolver.resolve(
        sourceId: 'baidu-a',
        configuredRoots: const <String>[workPath],
        directoryEntries: <String, List<CloudFileEntry>>{
          workPath: <CloudFileEntry>[
            for (var index = 0; index < hashes.length; index++)
              _video(
                'episode-${index + 1}',
                '$workPath/[KRL][Kamen Rider OOO][0${index + 1}][BDRip][1080P][x265_AC3][Main10][${hashes[index]}].mkv',
                '[KRL][Kamen Rider OOO][0${index + 1}][BDRip][1080P][x265_AC3][Main10][${hashes[index]}].mkv',
              ),
          ],
        },
        minSizeBytes: 100,
      );

      expect(tree.works, hasLength(1));
      final work = tree.works.single;
      expect(work.displayTitle, 'Kamen Rider OOO');
      expect(work.titleCandidates.first, 'Kamen Rider OOO');
      expect(
        work.titleCandidates
            .where((title) => title.contains(RegExp(r'[0-9A-F]{8}'))),
        isEmpty,
      );
      expect(work.seasons, hasLength(1));
      expect(
        work.seasons.single.episodes.map((episode) => episode.episodeNumber),
        <int>[1, 2, 3],
      );
    });

    test('标准分集与最终话剪辑版混放时仍归并标准分集', () {
      const seriesRoot = '/A视频/[2010] 假面骑士OOO';
      const workPath = '/A视频/[2010] 假面骑士OOO/OOO TV';
      final tree = resolver.resolve(
        sourceId: 'baidu-a',
        configuredRoots: const <String>['/A视频'],
        directoryEntries: <String, List<CloudFileEntry>>{
          '/A视频': <CloudFileEntry>[
            _dir('ooo-root', seriesRoot, '[2010] 假面骑士OOO'),
          ],
          seriesRoot: <CloudFileEntry>[
            _dir('ooo-tv', workPath, 'OOO TV'),
          ],
          workPath: <CloudFileEntry>[
            for (var episode = 1; episode <= 3; episode++)
              _video(
                'ooo-$episode',
                '$workPath/[KRL][Kamen Rider OOO][0$episode][BDRip][1080P][x265_AC3][Main10][9F632FD$episode].mkv',
                '[KRL][Kamen Rider OOO][0$episode][BDRip][1080P][x265_AC3][Main10][9F632FD$episode].mkv',
              ),
            _video(
              'final-cut',
              '$workPath/[PKM][假面骑士OOO最终话][DC][正式特效][x264].mkv',
              '[PKM][假面骑士OOO最终话][DC][正式特效][x264].mkv',
            ),
          ],
        },
        minSizeBytes: 100,
      );

      final series = tree.works.singleWhere((work) => work.seasons.isNotEmpty);
      expect(series.displayTitle, 'Kamen Rider OOO');
      expect(series.seasons.single.episodes, hasLength(3));
      expect(
        tree.works.where((work) =>
            work.standaloneVideos.any((video) => video.id == 'final-cut')),
        hasLength(1),
      );
    });

    test('迪迦奥特曼连续编号文件合并为一季五十二集', () {
      const workPath = '/视频/【日剧】迪迦奥特曼.全52集.国语配音中字.珍藏版.1996.1080P';
      final tree = resolver.resolve(
        sourceId: 'quark-a',
        configuredRoots: const <String>['/视频', workPath],
        directoryEntries: <String, List<CloudFileEntry>>{
          '/视频': <CloudFileEntry>[
            _dir('tiga-root', workPath, '【日剧】迪迦奥特曼.全52集.国语配音中字.珍藏版.1996.1080P'),
          ],
          workPath: <CloudFileEntry>[
            for (var episode = 1; episode <= 52; episode++)
              _video(
                'tiga-$episode',
                '$workPath/迪迦奥特曼${episode.toString().padLeft(2, '0')}.mp4',
                '迪迦奥特曼${episode.toString().padLeft(2, '0')}.mp4',
              ),
          ],
        },
        minSizeBytes: 100,
      );

      expect(tree.works, hasLength(1));
      final work = tree.works.single;
      expect(work.displayTitle, '迪迦奥特曼');
      expect(work.seasons, hasLength(1));
      expect(work.seasons.single.episodes, hasLength(52));
      expect(
        work.seasons.single.episodes.map((episode) => episode.episodeNumber),
        List<int>.generate(52, (index) => index + 1),
      );
    });

    test('真实多季度目录合并同季目录并继承纯数字集号', () {
      const workName = '154332_《弥留之国的爱丽丝3》(2025) 4K 全6集 内附第一二季';
      const workPath = '/影视/$workName';
      const season1Path = '$workPath/第一季';
      const season2Path = '$workPath/第二季';
      const season3FirstPath =
          '$workPath/第 3 季 - 2160p WEB-DL H265 DDP 5.1 Atmos';
      const season3SecondPath = '$workPath/第三季（2025）4K DV&HDR';
      final tree = resolver.resolve(
        sourceId: 'quark-a',
        configuredRoots: const <String>[
          '/影视',
          workPath,
          season1Path,
          season2Path,
          season3FirstPath,
        ],
        directoryEntries: <String, List<CloudFileEntry>>{
          '/影视': <CloudFileEntry>[
            _dir('work-a', workPath, workName),
          ],
          workPath: <CloudFileEntry>[
            _dir('season-1', season1Path, '第一季'),
            _dir('season-2', season2Path, '第二季'),
            _dir(
              'season-3-a',
              season3FirstPath,
              '第 3 季 - 2160p WEB-DL H265 DDP 5.1 Atmos',
            ),
            _dir(
              'season-3-b',
              season3SecondPath,
              '第三季（2025）4K DV&HDR',
            ),
            _dir(
                'ad-1', '$workPath/0001更多资源请访问 00t.vip', '0001更多资源请访问 00t.vip'),
            _dir('ad-2', '$workPath/0002全网搜索资源', '0002全网搜索资源'),
          ],
          season1Path: <CloudFileEntry>[
            _video(
              's1e1',
              '$season1Path/弥留之国的爱丽丝.S01E01.2160p.mkv',
              '弥留之国的爱丽丝.S01E01.2160p.mkv',
            ),
          ],
          season2Path: <CloudFileEntry>[
            _video(
              's2e1',
              '$season2Path/Alice in Borderland S02E01.mkv',
              'Alice in Borderland S02E01.mkv',
            ),
          ],
          season3FirstPath: <CloudFileEntry>[
            for (var episode = 1; episode <= 3; episode++)
              _video(
                's3a-$episode',
                '$season3FirstPath/${episode.toString().padLeft(2, '0')}.mkv',
                '${episode.toString().padLeft(2, '0')}.mkv',
              ),
          ],
          season3SecondPath: <CloudFileEntry>[
            for (var episode = 4; episode <= 6; episode++)
              _video(
                's3b-$episode',
                '$season3SecondPath/${episode.toString().padLeft(2, '0')}.mkv',
                '${episode.toString().padLeft(2, '0')}.mkv',
              ),
            _file(
              'promotion',
              '$season3SecondPath/更多【神秘入口】.png',
              '更多【神秘入口】.png',
            ),
          ],
        },
        minSizeBytes: 100,
      );

      expect(tree.works, hasLength(1));
      final work = tree.works.single;
      expect(work.displayTitle, '弥留之国的爱丽丝');
      expect(
        work.titleCandidates,
        containsAll(<String>[
          '弥留之国的爱丽丝',
          '弥留之国的爱丽丝3',
          'Alice in Borderland',
        ]),
      );
      expect(
        work.seasons.map((season) => season.seasonNumber),
        <int>[1, 2, 3],
      );
      expect(work.seasons.last.remoteDirectories, hasLength(2));
      expect(
        work.seasons.last.episodes.map((episode) => episode.episodeNumber),
        <int>[1, 2, 3, 4, 5, 6],
      );
      expect(
        work.seasons.last.episodes.first.displayName,
        '弥留之国的爱丽丝 S03E01.mkv',
      );
      expect(
        tree.ignored.map((entry) => entry.name),
        containsAll(<String>[
          '更多【神秘入口】.png',
          '0001更多资源请访问 00t.vip',
          '0002全网搜索资源',
        ]),
      );
    });

    test('同季三个版本保留二十七个文件并优先共同文件标题', () {
      const workPath = '/来自：分享/H-回-云鬼-计 【台剧】';
      const highBitratePath = '$workPath/4K 高码率';
      const embeddedPath = '$workPath/【全9集】【1080P】【内封简繁英】';
      const burnedInPath = '$workPath/【全9集】【1080P】【内嵌中字】';
      final directoryEntries = <String, List<CloudFileEntry>>{
        workPath: <CloudFileEntry>[
          _dir('4k', highBitratePath, '4K 高码率'),
          _dir('embedded', embeddedPath, '【全9集】【1080P】【内封简繁英】'),
          _dir('burned-in', burnedInPath, '【全9集】【1080P】【内嵌中字】'),
        ],
      };
      for (final (directoryId, directoryPath) in <(String, String)>[
        ('4k', highBitratePath),
        ('embedded', embeddedPath),
        ('burned-in', burnedInPath),
      ]) {
        directoryEntries[directoryPath] = <CloudFileEntry>[
          for (var episode = 1; episode <= 9; episode++)
            _video(
              '$directoryId-$episode',
              '$directoryPath/The.Resurrected.S01E${episode.toString().padLeft(2, '0')}.mkv',
              'The.Resurrected.S01E${episode.toString().padLeft(2, '0')}.mkv',
            ),
        ];
      }

      final tree = resolver.resolve(
        sourceId: 'quark-a',
        configuredRoots: const <String>[
          workPath,
          highBitratePath,
          embeddedPath,
          burnedInPath,
        ],
        directoryEntries: directoryEntries,
        minSizeBytes: 100,
      );

      expect(tree.works, hasLength(1));
      final work = tree.works.single;
      expect(work.titleCandidates.first, 'The Resurrected');
      expect(work.seasons, hasLength(1));
      expect(work.seasons.single.episodes, hasLength(27));
      expect(
        work.seasons.single.episodes
            .map((episode) => episode.episodeNumber)
            .toSet(),
        hasLength(9),
      );
      expect(
        work.seasons.single.episodes
            .where((episode) => episode.episodeNumber == 1),
        hasLength(3),
      );
      expect(
        work.seasons.single.episodes.map((episode) => episode.entry.id).toSet(),
        hasLength(27),
      );
      expect(
        work.seasons.single.episodes
            .singleWhere((episode) => episode.entry.id == '4k-1')
            .releaseTags
            .bitrate,
        '高码率',
      );
      expect(
        work.seasons.single.episodes
            .singleWhere((episode) => episode.entry.id == 'embedded-1')
            .releaseTags
            .subtitles,
        <String>['内封简繁英'],
      );
    });

    test('透明中字目录继承上级作品名并把纯数字视频归入第一季', () {
      const workPath = '/影视/正确剧名';
      const contentPath = '$workPath/内嵌中字';
      final tree = resolver.resolve(
        sourceId: 'quark-a',
        configuredRoots: const <String>['/影视'],
        directoryEntries: <String, List<CloudFileEntry>>{
          '/影视': <CloudFileEntry>[
            _dir('work', workPath, '正确剧名'),
          ],
          workPath: <CloudFileEntry>[
            _dir('content', contentPath, '内嵌中字'),
          ],
          contentPath: <CloudFileEntry>[
            for (var episode = 1; episode <= 3; episode++)
              _video(
                'episode-$episode',
                '$contentPath/${episode.toString().padLeft(2, '0')}.mp4',
                '${episode.toString().padLeft(2, '0')}.mp4',
              ),
          ],
        },
        minSizeBytes: 100,
      );

      expect(tree.works, hasLength(1));
      final work = tree.works.single;
      expect(work.displayTitle, '正确剧名');
      expect(work.standaloneVideos, isEmpty);
      expect(work.seasons, hasLength(1));
      expect(work.seasons.single.seasonNumber, 1);
      expect(
        work.seasons.single.episodes.map((episode) => episode.episodeNumber),
        <int>[1, 2, 3],
      );
      expect(
        work.seasons.single.episodes.first.displayName,
        '正确剧名 S01E01.mp4',
      );
    });

    test('配置根目录本身为透明中字目录时继承路径中的作品名', () {
      const contentPath = '/影视/正确剧名/内嵌中字';
      final tree = resolver.resolve(
        sourceId: 'quark-a',
        configuredRoots: const <String>[contentPath],
        directoryEntries: <String, List<CloudFileEntry>>{
          contentPath: <CloudFileEntry>[
            for (var episode = 1; episode <= 3; episode++)
              _video(
                'episode-$episode',
                '$contentPath/${episode.toString().padLeft(2, '0')}.mkv',
                '${episode.toString().padLeft(2, '0')}.mkv',
              ),
          ],
        },
        minSizeBytes: 100,
      );

      expect(tree.works, hasLength(1));
      final work = tree.works.single;
      expect(work.displayTitle, '正确剧名');
      expect(work.standaloneVideos, isEmpty);
      expect(work.seasons.single.seasonNumber, 1);
      expect(
        work.seasons.single.episodes.map((episode) => episode.displayName),
        <String>[
          '正确剧名 S01E01.mkv',
          '正确剧名 S01E02.mkv',
          '正确剧名 S01E03.mkv',
        ],
      );
    });

    test('配置根目录本身为带规格的季度目录时继承剧名和季号', () {
      const seasonPath = '/影视/正确剧名/第 3 季 - 2160p WEB-DL H265 DDP 5.1 Atmos';
      final tree = resolver.resolve(
        sourceId: 'quark-a',
        configuredRoots: const <String>[seasonPath],
        directoryEntries: <String, List<CloudFileEntry>>{
          seasonPath: <CloudFileEntry>[
            for (var episode = 1; episode <= 3; episode++)
              _video(
                'episode-$episode',
                '$seasonPath/${episode.toString().padLeft(2, '0')}.mkv',
                '${episode.toString().padLeft(2, '0')}.mkv',
              ),
          ],
        },
        minSizeBytes: 100,
      );

      expect(tree.works, hasLength(1));
      final work = tree.works.single;
      expect(work.displayTitle, '正确剧名');
      expect(work.standaloneVideos, isEmpty);
      expect(work.seasons.single.seasonNumber, 3);
      expect(
        work.seasons.single.episodes.map((episode) => episode.displayName),
        <String>[
          '正确剧名 S03E01.mkv',
          '正确剧名 S03E02.mkv',
          '正确剧名 S03E03.mkv',
        ],
      );
    });

    test('配置根目录本身为作品目录时归并直接存放的纯集号文件', () {
      const workPath = '/影视/正确剧名';
      final tree = resolver.resolve(
        sourceId: 'quark-a',
        configuredRoots: const <String>[workPath],
        directoryEntries: <String, List<CloudFileEntry>>{
          workPath: <CloudFileEntry>[
            for (var episode = 1; episode <= 3; episode++)
              _video(
                'episode-$episode',
                '$workPath/${episode.toString().padLeft(2, '0')}.mkv',
                '${episode.toString().padLeft(2, '0')}.mkv',
              ),
          ],
        },
        minSizeBytes: 100,
      );

      expect(tree.works, hasLength(1));
      final work = tree.works.single;
      expect(work.displayTitle, '正确剧名');
      expect(work.standaloneVideos, isEmpty);
      expect(work.seasons.single.seasonNumber, 1);
      expect(
        work.seasons.single.episodes.map((episode) => episode.episodeNumber),
        <int>[1, 2, 3],
      );
    });

    test('配置根目录本身为作品目录时归并其多个季度目录', () {
      const workPath = '/影视/正确剧名';
      const season1Path = '$workPath/第一季';
      const season2Path = '$workPath/第二季';
      final tree = resolver.resolve(
        sourceId: 'quark-a',
        configuredRoots: const <String>[workPath],
        directoryEntries: <String, List<CloudFileEntry>>{
          workPath: <CloudFileEntry>[
            _dir('season-1', season1Path, '第一季'),
            _dir('season-2', season2Path, '第二季'),
          ],
          season1Path: <CloudFileEntry>[
            _video('s1e1', '$season1Path/01.mkv', '01.mkv'),
          ],
          season2Path: <CloudFileEntry>[
            _video('s2e1', '$season2Path/01.mkv', '01.mkv'),
          ],
        },
        minSizeBytes: 100,
      );

      expect(tree.works, hasLength(1));
      final work = tree.works.single;
      expect(work.displayTitle, '正确剧名');
      expect(
        work.seasons.map((season) => season.seasonNumber),
        <int>[1, 2],
      );
    });

    test('百度纯集号视频继承目录剧名季度并保留多个版本', () {
      const workPath = '/剧集/回魂计';
      const seasonPath = '$workPath/第二季';
      final tree = resolver.resolve(
        sourceId: 'baidu-a',
        configuredRoots: const <String>[workPath],
        directoryEntries: <String, List<CloudFileEntry>>{
          workPath: <CloudFileEntry>[
            _dir('season-2', seasonPath, '第二季'),
          ],
          seasonPath: <CloudFileEntry>[
            _video('1001', '$seasonPath/01.mkv', '01.mkv'),
            _video('1002', '$seasonPath/01.mp4', '01.mp4'),
            _video('1003', '$seasonPath/02.mkv', '02.mkv'),
          ],
        },
        minSizeBytes: 100,
      );

      expect(tree.sourceId, 'baidu-a');
      expect(tree.works, hasLength(1));
      final work = tree.works.single;
      expect(work.displayTitle, '回魂计');
      expect(work.seasons.single.seasonNumber, 2);
      expect(work.seasons.single.episodes, hasLength(3));
      expect(
        work.seasons.single.episodes.map((episode) => episode.episodeNumber),
        <int>[1, 1, 2],
      );
      expect(
        work.seasons.single.episodes.map((episode) => episode.entry.id).toSet(),
        <String>{'1001', '1002', '1003'},
      );
    });

    test('媒体集合根同时存在独立电影时不与季度目录误合并', () {
      const rootPath = '/影视';
      const seasonPath = '$rootPath/Season 1';
      final tree = resolver.resolve(
        sourceId: 'quark-a',
        configuredRoots: const <String>[rootPath],
        directoryEntries: <String, List<CloudFileEntry>>{
          rootPath: <CloudFileEntry>[
            _video('movie', '$rootPath/独立电影.mkv', '独立电影.mkv'),
            _dir('season', seasonPath, 'Season 1'),
          ],
          seasonPath: <CloudFileEntry>[
            _video('episode', '$seasonPath/01.mkv', '01.mkv'),
          ],
        },
        minSizeBytes: 100,
      );

      expect(tree.works, hasLength(2));
    });

    test('正剧目录中的不同剧场版拆分作品且同片版本归并', () {
      const root = '/动漫/示例作品';
      const season = '$root/第一季';
      const movies = '$root/剧场版';
      final tree = resolver.resolve(
        sourceId: 'quark-a',
        configuredRoots: const <String>[root],
        directoryEntries: <String, List<CloudFileEntry>>{
          root: <CloudFileEntry>[
            _dir('season', season, '第一季'),
            _dir('movies', movies, '剧场版'),
          ],
          season: <CloudFileEntry>[
            _video('e1', '$season/01.mkv', '01.mkv'),
            _video('e2', '$season/02.mkv', '02.mkv'),
          ],
          movies: <CloudFileEntry>[
            _video(
              'a4k',
              '$movies/示例作品 剧场版 A 2160p.mkv',
              '示例作品 剧场版 A 2160p.mkv',
            ),
            _video(
              'a1080',
              '$movies/示例作品 剧场版 A 1080p.mkv',
              '示例作品 剧场版 A 1080p.mkv',
            ),
            _video(
              'b',
              '$movies/示例作品 剧场版 B.mkv',
              '示例作品 剧场版 B.mkv',
            ),
          ],
        },
        minSizeBytes: 100,
      );

      expect(tree.works, hasLength(3));
      expect(
        tree.works.where((work) => work.seasons.isNotEmpty),
        hasLength(1),
      );
      final moviesByTitle = <String, CloudWorkIdentity>{
        for (final work in tree.works.where((work) => work.seasons.isEmpty))
          work.displayTitle: work,
      };
      expect(
        moviesByTitle['示例作品 剧场版 A']!.standaloneVideos,
        hasLength(2),
      );
      expect(
        moviesByTitle['示例作品 剧场版 B']!.standaloneVideos,
        hasLength(1),
      );
      expect(
        moviesByTitle.values.map((work) => work.workKey).toSet(),
        hasLength(2),
      );
      expect(
        moviesByTitle['示例作品 剧场版 A']!
            .releaseTagsFor(
              moviesByTitle['示例作品 剧场版 A']!.standaloneVideos.first,
            )
            .resolution,
        isNotNull,
      );
    });

    test('同名电影年份不同不合并且电影键按来源和根目录隔离', () {
      CloudMediaTree build(String sourceId, String root) => resolver.resolve(
            sourceId: sourceId,
            configuredRoots: <String>[root],
            directoryEntries: <String, List<CloudFileEntry>>{
              root: <CloudFileEntry>[
                _video('old', '$root/示例电影 2024.mkv', '示例电影 2024.mkv'),
                _video('new', '$root/示例电影 2026.mkv', '示例电影 2026.mkv'),
              ],
            },
            minSizeBytes: 100,
          );

      final first = build('quark-a', '/电影/A');
      final anotherRoot = build('quark-a', '/电影/B');
      final anotherSource = build('openlist-a', '/电影/A');

      expect(first.works, hasLength(2));
      expect(first.works.map((work) => work.workKey).toSet(), hasLength(2));
      expect(
        first.works.map((work) => work.workKey).toSet().intersection(
              anotherRoot.works.map((work) => work.workKey).toSet(),
            ),
        isEmpty,
      );
      expect(
        first.works.map((work) => work.workKey).toSet().intersection(
              anotherSource.works.map((work) => work.workKey).toSet(),
            ),
        isEmpty,
      );
    });

    test('遍历多个媒体根并隔离同名异目录作品', () {
      final directoryEntries = <String, List<CloudFileEntry>>{
        '/剧集': <CloudFileEntry>[],
        '/电影': <CloudFileEntry>[],
      };
      for (final (index, title) in <String>[
        '葬送的芙莉莲',
        'The 100',
        '1923',
        '同名作品',
      ].indexed) {
        final workPath = '/剧集/$title';
        final seasonPath = '$workPath/Season 1';
        directoryEntries['/剧集']!.add(_dir('tv-$index', workPath, title));
        directoryEntries[workPath] = <CloudFileEntry>[
          _dir('tv-$index-season', seasonPath, 'Season 1'),
        ];
        directoryEntries[seasonPath] = <CloudFileEntry>[
          _video('tv-$index-episode', '$seasonPath/01.mkv', '01.mkv'),
        ];
      }
      for (final (index, title) in <String>[
        '流浪地球2',
        '同名作品',
      ].indexed) {
        final workPath = '/电影/$title';
        directoryEntries['/电影']!.add(
          _dir('movie-$index', workPath, title),
        );
        directoryEntries[workPath] = <CloudFileEntry>[
          _video(
            'movie-$index-video',
            '$workPath/$title 2023 4K.mkv',
            '$title 2023 4K.mkv',
          ),
        ];
      }

      final tree = resolver.resolve(
        sourceId: 'quark-a',
        configuredRoots: const <String>['/剧集', '/电影'],
        directoryEntries: directoryEntries,
        minSizeBytes: 100,
      );

      expect(
        tree.works.map((work) => work.displayTitle),
        containsAll(<String>[
          '葬送的芙莉莲',
          'The 100',
          '1923',
          '流浪地球2',
        ]),
      );
      expect(
        tree.works
            .where((work) => work.displayTitle == '同名作品')
            .map((work) => work.workKey)
            .toSet(),
        hasLength(2),
      );
      expect(
        tree.works
            .where((work) => work.displayTitle == '流浪地球2')
            .single
            .standaloneVideos,
        hasLength(1),
      );
    });

    test('显式文件季号与目录季号冲突时记录冲突且不覆盖目录', () {
      final tree = resolver.resolve(
        sourceId: 'openlist-a',
        configuredRoots: const <String>['/剧集'],
        directoryEntries: <String, List<CloudFileEntry>>{
          '/剧集': <CloudFileEntry>[
            _dir('work', '/剧集/测试作品', '测试作品'),
          ],
          '/剧集/测试作品': <CloudFileEntry>[
            _dir('season', '/剧集/测试作品/第二季', '第二季'),
          ],
          '/剧集/测试作品/第二季': <CloudFileEntry>[
            _video(
              'valid',
              '/剧集/测试作品/第二季/测试作品 S02E02.mkv',
              '测试作品 S02E02.mkv',
            ),
            _video(
              'conflict',
              '/剧集/测试作品/第二季/测试作品 S03E01.mkv',
              '测试作品 S03E01.mkv',
            ),
          ],
        },
        minSizeBytes: 100,
      );

      expect(tree.conflicts, hasLength(1));
      expect(tree.conflicts.single.folderSeasonNumber, 2);
      expect(tree.conflicts.single.detectedSeasonNumber, 3);
      expect(
        tree.works.single.seasons.single.episodes
            .map((episode) => episode.episodeNumber),
        <int>[2],
      );
    });

    test('五十个作品在不同来源中保持独立作品键和季度身份', () {
      final directoryEntries = <String, List<CloudFileEntry>>{
        '/剧集': <CloudFileEntry>[],
      };
      const seasonNames = <String>[
        '第一季',
        '第 1 季 - 2160p WEB-DL H265',
        'Season 1',
        'S01',
      ];
      for (var index = 0; index < 50; index++) {
        final title = switch (index) {
          0 => '中文作品',
          1 => 'English Show',
          2 => '中英双语 Bilingual',
          3 => 'The 100',
          4 => '1923',
          5 => '[发布组] 动漫作品',
          _ => '规模作品${index.toString().padLeft(2, '0')}',
        };
        final workPath = '/剧集/$title-$index';
        final seasonName = seasonNames[index % seasonNames.length];
        final seasonPath = '$workPath/$seasonName';
        directoryEntries['/剧集']!.add(
          _dir('work-$index', workPath, '$title-$index'),
        );
        directoryEntries[workPath] = <CloudFileEntry>[
          _dir('season-$index', seasonPath, seasonName),
        ];
        directoryEntries[seasonPath] = <CloudFileEntry>[
          _video('episode-$index', '$seasonPath/01.mkv', '01.mkv'),
        ];
      }

      final quark = resolver.resolve(
        sourceId: 'quark-scale',
        configuredRoots: const <String>['/剧集'],
        directoryEntries: directoryEntries,
        minSizeBytes: 100,
      );
      final openList = resolver.resolve(
        sourceId: 'openlist-scale',
        configuredRoots: const <String>['/剧集'],
        directoryEntries: directoryEntries,
        minSizeBytes: 100,
      );

      expect(quark.works, hasLength(50));
      expect(openList.works, hasLength(50));
      expect(
        quark.works.map((work) => work.workKey).toSet().intersection(
              openList.works.map((work) => work.workKey).toSet(),
            ),
        isEmpty,
      );
      expect(
        quark.works.followedBy(openList.works).every(
              (work) =>
                  work.seasons.length == 1 &&
                  work.seasons.single.seasonNumber == 1 &&
                  work.seasons.single.episodes.single.episodeNumber == 1,
            ),
        isTrue,
      );
    });

    test('平铺媒体根中的 4K 裸集号归为剧集且不吞并电影', () {
      const rootPath = '/视频';
      final tree = resolver.resolve(
        sourceId: 'quark-a',
        configuredRoots: const <String>[rootPath],
        directoryEntries: <String, List<CloudFileEntry>>{
          rootPath: <CloudFileEntry>[
            _video(
              'episode-1',
              '$rootPath/【熊猫】最强阴阳师的异世界转生记 BD 4K 1.mkv',
              '【熊猫】最强阴阳师的异世界转生记 BD 4K 1.mkv',
            ),
            _video(
              'episode-9',
              '$rootPath/【熊猫】最强阴阳师的异世界转生记 BD 4K 9.mkv',
              '【熊猫】最强阴阳师的异世界转生记 BD 4K 9.mkv',
            ),
            _video('movie', '$rootPath/独立电影.mkv', '独立电影.mkv'),
          ],
        },
        minSizeBytes: 100,
      );

      expect(tree.works, hasLength(2));
      final series = tree.works.singleWhere((work) => work.seasons.isNotEmpty);
      expect(series.displayTitle, '最强阴阳师的异世界转生记');
      expect(series.seasons.single.seasonNumber, 1);
      expect(
        series.seasons.single.episodes.map((episode) => episode.episodeNumber),
        <int>[1, 9],
      );
      expect(
        tree.works.singleWhere((work) => work.seasons.isEmpty).displayTitle,
        '独立电影',
      );
    });

    test('作品子目录中的 4K 裸集号归为同一剧集', () {
      const rootPath = '/视频';
      const workPath = '$rootPath/最强阴阳师异世界转生记';
      final tree = resolver.resolve(
        sourceId: 'quark-a',
        configuredRoots: const <String>[rootPath],
        directoryEntries: <String, List<CloudFileEntry>>{
          rootPath: <CloudFileEntry>[
            _dir('work', workPath, '最强阴阳师异世界转生记'),
          ],
          workPath: <CloudFileEntry>[
            for (final episode in <int>[1, 3, 10])
              _video(
                'episode-$episode',
                '$workPath/【熊猫】最强阴阳师的异世界转生记 BD 4K '
                    '$episode.mkv',
                '【熊猫】最强阴阳师的异世界转生记 BD 4K '
                    '$episode.mkv',
              ),
          ],
        },
        minSizeBytes: 100,
      );

      expect(tree.works, hasLength(1));
      final series = tree.works.single;
      expect(series.displayTitle, '最强阴阳师的异世界转生记');
      expect(series.standaloneVideos, isEmpty);
      expect(
        series.seasons.single.episodes.map((episode) => episode.episodeNumber),
        <int>[1, 3, 10],
      );
    });

    test('作品目录 S02 季号传递给短横线分集', () {
      const rootPath = '/视频';
      const workPath = '$rootPath/异世界悠闲农家S02';
      final tree = resolver.resolve(
        sourceId: 'quark-a',
        configuredRoots: const <String>[rootPath],
        directoryEntries: <String, List<CloudFileEntry>>{
          rootPath: <CloudFileEntry>[
            _dir('work-s02', workPath, '异世界悠闲农家S02'),
          ],
          workPath: <CloudFileEntry>[
            for (var episode = 1; episode <= 2; episode++)
              _video(
                's2e$episode',
                '$workPath/[LoliHouse] Isekai Nonbiri Nouka 2 - '
                    '${episode.toString().padLeft(2, '0')} '
                    '[WebRip 1080p HEVC-10bit AAC SRTx2].mkv',
                '[LoliHouse] Isekai Nonbiri Nouka 2 - '
                    '${episode.toString().padLeft(2, '0')} '
                    '[WebRip 1080p HEVC-10bit AAC SRTx2].mkv',
              ),
          ],
        },
        minSizeBytes: 100,
      );

      expect(tree.works, hasLength(1));
      final work = tree.works.single;
      expect(work.displayTitle, 'Isekai Nonbiri Nouka 2');
      expect(work.standaloneVideos, isEmpty);
      expect(work.seasons.single.seasonNumber, 2);
      expect(
        work.seasons.single.episodes.map((episode) => episode.episodeNumber),
        <int>[1, 2],
      );
    });

    test('生产识别与刮削代码不包含样例作品和固定 TMDB 分支', () {
      for (final path in <String>[
        'lib/services/media_name_analyzer.dart',
        'lib/services/cloud/cloud_media_tree_resolver.dart',
        'lib/services/cloud/cloud_work_tmdb_service.dart',
      ]) {
        final source = File(path).readAsStringSync();
        for (final forbidden in <String>[
          '弥留之国的爱丽丝',
          'Alice in Borderland',
          'tmdbId == 42',
        ]) {
          expect(
            source,
            isNot(contains(forbidden)),
            reason: '$path: $forbidden',
          );
        }
      }
    });

    test('网盘客户端接口不提供远程改名移动和删除能力', () {
      final source = File(
        'lib/services/cloud/cloud_drive_client.dart',
      ).readAsStringSync();

      for (final forbidden in <String>['rename(', 'move(', 'delete(']) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });
}

CloudFileEntry _dir(String id, String path, String name) => CloudFileEntry(
      id: id,
      remotePath: path,
      name: name,
      size: 0,
      modifiedAt: null,
      isDirectory: true,
    );

CloudFileEntry _video(String id, String path, String name) => CloudFileEntry(
      id: id,
      remotePath: path,
      name: name,
      size: 200,
      modifiedAt: null,
      isDirectory: false,
    );

CloudFileEntry _file(String id, String path, String name) => CloudFileEntry(
      id: id,
      remotePath: path,
      name: name,
      size: 20,
      modifiedAt: null,
      isDirectory: false,
    );
