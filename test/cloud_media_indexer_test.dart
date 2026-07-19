import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_series_match_rule.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/cloud_series_match_rule_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';
import 'package:kanyingyin/services/cloud/cloud_subtitle_cache.dart';
import 'package:path/path.dart' as p;

void main() {
  const source = CloudSource(
    id: 'openlist-a',
    type: CloudSourceType.openList,
    name: '家庭媒体库',
    baseUrl: 'https://drive.example.com',
    rootPaths: <String>['/动漫'],
  );

  group('CloudMediaIndexer', () {
    test('小于本地阈值的网盘视频仍进入索引并作为独立影片显示', () async {
      final repository =
          CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
      final client = _FakeCloudClient(<String, List<CloudFileEntry>>{
        '/动漫': <CloudFileEntry>[
          _file('small', '/动漫/短片.mkv', size: 200 * 1024 * 1024),
        ],
      });

      final result = await CloudMediaIndexer(repository: repository).scan(
        source: source,
        client: client,
      );

      expect(result.cancelled, isFalse);
      expect((await repository.getBySource(source.id)).single.name, '短片.mkv');
    });

    test('每次扫描只读取一次网盘视频阈值且阈值变化使缓存失效', () async {
      final repository =
          CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
      final directories = <String, List<CloudFileEntry>>{
        '/动漫': <CloudFileEntry>[
          _file('medium', '/动漫/短片.mkv', size: 50 * 1024 * 1024),
        ],
      };
      var minSizeBytes = 100 * 1024 * 1024;
      var providerCalls = 0;
      final indexer = CloudMediaIndexer(
        repository: repository,
        minRecognizedVideoSizeBytesProvider: () {
          providerCalls++;
          return minSizeBytes;
        },
      );

      final first = await indexer.scan(
        source: source,
        client: _FakeCloudClient(directories),
      );

      expect(first.videoCount, 0);
      expect(await repository.getBySource(source.id), isEmpty);
      expect(providerCalls, 1);

      minSizeBytes = 10 * 1024 * 1024;
      final second = await indexer.scan(
        source: source,
        client: _FakeCloudClient(directories),
      );

      expect(second.videoCount, 1);
      expect((await repository.getBySource(source.id)).single.name, '短片.mkv');
      expect(providerCalls, 2);
    });

    test('扫描新分集时离线继承已确认的同目录系列规则', () async {
      final repository =
          CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
      final ruleRepository = CloudSeriesMatchRuleRepository(
        storage: MemoryCloudSeriesMatchRuleStorage(),
      );
      await ruleRepository.upsert(
        CloudSeriesMatchRule(
          sourceId: source.id,
          parentPath: '/动漫',
          normalizedSeriesName: 'the resurrected',
          metadata: TmdbMetadata(
            id: 42,
            mediaType: TmdbMediaType.tv,
            title: '回魂计',
            language: 'zh-CN',
            matchedAt: DateTime.utc(2026, 7, 20),
            matchConfidence: 1,
          ),
          updatedAt: DateTime.utc(2026, 7, 20),
        ),
      );
      final indexer = CloudMediaIndexer(
        repository: repository,
        seriesMatchRuleRepository: ruleRepository,
        minRecognizedVideoSizeBytesProvider: () => 100,
      );

      await indexer.scan(
        source: source,
        client: _FakeCloudClient(<String, List<CloudFileEntry>>{
          '/动漫': <CloudFileEntry>[
            _file(
              'episode-5',
              '/动漫/The.Resurrected.S01E05.2160p.WEB-DL.mkv',
              size: 1000,
            ),
          ],
        }),
      );

      final item = (await repository.getBySource(source.id)).single;
      expect(item.tmdbId, 42);
      expect(item.tmdbTitle, '回魂计');
    });

    test('真实扫描将 OVA 和 Special 归入主系列特殊篇', () async {
      final repository =
          CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
      final client = _FakeCloudClient({
        '/动漫': [
          _file('ova', '/动漫/Show OVA 01.mkv', size: _videoSize),
          _file('special', '/动漫/Show Special.mkv', size: _videoSize),
        ],
      });
      await CloudMediaIndexer(repository: repository)
          .scan(source: source, client: client);
      final items = await repository.getBySource(source.id);
      expect(items, hasLength(2));
      expect(items.every((item) => item.mediaType == CloudMediaType.special),
          isTrue);
      expect(items.map((item) => item.seriesName).toSet(), {'Show'});
    });

    test('使用队列递归扫描、去重、筛选视频并关联同名和集数字幕', () async {
      final repository = CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      );
      final client = _FakeCloudClient(<String, List<CloudFileEntry>>{
        '/动漫': <CloudFileEntry>[
          _dir('season', '/动漫/Season 1'),
          _file('movie', '/动漫/Movie.mkv', size: _videoSize),
          _file('movie-copy', '/动漫/./Movie.mkv', size: _videoSize),
          _file('movie-sub', '/动漫/Movie.ass', size: 1200),
          _file('tiny', '/动漫/Tiny.mp4', size: 1024),
        ],
        '/动漫/Season 1': <CloudFileEntry>[
          _dir('subs', '/动漫/Season 1/Subs'),
          _file('episode', '/动漫/Season 1/Show S01E02.mkv', size: _videoSize),
        ],
        '/动漫/Season 1/Subs': <CloudFileEntry>[
          _file('episode-sub', '/动漫/Season 1/Subs/Show - 02.zh.srt', size: 900),
        ],
      });

      final result = await CloudMediaIndexer(repository: repository).scan(
        source: source,
        client: client,
      );

      expect(result.cancelled, isFalse);
      expect(result.failures, 0);
      expect(result.scanned, 3);
      final items = await repository.getBySource(source.id);
      expect(items, hasLength(2));
      expect(items.firstWhere((item) => item.name == 'Movie.mkv').subtitlePaths,
          <String>['/动漫/Movie.ass']);
      expect(
        items.firstWhere((item) => item.name.contains('S01E02')).subtitlePaths,
        <String>['/动漫/Season 1/Subs/Show - 02.zh.srt'],
      );
      expect(client.maxConcurrentLists, lessThanOrEqualTo(3));
    });

    test('索引按来源隔离，未变化目录复用旧索引', () async {
      final repository = CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      );
      final entries = <String, List<CloudFileEntry>>{
        '/动漫': <CloudFileEntry>[
          _file('same-id', '/动漫/Same.mkv', size: _videoSize),
        ],
      };
      final indexer = CloudMediaIndexer(repository: repository);
      await indexer.scan(source: source, client: _FakeCloudClient(entries));
      final second = await indexer.scan(
        source: const CloudSource(
          id: 'openlist-b',
          type: CloudSourceType.openList,
          name: '另一个来源',
          baseUrl: 'https://other.example.com',
          rootPaths: <String>['/动漫'],
        ),
        client: _FakeCloudClient(entries),
      );
      final unchanged = await indexer.scan(
        source: source,
        client: _FakeCloudClient(entries),
      );

      expect(second.scanned, 1);
      expect(unchanged.skipped, 1);
      expect(await repository.getBySource('openlist-a'), hasLength(1));
      expect(await repository.getBySource('openlist-b'), hasLength(1));
    });

    test('配置根目录缩减时移除旧根媒体，即使保留根未变化', () async {
      final repository =
          CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
      final indexer = CloudMediaIndexer(repository: repository);
      await indexer.scan(
        source: const CloudSource(
          id: 'roots',
          type: CloudSourceType.openList,
          name: '多根目录',
          baseUrl: 'https://drive.example.com',
          rootPaths: <String>['/A', '/B'],
        ),
        client: _FakeCloudClient(<String, List<CloudFileEntry>>{
          '/A': <CloudFileEntry>[_file('a', '/A/A.mkv', size: _videoSize)],
          '/B': <CloudFileEntry>[_file('b', '/B/B.mkv', size: _videoSize)],
        }),
      );

      await indexer.scan(
        source: const CloudSource(
          id: 'roots',
          type: CloudSourceType.openList,
          name: '单根目录',
          baseUrl: 'https://drive.example.com',
          rootPaths: <String>['/A'],
        ),
        client: _FakeCloudClient(<String, List<CloudFileEntry>>{
          '/A': <CloudFileEntry>[_file('a', '/A/A.mkv', size: _videoSize)],
        }),
      );

      expect((await repository.getBySource('roots')).map((item) => item.name),
          <String>['A.mkv']);
    });

    test('配置根目录扩展时写入新增根媒体', () async {
      final repository =
          CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
      final indexer = CloudMediaIndexer(repository: repository);
      const oneRoot = CloudSource(
        id: 'roots',
        type: CloudSourceType.openList,
        name: '根目录',
        baseUrl: 'https://drive.example.com',
        rootPaths: <String>['/A'],
      );
      await indexer.scan(
        source: oneRoot,
        client: _FakeCloudClient(<String, List<CloudFileEntry>>{
          '/A': <CloudFileEntry>[_file('a', '/A/A.mkv', size: _videoSize)],
        }),
      );
      await indexer.scan(
        source: const CloudSource(
          id: 'roots',
          type: CloudSourceType.openList,
          name: '根目录',
          baseUrl: 'https://drive.example.com',
          rootPaths: <String>['/A', '/B'],
        ),
        client: _FakeCloudClient(<String, List<CloudFileEntry>>{
          '/A': <CloudFileEntry>[_file('a', '/A/A.mkv', size: _videoSize)],
          '/B': <CloudFileEntry>[_file('b', '/B/B.mkv', size: _videoSize)],
        }),
      );

      expect(await repository.getBySource('roots'), hasLength(2));
    });

    test('视频目录变化时仍可匹配未变化字幕目录', () async {
      final repository =
          CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
      final indexer = CloudMediaIndexer(repository: repository);
      await indexer.scan(
          source: source,
          client: _FakeCloudClient(<String, List<CloudFileEntry>>{
            '/动漫': <CloudFileEntry>[_dir('season-new', '/动漫/Season 1')],
            '/动漫/Season 1': <CloudFileEntry>[
              _dir('subs', '/动漫/Season 1/Subs'),
              _file('video', '/动漫/Season 1/Show S01E02.mkv', size: _videoSize),
            ],
            '/动漫/Season 1/Subs': <CloudFileEntry>[
              _file('sub', '/动漫/Season 1/Subs/Show S01E02.srt', size: 100),
            ],
          }));

      await indexer.scan(
          source: source,
          client: _FakeCloudClient(<String, List<CloudFileEntry>>{
            '/动漫': <CloudFileEntry>[_dir('season', '/动漫/Season 1')],
            '/动漫/Season 1': <CloudFileEntry>[
              _dir('subs', '/动漫/Season 1/Subs'),
              _file('video-new', '/动漫/Season 1/Show S01E02.mkv',
                  size: _videoSize),
            ],
            '/动漫/Season 1/Subs': <CloudFileEntry>[
              _file('sub', '/动漫/Season 1/Subs/Show S01E02.srt', size: 100),
            ],
          }));

      expect((await repository.getBySource(source.id)).single.subtitlePaths,
          <String>['/动漫/Season 1/Subs/Show S01E02.srt']);
    });

    test('字幕目录变化或删除时重新匹配复用视频', () async {
      final repository =
          CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
      final indexer = CloudMediaIndexer(repository: repository);
      Map<String, List<CloudFileEntry>> tree(
              List<CloudFileEntry> subtitles, int revision) =>
          <String, List<CloudFileEntry>>{
            '/动漫': <CloudFileEntry>[_dir('season-$revision', '/动漫/Season 1')],
            '/动漫/Season 1': <CloudFileEntry>[
              _dir('subs-$revision', '/动漫/Season 1/Subs'),
              _file('video', '/动漫/Season 1/Show S01E02.mkv', size: _videoSize),
            ],
            '/动漫/Season 1/Subs': subtitles,
          };
      await indexer.scan(
          source: source,
          client: _FakeCloudClient(tree(const <CloudFileEntry>[], 1)));
      await indexer.scan(
          source: source,
          client: _FakeCloudClient(tree(<CloudFileEntry>[
            _file('sub', '/动漫/Season 1/Subs/Show S01E02.srt', size: 100),
          ], 2)));
      expect((await repository.getBySource(source.id)).single.subtitlePaths,
          isNotEmpty);

      await indexer.scan(
          source: source,
          client: _FakeCloudClient(tree(const <CloudFileEntry>[], 3)));
      expect((await repository.getBySource(source.id)).single.subtitlePaths,
          isEmpty);
    });

    test('目录指纹可检测名称、路径和类型变化', () async {
      final repository =
          CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
      final indexer = CloudMediaIndexer(repository: repository);
      await indexer.scan(
          source: source,
          client: _FakeCloudClient(<String, List<CloudFileEntry>>{
            '/动漫': <CloudFileEntry>[
              _file('same', '/动漫/Old.mkv', size: _videoSize)
            ],
          }));
      final changed = await indexer.scan(
          source: source,
          client: _FakeCloudClient(<String, List<CloudFileEntry>>{
            '/动漫': <CloudFileEntry>[
              CloudFileEntry(
                  id: 'same',
                  remotePath: '/动漫/New.mkv',
                  name: 'New.mkv',
                  size: _videoSize,
                  modifiedAt: DateTime.utc(2026, 7, 15),
                  isDirectory: false),
            ],
          }));
      expect(changed.skipped, 0);
      expect((await repository.getBySource(source.id)).single.name, 'New.mkv');
    });

    test('未变化父目录仍遍历子目录并发现孙级变化', () async {
      final repository =
          CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
      final indexer = CloudMediaIndexer(repository: repository);
      final tree = <String, List<CloudFileEntry>>{
        '/动漫': <CloudFileEntry>[_dir('season', '/动漫/Season 1')],
        '/动漫/Season 1': <CloudFileEntry>[
          _file('video', '/动漫/Season 1/Show.mkv', size: _videoSize),
        ],
      };
      await indexer.scan(source: source, client: _FakeCloudClient(tree));
      final changedTree = <String, List<CloudFileEntry>>{
        '/动漫': tree['/动漫']!,
        '/动漫/Season 1': <CloudFileEntry>[
          _file('video-new', '/动漫/Season 1/Changed.mkv', size: _videoSize),
        ],
      };
      final secondClient = _FakeCloudClient(changedTree);

      final result = await indexer.scan(source: source, client: secondClient);

      expect(result.skipped, 1);
      expect(secondClient.listedPaths,
          containsAll(<String>['/动漫', '/动漫/Season 1']));
      expect(await repository.getBySource(source.id), hasLength(1));
      expect(
          (await repository.getBySource(source.id)).single.name, 'Changed.mkv');
    });

    test('根目录读取失败时保留全部缓存后代', () async {
      final repository =
          CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
      final indexer = CloudMediaIndexer(repository: repository);
      await indexer.scan(
        source: const CloudSource(
          id: 'root-source',
          type: CloudSourceType.openList,
          name: '根目录',
          baseUrl: 'https://drive.example.com',
          rootPaths: <String>['/'],
        ),
        client: _FakeCloudClient(<String, List<CloudFileEntry>>{
          '/': <CloudFileEntry>[_dir('series', '/Series')],
          '/Series': <CloudFileEntry>[
            _dir('deep', '/Series/Deep'),
            _file('one', '/Series/One.mkv', size: _videoSize),
          ],
          '/Series/Deep': <CloudFileEntry>[
            _file('two', '/Series/Deep/Two.mkv', size: _videoSize),
          ],
        }),
      );
      final result = await indexer.scan(
        source: const CloudSource(
          id: 'root-source',
          type: CloudSourceType.openList,
          name: '根目录',
          baseUrl: 'https://drive.example.com',
          rootPaths: <String>['/'],
        ),
        client: _FakeCloudClient(const <String, List<CloudFileEntry>>{},
            failedPaths: <String>{'/'}),
      );

      expect(result.failedPaths, <String>['/']);
      expect(await repository.getBySource('root-source'), hasLength(2));
    });

    test('忽略并报告越过配置根目录的服务端条目', () async {
      final repository =
          CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
      final result = await CloudMediaIndexer(repository: repository).scan(
        source: source,
        client: _FakeCloudClient(<String, List<CloudFileEntry>>{
          '/动漫': <CloudFileEntry>[
            _file('escape', '/动漫/../秘密/Escape.mkv', size: _videoSize),
            _file('outside', '/其他/Outside.mkv', size: _videoSize),
            _file('relative', 'Relative.mkv', size: _videoSize),
            _file('valid', '/动漫/Valid.mkv', size: _videoSize),
          ],
        }),
      );

      expect(result.failures, 3);
      expect(
          (await repository.getBySource(source.id)).single.name, 'Valid.mkv');
    });

    test('深层目录失败保留该路径及缓存后代媒体', () async {
      final repository =
          CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
      final indexer = CloudMediaIndexer(repository: repository);
      await indexer.scan(
          source: source,
          client: _FakeCloudClient(<String, List<CloudFileEntry>>{
            '/动漫': <CloudFileEntry>[_dir('season-1', '/动漫/Season 1')],
            '/动漫/Season 1': <CloudFileEntry>[
              _dir('deep-1', '/动漫/Season 1/Deep')
            ],
            '/动漫/Season 1/Deep': <CloudFileEntry>[
              _dir('deeper', '/动漫/Season 1/Deep/Deeper'),
              _file('video', '/动漫/Season 1/Deep/Old.mkv', size: _videoSize),
            ],
            '/动漫/Season 1/Deep/Deeper': <CloudFileEntry>[
              _file('video-2', '/动漫/Season 1/Deep/Deeper/Old2.mkv',
                  size: _videoSize),
            ],
          }));
      final result = await indexer.scan(
          source: source,
          client: _FakeCloudClient(<String, List<CloudFileEntry>>{
            '/动漫': <CloudFileEntry>[_dir('season-2', '/动漫/Season 1')],
            '/动漫/Season 1': <CloudFileEntry>[
              _dir('deep-2', '/动漫/Season 1/Deep')
            ],
          }, failedPaths: <String>{
            '/动漫/Season 1/Deep'
          }));

      expect(result.failedPaths, <String>['/动漫/Season 1/Deep']);
      expect(await repository.getBySource(source.id), hasLength(2));
    });

    test('相同季集号字幕不会跨同级剧集目录串配', () async {
      final repository =
          CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
      await CloudMediaIndexer(repository: repository).scan(
        source: source,
        client: _FakeCloudClient(<String, List<CloudFileEntry>>{
          '/动漫': <CloudFileEntry>[
            _dir('a', '/动漫/SeriesA'),
            _dir('b', '/动漫/SeriesB'),
          ],
          '/动漫/SeriesA': <CloudFileEntry>[
            _file('video-a', '/动漫/SeriesA/SeriesA S01E01.mkv',
                size: _videoSize),
          ],
          '/动漫/SeriesB': <CloudFileEntry>[
            _dir('subs-b', '/动漫/SeriesB/Subs'),
          ],
          '/动漫/SeriesB/Subs': <CloudFileEntry>[
            _file('sub-b', '/动漫/SeriesB/Subs/SeriesB S01E01.srt', size: 100),
          ],
        }),
      );

      expect((await repository.getBySource(source.id)).single.subtitlePaths,
          isEmpty);
    });

    test('同目录相同季集号但系列名不同的字幕不会串配', () async {
      final repository =
          CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
      await CloudMediaIndexer(repository: repository).scan(
        source: source,
        client: _FakeCloudClient(<String, List<CloudFileEntry>>{
          '/动漫': <CloudFileEntry>[
            _file('video', '/动漫/SeriesA S01E01.mkv', size: _videoSize),
            _file('sub', '/动漫/SeriesB S01E01.srt', size: 100),
          ],
        }),
      );
      expect((await repository.getBySource(source.id)).single.subtitlePaths,
          isEmpty);
    });

    test('单目录失败继续并报告路径', () async {
      final repository = CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      );
      final client = _FakeCloudClient(<String, List<CloudFileEntry>>{
        '/动漫': <CloudFileEntry>[
          _dir('ok', '/动漫/OK'),
          _dir('bad', '/动漫/Bad'),
        ],
        '/动漫/OK': <CloudFileEntry>[
          _file('video', '/动漫/OK/Good.mkv', size: _videoSize),
        ],
      }, failedPaths: <String>{
        '/动漫/Bad'
      });

      final result = await CloudMediaIndexer(repository: repository).scan(
        source: source,
        client: client,
      );

      expect(result.failures, 1);
      expect(result.failedPaths, <String>['/动漫/Bad']);
      expect(await repository.getBySource(source.id), hasLength(1));
    });

    test('取消保留旧完整索引且同来源并发扫描被拒绝', () async {
      final repository = CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      );
      final indexer = CloudMediaIndexer(repository: repository);
      await indexer.scan(
        source: source,
        client: _FakeCloudClient(<String, List<CloudFileEntry>>{
          '/动漫': <CloudFileEntry>[
            _file('old', '/动漫/Old.mkv', size: _videoSize),
          ],
        }),
      );
      final blocker = Completer<void>();
      final started = Completer<void>();
      final token = CloudScanCancellationToken();
      final operation = indexer.scan(
        source: source,
        client: _FakeCloudClient(
          <String, List<CloudFileEntry>>{
            '/动漫': <CloudFileEntry>[
              _file('new', '/动漫/New.mkv', size: _videoSize),
            ],
          },
          listStarted: started,
          releaseList: blocker,
        ),
        cancellationToken: token,
      );
      await started.future;
      await expectLater(
        indexer.scan(source: source, client: _FakeCloudClient(const {})),
        throwsA(isA<CloudScanInProgressException>()),
      );
      token.cancel();
      blocker.complete();

      expect((await operation).cancelled, isTrue);
      expect((await repository.getBySource(source.id)).single.name, 'Old.mkv');
    });

    test('跨索引器实例拒绝同来源并发但允许不同来源', () async {
      final storage = MemoryCloudMediaIndexStorage();
      final first = CloudMediaIndexer(
          repository: CloudMediaIndexRepository(storage: storage));
      final second = CloudMediaIndexer(
          repository: CloudMediaIndexRepository(storage: storage));
      final started = Completer<void>();
      final release = Completer<void>();
      final running = first.scan(
          source: source,
          client: _FakeCloudClient(const <String, List<CloudFileEntry>>{},
              listStarted: started, releaseList: release));
      await started.future;
      await expectLater(
          second.scan(source: source, client: _FakeCloudClient(const {})),
          throwsA(isA<CloudScanInProgressException>()));
      final other = second.scan(
          source: const CloudSource(
              id: 'other',
              type: CloudSourceType.openList,
              name: 'other',
              baseUrl: 'https://other',
              rootPaths: <String>['/']),
          client: _FakeCloudClient(
              const <String, List<CloudFileEntry>>{'/': <CloudFileEntry>[]}));
      release.complete();
      await Future.wait(<Future<Object?>>[running, other]);
    });

    test('损坏持久化记录被隔离', () async {
      final storage = MemoryCloudMediaIndexStorage();
      await storage.write(<String, Object?>{
        'items': <Object?>[
          <String, Object?>{'sourceId': 7},
          <String, Object?>{
            'sourceId': 'a',
            'remoteId': 'id',
            'remotePath': '/A.mkv',
            'name': 'A.mkv',
            'size': _videoSize,
            'seriesName': 'A',
          },
        ],
        'fingerprints': <String, Object?>{},
      });
      final repository = CloudMediaIndexRepository(storage: storage);

      expect(await repository.getBySource('a'), hasLength(1));
    });
  });

  group('CloudSubtitleCache', () {
    test('只缓存支持的小字幕并使用稳定安全文件名', () async {
      final directory = await Directory.systemTemp.createTemp('cloud_sub_');
      addTearDown(() => directory.delete(recursive: true));
      final client = _FakeCloudClient(const <String, List<CloudFileEntry>>{});
      final cache = CloudSubtitleCache(
        cacheRoot: directory,
        downloader: (_) async => <int>[1, 2, 3],
      );
      final subtitle = _file('id:/unsafe', '/Subs/Episode 01.ass', size: 3);

      final path = await cache.cacheBeforePlayback(
        sourceId: 'source:/one',
        subtitle: subtitle,
        client: client,
      );

      expect(path, isNotNull);
      expect(File(path!).readAsBytesSync(), <int>[1, 2, 3]);
      expect(path, endsWith('.ass'));
      expect(p.basename(path), matches(RegExp(r'^[a-f0-9]{64}\.ass$')));
      expect(
        await cache.cacheBeforePlayback(
          sourceId: source.id,
          subtitle: _file('video', '/Movie.mkv', size: _videoSize),
          client: client,
        ),
        isNull,
      );
    });

    test('不同稳定 ID 清理后不会产生文件名碰撞', () async {
      final directory =
          await Directory.systemTemp.createTemp('cloud_sub_collision_');
      addTearDown(() => directory.delete(recursive: true));
      final cache = CloudSubtitleCache(
          cacheRoot: directory, downloader: (_) async => <int>[1]);
      final client = _FakeCloudClient(const <String, List<CloudFileEntry>>{});
      final first = await cache.cacheBeforePlayback(
          sourceId: 'source',
          subtitle: _file('a/b', '/A.srt', size: 1),
          client: client);
      final second = await cache.cacheBeforePlayback(
          sourceId: 'source',
          subtitle: _file('a:b', '/B.srt', size: 1),
          client: client);
      expect(first, isNot(second));
    });

    test('远端字幕内容版本变化生成新的缓存文件', () async {
      final directory =
          await Directory.systemTemp.createTemp('cloud_sub_version_');
      addTearDown(() => directory.delete(recursive: true));
      final cache = CloudSubtitleCache(
          cacheRoot: directory, downloader: (_) async => <int>[1]);
      final client = _FakeCloudClient(const <String, List<CloudFileEntry>>{});
      CloudFileEntry subtitle(DateTime modifiedAt, int size) => CloudFileEntry(
            id: 'same-id',
            remotePath: '/Subs/A.srt',
            name: 'A.srt',
            size: size,
            modifiedAt: modifiedAt,
            isDirectory: false,
          );

      final first = await cache.cacheBeforePlayback(
          sourceId: 'source',
          subtitle: subtitle(DateTime.utc(2026, 1, 1), 1),
          client: client);
      final updated = await cache.cacheBeforePlayback(
          sourceId: 'source',
          subtitle: subtitle(DateTime.utc(2026, 1, 2), 2),
          client: client);

      expect(first, isNot(updated));
    });

    test('并发缓存同一字幕只下载一次且不暴露部分文件', () async {
      final directory =
          await Directory.systemTemp.createTemp('cloud_sub_single_');
      addTearDown(() => directory.delete(recursive: true));
      final release = Completer<List<int>>();
      final downloadStarted = Completer<void>();
      var downloads = 0;
      CloudSubtitleCache cache() => CloudSubtitleCache(
            cacheRoot: directory,
            downloader: (_) {
              downloads++;
              if (!downloadStarted.isCompleted) downloadStarted.complete();
              return release.future;
            },
          );
      final subtitle = _file('same', '/Subs/A.srt', size: 3);
      final client = _FakeCloudClient(const <String, List<CloudFileEntry>>{});
      final first = cache().cacheBeforePlayback(
          sourceId: 'source', subtitle: subtitle, client: client);
      final second = cache().cacheBeforePlayback(
          sourceId: 'source', subtitle: subtitle, client: client);
      await downloadStarted.future;

      expect(downloads, 1);
      expect(directory.listSync(recursive: true).whereType<File>(), isEmpty);
      release.complete(<int>[1, 2, 3]);
      final paths = await Future.wait(<Future<String?>>[first, second]);
      expect(paths.toSet(), hasLength(1));
      expect(File(paths.first!).readAsBytesSync(), <int>[1, 2, 3]);
      expect(
          directory.listSync(recursive: true).whereType<File>(), hasLength(1));
    });

    test('下载失败返回 null，清理超过三十天缓存', () async {
      final directory = await Directory.systemTemp.createTemp('cloud_sub_');
      addTearDown(() => directory.delete(recursive: true));
      final sourceDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}cloud_subtitles${Platform.pathSeparator}source',
      );
      await sourceDirectory.create(recursive: true);
      final oldFile =
          File('${sourceDirectory.path}${Platform.pathSeparator}old.srt');
      final freshFile =
          File('${sourceDirectory.path}${Platform.pathSeparator}fresh.srt');
      await oldFile.writeAsString('old');
      await freshFile.writeAsString('fresh');
      await oldFile
          .setLastModified(DateTime.now().subtract(const Duration(days: 31)));
      final cache = CloudSubtitleCache(
        cacheRoot: directory,
        downloader: (_) => throw StateError('下载失败'),
      );

      final failed = await cache.cacheBeforePlayback(
        sourceId: source.id,
        subtitle: _file('sub', '/A.srt', size: 3),
        client: _FakeCloudClient(const <String, List<CloudFileEntry>>{}),
      );
      final removed = await cache.cleanExpired(now: DateTime.now());

      expect(failed, isNull);
      expect(
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.download')),
        isEmpty,
      );
      expect(removed, 1);
      expect(oldFile.existsSync(), isFalse);
      expect(freshFile.existsSync(), isTrue);
    });
  });

  test('CloudLibraryController 暴露扫描失败并可重试', () async {
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await sourceRepository.save(source);
    var attempt = 0;
    final scannedSourceIds = <String>[];
    final clients = <_FakeCloudClient>[];
    final controller = CloudLibraryController(
      repository: sourceRepository,
      credentialStore: MemoryCloudCredentialStore(),
      mediaIndexer: CloudMediaIndexer(
        repository: CloudMediaIndexRepository(
          storage: MemoryCloudMediaIndexStorage(),
        ),
      ),
      clientFactory: (source, __, ___) {
        scannedSourceIds.add(source.id);
        attempt++;
        final client = _FakeCloudClient(
          attempt == 1
              ? const <String, List<CloudFileEntry>>{}
              : <String, List<CloudFileEntry>>{
                  '/动漫': <CloudFileEntry>[
                    _file('video', '/动漫/Good.mkv', size: _videoSize),
                  ],
                },
          failedPaths: attempt == 1 ? <String>{'/动漫'} : const <String>{},
        );
        clients.add(client);
        return client;
      },
    );

    final first = await controller.scanSource(source.id);
    expect(first.failedPaths, <String>['/动漫']);
    expect(controller.scanFailedPaths, <String>['/动漫']);

    final retried = await controller.retryFailedScan();
    expect(retried.failures, 0);
    expect(scannedSourceIds, <String>[source.id, source.id]);
    expect(clients.every((client) => client.authenticateCalls == 0), isTrue);
    expect(controller.scanningSourceId, isNull);
    controller.dispose();
  });

  test('CloudLibraryController 持久化扫描状态和媒体统计', () async {
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await sourceRepository.save(source);
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    final controller = CloudLibraryController(
      repository: sourceRepository,
      credentialStore: MemoryCloudCredentialStore(),
      mediaIndexRepository: indexRepository,
      mediaIndexer: CloudMediaIndexer(repository: indexRepository),
      clientFactory: (_, __, ___) => _FakeCloudClient({
        '/动漫': [
          _file('video-1', '/动漫/Show S01E01.mkv', size: 100 * 1024 * 1024),
          _file('video-2', '/动漫/Show S01E02.mkv', size: 100 * 1024 * 1024),
          _file('subtitle', '/动漫/Show S01E01.srt', size: 10),
        ],
      }),
    );

    await controller.scanSource(source.id);

    final updated = await sourceRepository.getById(source.id);
    expect(updated?.scanStatus, CloudScanStatus.completed);
    expect(updated?.indexedVideoCount, 2);
    expect(updated?.matchedSubtitleCount, 1);
    expect(updated?.lastScanFailureCount, 0);
    expect(updated?.lastScannedAt, isNotNull);
    controller.dispose();
  });

  test('CloudLibraryController 浏览目录时只返回文件夹并关闭客户端', () async {
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await sourceRepository.save(source);
    final client = _FakeCloudClient(<String, List<CloudFileEntry>>{
      '/': <CloudFileEntry>[
        _file('video', '/Show.mkv', size: _videoSize),
        _dir('anime', '/动漫'),
        _dir('movies', '/电影'),
      ],
    });
    final controller = CloudLibraryController(
      repository: sourceRepository,
      credentialStore: MemoryCloudCredentialStore(),
      clientFactory: (_, __, ___) => client,
    );

    final directories = await controller.browseDirectories(source, '/');

    expect(
        directories.map((entry) => entry.remotePath), <String>['/动漫', '/电影']);
    expect(client.listedPaths, <String>['/']);
    expect(client.closeCalls, 1);
    controller.dispose();
  });

  test('CloudLibraryController 释放时取消扫描且不再改写状态', () async {
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await sourceRepository.save(source);
    final started = Completer<void>();
    final release = Completer<void>();
    final controller = CloudLibraryController(
      repository: sourceRepository,
      credentialStore: MemoryCloudCredentialStore(),
      mediaIndexer: CloudMediaIndexer(
          repository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      )),
      clientFactory: (_, __, ___) => _FakeCloudClient(
        const <String, List<CloudFileEntry>>{},
        listStarted: started,
        releaseList: release,
      ),
    );
    final operation = controller.scanSource(source.id);
    await started.future;
    controller.dispose();
    release.complete();

    expect((await operation).cancelled, isTrue);
    expect(controller.scanningSourceId, source.id);
    expect(controller.lastScanResult, isNull);
    expect((await sourceRepository.getById(source.id))?.scanStatus,
        CloudScanStatus.never);
  });

  test('CloudLibraryController 关闭客户端失败仍清理活动扫描', () async {
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await sourceRepository.save(source);
    var attempts = 0;
    final controller = CloudLibraryController(
      repository: sourceRepository,
      credentialStore: MemoryCloudCredentialStore(),
      mediaIndexer: CloudMediaIndexer(
          repository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      )),
      clientFactory: (_, __, ___) => _FakeCloudClient(
        const <String, List<CloudFileEntry>>{'/动漫': <CloudFileEntry>[]},
        closeThrows: attempts++ == 0,
      ),
    );

    await expectLater(controller.scanSource(source.id), throwsStateError);
    await expectLater(controller.scanSource(source.id), completes);
    controller.dispose();
  });

  test('CloudLibraryController 来源加载期间释放不会创建客户端', () async {
    final repository = _BlockingGetSourceRepository(source);
    var clientsCreated = 0;
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: MemoryCloudCredentialStore(),
      mediaIndexer: CloudMediaIndexer(
          repository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      )),
      clientFactory: (_, __, ___) {
        clientsCreated++;
        return _FakeCloudClient(const <String, List<CloudFileEntry>>{});
      },
    );
    final operation = controller.scanSource(source.id);
    await repository.started.future;
    controller.dispose();
    repository.release.complete();

    expect((await operation).cancelled, isTrue);
    expect(clientsCreated, 0);
  });

  test('CloudLibraryController 同时只允许一个来源扫描', () async {
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await repository.save(source);
    await repository.save(const CloudSource(
      id: 'source-2',
      type: CloudSourceType.openList,
      name: '来源二',
      baseUrl: 'https://two.example.com',
      rootPaths: <String>['/'],
    ));
    final started = Completer<void>();
    final release = Completer<void>();
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: MemoryCloudCredentialStore(),
      mediaIndexer: CloudMediaIndexer(
          repository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      )),
      clientFactory: (_, __, ___) => _FakeCloudClient(
        const <String, List<CloudFileEntry>>{},
        listStarted: started,
        releaseList: release,
      ),
    );
    final running = controller.scanSource(source.id);
    await started.future;

    await expectLater(controller.scanSource('source-2'),
        throwsA(isA<CloudScanInProgressException>()));
    release.complete();
    await running;
    controller.dispose();
  });

  test('删除来源等待目标扫描退出且不会残留索引', () async {
    final sourceRepository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await sourceRepository.save(source);
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    final started = Completer<void>();
    final release = Completer<void>();
    final controller = CloudLibraryController(
      repository: sourceRepository,
      credentialStore: MemoryCloudCredentialStore(),
      mediaIndexRepository: indexRepository,
      mediaIndexer: CloudMediaIndexer(repository: indexRepository),
      posterCacheCleaner: (_) async {},
      subtitleCacheCleaner: (_) async {},
      clientFactory: (_, __, ___) => _FakeCloudClient(
        <String, List<CloudFileEntry>>{
          '/动漫': <CloudFileEntry>[
            _file('episode', '/动漫/Show S01E01.mkv', size: _videoSize),
          ],
        },
        listStarted: started,
        releaseList: release,
      ),
    );
    final scan = controller.scanSource(source.id);
    await started.future;
    var deletionCompleted = false;
    final deletion = controller.delete(source.id).whenComplete(() {
      deletionCompleted = true;
    });

    await Future<void>.delayed(Duration.zero);
    expect(deletionCompleted, isFalse);
    release.complete();
    expect((await scan).cancelled, isTrue);
    await deletion;

    expect(await sourceRepository.getById(source.id), isNull);
    expect(await indexRepository.getBySource(source.id), isEmpty);
    controller.dispose();
  });
}

const int _videoSize = 900 * 1024 * 1024;

CloudFileEntry _dir(String id, String path) => CloudFileEntry(
      id: id,
      remotePath: path,
      name: path.split('/').last,
      size: 0,
      modifiedAt: DateTime.utc(2026, 7, 15),
      isDirectory: true,
    );

CloudFileEntry _file(String id, String path, {required int size}) =>
    CloudFileEntry(
      id: id,
      remotePath: path,
      name: path.split('/').last,
      size: size,
      modifiedAt: DateTime.utc(2026, 7, 15),
      isDirectory: false,
    );

class _FakeCloudClient implements CloudDriveClient {
  _FakeCloudClient(
    this.directories, {
    this.failedPaths = const <String>{},
    this.listStarted,
    this.releaseList,
    this.closeThrows = false,
  });

  final Map<String, List<CloudFileEntry>> directories;
  final Set<String> failedPaths;
  final Completer<void>? listStarted;
  final Completer<void>? releaseList;
  final bool closeThrows;
  int concurrentLists = 0;
  int maxConcurrentLists = 0;
  int authenticateCalls = 0;
  int closeCalls = 0;
  final List<String> listedPaths = <String>[];

  @override
  Future<List<CloudFileEntry>> listDirectory(CloudRemoteRef directory) async {
    final remotePath = directory.path;
    listedPaths.add(remotePath);
    concurrentLists++;
    if (concurrentLists > maxConcurrentLists) {
      maxConcurrentLists = concurrentLists;
    }
    try {
      if (listStarted?.isCompleted == false) listStarted!.complete();
      await releaseList?.future;
      if (failedPaths.contains(remotePath)) throw StateError('目录失败');
      return directories[remotePath] ?? <CloudFileEntry>[];
    } finally {
      concurrentLists--;
    }
  }

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) async =>
      CloudPlaybackResource(
          uri: Uri.parse('https://download.example.com$fileSafePath'));

  String get fileSafePath => '/subtitle';

  @override
  Future<void> authenticate(
      CloudSource source, CloudCredential credential) async {
    authenticateCalls++;
  }

  @override
  Future<void> close() async {
    closeCalls++;
    if (closeThrows) throw StateError('关闭失败');
  }

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) async =>
      throw UnimplementedError();
}

class _BlockingGetSourceRepository extends CloudSourceRepository {
  _BlockingGetSourceRepository(this.source)
      : super(
          storage: MemoryCloudSourceStorage(),
          credentialStore: MemoryCloudCredentialStore(),
        );

  final CloudSource source;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<CloudSource?> getById(String sourceId) async {
    started.complete();
    await release.future;
    return source;
  }
}
