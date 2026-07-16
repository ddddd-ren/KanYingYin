import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/repositories/tmdb_metadata_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scraper.dart';

void main() {
  test('高置信度结果写入缓存', () async {
    final repository = _MemoryRepository();
    final scraper = TmdbScraper(
      client: _FakeClient(),
      repository: repository,
    );

    final result = await scraper.scrape(
      mediaKey: 'series-1',
      title: '流浪地球',
      year: 2019,
      mediaType: TmdbMediaType.movie,
    );

    expect(result.status, TmdbScrapeStatus.matched);
    expect(repository.get('series-1')?.title, '流浪地球');
  });
}

class _FakeClient implements ITmdbClient {
  @override
  Future<TmdbMetadata> details(
    int id,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    return TmdbMetadata(
      id: id,
      mediaType: mediaType,
      title: '流浪地球',
      overview: '太阳即将毁灭，人类建造行星发动机。',
      releaseDate: '2019-02-05',
      language: language,
      matchedAt: DateTime(2026),
      matchConfidence: 0,
    );
  }

  @override
  Future<List<TmdbMetadata>> search(
    String query,
    TmdbMediaType mediaType, {
    String language = 'zh-CN',
  }) async {
    return [await details(1, mediaType, language: language)];
  }
}

class _MemoryRepository implements ITmdbMetadataRepository {
  final values = <String, TmdbMetadata>{};

  @override
  TmdbMetadata? get(String mediaKey) => values[mediaKey];

  @override
  Future<void> remove(String mediaKey) async => values.remove(mediaKey);

  @override
  Future<void> save(String mediaKey, TmdbMetadata metadata) async {
    values[mediaKey] = metadata;
  }
}
