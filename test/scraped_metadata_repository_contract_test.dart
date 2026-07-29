import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_series_match_rule.dart';
import 'package:kanyingyin/modules/cloud/cloud_work_tmdb_record.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_series_match_rule_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

void main() {
  test('网盘刮削仓库可全量替换用于提交和回滚', () async {
    final resourceRepository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    final workRepository = CloudWorkTmdbRepository(
      storage: MemoryCloudWorkTmdbStorage(),
    );
    final ruleRepository = CloudSeriesMatchRuleRepository(
      storage: MemoryCloudSeriesMatchRuleStorage(),
    );
    final oldResource = _resource('old-source', 'old-id', '/旧');
    final newResource = _resource('new-source', 'new-id', '/新');
    final oldWork = _work('old-source', 'old-work', '/旧');
    final newWork = _work('new-source', 'new-work', '/新');
    final oldRule = _rule('old-source', '/旧');
    final newRule = _rule('new-source', '/新');

    await resourceRepository.replaceAll(<CloudResourceTmdbRecord>[oldResource]);
    await workRepository.replaceAll(<CloudWorkTmdbRecord>[oldWork]);
    await ruleRepository.replaceAll(<CloudSeriesMatchRule>[oldRule]);
    expect(await resourceRepository.getAll(), <CloudResourceTmdbRecord>[
      oldResource,
    ]);
    expect(await workRepository.getAll(), <CloudWorkTmdbRecord>[oldWork]);
    expect(await ruleRepository.getAll(), <CloudSeriesMatchRule>[oldRule]);

    await resourceRepository.replaceAll(<CloudResourceTmdbRecord>[newResource]);
    await workRepository.replaceAll(<CloudWorkTmdbRecord>[newWork]);
    await ruleRepository.replaceAll(<CloudSeriesMatchRule>[newRule]);
    expect(await resourceRepository.getAll(), <CloudResourceTmdbRecord>[
      newResource,
    ]);
    expect(await workRepository.getAll(), <CloudWorkTmdbRecord>[newWork]);
    expect(await ruleRepository.getAll(), <CloudSeriesMatchRule>[newRule]);
  });

  test('本地索引批量更新只替换命中项目', () async {
    final storage = _MemoryLocalIndexStorage();
    final repository = LocalMediaIndexRepository(storage: storage);
    final first = _local(r'D:\影视\一.mkv', '一');
    final second = _local(r'D:\影视\二.mkv', '二');
    await repository.saveForSource(r'D:\影视', <LocalMediaIndexItem>[
      first,
      second,
    ]);

    final updated = first.copyWith(
      tmdb: _metadata.copyWith(title: '新标题'),
      scrapeStatus: TmdbScrapeStatus.matched,
    );
    await repository.updateItems(<String, LocalMediaIndexItem>{
      first.id: updated,
    });

    expect(repository.getByPath(first.path)?.tmdb?.title, '新标题');
    expect(repository.getByPath(second.path), second);
  });

  test('网盘记录重绑定只改变当前设备身份和图片路径', () {
    final original = _resource('old-source', 'old-id', '/影视/三体');
    final seasons = <TmdbSeasonMetadata>[
      _metadata.seasons.single.copyWith(
        posterCachePath: r'C:\new-cache\season.jpg',
      ),
    ];

    final rebound = original.rebindForTransfer(
      sourceId: 'new-source',
      remoteId: 'new-id',
      remotePath: '/媒体/三体',
      posterCachePath: r'C:\new-cache\poster.jpg',
      seasons: seasons,
    );

    expect(rebound.sourceId, 'new-source');
    expect(rebound.remoteId, 'new-id');
    expect(rebound.remotePath, '/媒体/三体');
    expect(rebound.posterCachePath, r'C:\new-cache\poster.jpg');
    expect(rebound.tmdbId, original.tmdbId);
    expect(rebound.customTitle, original.customTitle);
    expect(rebound.seasons, seasons);
  });

  test('网盘作品和系列规则重绑定后保留刮削资料', () {
    final work = _work('old-source', 'old-work', '/旧');
    final rule = _rule('old-source', '/旧');

    final reboundWork = work.rebindForTransfer(
      sourceId: 'new-source',
      workKey: 'new-work',
      workRootId: 'new-root',
      workRootPath: '/新',
      posterCachePath: 'new-poster.jpg',
      metadata: _metadata,
    );
    final reboundRule = rule.rebindForTransfer(
      sourceId: 'new-source',
      parentPath: '/新',
      posterCachePath: 'new-rule-poster.jpg',
      metadata: _metadata,
    );

    expect(reboundWork.sourceId, 'new-source');
    expect(reboundWork.workKey, 'new-work');
    expect(reboundWork.metadata?.title, work.metadata?.title);
    expect(reboundRule.sourceId, 'new-source');
    expect(reboundRule.normalizedSeriesName, rule.normalizedSeriesName);
    expect(reboundRule.metadata.title, rule.metadata.title);
  });
}

final TmdbMetadata _metadata = TmdbMetadata(
  id: 42,
  mediaType: TmdbMediaType.tv,
  title: '三体',
  language: 'zh-CN',
  matchedAt: DateTime.fromMillisecondsSinceEpoch(1000),
  matchConfidence: 1,
  seasons: <TmdbSeasonMetadata>[
    TmdbSeasonMetadata(
      id: 1,
      seasonNumber: 1,
      name: '第一季',
      episodeCount: 30,
      posterCachePath: 'old-season.jpg',
    ),
  ],
);

CloudResourceTmdbRecord _resource(
  String sourceId,
  String remoteId,
  String remotePath,
) =>
    CloudResourceTmdbRecord.matched(
      sourceId: sourceId,
      remoteId: remoteId,
      remotePath: remotePath,
      displayName: '三体',
      resourceKind: CloudResourceKind.directory,
      metadata: _metadata,
      checkedAt: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
      posterCachePath: 'old-poster.jpg',
      customTitle: '我的三体',
      tmdbMatchOrigin: TmdbMatchOrigin.manual,
      tmdbRuleVersion: 3,
    );

CloudWorkTmdbRecord _work(String sourceId, String workKey, String path) =>
    CloudWorkTmdbRecord.matched(
      sourceId: sourceId,
      workKey: workKey,
      workRootId: '$workKey-root',
      workRootPath: path,
      remoteName: '三体',
      metadata: _metadata,
      checkedAt: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
    );

CloudSeriesMatchRule _rule(String sourceId, String path) =>
    CloudSeriesMatchRule(
      sourceId: sourceId,
      parentPath: path,
      normalizedSeriesName: '三体',
      metadata: _metadata,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
    );

LocalMediaIndexItem _local(String path, String title) => LocalMediaIndexItem(
      path: path,
      name: '$title.mkv',
      parentPath: r'D:\影视',
      sourcePath: r'D:\影视',
      size: 1024,
      modified: DateTime.fromMillisecondsSinceEpoch(1000),
      seriesName: title,
      indexedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

final class _MemoryLocalIndexStorage implements LocalMediaIndexStorage {
  final Map<String, Object?> values = <String, Object?>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Object? read(String key, {Object? defaultValue}) =>
      values[key] ?? defaultValue;

  @override
  Future<void> write(String key, Object? value) async => values[key] = value;
}
