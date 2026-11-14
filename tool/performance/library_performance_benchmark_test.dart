import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/library/application/media_library_category.dart';
import 'package:kanyingyin/features/library/application/media_library_query.dart';
import 'package:kanyingyin/features/library/presentation/immersive_media_card.dart';
import 'package:kanyingyin/features/library/presentation/media_category_page.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/utils/library_performance_trace.dart';
import 'package:kanyingyin/utils/storage.dart';

const label = String.fromEnvironment('benchmark_label', defaultValue: 'probe');
const repetitions =
    int.fromEnvironment('benchmark_repetitions', defaultValue: 5);

void main() {
  testWidgets('固定合成媒体库性能采样', (tester) async {
    expect(repetitions, greaterThan(0));
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final report = <String, Object?>{
      'label': label,
      'mode': 'flutter test JIT; widget pump非GPU/Release首屏',
      'dart': Platform.version,
      'os': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      'viewport': '1280x720@1',
      'repetitions': repetitions,
      'fixture': 'deterministic-v1; one episode/movie; no network images',
      'indexReadScope': 'Hive重开单列；indexColdRead为已打开Hive的首次仓库解码；OS文件缓存未清除',
      'rssScope': '整个测试进程，含Flutter/JIT；不强制GC；两个规模顺序执行',
    };
    final results = <Map<String, Object?>>[];
    for (final count in [1000, 10000]) {
      final items = List.generate(count, _item, growable: false);
      final payload =
          items.map((item) => item.toJson()).toList(growable: false);
      final checksum =
          sha256.convert(utf8.encode(jsonEncode(payload))).toString();
      final samples = <Map<String, num>>[];
      for (var round = -1; round < repetitions; round++) {
        final metrics = <String, num>{};
        late CloudMediaLibrary library;
        await tester.runAsync(() async {
          final directory = await Directory.systemTemp.createTemp('kyy_perf_');
          Box<Object?>? box;
          try {
            final rssBefore = ProcessInfo.currentRss;
            box =
                await Hive.openBox<Object?>('benchmark', path: directory.path);
            await box.put(SettingBoxKey.localMediaIndex, payload);
            await box.flush();
            await box.close();
            final openWatch = Stopwatch()..start();
            box =
                await Hive.openBox<Object?>('benchmark', path: directory.path);
            metrics['hiveReopenMs'] = openWatch.elapsedMicroseconds / 1000;
            final storage = _HiveStorage(box);
            final repository = LocalMediaIndexRepository(
              storage: storage,
              performanceTrace: LibraryPerformanceTrace(log: (_) {}),
            );
            final watch = Stopwatch()..start();
            final loaded = repository.getAll();
            metrics['indexColdReadMs'] = watch.elapsedMicroseconds / 1000;
            watch.reset();
            final cached = repository.getAll();
            metrics['indexCachedReadMs'] = watch.elapsedMicroseconds / 1000;
            expect(identical(loaded, cached), isTrue);
            expect(loaded.length, count);
            library = CloudMediaLibrary(
              series: loaded.map(_series).toList(growable: false),
              filters: const [MediaLibrarySourceFilter('all', '全部', null)],
            );
            const query = MediaLibraryQuery();
            watch.reset();
            var found = 0;
            for (var iteration = 0; iteration < 20; iteration++) {
              found +=
                  query.apply(series: library.series, keyword: '作品0009').length;
            }
            metrics['searchMeanMs'] = watch.elapsedMicroseconds / 1000 / 20;
            expect(found, 2000);
            watch.reset();
            final aliases =
                query.apply(series: library.series, keyword: 'Original 00099');
            metrics['originalTitleSearchMs'] = watch.elapsedMicroseconds / 1000;
            metrics['originalTitleHits'] = aliases.length;
            watch.reset();
            await repository.updateItems({
              for (final item in loaded)
                item.id: item.copyWith(cover: 'benchmark.jpg')
            });
            await box.flush();
            metrics['bulkWriteFlushMs'] = watch.elapsedMicroseconds / 1000;
            expect(
                repository
                    .getAll()
                    .every((item) => item.cover == 'benchmark.jpg'),
                isTrue);
            metrics['rssBeforeBytes'] = rssBefore;
            metrics['rssAfterDataBytes'] = ProcessInfo.currentRss;
            metrics['rssDataDeltaBytes'] = ProcessInfo.currentRss - rssBefore;
          } finally {
            await box?.close();
            await directory.delete(recursive: true);
          }
        });
        final frameWatch = Stopwatch()..start();
        await tester.pumpWidget(MaterialApp(
          home: MediaCategoryPage(
            key: ValueKey('$count:$round'),
            category: MediaLibraryCategory.movie,
            initialize: () async {},
            libraryProvider: () => library,
            onPlayEpisode: (_, __) async {},
            observeLibrary: false,
            capabilities: AppPlatformCapabilities.windows,
          ),
        ));
        await tester.pump();
        frameWatch.stop();
        metrics['firstContentWidgetPumpMs'] =
            frameWatch.elapsedMicroseconds / 1000;
        final rendered = find.byType(ImmersiveMediaCard).evaluate().length;
        expect(rendered, greaterThan(0));
        expect(rendered, lessThan(count));
        expect(tester.takeException(), isNull);
        metrics['renderedCards'] = rendered;
        metrics['rssAfterWidgetBytes'] = ProcessInfo.currentRss;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        if (round >= 0) samples.add(metrics);
      }
      final medians = <String, num>{};
      for (final key in samples.first.keys) {
        final values = samples.map((sample) => sample[key]!).toList()..sort();
        medians[key] = values[values.length ~/ 2];
      }
      results.add({
        'count': count,
        'fixtureSha256': checksum,
        'medians': medians,
        'samples': samples
      });
    }
    report['results'] = results;
    final encoded = const JsonEncoder.withIndent('  ').convert(report);
    await tester.runAsync(() async {
      await Directory('build/three_round_validation').create(recursive: true);
      await File('build/three_round_validation/performance-$label.json')
          .writeAsString(encoded);
    });
    // 输出只含合成样本汇总，不含真实媒体或凭据。
    stdout.writeln(encoded);
  }, timeout: const Timeout(Duration(minutes: 4)));
}

LocalMediaIndexItem _item(int index) {
  final number = index.toString().padLeft(6, '0');
  return LocalMediaIndexItem(
    path: 'D:/Synthetic/作品$number.mkv',
    name: '作品$number.mkv',
    parentPath: 'D:/Synthetic',
    sourcePath: 'D:/Synthetic',
    size: 100000000,
    modified: DateTime.utc(2026),
    indexedAt: DateTime.utc(2026),
    seriesName: '作品$number',
    tmdb: TmdbMetadata(
        id: index + 1,
        mediaType: TmdbMediaType.movie,
        title: '中文标题$number',
        originalTitle: 'Original $number',
        aliases: ['别名$number'],
        genres: const ['剧情'],
        language: 'zh-CN',
        matchedAt: DateTime.utc(2026),
        matchConfidence: 1),
  );
}

MediaLibrarySeries _series(LocalMediaIndexItem item) => MediaLibrarySeries(
      key: item.id,
      seriesKey: item.seriesName,
      title: item.seriesName,
      sourceKind: MediaSourceKind.local,
      sourceId: 'local',
      sourceName: '本地',
      isAvailable: true,
      mediaType: TmdbMediaType.movie,
      tmdbMetadata: item.tmdb,
      episodes: [
        MediaLibraryEpisode.local(
            stableId: item.id, name: item.name, localItem: item)
      ],
    );

class _HiveStorage implements LocalMediaIndexStorage {
  _HiveStorage(this.box);
  final Box<Object?> box;
  @override
  Object? read(String key, {Object? defaultValue}) =>
      box.get(key, defaultValue: defaultValue);
  @override
  Future<void> write(String key, Object? value) => box.put(key, value);
  @override
  Future<void> delete(String key) => box.delete(key);
}
