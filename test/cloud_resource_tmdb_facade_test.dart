import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/cloud/application/cloud_resource_tmdb_facade.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

void main() {
  test('条目目标保留来源和真实远程引用', () {
    const facade = CloudResourceTmdbFacade();
    const source = CloudSource(
      id: 'source-a',
      type: CloudSourceType.quark,
      name: '夸克',
      baseUrl: '',
      rootPaths: ['/媒体'],
    );
    const entry = CloudFileEntry(
      id: 'file-1',
      remotePath: '/媒体/测试剧/S01E01.mp4',
      name: 'S01E01.mp4',
      size: 1024,
      modifiedAt: null,
      isDirectory: false,
    );

    final target = facade.targetFor(source: source, entry: entry);

    expect(target.sourceId, 'source-a');
    expect(target.remote.id, 'file-1');
    expect(target.remote.path, '/媒体/测试剧/S01E01.mp4');
  });

  test('已识别剧集使用系列名和季集生成电视剧草稿', () {
    const facade = CloudResourceTmdbFacade();
    const entry = CloudFileEntry(
      id: 'file-1',
      remotePath: '/媒体/测试剧/S01E02.mp4',
      name: 'S01E02.mp4',
      size: 1024,
      modifiedAt: null,
      isDirectory: false,
    );
    final indexed = CloudMediaIndexItem(
      sourceId: 'source-a',
      remoteId: 'file-1',
      remotePath: entry.remotePath,
      name: entry.name,
      remoteName: entry.name,
      displayName: entry.name,
      size: entry.size,
      modifiedAt: null,
      seriesName: '测试剧',
      seasonNumber: 1,
      episodeNumber: 2,
      mediaType: CloudMediaType.episode,
      recognitionVersion: 1,
    );

    final draft = facade.draftFor(entry: entry, indexed: indexed);

    expect(draft.searchTitle, '测试剧');
    expect(draft.mediaTypeMode, TmdbMediaTypeMode.tv);
    expect(draft.seasonNumber, 1);
    expect(draft.episodeNumber, 2);
  });
}
