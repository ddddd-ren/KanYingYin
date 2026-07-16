import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_matcher.dart';

void main() {
  final matcher = TmdbMatcher();

  test('同名同年份候选可以自动匹配', () {
    final result = matcher.choose(
      queryTitle: '流浪地球',
      queryYear: 2019,
      expectedType: TmdbMediaType.movie,
      candidates: [
        _metadata(id: 1, title: '流浪地球', date: '2019-02-05'),
        _metadata(id: 2, title: '流浪地球2', date: '2023-01-22'),
      ],
    );

    expect(result.best?.id, 1);
    expect(result.shouldAutoMatch, isTrue);
  });

  test('类型冲突不得自动匹配', () {
    final result = matcher.choose(
      queryTitle: '三体',
      queryYear: 2023,
      expectedType: TmdbMediaType.movie,
      candidates: [
        _metadata(
          id: 3,
          title: '三体',
          date: '2023-01-15',
          type: TmdbMediaType.tv,
        ),
      ],
    );

    expect(result.shouldAutoMatch, isFalse);
  });
}

TmdbMetadata _metadata({
  required int id,
  required String title,
  required String date,
  TmdbMediaType type = TmdbMediaType.movie,
}) {
  return TmdbMetadata(
    id: id,
    mediaType: type,
    title: title,
    releaseDate: date,
    language: 'zh-CN',
    matchedAt: DateTime(2026),
    matchConfidence: 0,
  );
}
