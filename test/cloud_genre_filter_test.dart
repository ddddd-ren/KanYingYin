import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/cloud/application/cloud_genre_filter.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';

void main() {
  test('标签去重排序且多选按任一匹配', () {
    const filter = CloudGenreFilter();
    final items = <CloudMediaIndexItem>[
      _item('a', const <String>['科幻', '动作', '科幻']),
      _item('b', const <String>['纪录片']),
      _item('c', const <String>[]),
    ];

    expect(filter.availableGenres(items), <String>['动作', '科幻', '纪录片']);
    expect(
      filter.apply(
          items, const <String>{'科幻', '纪录片'}).map((item) => item.remoteId),
      <String>['a', 'b'],
    );
  });

  test('空选择保留全部项目且类型名称会清理空白', () {
    const filter = CloudGenreFilter();
    final items = <CloudMediaIndexItem>[
      _item('a', const <String>[' 科幻 ', '', '科幻']),
      _item('b', const <String>[]),
    ];

    expect(filter.availableGenres(items), <String>['科幻']);
    expect(filter.apply(items, const <String>{}), items);
  });

  test('索引变化后移除已经不存在的选择', () {
    const filter = CloudGenreFilter();

    expect(
      filter.retainAvailable(
        const <String>{'科幻', '动画'},
        const <String>['科幻', '剧情'],
      ),
      const <String>{'科幻'},
    );
  });
}

CloudMediaIndexItem _item(String id, List<String> genres) {
  return CloudMediaIndexItem(
    sourceId: 'source-a',
    remoteId: id,
    remotePath: '/$id.mkv',
    name: '$id.mkv',
    size: 1024,
    modifiedAt: DateTime.utc(2026, 8, 4),
    seriesName: id,
    mediaType: CloudMediaType.movie,
    tmdbGenres: genres,
  );
}
