import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

void main() {
  test('作品记录往返保留刮削名称主海报和季度海报', () {
    final metadata = TmdbMetadata(
      id: 42,
      mediaType: TmdbMediaType.tv,
      title: 'TMDB 中文标题',
      originalTitle: 'Original Title',
      overview: '作品简介',
      rating: 8.5,
      posterUrl: '/poster.jpg',
      backdropUrl: '/backdrop.jpg',
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 7, 20),
      matchConfidence: 1,
      seasons: <TmdbSeasonMetadata>[
        for (var season = 1; season <= 3; season++)
          TmdbSeasonMetadata(
            id: season * 100,
            seasonNumber: season,
            name: '第 $season 季',
            episodeCount: season == 3 ? 6 : 8,
            posterUrl: '/season-$season.jpg',
            posterCachePath: 'cache-season-$season.jpg',
          ),
      ],
    );
    final record = CloudWorkTmdbRecord.matched(
      sourceId: 'quark-a',
      workKey: 'quark-a|work|root-id',
      workRootId: 'root-id',
      workRootPath: '/影视/作品',
      remoteName: '分享目录原名',
      scrapeTitleOverride: '手动刮削名称',
      metadata: metadata,
      posterCachePath: 'cache-poster.jpg',
      checkedAt: DateTime.utc(2026, 7, 20),
    );

    final restored = CloudWorkTmdbRecord.fromJson(record.toJson());

    expect(restored.metadata?.toJson(), metadata.toJson());
    expect(
      restored.metadata?.matchedAt.isAtSameMomentAs(metadata.matchedAt),
      isTrue,
    );
    expect(restored.metadata?.seasons, metadata.seasons);
    expect(restored.checkedAt, record.checkedAt);
    expect(restored.scrapeTitleOverride, record.scrapeTitleOverride);
    expect(restored.posterCachePath, record.posterCachePath);
    expect(restored, record);
    expect(restored.status, CloudWorkTmdbStatus.matched);
    expect(restored.seasons.map((item) => item.seasonNumber), <int>[1, 2, 3]);
    expect(restored.seasons.last.posterUrl, '/season-3.jpg');
    expect(restored.posterCachePath, 'cache-poster.jpg');
    expect(restored.effectiveTitle('规则标题'), 'TMDB 中文标题');
  });

  test('未匹配作品使用刮削名称且冲突记录不伪造元数据', () {
    final unchecked = CloudWorkTmdbRecord.unchecked(
      sourceId: 'openlist-a',
      workKey: 'openlist-a|work|root-id',
      workRootId: 'root-id',
      workRootPath: '/剧集/作品',
      remoteName: '作品原名',
      checkedAt: DateTime.utc(2026, 7, 20),
    ).copyWithScrapeTitle('  修正剧名  ');
    final conflict = CloudWorkTmdbRecord.conflict(
      sourceId: unchecked.sourceId,
      workKey: unchecked.workKey,
      workRootId: unchecked.workRootId,
      workRootPath: unchecked.workRootPath,
      remoteName: unchecked.remoteName,
      checkedAt: DateTime.utc(2026, 7, 21),
      scrapeTitleOverride: unchecked.scrapeTitleOverride,
    );

    expect(unchecked.scrapeTitleOverride, '修正剧名');
    expect(unchecked.effectiveTitle('规则标题'), '修正剧名');
    expect(conflict.status, CloudWorkTmdbStatus.conflict);
    expect(conflict.metadata, isNull);
    expect(CloudWorkTmdbRecord.fromJson(conflict.toJson()), conflict);
  });
}
