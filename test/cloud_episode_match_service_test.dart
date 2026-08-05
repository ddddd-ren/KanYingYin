import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/episode_matching/application/cloud_episode_match_service.dart';
import 'package:kanyingyin/features/episode_matching/domain/manual_episode_match.dart';
import 'package:kanyingyin/modules/cloud/cloud_episode_match_rule.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_episode_match_rule_repository.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';

void main() {
  test('加载匹配资源时同时恢复手动规则和严格自动识别结果', () async {
    final indexRepository =
        CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
    final ruleRepository = CloudEpisodeMatchRuleRepository(
      storage: MemoryCloudEpisodeMatchRuleStorage(),
    );
    await _seedIndex(indexRepository);
    final indexed = await indexRepository.getBySource('quark-1');
    final second = indexed.firstWhere((item) => item.remoteId == 'video-2');
    await ruleRepository.upsert(
      CloudEpisodeMatchRule.keepOriginal(
        sourceId: second.sourceId,
        remoteId: second.remoteId,
        remotePath: second.remotePath,
        tmdbId: 196285,
        updatedAt: DateTime.utc(2026, 8, 6),
      ),
    );
    final service = CloudEpisodeMatchService(
      ruleRepository: ruleRepository,
      indexRepository: indexRepository,
    );

    final items = await service.loadMatchItems(
      sourceId: 'quark-1',
      resourceIds: const <String>['video-1', 'video-2'],
      expectedSeriesName: 'Show',
      selectedSeasonNumber: 1,
    );

    expect(items, hasLength(2));
    expect(items.first.automaticSeasonNumber, 1);
    expect(items.first.automaticEpisodeNumber, 1);
    expect(items.first.manualOverride, isFalse);
    expect(items.last.manualOverride, isTrue);
  });

  test('保存规则后立即批量刷新当前网盘索引', () async {
    final indexRepository =
        CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
    final ruleRepository = CloudEpisodeMatchRuleRepository(
      storage: MemoryCloudEpisodeMatchRuleStorage(),
    );
    await _seedIndex(indexRepository);
    final service = CloudEpisodeMatchService(
      ruleRepository: ruleRepository,
      indexRepository: indexRepository,
      now: () => DateTime.utc(2026, 8, 6),
    );
    final items = await indexRepository.getBySource('quark-1');

    final outcome = await service.save(
      sourceId: 'quark-1',
      resourceIds: items.map((item) => item.remoteId),
      assignments: <ManualEpisodeAssignment>[
        ManualEpisodeAssignment.mapped(
          resourceId: 'video-1',
          seasonNumber: 1,
          episodeNumber: 2,
        ),
        ManualEpisodeAssignment.keepOriginal('video-2'),
      ],
      metadata: _metadata(),
      selectedSeasonNumber: 1,
    );

    expect(outcome.rulesSaved, isTrue);
    expect(outcome.indexSynced, isTrue);
    final updated = <String, CloudMediaIndexItem>{
      for (final item in await indexRepository.getBySource('quark-1'))
        item.remoteId: item,
    };
    expect(updated['video-1']!.episodeNumber, 2);
    expect(updated['video-1']!.tmdbId, 196285);
    expect(updated['video-1']!.tmdbTitle, '异世界悠闲农家');
    expect(
      updated['video-1']!.displayName,
      '异世界悠闲农家 S01E02 第一位村民.mkv',
    );
    expect(updated['video-2']!.seasonNumber, isNull);
    expect(updated['video-2']!.episodeNumber, isNull);
    expect(await ruleRepository.getBySource('quark-1'), hasLength(2));
  });

  test('恢复自动识别会删除规则并重新采用可靠文件名', () async {
    final indexRepository =
        CloudMediaIndexRepository(storage: MemoryCloudMediaIndexStorage());
    final ruleRepository = CloudEpisodeMatchRuleRepository(
      storage: MemoryCloudEpisodeMatchRuleStorage(),
    );
    await _seedIndex(indexRepository);
    final item = (await indexRepository.getBySource('quark-1')).first;
    await ruleRepository.upsert(
      CloudEpisodeMatchRule.keepOriginal(
        sourceId: item.sourceId,
        remoteId: item.remoteId,
        remotePath: item.remotePath,
        tmdbId: 196285,
        updatedAt: DateTime.utc(2026, 8, 5),
      ),
    );
    final service = CloudEpisodeMatchService(
      ruleRepository: ruleRepository,
      indexRepository: indexRepository,
    );

    await service.save(
      sourceId: 'quark-1',
      resourceIds: <String>[item.remoteId],
      assignments: <ManualEpisodeAssignment>[
        ManualEpisodeAssignment.restoreAutomatic(item.remoteId),
      ],
      metadata: _metadata(),
      selectedSeasonNumber: 1,
    );

    final restored = (await indexRepository.getBySource('quark-1'))
        .firstWhere((current) => current.remoteId == item.remoteId);
    expect(restored.seasonNumber, 1);
    expect(restored.episodeNumber, 1);
    expect(await ruleRepository.get(itemRuleKey(item)), isNull);
  });

  test('索引刷新失败时保留已保存规则并返回下次扫描生效', () async {
    final storage = _FailingCloudMediaIndexStorage();
    final indexRepository = CloudMediaIndexRepository(storage: storage);
    final ruleRepository = CloudEpisodeMatchRuleRepository(
      storage: MemoryCloudEpisodeMatchRuleStorage(),
    );
    await _seedIndex(indexRepository);
    storage.failWrites = true;
    final service = CloudEpisodeMatchService(
      ruleRepository: ruleRepository,
      indexRepository: indexRepository,
    );

    final outcome = await service.save(
      sourceId: 'quark-1',
      resourceIds: const <String>['video-1'],
      assignments: <ManualEpisodeAssignment>[
        ManualEpisodeAssignment.mapped(
          resourceId: 'video-1',
          seasonNumber: 1,
          episodeNumber: 2,
        ),
      ],
      metadata: _metadata(),
      selectedSeasonNumber: 1,
    );

    expect(outcome.rulesSaved, isTrue);
    expect(outcome.indexSynced, isFalse);
    expect(await ruleRepository.getBySource('quark-1'), hasLength(1));
  });
}

String itemRuleKey(CloudMediaIndexItem item) {
  return cloudEpisodeMatchRuleKey(
    sourceId: item.sourceId,
    remoteId: item.remoteId,
    remotePath: item.remotePath,
  );
}

Future<void> _seedIndex(CloudMediaIndexRepository repository) {
  return repository.replaceSource(
    'quark-1',
    <CloudMediaIndexItem>[
      CloudMediaIndexItem(
        sourceId: 'quark-1',
        remoteId: 'video-1',
        remotePath: '/Show/Season 1/Show.S01E01.mkv',
        name: 'Show.S01E01.mkv',
        size: 100,
        modifiedAt: DateTime.utc(2026, 8, 6),
        seriesName: 'Show',
        seasonNumber: 1,
        episodeNumber: 1,
        mediaType: CloudMediaType.episode,
      ),
      CloudMediaIndexItem(
        sourceId: 'quark-1',
        remoteId: 'video-2',
        remotePath: '/Show/Season 1/Show.S01E02.mkv',
        name: 'Show.S01E02.mkv',
        size: 100,
        modifiedAt: DateTime.utc(2026, 8, 6),
        seriesName: 'Show',
        seasonNumber: 1,
        episodeNumber: 2,
        mediaType: CloudMediaType.episode,
      ),
    ],
    const <String, String>{},
    const <String, List<CloudFileEntry>>{},
    const <String>['/Show'],
  );
}

TmdbMetadata _metadata() {
  return TmdbMetadata(
    id: 196285,
    mediaType: TmdbMediaType.tv,
    title: '异世界悠闲农家',
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026, 8, 6),
    matchConfidence: 1,
    seasons: const <TmdbSeasonMetadata>[
      TmdbSeasonMetadata(
        id: 1,
        seasonNumber: 1,
        name: '第 1 季',
        episodeCount: 2,
        episodes: <TmdbEpisodeMetadata>[
          TmdbEpisodeMetadata(id: 11, episodeNumber: 1, name: '万能农具'),
          TmdbEpisodeMetadata(id: 12, episodeNumber: 2, name: '第一位村民'),
        ],
      ),
    ],
  );
}

final class _FailingCloudMediaIndexStorage implements CloudMediaIndexStorage {
  Map<String, Object?> value = <String, Object?>{};
  bool failWrites = false;

  @override
  Object get synchronizationIdentity => this;

  @override
  Future<Map<String, Object?>> read() async => Map<String, Object?>.from(value);

  @override
  Future<void> write(Map<String, Object?> value) async {
    if (failWrites) throw StateError('模拟索引刷新失败');
    this.value = Map<String, Object?>.from(value);
  }
}
