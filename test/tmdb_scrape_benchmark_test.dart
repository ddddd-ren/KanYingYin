import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_engine.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_cache.dart';

import 'fixtures/tmdb_scrape_corpus.dart';

void main() {
  test('对标样本输出可重复的召回和自动匹配基线', () async {
    expect(tmdbScrapeCorpus.length, greaterThanOrEqualTo(30));

    var topOneCorrect = 0;
    var topThreeCorrect = 0;
    var automaticCount = 0;
    var automaticCorrect = 0;
    var unexpectedAutomaticCount = 0;
    var coldRequestCount = 0;

    for (final sample in tmdbScrapeCorpus) {
      final client = _CorpusClient(sample);
      final outcome = await TmdbScrapeEngine(client: client).search(
        TmdbScrapeSubject(
          stableKey: sample.name,
          titleCandidates: sample.titleCandidates,
          year: sample.year,
          seasonNumbers: sample.seasonNumbers,
          episodeNumbers: sample.episodeNumbers,
          mediaEvidence: sample.expectedAutoMatch
              ? sample.expectedType == TmdbMediaType.movie
                  ? TmdbMediaEvidence.movie
                  : TmdbMediaEvidence.tv
              : TmdbMediaEvidence.unknown,
        ),
        const TmdbScrapeOptions.defaults(),
      );

      final ranked = outcome.ranked.candidates;
      final identities = ranked
          .take(3)
          .map((candidate) => _identity(candidate.metadata))
          .toList(growable: false);
      final bestIdentity = identities.firstOrNull;
      _expectSafeMatch(sample, bestIdentity, outcome.ranked.shouldAutoMatch);
      if (!sample.expectedAutoMatch) {
        expect(identities, contains(sample.expectedIdentity),
            reason: '${sample.name}：待确认候选必须保留正确答案');
      }
      final topOne = bestIdentity == sample.expectedIdentity;
      final topThree = identities.contains(sample.expectedIdentity);
      if (topOne) topOneCorrect++;
      if (topThree) topThreeCorrect++;
      if (outcome.ranked.shouldAutoMatch) {
        automaticCount++;
        if (topOne) automaticCorrect++;
        if (!sample.expectedAutoMatch) unexpectedAutomaticCount++;
      }
      coldRequestCount += client.queries.length;
      stdout.writeln(
        '${sample.name}\t${sample.expectedIdentity}\t'
        '${bestIdentity ?? '-'}\t${outcome.ranked.shouldAutoMatch}\t'
        '${ranked.length}\t${client.queries.length}',
      );
    }

    final total = tmdbScrapeCorpus.length;
    expect(unexpectedAutomaticCount, 0);
    expect(topOneCorrect / total, greaterThanOrEqualTo(0.95),
        reason: 'Top-1 正确率不得低于 95%');
    expect(topThreeCorrect / total, greaterThanOrEqualTo(0.95),
        reason: 'Top-3 召回率不得低于 95%');
    expect(automaticCount / total, greaterThanOrEqualTo(0.65),
        reason: '自动确认覆盖率须较历史 50% 基线提升至少 15 个百分点');
    expect(automaticCorrect, automaticCount, reason: '固定样本不允许自动误匹配');
    expect(automaticCorrect / automaticCount, greaterThanOrEqualTo(0.98));
    final cacheHitP95Milliseconds = await _cacheHitP95Milliseconds();
    final averageColdRequests = coldRequestCount / total;
    stdout.writeln(
      'TMDB benchmark: total=$total, top1=$topOneCorrect/$total, '
      'top3=$topThreeCorrect/$total, auto=$automaticCount, '
      'autoCorrect=$automaticCorrect/$automaticCount, '
      'avgColdRequests=${averageColdRequests.toStringAsFixed(2)}, '
      'cacheHitP95Ms=${cacheHitP95Milliseconds.toStringAsFixed(3)}',
    );
  });

  test('基准门禁能发现故意注入的自动错误身份', () async {
    final sample = tmdbScrapeCorpus.first;
    final outcome = await TmdbScrapeEngine(
      client: _CorpusClient(sample, injectWrongIdentity: true),
    ).search(
      TmdbScrapeSubject(
        stableKey: sample.name,
        titleCandidates: sample.titleCandidates,
        year: sample.year,
        mediaEvidence: TmdbMediaEvidence.movie,
      ),
      const TmdbScrapeOptions.defaults(),
    );
    final bestIdentity = _identity(outcome.ranked.candidates.first.metadata);
    expect(outcome.ranked.shouldAutoMatch, isTrue);
    expect(bestIdentity, isNot(sample.expectedIdentity));
    expect(
      () => _expectSafeMatch(sample, bestIdentity, true),
      throwsA(isA<TestFailure>()),
    );
  });

  test('基准门禁能发现歧义候选被错误自动确认', () {
    final sample =
        tmdbScrapeCorpus.firstWhere((item) => !item.expectedAutoMatch);
    expect(
      () => _expectSafeMatch(sample, sample.expectedIdentity, true),
      throwsA(isA<TestFailure>()),
    );
  });
}

void _expectSafeMatch(
  TmdbScrapeCorpusCase sample,
  String? bestIdentity,
  bool automatic,
) {
  if (!sample.expectedAutoMatch) {
    expect(automatic, isFalse, reason: '${sample.name}：歧义样本必须待确认');
  }
  if (automatic) {
    expect(bestIdentity, sample.expectedIdentity,
        reason: '${sample.name}：自动匹配不能写入错误身份');
  }
}

Future<double> _cacheHitP95Milliseconds() async {
  final cache = TmdbScrapeCache();
  const key = 'search|tv|zh-CN|benchmark|page:1';
  await cache.getOrLoad<List<int>>(
    key,
    () async => const <int>[1],
    kind: TmdbScrapeCacheKind.search,
  );
  final samples = <int>[];
  for (var index = 0; index < 100; index += 1) {
    final stopwatch = Stopwatch()..start();
    await cache.getOrLoad<List<int>>(
      key,
      () async => const <int>[1],
      kind: TmdbScrapeCacheKind.search,
    );
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds);
  }
  samples.sort();
  final p95Index = ((samples.length * 95 + 99) ~/ 100) - 1;
  return samples[p95Index] / Duration.microsecondsPerMillisecond;
}

class _CorpusClient implements ITmdbClient {
  _CorpusClient(this.sample, {this.injectWrongIdentity = false});

  final TmdbScrapeCorpusCase sample;
  final bool injectWrongIdentity;
  final List<String> queries = <String>[];
  var _nextDistractorId = 90000;

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    queries.add('${mediaType.name}:$query');
    if (query.trim().toLowerCase() != sample.expectedQuery.toLowerCase()) {
      return <TmdbMetadata>[
        _metadata(
          id: _nextDistractorId++,
          mediaType: mediaType,
          title: '无关候选',
          year: sample.year,
        ),
      ];
    }

    final expected = _metadata(
      id: injectWrongIdentity ? sample.candidateId + 50000 : sample.candidateId,
      mediaType: sample.expectedType,
      title: sample.expectedTitle,
      year: sample.year,
      aliases: sample.aliases,
    );
    if (!sample.expectedAutoMatch) {
      return <TmdbMetadata>[
        expected,
        _metadata(
          id: sample.candidateId + 1000,
          mediaType: sample.expectedType == TmdbMediaType.movie
              ? TmdbMediaType.tv
              : TmdbMediaType.movie,
          title: sample.expectedTitle,
          year: sample.year,
        ),
      ];
    }
    if (mediaType != sample.expectedType) return const <TmdbMetadata>[];
    return <TmdbMetadata>[expected];
  }

  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) {
    return Future<TmdbMetadata>.error(
      UnimplementedError('benchmark 不请求详情'),
    );
  }
}

TmdbMetadata _metadata({
  required int id,
  required TmdbMediaType mediaType,
  required String title,
  required int? year,
  List<String> aliases = const <String>[],
}) {
  return TmdbMetadata(
    id: id,
    mediaType: mediaType,
    title: title,
    aliases: aliases,
    releaseDate: year == null ? null : '$year-01-01',
    language: 'zh-CN',
    matchedAt: DateTime.utc(2026),
    matchConfidence: 0,
  );
}

String _identity(TmdbMetadata metadata) {
  return '${metadata.mediaType.name}:${metadata.id}';
}
