import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';
import 'package:kanyingyin/services/cloud/cloud_provider_registry.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_auto_organizer.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_search.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/cloud/cloud_series_match_service.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

void main() {
  group('CloudResourcesController', () {
    test('只显示已启用来源且递归扫描配置根目录', () async {
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'quark-enabled',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
          CloudSource(
            id: 'openlist-disabled',
            type: CloudSourceType.openList,
            name: '已停用',
            baseUrl: 'https://drive.example.invalid',
            rootPaths: <String>['/'],
            enabled: false,
          ),
        ],
        clients: <String, _FakeCloudClient>{
          'quark-enabled': _FakeCloudClient(
            entriesById: <String, List<CloudFileEntry>>{
              'root-fid': const <CloudFileEntry>[
                CloudFileEntry(
                  id: 'child-fid',
                  remotePath: '/影视/动漫',
                  name: '动漫',
                  size: 0,
                  modifiedAt: null,
                  isDirectory: true,
                ),
              ],
            },
          ),
        },
      );

      await fixture.load();

      expect(
        fixture.controller.sources.map((source) => source.id),
        <String>['quark-enabled'],
      );
      expect(
        fixture.clients['quark-enabled']!.listed.map((item) => item.id),
        <String>['root-fid', 'child-fid'],
      );
      expect(fixture.controller.currentDirectory, isNull);
      expect(fixture.controller.entries, isEmpty);
      fixture.controller.dispose();
    });

    test('多根目录全部递归扫描且不显示虚拟根页', () async {
      final client = _FakeCloudClient();
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'openlist-multiple',
            type: CloudSourceType.openList,
            name: '家庭网盘',
            baseUrl: 'https://drive.example.invalid',
            rootPaths: <String>['/动漫', '/电影'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: '/动漫', path: '/动漫'),
              CloudRemoteRef(id: '/电影', path: '/电影'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{'openlist-multiple': client},
      );

      await fixture.load();

      expect(fixture.controller.isVirtualRoot, isFalse);
      expect(fixture.controller.entries, isEmpty);
      expect(
        client.listed.map((item) => item.id),
        <String>['/动漫', '/电影'],
      );
      fixture.controller.dispose();
    });

    test('递归结果只显示视频且搜索覆盖全部目录', () async {
      final client = _FakeCloudClient(
        entriesById: <String, List<CloudFileEntry>>{
          'root-fid': <CloudFileEntry>[
            const CloudFileEntry(
              id: 'child-fid',
              remotePath: '/影视/动漫',
              name: '动漫',
              size: 0,
              modifiedAt: null,
              isDirectory: true,
            ),
            CloudFileEntry(
              id: 'movie-fid',
              remotePath: '/影视/剧场版.mkv',
              name: '剧场版.mkv',
              size: 1024,
              modifiedAt: DateTime(2026, 7, 19),
              isDirectory: false,
            ),
            const CloudFileEntry(
              id: 'subtitle-fid',
              remotePath: '/影视/剧场版.ass',
              name: '剧场版.ass',
              size: 100,
              modifiedAt: null,
              isDirectory: false,
            ),
          ],
          'child-fid': const <CloudFileEntry>[
            CloudFileEntry(
              id: 'episode-fid',
              remotePath: '/影视/动漫/第01集.mkv',
              name: '第01集.mkv',
              size: 2048,
              modifiedAt: null,
              isDirectory: false,
            ),
          ],
        },
      );
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'quark-navigation',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{'quark-navigation': client},
      );
      await fixture.load();

      expect(
        fixture.controller.visibleEntries.map((entry) => entry.name),
        containsAll(<String>['剧场版.mkv', '第01集.mkv']),
      );
      fixture.controller.setQuery('剧场版');
      expect(fixture.controller.visibleEntries.single.name, '剧场版.mkv');
      fixture.controller.setQuery('');
      expect(fixture.controller.currentDirectory, isNull);
      expect(fixture.controller.canGoBack, isFalse);
      final movie = fixture.controller.entries.singleWhere(
        (entry) => entry.id == 'movie-fid',
      );
      expect(fixture.controller.subtitleFor(movie)?.id, 'subtitle-fid');
      fixture.controller.dispose();
    });

    test('慢响应不会覆盖新来源', () async {
      final slowClient = _DelayedCloudClient();
      final fastClient = _FakeCloudClient(
        entriesById: <String, List<CloudFileEntry>>{
          'fast-root': const <CloudFileEntry>[
            CloudFileEntry(
              id: 'new-video',
              remotePath: '/新电影.mkv',
              name: '新电影.mkv',
              size: 100,
              modifiedAt: null,
              isDirectory: false,
            ),
          ],
        },
      );
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'fast',
            type: CloudSourceType.openList,
            name: '快来源',
            baseUrl: 'https://fast.example.invalid',
            rootPaths: <String>['/'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'fast-root', path: '/'),
            ],
          ),
          CloudSource(
            id: 'slow',
            type: CloudSourceType.quark,
            name: '慢来源',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/慢'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'slow-root', path: '/慢'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{
          'fast': fastClient,
          'slow': slowClient,
        },
      );
      await fixture.load();

      final oldRequest = fixture.controller.selectSource('slow');
      await fixture.controller.selectSource('fast');
      slowClient.complete(const <CloudFileEntry>[
        CloudFileEntry(
          id: 'old-video',
          remotePath: '/慢/旧电影.mkv',
          name: '旧电影.mkv',
          size: 100,
          modifiedAt: null,
          isDirectory: false,
        ),
      ]);
      await oldRequest;
      await fixture.controller.scanCompletion;

      expect(fixture.controller.selectedSource?.id, 'fast');
      expect(fixture.controller.entries.single.name, '新电影.mkv');
      fixture.controller.dispose();
    });

    test('TMDB 调度使用来源级完整视频上下文', () async {
      final coordinator = _RecordingTmdbCoordinator();
      final client = _FakeCloudClient(
        entriesById: <String, List<CloudFileEntry>>{
          'root-fid': const <CloudFileEntry>[
            CloudFileEntry(
              id: 'folder-fid',
              remotePath: '/影视/剧集',
              name: '剧集',
              size: 0,
              modifiedAt: null,
              isDirectory: true,
            ),
            CloudFileEntry(
              id: 'movie-fid',
              remotePath: '/影视/电影.mkv',
              name: '电影.mkv',
              size: 100,
              modifiedAt: null,
              isDirectory: false,
            ),
          ],
          'folder-fid': const <CloudFileEntry>[
            CloudFileEntry(
              id: 'season-fid',
              remotePath: '/影视/剧集/第一季',
              name: '第一季',
              size: 0,
              modifiedAt: null,
              isDirectory: true,
            ),
          ],
        },
      );
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-a',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{'source-a': client},
        tmdbCoordinator: coordinator,
      );

      await fixture.load();
      expect(coordinator.contexts.last.isConfiguredRoot, isTrue);
      expect(
        coordinator.contexts.last.directory,
        const CloudRemoteRef(id: 'library:source-a', path: '/'),
      );
      expect(
        coordinator.contexts.last.entries.map((entry) => entry.id),
        <String>['movie-fid'],
      );
      fixture.controller.dispose();
    });

    test('TMDB 失败不改写目录错误且视频仍可播放', () async {
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-a',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{
          'source-a': _FakeCloudClient(
            entriesById: <String, List<CloudFileEntry>>{
              'root-fid': const <CloudFileEntry>[
                CloudFileEntry(
                  id: 'video-fid',
                  remotePath: '/影视/电影.mkv',
                  name: '电影.mkv',
                  size: 100,
                  modifiedAt: null,
                  isDirectory: false,
                ),
              ],
            },
          ),
        },
        tmdbCoordinator: _FailingTmdbCoordinator(),
      );

      await fixture.load();
      await Future<void>.delayed(Duration.zero);

      expect(fixture.controller.errorMessage, isNull);
      expect(fixture.controller.visibleEntries.single.name, '电影.mkv');
      fixture.controller.dispose();
    });

    test('修改显示剧名不改变视频远程引用', () async {
      final coordinator = _RecordingTmdbCoordinator();
      final client = _FakeCloudClient(
        entriesById: <String, List<CloudFileEntry>>{
          'root-fid': const <CloudFileEntry>[
            CloudFileEntry(
              id: 'video-fid',
              remotePath: '/影视/原剧名.S01E01.mkv',
              name: '原剧名.S01E01.mkv',
              size: 100,
              modifiedAt: null,
              isDirectory: false,
            ),
          ],
        },
      );
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-a',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{'source-a': client},
        tmdbCoordinator: coordinator,
      );
      await fixture.load();
      final video = fixture.controller.entries.single;

      await fixture.controller.saveCustomTitle(video, '新剧名');

      expect(fixture.controller.tmdbTargetFor(video).remote.id, 'video-fid');
      expect(
        fixture.controller.tmdbTargetFor(video).remote.path,
        '/影视/原剧名.S01E01.mkv',
      );
      expect(
        client.listed,
        <CloudRemoteRef>[
          const CloudRemoteRef(id: 'root-fid', path: '/影视'),
        ],
      );
      fixture.controller.dispose();
    });

    test('生成结构化草稿并透传显式搜索和候选选择', () async {
      final coordinator = _RecordingTmdbCoordinator();
      final client = _FakeCloudClient(
        entriesById: <String, List<CloudFileEntry>>{
          'root-fid': const <CloudFileEntry>[
            CloudFileEntry(
              id: 'episode-fid',
              remotePath: '/影视/Alice in Borderland S01E01.mkv',
              name: 'Alice in Borderland S01E01.mkv',
              size: 100,
              modifiedAt: null,
              isDirectory: false,
            ),
          ],
        },
      );
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-a',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{'source-a': client},
        tmdbCoordinator: coordinator,
      );
      await fixture.load();
      final episode = fixture.controller.entries.single;
      await fixture.controller.saveCustomTitle(episode, '弥留之国的爱丽丝');

      final draft = fixture.controller.tmdbDraftFor(episode);
      expect(draft.searchTitle, '弥留之国的爱丽丝');
      expect(draft.seasonNumber, 1);
      expect(draft.episodeNumber, 1);

      const request = CloudResourceTmdbSearchRequest(
        queryTitle: 'Alice in Borderland',
        queryYear: 2020,
        mediaTypeMode: TmdbMediaTypeMode.tv,
        options: TmdbScrapeOptions.defaults(),
      );
      await fixture.controller.searchTmdb(episode, request);
      expect(coordinator.searchRequest, same(request));

      final candidate = TmdbRankedCandidate(
        metadata: TmdbMetadata(
          id: 42,
          mediaType: TmdbMediaType.tv,
          title: '弥留之国的爱丽丝',
          language: 'zh-CN',
          matchedAt: _matchedAt,
          matchConfidence: 1,
        ),
        score: 1,
        titleMatched: true,
        yearMatched: true,
        typeMatched: true,
      );
      await fixture.controller.applyTmdbCandidate(
        episode,
        candidate,
        options: const TmdbScrapeOptions.defaults(),
      );
      expect(coordinator.appliedCandidate, same(candidate));
      fixture.controller.dispose();
    });

    test('纯集数视频使用索引剧名和季度生成 TMDB 草稿', () async {
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-folder-season',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{
          'source-folder-season': _FakeCloudClient(
            entriesById: <String, List<CloudFileEntry>>{
              'root-fid': const <CloudFileEntry>[
                CloudFileEntry(
                  id: 'show-fid',
                  remotePath: '/影视/三体',
                  name: '三体',
                  size: 0,
                  modifiedAt: null,
                  isDirectory: true,
                ),
              ],
              'show-fid': const <CloudFileEntry>[
                CloudFileEntry(
                  id: 'season-fid',
                  remotePath: '/影视/三体/第二季',
                  name: '第二季',
                  size: 0,
                  modifiedAt: null,
                  isDirectory: true,
                ),
              ],
              'season-fid': const <CloudFileEntry>[
                CloudFileEntry(
                  id: 'episode-fid',
                  remotePath: '/影视/三体/第二季/01.mkv',
                  name: '01.mkv',
                  size: 100,
                  modifiedAt: null,
                  isDirectory: false,
                ),
              ],
            },
          ),
        },
      );
      await fixture.load();
      final episode = fixture.controller.entries.single;

      final draft = fixture.controller.tmdbDraftFor(episode);
      final target = fixture.controller.tmdbTargetFor(episode);

      expect(draft.searchTitle, '三体');
      expect(draft.seasonNumber, 2);
      expect(draft.episodeNumber, 1);
      expect(draft.mediaTypeMode, TmdbMediaTypeMode.tv);
      expect(target.matchingTitle, '三体');
      expect(target.matchingSeasonNumber, 2);
      expect(target.matchingEpisodeNumber, 1);
      expect(target.displayName, '01.mkv');
      fixture.controller.dispose();
    });

    test('手动匹配会传入当前完整目录并保留每集文件大小', () async {
      final coordinator = _RecordingTmdbCoordinator();
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-a',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{
          'source-a': _FakeCloudClient(
            entriesById: <String, List<CloudFileEntry>>{
              'root-fid': <CloudFileEntry>[
                for (var episode = 1; episode <= 4; episode++)
                  CloudFileEntry(
                    id: 'episode-$episode',
                    remotePath:
                        '/影视/Show.S01E${episode.toString().padLeft(2, '0')}.mkv',
                    name: 'Show.S01E${episode.toString().padLeft(2, '0')}.mkv',
                    size: 1000 + episode,
                    modifiedAt: null,
                    isDirectory: false,
                  ),
              ],
            },
          ),
        },
        tmdbCoordinator: coordinator,
      );
      await fixture.load();
      fixture.controller.setQuery('S01E01');
      final first = fixture.controller.entries.first;
      final candidate = TmdbRankedCandidate(
        metadata: TmdbMetadata(
          id: 42,
          mediaType: TmdbMediaType.tv,
          title: '回魂计',
          language: 'zh-CN',
          matchedAt: _matchedAt,
          matchConfidence: 1,
        ),
        score: 1,
        titleMatched: true,
        yearMatched: false,
        typeMatched: true,
      );

      final outcome = await fixture.controller.applyTmdbCandidate(
        first,
        candidate,
        options: const TmdbScrapeOptions.defaults(),
      );

      expect(outcome.seriesPropagation.eligible, isTrue);
      expect(outcome.seriesPropagation.propagatedCount, 3);
      expect(
        coordinator.propagationCandidates.map((target) => target.remote.id),
        <String>['episode-1', 'episode-2', 'episode-3', 'episode-4'],
      );
      expect(
        coordinator.propagationCandidates
            .every((target) => target.size != null),
        isTrue,
      );
      fixture.controller.dispose();
    });

    test('作品集合和来源刮削候选动态遵守网盘识别大小', () async {
      var minSizeBytes = 100;
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-a',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{
          'source-a': _FakeCloudClient(
            entriesById: const <String, List<CloudFileEntry>>{
              'root-fid': <CloudFileEntry>[
                CloudFileEntry(
                  id: 'folder',
                  remotePath: '/影视/子目录',
                  name: '子目录',
                  size: 0,
                  modifiedAt: null,
                  isDirectory: true,
                ),
                CloudFileEntry(
                  id: 'boundary',
                  remotePath: '/影视/边界.mkv',
                  name: '边界.mkv',
                  size: 100,
                  modifiedAt: null,
                  isDirectory: false,
                ),
                CloudFileEntry(
                  id: 'large',
                  remotePath: '/影视/正片.mkv',
                  name: '正片.mkv',
                  size: 101,
                  modifiedAt: null,
                  isDirectory: false,
                ),
                CloudFileEntry(
                  id: 'subtitle',
                  remotePath: '/影视/正片.ass',
                  name: '正片.ass',
                  size: 10,
                  modifiedAt: null,
                  isDirectory: false,
                ),
              ],
            },
          ),
        },
        minRecognizedVideoSizeBytesProvider: () => minSizeBytes,
      );
      await fixture.load();

      expect(fixture.controller.collection.folders, isEmpty);
      expect(
        fixture.controller.collection.groups.single.anchor.id,
        'large',
      );
      expect(
        fixture.controller.tmdbEntriesForSelectedSource
            .map((entry) => entry.id),
        <String>['large'],
      );

      minSizeBytes = 101;
      expect(fixture.controller.collection.groups, isEmpty);
      expect(
        fixture.controller.tmdbEntriesForSelectedSource
            .map((entry) => entry.id),
        isEmpty,
      );
      fixture.controller.dispose();
    });

    test('自动批量整理继续处理单项失败并汇总全部结果', () async {
      final coordinator = _AutoOrganizeTmdbCoordinator();
      final client = _FakeCloudClient(
        entriesById: <String, List<CloudFileEntry>>{
          'root-fid': const <CloudFileEntry>[
            CloudFileEntry(
              id: 'matched',
              remotePath: '/影视/匹配.mkv',
              name: '匹配.mkv',
              size: 100,
              modifiedAt: null,
              isDirectory: false,
            ),
            CloudFileEntry(
              id: 'pending',
              remotePath: '/影视/待确认.mkv',
              name: '待确认.mkv',
              size: 100,
              modifiedAt: null,
              isDirectory: false,
            ),
            CloudFileEntry(
              id: 'empty',
              remotePath: '/影视/无结果.mkv',
              name: '无结果.mkv',
              size: 100,
              modifiedAt: null,
              isDirectory: false,
            ),
            CloudFileEntry(
              id: 'failed',
              remotePath: '/影视/失败.mkv',
              name: '失败.mkv',
              size: 100,
              modifiedAt: null,
              isDirectory: false,
            ),
          ],
        },
      );
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-a',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{'source-a': client},
        tmdbCoordinator: coordinator,
      );
      await fixture.load();
      final progress = <CloudResourceAutoOrganizeProgress>[];

      final summary = await fixture.controller.autoOrganizeSelectedSource(
        onProgress: progress.add,
      );

      expect(summary.matched, 1);
      expect(summary.pending, 1);
      expect(summary.noResult, 1);
      expect(summary.failed, 1);
      expect(summary.skipped, 0);
      expect(progress.last.phase, CloudResourceAutoOrganizePhase.scraping);
      expect(progress.last.completedTargets, 4);
      expect(progress.last.totalTargets, 4);
      expect(client.closeCount, 2);
      fixture.controller.dispose();
    });

    test('自动批量整理优先应用系列规则且命中项不再请求 TMDB', () async {
      final coordinator = _RuleApplyingAutoOrganizeTmdbCoordinator();
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-a',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{
          'source-a': _FakeCloudClient(
            entriesById: const <String, List<CloudFileEntry>>{
              'root-fid': <CloudFileEntry>[
                CloudFileEntry(
                  id: 'inherited',
                  remotePath: '/影视/Show.S01E06.mkv',
                  name: 'Show.S01E06.mkv',
                  size: 101,
                  modifiedAt: null,
                  isDirectory: false,
                ),
              ],
            },
          ),
        },
        tmdbCoordinator: coordinator,
        autoOrganizer: CloudResourceAutoOrganizer(
          minRecognizedVideoSizeBytesProvider: () => 100,
        ),
      );
      await fixture.load();

      final summary = await fixture.controller.autoOrganizeSelectedSource();

      expect(summary.matched, 1);
      expect(summary.failed, 0);
      expect(coordinator.appliedRuleIds, <String>['inherited']);
      expect(coordinator.scrapedIds, isEmpty);
      fixture.controller.dispose();
    });

    test('自动批量整理跳过已匹配和七天内无结果并重试过期记录', () async {
      final now = DateTime.now();
      final records = <CloudResourceTmdbRecord>[
        CloudResourceTmdbRecord.matched(
          sourceId: 'source-a',
          remoteId: 'cached-matched',
          remotePath: '/影视/已匹配.mkv',
          displayName: '已匹配.mkv',
          resourceKind: CloudResourceKind.standaloneVideo,
          metadata: _autoCandidate,
          checkedAt: now,
        ),
        CloudResourceTmdbRecord.unmatched(
          sourceId: 'source-a',
          remoteId: 'recent-unmatched',
          remotePath: '/影视/近期无结果.mkv',
          displayName: '近期无结果.mkv',
          resourceKind: CloudResourceKind.standaloneVideo,
          checkedAt: now,
        ),
        CloudResourceTmdbRecord.unmatched(
          sourceId: 'source-a',
          remoteId: 'stale-unmatched',
          remotePath: '/影视/过期无结果.mkv',
          displayName: '过期无结果.mkv',
          resourceKind: CloudResourceKind.standaloneVideo,
          checkedAt: now.subtract(const Duration(days: 8)),
        ),
      ];
      final coordinator = _SkippingAutoOrganizeTmdbCoordinator(records);
      final client = _FakeCloudClient(
        entriesById: <String, List<CloudFileEntry>>{
          'root-fid': const <CloudFileEntry>[
            CloudFileEntry(
              id: 'cached-matched',
              remotePath: '/影视/已匹配.mkv',
              name: '已匹配.mkv',
              size: 100,
              modifiedAt: null,
              isDirectory: false,
            ),
            CloudFileEntry(
              id: 'recent-unmatched',
              remotePath: '/影视/近期无结果.mkv',
              name: '近期无结果.mkv',
              size: 100,
              modifiedAt: null,
              isDirectory: false,
            ),
            CloudFileEntry(
              id: 'stale-unmatched',
              remotePath: '/影视/过期无结果.mkv',
              name: '过期无结果.mkv',
              size: 100,
              modifiedAt: null,
              isDirectory: false,
            ),
          ],
        },
      );
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-a',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{'source-a': client},
        tmdbCoordinator: coordinator,
      );
      await fixture.load();

      final summary = await fixture.controller.autoOrganizeSelectedSource();

      expect(summary.skipped, 2);
      expect(summary.noResult, 1);
      expect(summary.matched, 0);
      expect(summary.pending, 0);
      expect(summary.failed, 0);
      expect(coordinator.scrapedIds, <String>['stale-unmatched']);
      expect(client.closeCount, 2);
      fixture.controller.dispose();
    });

    test('没有 TMDB API Key 时不为自动整理再次读取网盘', () async {
      final coordinator = _RecordingTmdbCoordinator();
      final client = _FakeCloudClient();
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-a',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{'source-a': client},
        tmdbCoordinator: coordinator,
      );
      await fixture.load();
      final listedBefore = client.listed.length;

      await expectLater(
        fixture.controller.autoOrganizeSelectedSource(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('请先在设置中填写 TMDB API Key'),
          ),
        ),
      );

      expect(client.listed, hasLength(listedBefore));
      expect(client.closeCount, 1);
      fixture.controller.dispose();
    });

    test('当前目录正在后台刮削时不启动自动整理扫描', () async {
      final coordinator = _BusyAutoOrganizeTmdbCoordinator();
      final client = _FakeCloudClient();
      final fixture = await _Fixture.create(
        sources: const <CloudSource>[
          CloudSource(
            id: 'source-a',
            type: CloudSourceType.quark,
            name: '夸克媒体库',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>['/影视'],
            rootRefs: <CloudRemoteRef>[
              CloudRemoteRef(id: 'root-fid', path: '/影视'),
            ],
          ),
        ],
        clients: <String, _FakeCloudClient>{'source-a': client},
        tmdbCoordinator: coordinator,
      );
      await fixture.load();
      final listedBefore = client.listed.length;

      await expectLater(
        fixture.controller.autoOrganizeSelectedSource(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('当前目录正在刮削'),
          ),
        ),
      );

      expect(client.listed, hasLength(listedBefore));
      fixture.controller.dispose();
    });
  });
}

final _matchedAt = DateTime.utc(2026, 7, 19);

class _Fixture {
  const _Fixture({required this.controller, required this.clients});

  final CloudResourcesController controller;
  final Map<String, _FakeCloudClient> clients;

  Future<void> load() async {
    await controller.load();
    await controller.scanCompletion;
  }

  static Future<_Fixture> create({
    required List<CloudSource> sources,
    required Map<String, _FakeCloudClient> clients,
    CloudResourceTmdbCoordinator? tmdbCoordinator,
    CloudResourceAutoOrganizer? autoOrganizer,
    int Function()? minRecognizedVideoSizeBytesProvider,
  }) async {
    final credentials = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentials,
    );
    for (final source in sources) {
      await repository.save(source);
    }
    final registry = CloudProviderRegistry(
      clientFactories: <CloudSourceType, CloudProviderClientFactory>{
        CloudSourceType.openList: (source, _, __) => clients[source.id]!,
        CloudSourceType.quark: (source, _, __) => clients[source.id]!,
      },
    );
    final minSizeProvider = minRecognizedVideoSizeBytesProvider ?? (() => 0);
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    return _Fixture(
      controller: CloudResourcesController(
        repository: repository,
        credentialStore: credentials,
        providerRegistry: registry,
        mediaIndexRepository: indexRepository,
        mediaIndexer: CloudMediaIndexer(
          repository: indexRepository,
          minRecognizedVideoSizeBytesProvider: minSizeProvider,
        ),
        tmdbCoordinator: tmdbCoordinator,
        autoOrganizer: autoOrganizer ??
            CloudResourceAutoOrganizer(
              minRecognizedVideoSizeBytesProvider: () => 0,
            ),
        minRecognizedVideoSizeBytesProvider: minSizeProvider,
      ),
      clients: clients,
    );
  }
}

class _RecordingTmdbCoordinator extends CloudResourceTmdbCoordinator {
  _RecordingTmdbCoordinator()
      : super(
          repository: CloudResourceTmdbRepository(
            storage: MemoryCloudResourceTmdbStorage(),
          ),
          serviceFactory: (_) => throw UnimplementedError(),
          apiKeyProvider: () => '',
        );

  final List<CloudResourceDirectoryContext> contexts =
      <CloudResourceDirectoryContext>[];
  CloudResourceTmdbSearchRequest? searchRequest;
  TmdbRankedCandidate? appliedCandidate;
  List<CloudResourceTmdbTarget> propagationCandidates =
      const <CloudResourceTmdbTarget>[];

  @override
  Future<void> loadAndSchedule(CloudResourceDirectoryContext context) async {
    contexts.add(context);
  }

  @override
  Future<CloudResourceTmdbSearchOutcome> searchPrepared(
    CloudResourceTmdbTarget target,
    CloudResourceTmdbSearchRequest request,
  ) async {
    searchRequest = request;
    return const CloudResourceTmdbSearchOutcome(
      ranked: TmdbRankedResult(
        candidates: <TmdbRankedCandidate>[],
        shouldAutoMatch: false,
      ),
    );
  }

  @override
  Future<CloudResourceTmdbSelectionOutcome> selectPrepared(
    CloudResourceTmdbTarget target,
    TmdbRankedCandidate candidate, {
    required TmdbScrapeOptions options,
    List<CloudResourceTmdbTarget> propagationCandidates =
        const <CloudResourceTmdbTarget>[],
  }) async {
    appliedCandidate = candidate;
    this.propagationCandidates = propagationCandidates;
    return CloudResourceTmdbSelectionOutcome(
      record: CloudResourceTmdbRecord.matched(
        sourceId: target.sourceId,
        remoteId: target.remote.id,
        remotePath: target.remote.path,
        displayName: target.displayName,
        resourceKind: target.resourceKind,
        metadata: candidate.metadata,
        checkedAt: _matchedAt,
      ),
      posterCached: true,
      indexSynced: true,
      seriesPropagation: const CloudSeriesPropagationSummary(
        eligible: true,
        ruleSaved: true,
        propagatedCount: 3,
        indexSyncFailures: 0,
      ),
    );
  }
}

class _FailingTmdbCoordinator extends _RecordingTmdbCoordinator {
  @override
  Future<void> loadAndSchedule(CloudResourceDirectoryContext context) async {
    throw StateError('模拟 TMDB 失败');
  }
}

class _AutoOrganizeTmdbCoordinator extends _RecordingTmdbCoordinator {
  @override
  bool get hasApiKey => true;

  @override
  Future<CloudResourceTmdbOutcome> scrape(
    CloudResourceTmdbTarget target, {
    TmdbScrapeOptions? options,
  }) async {
    switch (target.remote.id) {
      case 'matched':
        return CloudResourceTmdbOutcome(
          candidates: <TmdbMetadata>[_autoCandidate],
          selected: CloudResourceTmdbRecord.matched(
            sourceId: target.sourceId,
            remoteId: target.remote.id,
            remotePath: target.remote.path,
            displayName: target.displayName,
            resourceKind: target.resourceKind,
            metadata: _autoCandidate,
            checkedAt: _matchedAt,
          ),
        );
      case 'pending':
        return CloudResourceTmdbOutcome(
          candidates: <TmdbMetadata>[_autoCandidate],
        );
      case 'empty':
        return const CloudResourceTmdbOutcome(
          candidates: <TmdbMetadata>[],
        );
      case 'failed':
        throw StateError('模拟单项失败');
    }
    throw StateError('未知测试资源');
  }
}

class _SkippingAutoOrganizeTmdbCoordinator extends _RecordingTmdbCoordinator {
  _SkippingAutoOrganizeTmdbCoordinator(List<CloudResourceTmdbRecord> records)
      : cachedRecords = <String, CloudResourceTmdbRecord>{
          for (final record in records) record.stableKey: record,
        };

  final Map<String, CloudResourceTmdbRecord> cachedRecords;
  final List<String> scrapedIds = <String>[];

  @override
  bool get hasApiKey => true;

  @override
  Map<String, CloudResourceTmdbRecord> get records => cachedRecords;

  @override
  Future<CloudResourceTmdbOutcome> scrape(
    CloudResourceTmdbTarget target, {
    TmdbScrapeOptions? options,
  }) async {
    scrapedIds.add(target.remote.id);
    return const CloudResourceTmdbOutcome(candidates: <TmdbMetadata>[]);
  }
}

class _RuleApplyingAutoOrganizeTmdbCoordinator
    extends _AutoOrganizeTmdbCoordinator {
  final List<String> appliedRuleIds = <String>[];
  final List<String> scrapedIds = <String>[];

  @override
  Future<CloudSeriesRuleApplication?> applySeriesRule(
    CloudResourceTmdbTarget target,
  ) async {
    appliedRuleIds.add(target.remote.id);
    if (target.remote.id != 'inherited') return null;
    final metadata = TmdbMetadata(
      id: 42,
      mediaType: TmdbMediaType.tv,
      title: '回魂计',
      language: 'zh-CN',
      matchedAt: _matchedAt,
      matchConfidence: 1,
    );
    return CloudSeriesRuleApplication(
      record: CloudResourceTmdbRecord.matched(
        sourceId: target.sourceId,
        remoteId: target.remote.id,
        remotePath: target.remote.path,
        displayName: target.displayName,
        resourceKind: target.resourceKind,
        metadata: metadata,
        checkedAt: _matchedAt,
      ),
      metadata: metadata,
      indexSynced: true,
    );
  }

  @override
  Future<CloudResourceTmdbOutcome> scrape(
    CloudResourceTmdbTarget target, {
    TmdbScrapeOptions? options,
  }) async {
    scrapedIds.add(target.remote.id);
    return super.scrape(target, options: options);
  }
}

class _BusyAutoOrganizeTmdbCoordinator extends _RecordingTmdbCoordinator {
  @override
  bool get hasApiKey => true;

  @override
  bool get isScraping => true;
}

final _autoCandidate = TmdbMetadata(
  id: 42,
  mediaType: TmdbMediaType.movie,
  title: '中文片名',
  language: 'zh-CN',
  matchedAt: _matchedAt,
  matchConfidence: 1,
);

class _FakeCloudClient implements CloudDriveClient {
  _FakeCloudClient({
    this.entriesById = const <String, List<CloudFileEntry>>{},
  });

  final Map<String, List<CloudFileEntry>> entriesById;
  final List<CloudRemoteRef> listed = <CloudRemoteRef>[];
  int closeCount = 0;

  @override
  Future<void> authenticate(CloudSource source, CloudCredential credential) =>
      throw UnimplementedError();

  @override
  Future<void> close() async => closeCount++;

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) =>
      throw UnimplementedError();

  @override
  Future<List<CloudFileEntry>> listDirectory(
    CloudRemoteRef directory,
  ) async {
    listed.add(directory);
    return entriesById[directory.id] ?? const <CloudFileEntry>[];
  }

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}

class _DelayedCloudClient extends _FakeCloudClient {
  final Completer<List<CloudFileEntry>> _completer =
      Completer<List<CloudFileEntry>>();

  void complete(List<CloudFileEntry> entries) => _completer.complete(entries);

  @override
  Future<List<CloudFileEntry>> listDirectory(CloudRemoteRef directory) {
    listed.add(directory);
    return _completer.future;
  }
}
