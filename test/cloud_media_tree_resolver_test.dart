import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/services/cloud/cloud_media_tree_resolver.dart';

void main() {
  group('CloudMediaTreeResolver', () {
    const resolver = CloudMediaTreeResolver();

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
        configuredRoots: const <String>['/影视'],
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
