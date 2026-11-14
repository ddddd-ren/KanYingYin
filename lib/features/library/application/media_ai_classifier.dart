import 'dart:async';
import 'dart:convert';

import 'package:kanyingyin/features/library/application/media_library_classification.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_cache.dart';
import 'package:kanyingyin/services/tmdb/tmdb_vision_model_client.dart';

/// 索引更新后补充不明确的主分类，不阻塞扫描、列表或播放。
class MediaAiClassifier {
  MediaAiClassifier(
      {required this.config,
      required this.mode,
      required this.readKey,
      required this.client,
      required this.repository});

  final TmdbVisionModelConfig Function() config;
  final MediaClassificationMode Function() mode;
  final Future<String> Function() readKey;
  final TmdbVisionModelClient client;
  final MediaLibraryUserStateRepository repository;
  final _cache = TmdbScrapeCache(maximumEntries: 100);
  final _pending = <String, CloudMediaLibrary Function()>{};
  Future<void>? _running;
  int _generation = 0;

  void clearCache() {
    _generation++;
    _cache.clear();
  }

  Future<void> process(CloudMediaLibrary Function() library) {
    if (!config().autoClassification ||
        mode() == MediaClassificationMode.manual) {
      return Future<void>.value();
    }
    for (final series in library().series) {
      _pending[series.key] = library;
    }
    return _running ??= _drain().whenComplete(() => _running = null);
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty) {
      final key = _pending.keys.first;
      final library = _pending.remove(key)!;
      try {
        final series = library().series.where((s) => s.key == key).firstOrNull;
        final metadata = series?.tmdbMetadata;
        final settings = config();
        final generation = _generation;
        if (series == null ||
            metadata == null ||
            !settings.isConfigured ||
            !settings.autoClassification ||
            mode() == MediaClassificationMode.manual) {
          continue;
        }
        final state = await repository.get(key);
        final resolved = const MediaClassificationResolver()
            .resolve(series, state: state, mode: mode());
        if (!resolved.needsConfirmation ||
            (state?.categoryOverride != null && state?.aiClassified != true)) {
          continue;
        }
        final identity = '${metadata.mediaType.name}:${metadata.id}';
        final stamp = jsonEncode(settings.toMap());
        final apiKey = await readKey();
        if (apiKey.isEmpty) continue;
        final result = await _cache.getOrLoad<TmdbVisionClassification?>(
          'classification:$stamp:${apiKey.hashCode}:$identity:${metadata.title}:${metadata.overview}:${metadata.genres}',
          () async {
            try {
              return await client.classify(
                  config: settings,
                  apiKey: apiKey,
                  title: metadata.title,
                  mediaType: metadata.mediaType,
                  overview: metadata.overview,
                  genres: metadata.genres);
            } on TmdbVisionException catch (error) {
              TmdbVisionModelClient.report(error.message);
              return null;
            }
          },
          kind: TmdbScrapeCacheKind.search,
        );
        final current = library().series.where((s) => s.key == key).firstOrNull;
        final currentMetadata = current?.tmdbMetadata;
        if (result == null ||
            generation != _generation ||
            currentMetadata == null ||
            result.confidence < .8 ||
            jsonEncode(config().toMap()) != stamp ||
            mode() == MediaClassificationMode.manual ||
            currentMetadata.title != metadata.title ||
            currentMetadata.overview != metadata.overview ||
            jsonEncode(currentMetadata.genres) != jsonEncode(metadata.genres) ||
            '${currentMetadata.mediaType.name}:${currentMetadata.id}' !=
                identity) {
          continue;
        }
        final saved = await repository.saveAutomaticCategory(key,
            category: result.category,
            identity: identity,
            mediaIds: current!.episodes.map((episode) => episode.stableId));
        if (saved) TmdbVisionModelClient.report('AI 分类已更新');
      } on Object catch (error) {
        // 不输出原始异常正文，防止网络凭据和媒体路径进入日志。
        TmdbVisionModelClient.report('AI 分类暂不可用（${error.runtimeType}），已保留现有分类');
      }
    }
  }
}
