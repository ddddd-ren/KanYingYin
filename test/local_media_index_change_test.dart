import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/services/local_media_indexer.dart';

void main() {
  test('扫描变更按新增、更新、删除和失败分类', () {
    final previous = <LocalMediaIndexItem>[
      _item('old.mkv', size: 1),
      _item('changed.mkv', size: 1),
      _item('same.mkv', size: 1),
    ];
    final current = <LocalMediaIndexItem>[
      _item('changed.mkv', size: 2),
      _item('same.mkv', size: 1),
      _item('new.mkv', size: 1),
    ];

    final changes = buildLocalMediaIndexChanges(
      previous: previous,
      current: current,
      failures: const <LocalMediaIndexFailure>[
        LocalMediaIndexFailure(path: 'broken.mkv', message: '读取失败'),
      ],
    );

    expect(
      changes.map((change) => '${change.kind.name}:${change.path}'),
      containsAll(<String>[
        'removed:old.mkv',
        'updated:changed.mkv',
        'added:new.mkv',
        'failed:broken.mkv',
      ]),
    );
    expect(changes, hasLength(4));
  });
}

LocalMediaIndexItem _item(String name, {required int size}) {
  return LocalMediaIndexItem(
    path: name,
    name: name,
    parentPath: '.',
    sourcePath: '.',
    size: size,
    modified: DateTime(2026),
    seriesName: name,
    indexedAt: DateTime(2026),
  );
}
