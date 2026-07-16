import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/local/poster_scrape.dart';
import 'package:kanyingyin/services/local_poster_scraper.dart';
import 'package:kanyingyin/services/poster_service.dart';
import 'package:kanyingyin/modules/local/local_episode_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LocalPosterScraper continues after one item throws', () async {
    final service = _FakePosterService(
      searchResults: {
        'bad': Exception('search failed'),
        'good': 'https://example.test/good.jpg',
      },
      downloadResults: {
        'https://example.test/good.jpg': r'D:\Media\good.jpg',
      },
    );
    final progress = <PosterScrapeProgress>[];

    final result =
        await LocalPosterScraper(posterService: service).scrapeMissingPosters(
      [
        _video(path: r'D:\Media\bad\bad.mkv', name: 'bad.mkv'),
        _video(path: r'D:\Media\good\good.mkv', name: 'good.mkv'),
      ],
      onProgress: progress.add,
    );

    expect(result.success, 1);
    expect(result.failed, 1);
    expect(result.skipped, 0);
    expect(result.total, 2);
    expect(service.searchQueries, ['bad', 'good']);
    expect(service.downloadedUrls, ['https://example.test/good.jpg']);
    expect(progress.last.progress, 1);
  });

  test('LocalPosterScraper counts existing covers as skipped', () async {
    final result = await LocalPosterScraper(
      posterService: _FakePosterService(),
    ).scrapeMissingPosters([
      _video(
        path: r'D:\Media\covered\covered.mkv',
        name: 'covered.mkv',
        cover: r'D:\Media\covered\covered.poster.jpg',
      ),
      _video(path: r'D:\Media\missing\missing.mkv', name: 'missing.mkv'),
    ]);

    expect(result.success, 0);
    expect(result.failed, 1);
    expect(result.skipped, 1);
    expect(result.total, 2);
  });

  test('LocalPosterScraper replaces generated thumbnail covers', () async {
    final service = _FakePosterService(
      searchResults: {'thumb': 'https://example.test/thumb.jpg'},
      downloadResults: {
        'https://example.test/thumb.jpg': r'D:\Media\thumb.jpg',
      },
    );

    final result = await LocalPosterScraper(
      posterService: service,
    ).scrapeMissingPosters([
      _video(
        path: r'D:\Media\thumb\thumb.mkv',
        name: 'thumb.mkv',
        cover: r'D:\Media\thumb\.kanyingyin_thumbs\thumb.jpg',
      ),
    ]);

    expect(result.success, 1);
    expect(result.failed, 0);
    expect(result.skipped, 0);
    expect(result.total, 1);
    expect(service.searchQueries, ['thumb']);
  });

  test('LocalPosterScraper searches once per recognized series', () async {
    final service = _FakePosterService(
      searchResults: {'Show': 'https://example.test/show.jpg'},
      downloadResults: {
        'https://example.test/show.jpg': r'D:\Media\show.jpg',
      },
    );

    final result = await LocalPosterScraper(
      posterService: service,
    ).scrapeMissingPosters([
      _video(
        path: r'D:\Media\Show S01E01.mkv',
        name: 'Show S01E01.mkv',
        episodeInfo: const LocalEpisodeInfo(
          seriesName: 'Show',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
      ),
      _video(
        path: r'D:\Media\Show S01E02.mkv',
        name: 'Show S01E02.mkv',
        episodeInfo: const LocalEpisodeInfo(
          seriesName: 'Show',
          seasonNumber: 1,
          episodeNumber: 2,
        ),
      ),
    ]);

    expect(result.success, 1);
    expect(result.failed, 0);
    expect(result.skipped, 0);
    expect(result.total, 1);
    expect(service.searchQueries, ['Show']);
    expect(service.downloadedUrls, ['https://example.test/show.jpg']);
  });

  test('LocalPosterScraper searches once per series collection', () async {
    final service = _FakePosterService(
      searchResults: {'Show': 'https://example.test/show.jpg'},
      downloadResults: {
        'https://example.test/show.jpg': r'D:\Media\show.jpg',
      },
    );

    final result = await LocalPosterScraper(
      posterService: service,
    ).scrapeMissingPosters([
      _video(
        path: r'D:\Media\Show S01\Show S01E01.mkv',
        name: 'Show S01E01.mkv',
        episodeInfo: const LocalEpisodeInfo(
          seriesName: 'Show S01',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
      ),
      _video(
        path: r'D:\Media\Show S02\Show S02E01.mkv',
        name: 'Show S02E01.mkv',
        episodeInfo: const LocalEpisodeInfo(
          seriesName: 'Show S02',
          seasonNumber: 2,
          episodeNumber: 1,
        ),
      ),
      _video(
        path: r'D:\Media\Show Movie\Show Movie.mkv',
        name: 'Show Movie.mkv',
        episodeInfo: const LocalEpisodeInfo(
          seriesName: 'Show Movie',
          episodeNumber: 1,
        ),
      ),
    ]);

    expect(result.success, 1);
    expect(result.failed, 0);
    expect(result.total, 1);
    expect(service.searchQueries, ['Show']);
    expect(service.downloadedVideos, [
      r'D:\Media\Show S01\Show S01E01.mkv',
      r'D:\Media\Show S02\Show S02E01.mkv',
      r'D:\Media\Show Movie\Show Movie.mkv',
    ]);
  });

  test('LocalPosterScraper downloads one cover into every episode directory',
      () async {
    final service = _FakePosterService(
      searchResults: {'Show': 'https://example.test/show.jpg'},
      downloadResults: {
        'https://example.test/show.jpg': r'D:\Media\show.jpg',
      },
    );

    final result = await LocalPosterScraper(
      posterService: service,
    ).scrapeMissingPosters([
      _video(
        path: r'D:\Media\Show\第1季\Show S01E01.mkv',
        name: 'Show S01E01.mkv',
        episodeInfo: const LocalEpisodeInfo(
          seriesName: 'Show',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
      ),
      _video(
        path: r'D:\Media\Show\第2季\Show S02E01.mkv',
        name: 'Show S02E01.mkv',
        episodeInfo: const LocalEpisodeInfo(
          seriesName: 'Show',
          seasonNumber: 2,
          episodeNumber: 1,
        ),
      ),
      _video(
        path: r'D:\Media\Show\剧场版\Show Movie.mkv',
        name: 'Show Movie.mkv',
        episodeInfo: const LocalEpisodeInfo(
          seriesName: 'Show Movie',
          episodeNumber: 1,
        ),
      ),
    ]);

    expect(result.success, 1);
    expect(result.failed, 0);
    expect(result.total, 1);
    expect(service.searchQueries, ['Show']);
    expect(service.downloadedUrls, [
      'https://example.test/show.jpg',
      'https://example.test/show.jpg',
      'https://example.test/show.jpg',
    ]);
    expect(service.downloadedVideos, [
      r'D:\Media\Show\第1季\Show S01E01.mkv',
      r'D:\Media\Show\第2季\Show S02E01.mkv',
      r'D:\Media\Show\剧场版\Show Movie.mkv',
    ]);
  });

  test('LocalPosterScraper searches unrecognized episodes by parent folder',
      () async {
    final service = _FakePosterService(
      searchResults: {'Show': 'https://example.test/show.jpg'},
      downloadResults: {
        'https://example.test/show.jpg': r'D:\Media\Show\Show.poster.jpg',
      },
    );

    final result = await LocalPosterScraper(
      posterService: service,
    ).scrapeMissingPosters([
      _video(path: r'D:\Media\Show\01.mkv', name: '01.mkv'),
      _video(path: r'D:\Media\Show\02.mkv', name: '02.mkv'),
    ]);

    expect(result.success, 1);
    expect(result.failed, 0);
    expect(result.total, 1);
    expect(service.searchQueries, ['Show']);
    expect(service.downloadedUrls, ['https://example.test/show.jpg']);
  });

  test('LocalPosterScraper counts a mixed-cover series once', () async {
    final service = _FakePosterService(
      searchResults: {'Show': 'https://example.test/show.jpg'},
      downloadResults: {
        'https://example.test/show.jpg': r'D:\Media\show.jpg',
      },
    );

    final result = await LocalPosterScraper(
      posterService: service,
    ).scrapeMissingPosters([
      _video(
        path: r'D:\Media\Show S01E01.mkv',
        name: 'Show S01E01.mkv',
        cover: r'D:\Media\Show.poster.jpg',
        episodeInfo: const LocalEpisodeInfo(
          seriesName: 'Show',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
      ),
      _video(
        path: r'D:\Media\Show S01E02.mkv',
        name: 'Show S01E02.mkv',
        episodeInfo: const LocalEpisodeInfo(
          seriesName: 'Show',
          seasonNumber: 1,
          episodeNumber: 2,
        ),
      ),
    ]);

    expect(result.success, 1);
    expect(result.failed, 0);
    expect(result.skipped, 0);
    expect(result.total, 1);
    expect(service.searchQueries, ['Show']);
    expect(service.downloadedUrls, ['https://example.test/show.jpg']);
  });

  test('LocalPosterScraper uses fallback cover when search throws', () async {
    final service = _FakePosterService(
      searchResults: {'Show': Exception('search failed')},
      downloadResults: {
        'https://example.test/bangumi.jpg': r'D:\Media\show.jpg',
      },
    );

    final result = await LocalPosterScraper(
      posterService: service,
    ).scrapeMissingPosters(
      [
        _video(
          path: r'D:\Media\Show S01E01.mkv',
          name: 'Show S01E01.mkv',
          episodeInfo: const LocalEpisodeInfo(
            seriesName: 'Show',
            seasonNumber: 1,
            episodeNumber: 1,
          ),
        ),
      ],
      fallbackCover: (_) => 'https://example.test/bangumi.jpg',
    );

    expect(result.success, 1);
    expect(result.failed, 0);
    expect(service.searchQueries, ['Show']);
    expect(service.downloadedUrls, ['https://example.test/bangumi.jpg']);
  });
}

LocalFileItem _video({
  required String path,
  required String name,
  String? cover,
  LocalEpisodeInfo? episodeInfo,
}) {
  return LocalFileItem(
    path: path,
    name: name,
    size: 1024,
    modified: DateTime(2026),
    isDirectory: false,
    isVideo: true,
    cover: cover,
    episodeInfo: episodeInfo,
  );
}

class _FakePosterService extends PosterService {
  _FakePosterService({
    Map<String, Object?>? searchResults,
    Map<String, String?>? downloadResults,
  })  : searchResults = searchResults ?? const {},
        downloadResults = downloadResults ?? const {};

  final Map<String, Object?> searchResults;
  final Map<String, String?> downloadResults;
  final searchQueries = <String>[];
  final downloadedUrls = <String>[];
  final downloadedVideos = <String>[];

  @override
  String extractMovieName(String filename) {
    return filename.replaceAll('.mkv', '');
  }

  @override
  Future<String?> searchPoster({
    String? rawFilename,
    LocalEpisodeInfo? episodeInfo,
    String? seriesName,
  }) async {
    final effectiveSeriesName = seriesName?.trim();
    final infoSeriesName = episodeInfo?.seriesName.trim();
    final query =
        (effectiveSeriesName != null && effectiveSeriesName.isNotEmpty)
            ? effectiveSeriesName
            : (infoSeriesName != null && infoSeriesName.isNotEmpty)
                ? infoSeriesName
                : extractMovieName(rawFilename ?? '');
    searchQueries.add(query);
    final result = searchResults[query];
    if (result is Exception) throw result;
    return result as String?;
  }

  @override
  Future<String?> downloadPoster(String posterUrl, String videoPath) async {
    downloadedUrls.add(posterUrl);
    downloadedVideos.add(videoPath);
    return downloadResults[posterUrl];
  }
}
