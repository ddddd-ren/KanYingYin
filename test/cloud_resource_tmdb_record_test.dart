import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

void main() {
  test('资源 TMDB 记录稳定键和 JSON 往返保留公开元数据', () {
    final record = CloudResourceTmdbRecord.matched(
      sourceId: 'quark-source',
      remoteId: 'folder-fid',
      remotePath: r'\影视\\流浪地球',
      displayName: '流浪地球',
      resourceKind: CloudResourceKind.directory,
      metadata: TmdbMetadata(
        id: 42,
        mediaType: TmdbMediaType.movie,
        title: '流浪地球',
        originalTitle: 'The Wandering Earth',
        overview: '公开简介',
        rating: 8.1,
        posterUrl: '/poster.jpg',
        backdropUrl: '/backdrop.jpg',
        language: 'zh-CN',
        matchedAt: DateTime.utc(2026, 7, 19),
        matchConfidence: 1,
      ),
      posterCachePath: r'C:\cache\poster.jpg',
      checkedAt: DateTime.utc(2026, 7, 19),
    );

    expect(
      record.stableKey,
      'quark-source|folder-fid|/影视/流浪地球',
    );
    expect(CloudResourceTmdbRecord.fromJson(record.toJson()), record);
    final serialized = record.toJson().toString().toLowerCase();
    for (final secret in <String>[
      'cookie',
      'authorization',
      'playback',
      'stoken',
    ]) {
      expect(serialized, isNot(contains(secret)));
    }
  });

  test('未匹配和失败记录不伪造 TMDB 字段', () {
    final unmatched = CloudResourceTmdbRecord.unmatched(
      sourceId: 'openlist-source',
      remoteId: '/影视/未知',
      remotePath: '/影视/未知',
      displayName: '未知',
      resourceKind: CloudResourceKind.directory,
      checkedAt: DateTime.utc(2026, 7, 19),
    );
    final failed = unmatched.asFailed(DateTime.utc(2026, 7, 20));

    expect(unmatched.status, CloudResourceTmdbStatus.unmatched);
    expect(unmatched.tmdbId, isNull);
    expect(failed.status, CloudResourceTmdbStatus.failed);
    expect(failed.checkedAt, DateTime.utc(2026, 7, 20));
  });

  test('自定义剧名优先显示且清除后恢复 TMDB 标题', () {
    final matched = CloudResourceTmdbRecord.matched(
      sourceId: 'source-a',
      remoteId: 'folder-a',
      remotePath: '/影视/A',
      displayName: '原文件夹',
      resourceKind: CloudResourceKind.directory,
      metadata: TmdbMetadata(
        id: 42,
        mediaType: TmdbMediaType.tv,
        title: 'TMDB 标题',
        language: 'zh-CN',
        matchedAt: DateTime.utc(2026, 7, 19),
        matchConfidence: 1,
      ),
      checkedAt: DateTime.utc(2026, 7, 19),
    );

    final customized = matched.withCustomTitle('  我的剧名  ');
    expect(customized.customTitle, '我的剧名');
    expect(customized.effectiveTitle, '我的剧名');
    expect(CloudResourceTmdbRecord.fromJson(customized.toJson()), customized);

    final restored = customized.clearCustomTitle();
    expect(restored.customTitle, isNull);
    expect(restored.effectiveTitle, matched.title);
  });

  test('未检查资源也能保存自定义剧名', () {
    final record = CloudResourceTmdbRecord.unchecked(
      sourceId: 'source-a',
      remoteId: 'folder-a',
      remotePath: '/影视/A',
      displayName: 'A',
      resourceKind: CloudResourceKind.directory,
      checkedAt: DateTime.utc(2026, 7, 19),
    ).withCustomTitle('自定义 A');

    expect(record.status, CloudResourceTmdbStatus.unchecked);
    expect(record.effectiveTitle, '自定义 A');
  });
}
