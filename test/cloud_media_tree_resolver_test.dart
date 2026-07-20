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
