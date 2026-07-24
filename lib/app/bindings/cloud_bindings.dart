import 'dart:io';

import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_series_match_rule_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_cache_directories.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_media_indexer.dart';
import 'package:kanyingyin/services/cloud/cloud_poster_cache.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_resource_tmdb_service.dart';
import 'package:kanyingyin/services/cloud/cloud_series_match_service.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_coordinator.dart';
import 'package:kanyingyin/services/cloud/cloud_work_tmdb_service.dart';
import 'package:kanyingyin/services/media_recognition_settings.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';
import 'package:kanyingyin/utils/storage.dart';

/// 注册网盘媒体库、索引和 TMDB 协调依赖。
void registerCloudBindings(Injector i) {
  i.addSingleton<CloudMediaIndexRepository>(CloudMediaIndexRepository.new);
  i.addSingleton<CloudResourceTmdbRepository>(
    CloudResourceTmdbRepository.new,
  );
  i.addSingleton<CloudWorkTmdbRepository>(CloudWorkTmdbRepository.new);
  i.addSingleton<CloudSeriesMatchRuleRepository>(
    CloudSeriesMatchRuleRepository.new,
  );
  i.addSingleton<CloudSeriesMatchService>(
    () => CloudSeriesMatchService(
      ruleRepository: Modular.get<CloudSeriesMatchRuleRepository>(),
      recordRepository: Modular.get<CloudResourceTmdbRepository>(),
      indexRepository: Modular.get<CloudMediaIndexRepository>(),
      minRecognizedVideoSizeBytesProvider: () =>
          Modular.get<MediaRecognitionSettings>().cloudMinSizeBytes,
    ),
  );
  i.addSingleton<CloudCredentialStore>(SecureCloudCredentialStore.new);
  i.addSingleton<CloudSourceRepository>(
    () => CloudSourceRepository(
      credentialStore: Modular.get<CloudCredentialStore>(),
    ),
  );
  i.addSingleton<CloudMediaIndexer>(
    () => CloudMediaIndexer(
      repository: Modular.get<CloudMediaIndexRepository>(),
      seriesMatchRuleRepository: Modular.get<CloudSeriesMatchRuleRepository>(),
      minRecognizedVideoSizeBytesProvider: () =>
          Modular.get<MediaRecognitionSettings>().cloudMinSizeBytes,
    ),
  );
  i.addSingleton<CloudLibraryController>(
    () => CloudLibraryController(
      repository: Modular.get<CloudSourceRepository>(),
      credentialStore: Modular.get<CloudCredentialStore>(),
      mediaIndexRepository: Modular.get<CloudMediaIndexRepository>(),
      resourceTmdbRepository: Modular.get<CloudResourceTmdbRepository>(),
      workTmdbRepository: Modular.get<CloudWorkTmdbRepository>(),
      seriesMatchRuleRepository: Modular.get<CloudSeriesMatchRuleRepository>(),
      mediaIndexer: Modular.get<CloudMediaIndexer>(),
    ),
  );
  i.addSingleton<CloudResourceTmdbCoordinator>(
    () => CloudResourceTmdbCoordinator(
      repository: Modular.get<CloudResourceTmdbRepository>(),
      serviceFactory: (apiKey) async => CloudResourceTmdbService(
        repository: Modular.get<CloudResourceTmdbRepository>(),
        indexRepository: Modular.get<CloudMediaIndexRepository>(),
        client: TmdbClient(apiKey: apiKey),
        posterCache: CloudPosterCache(
          cacheRoot: await defaultCloudCacheRoot(),
          downloader: _downloadCloudPoster,
        ),
      ),
      apiKeyProvider: Modular.get<TmdbApiKeyProvider>().read,
      optionsProvider: _tmdbScrapeOptions,
      seriesMatchService: Modular.get<CloudSeriesMatchService>(),
    ),
  );
  i.addSingleton<CloudWorkTmdbCoordinator>(
    () => CloudWorkTmdbCoordinator(
      repository: Modular.get<CloudWorkTmdbRepository>(),
      legacyRepository: Modular.get<CloudResourceTmdbRepository>(),
      indexRepository: Modular.get<CloudMediaIndexRepository>(),
      serviceFactory: (apiKey) async => CloudWorkTmdbService(
        repository: Modular.get<CloudWorkTmdbRepository>(),
        indexRepository: Modular.get<CloudMediaIndexRepository>(),
        client: TmdbClient(apiKey: apiKey),
        posterCache: CloudPosterCache(
          cacheRoot: await defaultCloudCacheRoot(),
          downloader: _downloadCloudPoster,
        ),
      ),
      apiKeyProvider: Modular.get<TmdbApiKeyProvider>().read,
      optionsProvider: _tmdbScrapeOptions,
    ),
  );
  i.addSingleton<CloudResourcesController>(
    () => CloudResourcesController(
      repository: Modular.get<CloudSourceRepository>(),
      credentialStore: Modular.get<CloudCredentialStore>(),
      tmdbCoordinator: Modular.get<CloudResourceTmdbCoordinator>(),
      workTmdbCoordinator: Modular.get<CloudWorkTmdbCoordinator>(),
      mediaIndexRepository: Modular.get<CloudMediaIndexRepository>(),
      mediaIndexer: Modular.get<CloudMediaIndexer>(),
      minRecognizedVideoSizeBytesProvider: () =>
          Modular.get<MediaRecognitionSettings>().cloudMinSizeBytes,
    ),
  );
}

TmdbScrapeOptions _tmdbScrapeOptions() {
  try {
    return TmdbScrapeOptions.fromMap(
      GStorage.setting.get('tmdbScrapeOptions'),
    );
  } on Object {
    return const TmdbScrapeOptions.defaults();
  }
}

Future<List<int>> _downloadCloudPoster(String url) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('海报下载失败：${response.statusCode}');
    }
    return response.fold<List<int>>(<int>[], (bytes, chunk) {
      bytes.addAll(chunk);
      return bytes;
    });
  } finally {
    client.close(force: true);
  }
}
