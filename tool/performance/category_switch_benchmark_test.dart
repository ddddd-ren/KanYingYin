import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/library/application/library_ports.dart';
import 'package:kanyingyin/features/library/application/media_category_runtime.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/modules/local/local_media_index_item.dart';
import 'package:kanyingyin/modules/local/local_media_source.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/pages/index_module.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:kanyingyin/utils/storage.dart';
import 'package:path/path.dart' as p;

const label = String.fromEnvironment('benchmark_label', defaultValue: 'sample');
const count = int.fromEnvironment('benchmark_count', defaultValue: 1000);

void main() {
  test('固定普通文件经过正式分类页业务入口，保留每次采样', () async {
    expect(RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(label), isTrue);
    expect([1000, 10000], contains(count));
    final output = Directory('build/navigation_validation').absolute;
    await output.create(recursive: true);
    final results = <Map<String, Object?>>[];
    final hive = await Directory.systemTemp.createTemp('kyy_category_bench_');
    final box = await Hive.openBox<Object?>('setting', path: hive.path);
    GStorage.setting = box;
    addTearDown(() async {
      await box.close();
      await hive.delete(recursive: true);
    });
    final media = Directory(p.join(output.path, 'sample-media', '$count'));
    await media.create(recursive: true);
    final items = <Map<String, Object?>>[];
    final date = DateTime.utc(2026, 1, 1);
    for (var index = 0; index < count; index++) {
      final title = '作品${index.toString().padLeft(6, '0')}';
      final path = p.join(media.path, '$title.mkv');
      File(path).createSync();
      items.add(LocalMediaIndexItem(
        path: path,
        name: p.basename(path),
        parentPath: media.path,
        sourcePath: media.path,
        size: 1500000000,
        modified: date,
        indexedAt: date,
        seriesName: title,
        tmdb: TmdbMetadata(
          id: index + 1,
          mediaType: TmdbMediaType.movie,
          title: title,
          language: 'zh-CN',
          matchedAt: date,
          matchConfidence: 1,
        ),
      ).toJson());
    }
    try {
      await box.putAll({
        SettingBoxKey.localMediaSources: [
          LocalMediaSource.fromPath(media.path).toJson()
        ],
        SettingBoxKey.localMediaIndex: items,
        'tmdbAutoScrape': false,
      });
      Modular.init(IndexModule(
          tmdbCredentialManager: TmdbCredentialManager(
        store: MemoryTmdbCredentialStore(),
        legacyReader: () => '',
        legacyDelete: () async {},
      )));
      final samples = <Map<String, num>>[];
      for (var round = 0; round < 6; round++) {
        final runtime = MediaCategoryRuntime(
          localLibrary: Modular.get<LocalLibraryPort>(),
          cloudLibrary: Modular.get<CloudLibraryPort>(),
          playback: Modular.get<PlaybackPort>(),
          settings: TypedSettings(box),
          navigateToPlayer: () async {},
        );
        try {
          final nextEvent = Completer<double>();
          final timer = Stopwatch()..start();
          Timer.run(() => nextEvent.complete(timer.elapsedMicroseconds / 1000));
          await runtime.initialize();
          final visible = runtime.library.series.length;
          final readyMs = timer.elapsedMicroseconds / 1000;
          final yieldMs = await nextEvent.future;
          expect(visible, count);
          samples.add({
            'round': round,
            'readyMs': readyMs,
            'nextEventMs': yieldMs,
            'visible': visible
          });
        } finally {
          runtime.dispose();
        }
      }
      results.add({
        'count': count,
        'fixtureSha256':
            sha256.convert(utf8.encode(jsonEncode(items))).toString(),
        'samples': samples,
      });
    } finally {
      Modular.destroy();
    }
    final file = File(p.join(output.path, 'category-$label-$count.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'mode': 'Flutter test JIT, real files and application bindings; no GPU',
      'scope':
          'initialize + reading visible series; round 0 first, rounds 1-5 warm',
      'results': results,
    }));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
