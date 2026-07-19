import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resource_card_view_data.dart';

void main() {
  const directory = CloudFileEntry(
    id: 'folder',
    remotePath: '/影视/目录原名',
    name: '目录原名',
    size: 0,
    modifiedAt: null,
    isDirectory: true,
  );
  const video = CloudFileEntry(
    id: 'video',
    remotePath: '/影视/电影.mkv',
    name: '电影.mkv',
    size: 2 * 1024 * 1024 * 1024,
    modifiedAt: null,
    isDirectory: false,
  );

  test('已匹配目录使用媒体卡并按优先级组合完整信息', () {
    final data = CloudResourceCardViewData.fromEntry(
      entry: directory,
      record: _matchedRecord().withCustomTitle('自定义片名'),
      scraping: false,
      hasSubtitle: false,
    );

    expect(data.kind, CloudResourceCardKind.media);
    expect(data.title, '自定义片名');
    expect(data.subtitle, '目录原名');
    expect(data.details, '8.7 ★  ·  电视剧  ·  2025');
    expect(data.posterCachePath, r'C:\cache\poster.jpg');
    expect(data.posterUrl, '/poster.jpg');
    expect(data.badges.map((badge) => badge.label), <String>['已刮削']);
  });

  test('未匹配、失败和未检查目录保持普通目录卡', () {
    final records = <CloudResourceTmdbRecord>[
      CloudResourceTmdbRecord.unmatched(
        sourceId: 'source',
        remoteId: directory.id,
        remotePath: directory.remotePath,
        displayName: directory.name,
        resourceKind: CloudResourceKind.directory,
        checkedAt: DateTime.utc(2026, 7, 19),
      ),
      CloudResourceTmdbRecord.failed(
        sourceId: 'source',
        remoteId: directory.id,
        remotePath: directory.remotePath,
        displayName: directory.name,
        resourceKind: CloudResourceKind.directory,
        checkedAt: DateTime.utc(2026, 7, 19),
      ),
      CloudResourceTmdbRecord.unchecked(
        sourceId: 'source',
        remoteId: directory.id,
        remotePath: directory.remotePath,
        displayName: directory.name,
        resourceKind: CloudResourceKind.directory,
        checkedAt: DateTime.utc(2026, 7, 19),
      ),
    ];

    for (final record in records) {
      final data = CloudResourceCardViewData.fromEntry(
        entry: directory,
        record: record,
        scraping: false,
        hasSubtitle: false,
      );
      expect(data.kind, CloudResourceCardKind.directory);
      expect(data.badges, isEmpty);
    }
  });

  test('独立视频始终使用媒体卡并显示大小和已确认字幕', () {
    final data = CloudResourceCardViewData.fromEntry(
      entry: video,
      record: null,
      scraping: false,
      hasSubtitle: true,
    );

    expect(data.kind, CloudResourceCardKind.media);
    expect(data.title, '电影.mkv');
    expect(data.subtitle, isEmpty);
    expect(data.details, '2.0 GB');
    expect(
      data.badges.map((badge) => badge.label),
      <String>['有字幕', '未刮削'],
    );
    expect(data.badges.map((badge) => badge.label), isNot(contains('无字幕')));
  });

  test('独立视频显示未匹配、失败、未检查和刮削中状态', () {
    CloudResourceCardViewData build(
      CloudResourceTmdbRecord? record, {
      bool scraping = false,
    }) {
      return CloudResourceCardViewData.fromEntry(
        entry: video,
        record: record,
        scraping: scraping,
        hasSubtitle: false,
      );
    }

    final unmatched = CloudResourceTmdbRecord.unmatched(
      sourceId: 'source',
      remoteId: video.id,
      remotePath: video.remotePath,
      displayName: video.name,
      resourceKind: CloudResourceKind.standaloneVideo,
      checkedAt: DateTime.utc(2026, 7, 19),
    );
    final failed = CloudResourceTmdbRecord.failed(
      sourceId: 'source',
      remoteId: video.id,
      remotePath: video.remotePath,
      displayName: video.name,
      resourceKind: CloudResourceKind.standaloneVideo,
      checkedAt: DateTime.utc(2026, 7, 19),
    );
    final unchecked = CloudResourceTmdbRecord.unchecked(
      sourceId: 'source',
      remoteId: video.id,
      remotePath: video.remotePath,
      displayName: video.name,
      resourceKind: CloudResourceKind.standaloneVideo,
      checkedAt: DateTime.utc(2026, 7, 19),
    );

    expect(build(unmatched).badges.single.label, '未匹配');
    expect(build(failed).badges.single.label, '刮削失败');
    expect(build(unchecked).badges.single.label, '未刮削');
    expect(build(null).badges.single.label, '未刮削');
    final scraping = build(failed, scraping: true);
    expect(scraping.badges.single.label, '刮削中');
    expect(scraping.badges.single.loading, isTrue);
  });

  test('缺失或非法元数据会被省略且不产生多余分隔符', () {
    final record = CloudResourceTmdbRecord.matched(
      sourceId: 'source',
      remoteId: directory.id,
      remotePath: directory.remotePath,
      displayName: directory.name,
      resourceKind: CloudResourceKind.directory,
      metadata: TmdbMetadata(
        id: 42,
        mediaType: TmdbMediaType.movie,
        title: '目录原名',
        releaseDate: '日期未知',
        language: 'zh-CN',
        matchedAt: DateTime.utc(2026, 7, 19),
        matchConfidence: 1,
      ),
      checkedAt: DateTime.utc(2026, 7, 19),
    );

    final data = CloudResourceCardViewData.fromEntry(
      entry: directory,
      record: record,
      scraping: false,
      hasSubtitle: false,
    );

    expect(data.title, '目录原名');
    expect(data.subtitle, isEmpty);
    expect(data.details, '电影');
    expect(data.details, isNot(contains('··')));
  });
}

CloudResourceTmdbRecord _matchedRecord() {
  return CloudResourceTmdbRecord.matched(
    sourceId: 'source',
    remoteId: 'folder',
    remotePath: '/影视/目录原名',
    displayName: '目录原名',
    resourceKind: CloudResourceKind.directory,
    metadata: TmdbMetadata(
      id: 42,
      mediaType: TmdbMediaType.tv,
      title: 'TMDB 中文片名',
      rating: 8.7,
      releaseDate: '2025-01-01',
      posterUrl: '/poster.jpg',
      language: 'zh-CN',
      matchedAt: DateTime.utc(2026, 7, 19),
      matchConfidence: 1,
    ),
    posterCachePath: r'C:\cache\poster.jpg',
    checkedAt: DateTime.utc(2026, 7, 19),
  );
}
