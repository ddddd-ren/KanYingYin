import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/bangumi/bangumi_item.dart';

void main() {
  test('兼容 api.bgm.tv 的评分计数 Map 格式', () {
    final item = BangumiItem.fromJson(
      _validJson(
        count: <String, int>{
          for (var index = 1; index <= 10; index++) '$index': index,
        },
      ),
    );

    expect(item.id, 42);
    expect(item.votesCount, <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(item.tags.single.name, '科幻');
  });

  test('兼容 next.bgm.tv 的评分计数 List 格式', () {
    final item = BangumiItem.fromJson(
      _validJson(count: <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
    );

    expect(item.votesCount, <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  });

  test('缺少必需 id 时拒绝构造条目', () {
    final json = _validJson()..remove('id');

    expect(() => BangumiItem.fromJson(json), throwsFormatException);
  });

  test('id 为字符串时拒绝构造条目', () {
    final json = _validJson()..['id'] = '42';

    expect(() => BangumiItem.fromJson(json), throwsFormatException);
  });

  test('tags 混入非 Map 元素时整体失败', () {
    final json = _validJson()
      ..['tags'] = <Object?>[
        <String, Object?>{'name': '科幻', 'count': 1, 'total_cont': 2},
        '错误条目',
      ];

    expect(() => BangumiItem.fromJson(json), throwsFormatException);
  });

  test('评分计数 List 混入非 int 元素时整体失败', () {
    final json = _validJson(count: <Object?>[1, 2, '3']);

    expect(() => BangumiItem.fromJson(json), throwsFormatException);
  });

  test('评分计数 Map 混入非 int 元素时整体失败', () {
    final count = <String, Object?>{
      for (var index = 1; index <= 10; index++) '$index': index,
    }..['5'] = '5';
    final json = _validJson(count: count);

    expect(() => BangumiItem.fromJson(json), throwsFormatException);
  });

  test('已有强类型字段收到错误类型时明确失败', () {
    for (final entry in <MapEntry<String, Object?>>[
      const MapEntry('type', '2'),
      const MapEntry('name', 42),
      const MapEntry('summary', false),
    ]) {
      final json = _validJson()..[entry.key] = entry.value;
      expect(
        () => BangumiItem.fromJson(json),
        throwsFormatException,
        reason: entry.key,
      );
    }

    for (final entry in <MapEntry<String, Object?>>[
      const MapEntry('rank', '1'),
      const MapEntry('total', '10'),
    ]) {
      final json = _validJson();
      (json['rating'] as Map<String, Object?>)[entry.key] = entry.value;
      expect(
        () => BangumiItem.fromJson(json),
        throwsFormatException,
        reason: 'rating.${entry.key}',
      );
    }
  });
}

Map<String, dynamic> _validJson({Object? count}) {
  return <String, dynamic>{
    'id': 42,
    'type': 2,
    'name': '测试条目',
    'name_cn': '测试条目',
    'summary': '简介',
    'date': '2026-07-19',
    'tags': <Map<String, Object?>>[
      <String, Object?>{'name': '科幻', 'count': 1, 'total_cont': 2},
    ],
    'rating': <String, Object?>{
      'rank': 1,
      'score': 8.5,
      'total': 10,
      if (count != null) 'count': count,
    },
    'images': <String, Object?>{'large': 'poster.jpg'},
    'info': '信息',
  };
}
