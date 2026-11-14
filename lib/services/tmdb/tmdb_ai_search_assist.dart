import 'dart:convert';

import 'package:kanyingyin/services/tmdb/tmdb_scrape_cache.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_subject.dart';
import 'package:kanyingyin/services/tmdb/tmdb_vision_model_client.dart';

class TmdbAiSearchAssist {
  TmdbAiSearchAssist(
      {required this.config, required this.readKey, required this.client});

  final TmdbVisionModelConfig Function() config;
  final Future<String> Function() readKey;
  final TmdbVisionModelClient client;
  final _cache = TmdbScrapeCache(maximumEntries: 100);
  int _generation = 0;

  void clearCache() {
    _generation++;
    _cache.clear();
  }

  Future<TmdbVisionSuggestion?> identify(TmdbScrapeSubject subject) async {
    final settings = config();
    final generation = _generation;
    if (!settings.enabled || !settings.isConfigured) return null;
    final String key;
    try {
      key = await readKey();
    } on Object {
      throw const TmdbVisionException('AI 密钥读取失败，请重新保存模型密钥');
    }
    final names = subject.sourceNames.isEmpty
        ? subject.titleCandidates
        : subject.sourceNames;
    final stamp = jsonEncode(settings.toMap());
    final result = await _cache.getOrLoad<TmdbVisionSuggestion?>(
      'ai:$stamp:${key.hashCode}:${jsonEncode(names)}:${subject.seasonNumbers}:${subject.episodeNumbers}',
      () => client.identify(
          config: settings,
          apiKey: key,
          fileName: names.firstOrNull ?? '',
          sourceNames: names,
          seasonEpisodeInfo:
              '季：${subject.seasonNumbers}；集：${subject.episodeNumbers}',
          frames: const []),
      kind: TmdbScrapeCacheKind.search,
    );
    return generation == _generation && jsonEncode(config().toMap()) == stamp
        ? result
        : null;
  }
}
