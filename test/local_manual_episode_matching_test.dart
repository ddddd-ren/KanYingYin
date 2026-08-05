import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client_capabilities.dart';

void main() {
  test('LocalController 创建会话并批量保存手动集号', () async {
    final repository = LocalMediaIndexRepository(storage: _MemoryStorage());
    const path = r'D:\Library\Show\Season 1\Show.S01E01.mkv';
    await repository.saveForSource(r'D:\Library', <LocalMediaIndexItem>[
      LocalMediaIndexItem(
        path: path,
        name: 'Show.S01E01.mkv',
        parentPath: r'D:\Library\Show\Season 1',
        sourcePath: r'D:\Library',
        size: 100,
        modified: DateTime.utc(2026, 8, 6),
        seriesName: 'Show',
        seasonNumber: 1,
        episodeNumber: 1,
        indexedAt: DateTime.utc(2026, 8, 6),
      ),
    ]);
    final fakeClient = _FakeTmdbClient();
    final controller = LocalController(
      mediaIndexRepository: repository,
      tmdbApiKeyProvider: TmdbApiKeyProvider(userKeyReader: () => 'key'),
      tmdbClientContextRegistry: TmdbClientContextRegistry(
        clientFactory: (_) => fakeClient,
      ),
    );

    final matchController = controller.manualEpisodeMatchControllerForPaths(
      paths: const <String>[path],
      selectedSeries: _metadata(summaryOnly: true),
    );
    await matchController.initialize();
    matchController.assignEpisode(
      repository.getAll().single.id,
      2,
    );
    await controller.saveManualEpisodeAssignments(
      paths: const <String>[path],
      assignments: matchController.assignments,
      metadata: matchController.metadata,
      selectedSeasonNumber: 1,
    );

    final updated = repository.getAll().single;
    expect(fakeClient.detailsCalls, 1);
    expect(fakeClient.seasonCalls, <int>[1]);
    expect(updated.episodeNumber, 2);
    expect(updated.displayTitle, '异世界悠闲农家 S01E02 第一位村民');
  });

  test('本地两个系列菜单都提供匹配剧集入口', () async {
    final localPage =
        await File('lib/pages/local/local_page.dart').readAsString();
    final librarySheet =
        await File('lib/pages/local/library_sheet.dart').readAsString();

    expect(localPage, contains("Text('匹配剧集')"));
    expect(librarySheet, contains("Text('匹配剧集')"));
  });
}

TmdbMetadata _metadata({required bool summaryOnly}) {
  return TmdbMetadata(
    id: 196285,
    mediaType: TmdbMediaType.tv,
    title: '异世界悠闲农家',
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026, 8, 6),
    matchConfidence: 1,
    seasons: <TmdbSeasonMetadata>[
      TmdbSeasonMetadata(
        id: 1,
        seasonNumber: 1,
        name: '第 1 季',
        episodeCount: 2,
        episodes: summaryOnly
            ? const <TmdbEpisodeMetadata>[]
            : const <TmdbEpisodeMetadata>[
                TmdbEpisodeMetadata(id: 11, episodeNumber: 1, name: '万能农具'),
                TmdbEpisodeMetadata(
                  id: 12,
                  episodeNumber: 2,
                  name: '第一位村民',
                ),
              ],
      ),
    ],
  );
}

final class _FakeTmdbClient implements ITmdbClient, ITmdbClientCapabilities {
  int detailsCalls = 0;
  final List<int> seasonCalls = <int>[];

  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    detailsCalls++;
    return _metadata(summaryOnly: true);
  }

  @override
  Future<TmdbSeasonMetadata> seasonDetails(
    int id,
    int seasonNumber, {
    String language = 'zh-CN',
  }) async {
    seasonCalls.add(seasonNumber);
    return _metadata(summaryOnly: false).seasons.single;
  }

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async =>
      <TmdbMetadata>[_metadata(summaryOnly: true)];

  @override
  Future<TmdbSearchPage> searchPage(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
    required int page,
  }) async {
    return TmdbSearchPage(
      page: page,
      totalPages: 1,
      results: <TmdbMetadata>[_metadata(summaryOnly: true)],
    );
  }

  @override
  Future<List<String>> alternativeTitles(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async =>
      const <String>[];
}

final class _MemoryStorage implements LocalMediaIndexStorage {
  final Map<String, Object?> values = <String, Object?>{};

  @override
  Object? read(String key, {Object? defaultValue}) =>
      values[key] ?? defaultValue;

  @override
  Future<void> write(String key, Object? value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
