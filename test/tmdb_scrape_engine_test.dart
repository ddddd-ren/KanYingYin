import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_engine.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

void main() {
  test('首个标题只有低分结果时继续使用后续标题自动匹配', () async {
    final client = _RecordingClient(<String, List<TmdbMetadata>>{
      '错误标题|tv': <TmdbMetadata>[
        _metadata(id: 1, title: '无关作品', type: TmdbMediaType.tv),
      ],
      '三体|tv': <TmdbMetadata>[
        _metadata(id: 42, title: '三体', type: TmdbMediaType.tv),
      ],
    });
    final engine = TmdbScrapeEngine(client: client);
    const subject = TmdbScrapeSubject(
      stableKey: 'work',
      titleCandidates: <String>['错误标题', '三体'],
      mediaEvidence: TmdbMediaEvidence.tv,
    );

    final outcome = await engine.search(
      subject,
      const TmdbScrapeOptions.defaults(),
    );

    expect(outcome.queryTitle, '三体');
    expect(outcome.ranked.shouldAutoMatch, isTrue);
    expect(outcome.ranked.best?.metadata.id, 42);
    expect(client.calls, <String>['错误标题|tv', '三体|tv']);
  });

  test('电影和电视剧相同数字ID分别保留且同类型重复候选去重', () async {
    final movie = _metadata(id: 7, title: '同名作品');
    final tv = _metadata(
      id: 7,
      title: '同名作品',
      type: TmdbMediaType.tv,
    );
    final client = _RecordingClient(<String, List<TmdbMetadata>>{
      '同名作品|movie': <TmdbMetadata>[movie, movie],
      '同名作品|tv': <TmdbMetadata>[tv, tv],
    });
    final engine = TmdbScrapeEngine(client: client);
    const subject = TmdbScrapeSubject(
      stableKey: 'unknown',
      titleCandidates: <String>['同名作品'],
    );

    final outcome = await engine.search(
      subject,
      const TmdbScrapeOptions.defaults(),
    );

    expect(outcome.ranked.candidates, hasLength(2));
    expect(
      outcome.ranked.candidates
          .map((candidate) => candidate.metadata.mediaType),
      <TmdbMediaType>[TmdbMediaType.movie, TmdbMediaType.tv],
    );
    expect(outcome.ranked.shouldAutoMatch, isFalse);
  });

  test('所有请求成功但没有候选时返回空结果', () async {
    final engine = TmdbScrapeEngine(
      client: _RecordingClient(const <String, List<TmdbMetadata>>{}),
    );
    const subject = TmdbScrapeSubject(
      stableKey: 'empty',
      titleCandidates: <String>['没有结果'],
      mediaEvidence: TmdbMediaEvidence.movie,
    );

    final outcome = await engine.search(
      subject,
      const TmdbScrapeOptions.defaults(),
    );

    expect(outcome.queryTitle, isNull);
    expect(outcome.ranked.candidates, isEmpty);
    expect(outcome.ranked.shouldAutoMatch, isFalse);
  });

  test('TMDB 请求异常向调用方抛出而不伪装成未匹配', () async {
    final engine = TmdbScrapeEngine(client: _ThrowingClient());
    const subject = TmdbScrapeSubject(
      stableKey: 'failed',
      titleCandidates: <String>['三体'],
      mediaEvidence: TmdbMediaEvidence.tv,
    );

    await expectLater(
      engine.search(subject, const TmdbScrapeOptions.defaults()),
      throwsA(isA<StateError>()),
    );
  });
}

class _RecordingClient implements ITmdbClient {
  _RecordingClient(this.responses);

  final Map<String, List<TmdbMetadata>> responses;
  final List<String> calls = <String>[];

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    final key = '$query|${mediaType.name}';
    calls.add(key);
    return responses[key] ?? const <TmdbMetadata>[];
  }

  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) {
    throw UnimplementedError();
  }
}

class _ThrowingClient implements ITmdbClient {
  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) {
    throw StateError('模拟网络失败');
  }

  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) {
    throw UnimplementedError();
  }
}

TmdbMetadata _metadata({
  required int id,
  required String title,
  TmdbMediaType type = TmdbMediaType.movie,
}) {
  return TmdbMetadata(
    id: id,
    mediaType: type,
    title: title,
    language: 'zh-CN',
    matchedAt: DateTime(2026),
    matchConfidence: 0,
  );
}
