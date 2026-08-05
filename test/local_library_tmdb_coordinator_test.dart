import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/local_library_tmdb_coordinator.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';

void main() {
  test('没有 TMDB Key 时不执行自动刮削', () {
    final coordinator = LocalLibraryTmdbCoordinator(
      apiKeyProvider: () => '',
      optionsProvider: () => const TmdbScrapeOptions.defaults(),
      autoScrapeProvider: () => true,
    );

    expect(coordinator.shouldAutoScrape(const []), isFalse);
  });

  test('关闭自动刮削时不执行自动刮削', () {
    final coordinator = LocalLibraryTmdbCoordinator(
      apiKeyProvider: () => 'key',
      optionsProvider: () => const TmdbScrapeOptions.defaults(),
      autoScrapeProvider: () => false,
    );

    expect(coordinator.shouldAutoScrape([_item('测试剧')]), isFalse);
  });

  test('只返回尚未匹配的非空系列名', () {
    final coordinator = LocalLibraryTmdbCoordinator(
      apiKeyProvider: () => 'key',
      optionsProvider: () => const TmdbScrapeOptions.defaults(),
      autoScrapeProvider: () => true,
    );

    final names = coordinator.unmatchedSeriesNames([
      _item('测试剧'),
      _item('测试剧'),
      _item('  '),
    ]);

    expect(names, {'测试剧'});
    expect(coordinator.shouldAutoScrape([_item('测试剧')]), isTrue);
    expect(coordinator.options.language, 'zh-CN');
  });

  test('已匹配但缺少 TMDB 集名的电视剧仍需要补抓', () {
    final coordinator = LocalLibraryTmdbCoordinator(
      apiKeyProvider: () => 'key',
      optionsProvider: () => const TmdbScrapeOptions.defaults(),
      autoScrapeProvider: () => true,
    );
    final item = _item('异世界悠闲农家').copyWith(
      seasonNumber: 1,
      episodeNumber: 1,
      tmdb: TmdbMetadata(
        id: 196285,
        mediaType: TmdbMediaType.tv,
        title: '异世界悠闲农家',
        language: 'zh-CN',
        matchedAt: DateTime(2026),
        matchConfidence: 1,
      ),
      scrapeStatus: TmdbScrapeStatus.matched,
      tmdbRuleVersion: currentTmdbRuleVersion,
    );

    expect(coordinator.unmatchedSeriesNames([item]), {'异世界悠闲农家'});
    expect(coordinator.shouldAutoScrape([item]), isTrue);
  });
}

LocalMediaIndexItem _item(String seriesName) => LocalMediaIndexItem(
      path: 'D:/$seriesName/01.mp4',
      name: '01.mp4',
      parentPath: 'D:/$seriesName',
      sourcePath: 'D:/',
      size: 1,
      modified: DateTime.fromMillisecondsSinceEpoch(1),
      seriesName: seriesName,
      indexedAt: DateTime.fromMillisecondsSinceEpoch(1),
    );
