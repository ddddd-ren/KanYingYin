import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_series_match_rule.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_series_match_rule_repository.dart';

void main() {
  group('CloudSeriesMatchRuleRepository', () {
    test('规则支持 JSON 往返并保留完整元数据', () {
      final original = _rule(
        sourceId: 'quark',
        parentPath: '/剧集',
        seriesName: 'the resurrected',
      );

      final restored = CloudSeriesMatchRule.fromJson(original.toJson());

      expect(restored.toJson(), original.toJson());
      expect(restored, original);
      expect(restored.metadata.title, '回魂计');
      expect(restored.posterCachePath, r'C:\cache\poster.jpg');
    });

    test('相同系列键覆盖更新并可跨仓库实例读取', () async {
      final storage = MemoryCloudSeriesMatchRuleStorage();
      final firstRepository = CloudSeriesMatchRuleRepository(storage: storage);
      final secondRepository = CloudSeriesMatchRuleRepository(storage: storage);
      final original = _rule(
        sourceId: 'quark',
        parentPath: '/剧集',
        seriesName: 'the resurrected',
      );
      final updated = original.copyWith(
        updatedAt: DateTime.utc(2026, 7, 21),
      );

      await firstRepository.upsert(original);
      await secondRepository.upsert(updated);

      expect(await firstRepository.get(original.stableKey), updated);
      expect(await firstRepository.getBySource('quark'), <CloudSeriesMatchRule>[
        updated,
      ]);
    });

    test('并发保存不丢规则且删除来源后可原样恢复', () async {
      final repository = CloudSeriesMatchRuleRepository(
        storage: MemoryCloudSeriesMatchRuleStorage(),
      );
      final first = _rule(
        sourceId: 'quark',
        parentPath: '/A',
        seriesName: 'show a',
      );
      final second = _rule(
        sourceId: 'quark',
        parentPath: '/B',
        seriesName: 'show b',
      );
      final retained = _rule(
        sourceId: 'openlist',
        parentPath: '/C',
        seriesName: 'show c',
      );

      await Future.wait(<Future<void>>[
        repository.upsert(first),
        repository.upsert(second),
        repository.upsert(retained),
      ]);

      expect(await repository.getBySource('quark'), hasLength(2));
      final removed = await repository.removeSource('quark');
      expect(removed.toSet(), <CloudSeriesMatchRule>{first, second});
      expect(await repository.getBySource('quark'), isEmpty);
      expect(await repository.getBySource('openlist'), <CloudSeriesMatchRule>[
        retained,
      ]);

      await repository.replaceSource('quark', removed);
      expect(
          (await repository.getBySource('quark')).toSet(),
          <CloudSeriesMatchRule>{
            first,
            second,
          });
    });

    test('损坏记录被忽略且不会阻止读取有效规则', () async {
      final storage = MemoryCloudSeriesMatchRuleStorage();
      final valid = _rule(
        sourceId: 'quark',
        parentPath: '/剧集',
        seriesName: 'show',
      );
      await storage.write(<Map<String, Object?>>[
        <String, Object?>{'sourceId': 42},
        valid.toJson(),
      ]);
      final repository = CloudSeriesMatchRuleRepository(storage: storage);

      expect(await repository.getBySource('quark'), <CloudSeriesMatchRule>[
        valid,
      ]);
    });
  });
}

CloudSeriesMatchRule _rule({
  required String sourceId,
  required String parentPath,
  required String seriesName,
}) {
  return CloudSeriesMatchRule(
    sourceId: sourceId,
    parentPath: parentPath,
    normalizedSeriesName: seriesName,
    metadata: TmdbMetadata(
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
      matchedAt: DateTime.utc(2026, 7, 20),
      matchConfidence: 1,
    ),
    posterCachePath: r'C:\cache\poster.jpg',
    updatedAt: DateTime.utc(2026, 7, 20),
  );
}
