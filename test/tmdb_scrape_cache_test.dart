import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_cache.dart';

void main() {
  test('同一搜索键并发请求只执行一次并共享结果', () async {
    var loadCount = 0;
    final gate = Completer<List<String>>();
    final cache = TmdbScrapeCache(
      now: () => DateTime.utc(2026, 8, 5),
    );

    Future<List<String>> load() {
      loadCount += 1;
      return gate.future;
    }

    final first = cache.getOrLoad<List<String>>(
      'search|tv|zh-CN|三体|page:1',
      load,
    );
    final second = cache.getOrLoad<List<String>>(
      'search|tv|zh-CN|三体|page:1',
      load,
    );

    expect(loadCount, 1);
    gate.complete(<String>['三体']);
    expect(await Future.wait(<Future<List<String>>>[first, second]), [
      ['三体'],
      ['三体'],
    ]);
    expect(loadCount, 1);
  });

  test('搜索、详情和别名分别使用各自 TTL', () async {
    var clock = DateTime.utc(2026, 8, 5);
    var searchLoads = 0;
    var detailLoads = 0;
    var aliasLoads = 0;
    final cache = TmdbScrapeCache(
      now: () => clock,
      searchTtl: const Duration(minutes: 10),
      detailsTtl: const Duration(hours: 24),
      aliasTtl: const Duration(days: 30),
    );

    Future<String> search() async {
      searchLoads += 1;
      return 'search-$searchLoads';
    }

    Future<String> details() async {
      detailLoads += 1;
      return 'details-$detailLoads';
    }

    Future<String> aliases() async {
      aliasLoads += 1;
      return 'aliases-$aliasLoads';
    }

    expect(
      await cache.getOrLoad<String>('search|movie|zh-CN|Avatar|page:1', search),
      'search-1',
    );
    expect(
      await cache.getOrLoad<String>('details|movie|zh-CN|42', details),
      'details-1',
    );
    expect(
      await cache.getOrLoad<String>('alias|movie|zh-CN|42', aliases),
      'aliases-1',
    );

    clock = clock.add(const Duration(minutes: 11));
    expect(
      await cache.getOrLoad<String>('search|movie|zh-CN|Avatar|page:1', search),
      'search-2',
    );
    expect(
      await cache.getOrLoad<String>('details|movie|zh-CN|42', details),
      'details-1',
    );
    expect(
      await cache.getOrLoad<String>('alias|movie|zh-CN|42', aliases),
      'aliases-1',
    );

    clock = clock.add(const Duration(hours: 24));
    expect(
      await cache.getOrLoad<String>('details|movie|zh-CN|42', details),
      'details-2',
    );
    expect(searchLoads, 2);
    expect(detailLoads, 2);
    expect(aliasLoads, 1);
  });

  test('访问会刷新 LRU 顺序，超限时淘汰最久未访问项', () async {
    var loadCount = 0;
    final cache = TmdbScrapeCache(
      maximumEntries: 2,
      now: () => DateTime.utc(2026, 8, 5),
    );

    Future<String> load(String value) async {
      loadCount += 1;
      return '$value-$loadCount';
    }

    expect(
      await cache.getOrLoad<String>(
          'search|tv|zh-CN|A|page:1', () => load('A')),
      'A-1',
    );
    expect(
      await cache.getOrLoad<String>(
          'search|tv|zh-CN|B|page:1', () => load('B')),
      'B-2',
    );
    expect(
      await cache.getOrLoad<String>(
          'search|tv|zh-CN|A|page:1', () => load('A')),
      'A-1',
    );
    expect(
      await cache.getOrLoad<String>(
          'search|tv|zh-CN|C|page:1', () => load('C')),
      'C-3',
    );
    expect(
      await cache.getOrLoad<String>(
          'search|tv|zh-CN|B|page:1', () => load('B')),
      'B-4',
    );
    expect(loadCount, 4);
  });

  test('失败结果不入缓存，下一次请求可以重试', () async {
    var attempts = 0;
    final cache = TmdbScrapeCache(
      now: () => DateTime.utc(2026, 8, 5),
    );

    Future<String> load() async {
      attempts += 1;
      if (attempts == 1) throw StateError('temporary');
      return 'ok';
    }

    await expectLater(
      cache.getOrLoad<String>('details|tv|zh-CN|42', load),
      throwsA(isA<StateError>()),
    );
    expect(
      await cache.getOrLoad<String>('details|tv|zh-CN|42', load),
      'ok',
    );
    expect(attempts, 2);
  });

  test('语言、媒体类型和页码进入缓存键', () async {
    var loads = 0;
    final cache = TmdbScrapeCache(
      now: () => DateTime.utc(2026, 8, 5),
    );

    Future<int> load() async => ++loads;

    expect(
      await cache.getOrLoad<int>('search|tv|zh-CN|三体|page:1', load),
      1,
    );
    expect(
      await cache.getOrLoad<int>('search|tv|en-US|三体|page:1', load),
      2,
    );
    expect(
      await cache.getOrLoad<int>('search|movie|zh-CN|三体|page:1', load),
      3,
    );
    expect(
      await cache.getOrLoad<int>('search|tv|zh-CN|三体|page:2', load),
      4,
    );
    expect(loads, 4);
  });

  test('同一 API Key 复用客户端和缓存，不同 Key 相互隔离', () {
    var clientCreations = 0;
    final registry = TmdbClientContextRegistry(
      clientFactory: (apiKey) {
        clientCreations += 1;
        return TmdbClient(apiKey: apiKey, dio: Dio());
      },
    );

    final first = registry.contextFor('key-a');
    final same = registry.contextFor(' key-a ');
    final other = registry.contextFor('key-b');

    expect(identical(first.client, same.client), isTrue);
    expect(identical(first.cache, same.cache), isTrue);
    expect(identical(first.client, other.client), isFalse);
    expect(identical(first.cache, other.cache), isFalse);
    expect(clientCreations, 2);
  });
}
