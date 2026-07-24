import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/library/application/local_library_tmdb_coordinator.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

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
