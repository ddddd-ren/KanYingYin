import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/local/library_sheet.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';

void main() {
  test('云系列有缓存海报时优先选择 FileImage 且不请求网络', () {
    final episode = MediaLibraryEpisode.cloud(
      stableId: 'episode-1',
      name: 'E01',
      sourceId: 'openlist',
      sourceName: '家庭网盘',
      isAvailable: true,
      remotePath: '/Show/E01.mkv',
    );
    final series = MediaLibrarySeries(
      key: 'openlist|show',
      seriesKey: 'Show',
      title: '中文片名 S01',
      sourceKind: MediaSourceKind.cloud,
      sourceId: 'openlist',
      sourceName: '家庭网盘',
      isAvailable: true,
      episodes: [episode],
      tmdbPosterUrl: 'https://image.example.com/poster.jpg',
      posterCachePath: r'C:\cache\poster.jpg',
    );

    final provider = cloudSeriesCoverProvider(series);

    expect(provider, isA<FileImage>());
    expect((provider as FileImage).file.path, r'C:\cache\poster.jpg');
  });
}
