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

  test('候选按严格分数排序并暴露匹配信号', () {
    final result = matcher.rank(
      queryTitle: 'Alice in Borderland',
      queryYear: 2020,
      expectedTypes: const <TmdbMediaType>{TmdbMediaType.tv},
      candidates: [
        _metadata(
          id: 2,
          title: 'Alice',
          date: '2020-01-01',
          type: TmdbMediaType.tv,
        ),
        _metadata(
          id: 1,
          title: 'Alice in Borderland',
          date: '2020-12-10',
          type: TmdbMediaType.tv,
        ),
      ],
    );

    expect(result.candidates.first.metadata.id, 1);
    expect(result.candidates.first.titleMatched, isTrue);
    expect(result.candidates.first.yearMatched, isTrue);
    expect(result.candidates.first.typeMatched, isTrue);
    expect(result.shouldAutoMatch, isTrue);
  });

  test('自动类型统一评分且同分保持 TMDB 原始顺序', () {
    final result = matcher.rank(
      queryTitle: '同名作品',
      queryYear: 2020,
      expectedTypes: const <TmdbMediaType>{
        TmdbMediaType.movie,
        TmdbMediaType.tv,
      },
      candidates: [
        _metadata(id: 1, title: '同名作品', date: '2020-01-01'),
        _metadata(
          id: 2,
          title: '同名作品',
          date: '2020-01-01',
          type: TmdbMediaType.tv,
        ),
      ],
    );

    expect(
      result.candidates.map((candidate) => candidate.metadata.id),
      <int>[1, 2],
    );
    expect(result.shouldAutoMatch, isFalse);
  });

  test('英文别名命中优先于年份错误的同名候选', () {
    final result = matcher.rank(
      queryTitle: 'The Three Body Problem',
      queryYear: 2023,
      expectedTypes: const <TmdbMediaType>{TmdbMediaType.tv},
      candidates: <TmdbMetadata>[
        _metadata(
          id: 10,
          title: '三体',
          date: '2023-01-01',
          type: TmdbMediaType.tv,
          aliases: const <String>['The Three-Body Problem'],
        ),
        _metadata(
          id: 11,
          title: 'The Three Body Problem',
          date: '2019-01-01',
          type: TmdbMediaType.tv,
        ),
      ],
    );

    expect(result.best?.metadata.id, 10);
    expect(result.best?.aliasMatched, isTrue);
    expect(result.best?.titleSimilarity, greaterThanOrEqualTo(0.78));
    expect(result.best?.matchReason, contains('别名匹配'));
    expect(result.shouldAutoMatch, isTrue);
  });

  test('混合媒体类型没有季集证据时同名同年不得自动确认', () {
    final result = matcher.rank(
      queryTitle: '同名作品',
      queryYear: 2020,
      expectedTypes: const <TmdbMediaType>{
        TmdbMediaType.movie,
        TmdbMediaType.tv,
      },
      candidates: <TmdbMetadata>[
        _metadata(id: 20, title: '同名作品', date: '2020-01-01'),
        _metadata(
          id: 21,
          title: '同名作品',
          date: '2020-01-01',
          type: TmdbMediaType.tv,
        ),
      ],
    );

    expect(result.shouldAutoMatch, isFalse);
  });

  test('电视剧季集证据会标记候选理由并提高确认资格', () {
    final result = matcher.rank(
      queryTitle: '三体',
      queryYear: 2023,
      expectedTypes: const <TmdbMediaType>{TmdbMediaType.tv},
      seasonEvidence: true,
      candidates: <TmdbMetadata>[
        _metadata(
          id: 30,
          title: '三体',
          date: '2023-01-01',
          type: TmdbMediaType.tv,
        ),
      ],
    );

    expect(result.best?.seasonEvidenceMatched, isTrue);
    expect(result.best?.matchReason, contains('季集证据匹配'));
    expect(result.shouldAutoMatch, isTrue);
  });

  test('剧场版资源序号不同但中文主体一致时可以自动匹配', () {
    final result = matcher.choose(
      queryTitle: '火影忍者剧场版03 大兴奋 三日月岛的动物骚动',
      expectedType: TmdbMediaType.movie,
      candidates: [
        _metadata(
          id: 18861,
          title: '火影忍者剧场版：大兴奋！三日月岛的动物骚动',
          date: '2006-08-05',
        ),
      ],
    );

    expect(result.best?.id, 18861);
    expect(result.confidence, greaterThanOrEqualTo(0.8));
    expect(result.shouldAutoMatch, isTrue);
  });
}

TmdbMetadata _metadata({
  required int id,
  required String title,
  required String date,
  TmdbMediaType type = TmdbMediaType.movie,
  List<String> aliases = const <String>[],
}) {
  return TmdbMetadata(
    id: id,
    mediaType: type,
    title: title,
    aliases: aliases,
    releaseDate: date,
    language: 'zh-CN',
    matchedAt: DateTime(2026),
    matchConfidence: 0,
  );
}
