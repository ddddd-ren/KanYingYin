import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_series_match_rule.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_series_match_rule_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/cloud/cloud_series_match_service.dart';

void main() {
  group('CloudSeriesMatchService', () {
    test('手动确认一次会传播到同目录未匹配分集并保留现有信息', () async {
      final fixture = await _Fixture.create();
      final first = _target('episode-1', '/剧集/Show.S01E01.mkv');
      final second = _target('episode-2', '/剧集/Show.S01E02.mkv');
      final third = _target('episode-3', '/剧集/Show.S01E03.mkv');
      final matched = _target('matched', '/剧集/Show.S01E04.mkv');
      final custom = _target(
        'custom',
        '/剧集/Show.S01E05.mkv',
        customTitle: '我的剧名',
      );
      final otherDirectory = _target(
        'other-directory',
        '/其他/Show.S01E06.mkv',
      );
      final matchedRecord = _matchedRecord(matched, metadata: _otherMetadata);
      final customRecord = CloudResourceTmdbRecord.unchecked(
        sourceId: custom.sourceId,
        remoteId: custom.remote.id,
        remotePath: custom.remote.path,
        displayName: custom.displayName,
        resourceKind: custom.resourceKind,
        checkedAt: _now,
        customTitle: '我的剧名',
      );

      final result = await fixture.service.learnAndPropagate(
        anchor: first,
        anchorRecord: _matchedRecord(first),
        candidates: <CloudResourceTmdbTarget>[
          first,
          second,
          third,
          matched,
          custom,
          otherDirectory,
        ],
        existingRecords: <String, CloudResourceTmdbRecord>{
          matchedRecord.stableKey: matchedRecord,
          customRecord.stableKey: customRecord,
        },
        language: 'zh-CN',
      );

      expect(result.eligible, isTrue);
      expect(result.ruleSaved, isTrue);
      expect(
        result.records.map((record) => record.remoteId),
        <String>['episode-2', 'episode-3'],
      );
      expect(result.indexSyncFailures, 0);
      expect(result.pendingIndexSyncTargets, isEmpty);
      expect(
        (await fixture.ruleRepository.getBySource('quark')).single.metadata.id,
        _metadata.id,
      );
      expect(
        (await fixture.recordRepository.get(second.stableKey))?.title,
        '回魂计',
      );
      expect(
        (await fixture.recordRepository.get(second.stableKey))
            ?.seasons
            .single
            .posterUrl,
        '/season-1.jpg',
      );
      expect(
        (await fixture.indexRepository.getBySource('quark'))
            .where((item) => item.remoteId == 'episode-2')
            .single
            .tmdbId,
        42,
      );
      expect(await fixture.recordRepository.get(matched.stableKey), isNull);
      expect(await fixture.recordRepository.get(custom.stableKey), isNull);
      expect(
        await fixture.recordRepository.get(otherDirectory.stableKey),
        isNull,
      );
    });

    test('规则优先覆盖近期无结果记录且不需要 TMDB 客户端', () async {
      final fixture = await _Fixture.create();
      final target = _target('episode-7', '/剧集/Show.S01E07.mkv');
      final identity = fixture.service.identityFor(target)!;
      await fixture.ruleRepository.upsert(
        CloudSeriesMatchRule(
          sourceId: identity.sourceId,
          parentPath: identity.parentPath,
          normalizedSeriesName: identity.normalizedSeriesName,
          metadata: _metadata,
          posterCachePath: r'C:\cache\show.jpg',
          updatedAt: _now,
        ),
      );
      final recentUnmatched = CloudResourceTmdbRecord.unmatched(
        sourceId: target.sourceId,
        remoteId: target.remote.id,
        remotePath: target.remote.path,
        displayName: target.displayName,
        resourceKind: target.resourceKind,
        checkedAt: _now,
      );

      final application = await fixture.service.applyRule(
        target: target,
        existingRecord: recentUnmatched,
      );

      expect(application, isNotNull);
      expect(application?.record.status, CloudResourceTmdbStatus.matched);
      expect(application?.record.title, '回魂计');
      expect(application?.record.posterCachePath, r'C:\cache\show.jpg');
      expect(application?.record.seasons.single.seasonNumber, 1);
      expect(application?.indexSynced, isTrue);
      expect(
        (await fixture.recordRepository.get(target.stableKey))?.tmdbId,
        42,
      );
    });

    test('已有匹配和自定义标题不会被规则覆盖', () async {
      final fixture = await _Fixture.create();
      final target = _target('episode-8', '/剧集/Show.S01E08.mkv');
      final identity = fixture.service.identityFor(target)!;
      await fixture.ruleRepository.upsert(
        CloudSeriesMatchRule(
          sourceId: identity.sourceId,
          parentPath: identity.parentPath,
          normalizedSeriesName: identity.normalizedSeriesName,
          metadata: _metadata,
          updatedAt: _now,
        ),
      );
      final matched = _matchedRecord(target, metadata: _otherMetadata);
      final custom = CloudResourceTmdbRecord.unchecked(
        sourceId: target.sourceId,
        remoteId: target.remote.id,
        remotePath: target.remote.path,
        displayName: target.displayName,
        resourceKind: target.resourceKind,
        checkedAt: _now,
        customTitle: '保留名称',
      );

      expect(
        await fixture.service.applyRule(
          target: target,
          existingRecord: matched,
        ),
        isNull,
      );
      expect(
        await fixture.service.applyRule(
          target: target,
          existingRecord: custom,
        ),
        isNull,
      );
    });

    test('规则保存失败仍传播当前目录并报告未持久化', () async {
      final ruleStorage = _FailingRuleStorage();
      final fixture = await _Fixture.create(ruleStorage: ruleStorage);
      final first = _target('episode-1', '/剧集/Show.S01E01.mkv');
      final second = _target('episode-2', '/剧集/Show.S01E02.mkv');
      ruleStorage.failNextWrite = true;

      final result = await fixture.service.learnAndPropagate(
        anchor: first,
        anchorRecord: _matchedRecord(first),
        candidates: <CloudResourceTmdbTarget>[first, second],
        existingRecords: const <String, CloudResourceTmdbRecord>{},
        language: 'zh-CN',
      );

      expect(result.eligible, isTrue);
      expect(result.ruleSaved, isFalse);
      expect(result.records.single.remoteId, 'episode-2');
      expect(await fixture.ruleRepository.getBySource('quark'), isEmpty);
    });
  });
}

class _Fixture {
  const _Fixture({
    required this.service,
    required this.ruleRepository,
    required this.recordRepository,
    required this.indexRepository,
  });

  final CloudSeriesMatchService service;
  final CloudSeriesMatchRuleRepository ruleRepository;
  final CloudResourceTmdbRepository recordRepository;
  final CloudMediaIndexRepository indexRepository;

  static Future<_Fixture> create({
    CloudSeriesMatchRuleStorage? ruleStorage,
  }) async {
    final ruleRepository = CloudSeriesMatchRuleRepository(
      storage: ruleStorage ?? MemoryCloudSeriesMatchRuleStorage(),
    );
    final recordRepository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await indexRepository.replaceSource(
      'quark',
      <CloudMediaIndexItem>[
        for (var episode = 1; episode <= 8; episode++)
          _indexItem(
            'episode-$episode',
            '/剧集/Show.S01E${episode.toString().padLeft(2, '0')}.mkv',
            episode,
          ),
      ],
      const <String, String>{},
      const <String, List<CloudFileEntry>>{},
      const <String>['/剧集'],
    );
    final service = CloudSeriesMatchService(
      ruleRepository: ruleRepository,
      recordRepository: recordRepository,
      indexRepository: indexRepository,
      minRecognizedVideoSizeBytesProvider: () => 100,
      now: () => _now,
    );
    return _Fixture(
      service: service,
      ruleRepository: ruleRepository,
      recordRepository: recordRepository,
      indexRepository: indexRepository,
    );
  }
}

class _FailingRuleStorage extends MemoryCloudSeriesMatchRuleStorage {
  bool failNextWrite = false;

  @override
  Future<void> write(List<Map<String, Object?>> rules) {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('模拟规则保存失败');
    }
    return super.write(rules);
  }
}

CloudResourceTmdbTarget _target(
  String id,
  String path, {
  String? customTitle,
}) {
  return CloudResourceTmdbTarget(
    sourceId: 'quark',
    remote: CloudRemoteRef(id: id, path: path),
    displayName: path.split('/').last,
    resourceKind: CloudResourceKind.standaloneVideo,
    customTitle: customTitle,
    size: 1000,
  );
}

CloudResourceTmdbRecord _matchedRecord(
  CloudResourceTmdbTarget target, {
  TmdbMetadata? metadata,
}) {
  return CloudResourceTmdbRecord.matched(
    sourceId: target.sourceId,
    remoteId: target.remote.id,
    remotePath: target.remote.path,
    displayName: target.displayName,
    resourceKind: target.resourceKind,
    metadata: metadata ?? _metadata,
    checkedAt: _now,
    posterCachePath: r'C:\cache\show.jpg',
    customTitle: target.customTitle,
  );
}

CloudMediaIndexItem _indexItem(String id, String path, int episode) {
  return CloudMediaIndexItem(
    sourceId: 'quark',
    remoteId: id,
    remotePath: path,
    name: path.split('/').last,
    size: 1000,
    modifiedAt: null,
    seriesName: 'Show',
    seasonNumber: 1,
    episodeNumber: episode,
    mediaType: CloudMediaType.episode,
  );
}

final _now = DateTime.utc(2026, 7, 20);

final _metadata = TmdbMetadata(
  id: 42,
  mediaType: TmdbMediaType.tv,
  title: '回魂计',
  originalTitle: 'The Resurrected',
  overview: '简介',
  releaseDate: '2025-10-09',
  rating: 7.7,
  posterUrl: '/poster.jpg',
  backdropUrl: '/backdrop.jpg',
  language: 'zh-CN',
  matchedAt: _now,
  matchConfidence: 1,
  seasons: const <TmdbSeasonMetadata>[
    TmdbSeasonMetadata(
      id: 100,
      seasonNumber: 1,
      name: '第 1 季',
      episodeCount: 8,
      posterUrl: '/season-1.jpg',
      posterCachePath: r'C:\cache\season-1.jpg',
    ),
  ],
);

final _otherMetadata = TmdbMetadata(
  id: 99,
  mediaType: TmdbMediaType.tv,
  title: '其他剧集',
  language: 'zh-CN',
  matchedAt: _now,
  matchConfidence: 1,
);
