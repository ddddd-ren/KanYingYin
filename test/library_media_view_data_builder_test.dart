import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/library_media_view_data_builder.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/services/local_series_grouper.dart';

void main() {
  const builder = LibraryMediaViewDataBuilder();

  test('单集卡片组合文件、媒体信息和刮削状态', () {
    final item = _item(
      path: r'D:\Videos\电影.mkv',
      name: '电影.mkv',
      size: 2 * 1024 * 1024 * 1024,
      modified: DateTime(2026, 7, 24),
      duration: const Duration(hours: 1, minutes: 30),
      resolution: '4K',
      subtitlePath: r'D:\Videos\电影.srt',
    );
    final group = LocalVideoGroup(episodes: [item], titleOverride: '电影');

    final data = builder.build(
      group,
      isScraping: true,
      networkCoverUrl: 'https://image.example/poster.jpg',
    );

    expect(data.id, item.path);
    expect(data.title, '电影');
    expect(data.infoText, 'MKV  2.0 GB');
    expect(data.mediaInfoText, '1:30:00  4K');
    expect(data.modifiedText, '2026-07-24');
    expect(data.hasSubtitle, isTrue);
    expect(data.scrapeLabel, '正在刮削');
    expect(data.networkCoverUrl, 'https://image.example/poster.jpg');
  });

  test('多集卡片汇总格式、总大小和最近修改日期', () {
    final group = LocalVideoGroup(
      episodes: [
        _item(
          path: r'D:\Series\S01E01.mkv',
          name: 'S01E01.mkv',
          size: 1024 * 1024 * 1024,
          modified: DateTime(2026, 7, 20),
        ),
        _item(
          path: r'D:\Series\S01E02.mp4',
          name: 'S01E02.mp4',
          size: 512 * 1024 * 1024,
          modified: DateTime(2026, 7, 23),
        ),
      ],
      titleOverride: '剧集',
    );

    final data = builder.build(group, isScraping: false);

    expect(data.infoText, 'MKV/MP4  1.5 GB');
    expect(data.mediaInfoText, isEmpty);
    expect(data.modifiedText, '2026-07-23');
    expect(data.hasMultipleEpisodes, isTrue);
    expect(data.scrapeLabel, '未刮削');
  });
}

LocalFileItem _item({
  required String path,
  required String name,
  required int size,
  required DateTime modified,
  Duration? duration,
  String? resolution,
  String? subtitlePath,
}) {
  return LocalFileItem(
    path: path,
    name: name,
    size: size,
    modified: modified,
    isDirectory: false,
    isVideo: true,
    duration: duration,
    resolution: resolution,
    subtitlePath: subtitlePath,
  );
}
