import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

void main() {
  test('TMDB 详情解析演员、导演和相似作品', () {
    final metadata = TmdbMetadata.fromJson(<String, dynamic>{
      'id': 42,
      'mediaType': 'movie',
      'title': '示例电影',
      'language': 'zh-CN',
      'matchedAtMillis': 1,
      'cast': <Object?>[
        <String, dynamic>{'id': 1, 'name': '演员甲', 'character': '角色甲'},
      ],
      'directors': <Object?>[
        <String, dynamic>{'id': 2, 'name': '导演乙', 'job': 'Director'},
      ],
      'similar': <Object?>[
        <String, dynamic>{
          'id': 3,
          'title': '相似电影',
          'mediaType': 'movie',
          'rating': 8.1,
        },
      ],
    });

    expect(metadata.cast.single.name, '演员甲');
    expect(metadata.cast.single.character, '角色甲');
    expect(metadata.directors.single.name, '导演乙');
    expect(metadata.similar.single.title, '相似电影');
    expect(metadata.similar.single.rating, 8.1);
    expect(TmdbMetadata.fromJson(metadata.toJson()), metadata);
  });
}
