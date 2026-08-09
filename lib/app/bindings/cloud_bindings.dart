import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_archive_codec.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_transfer_service.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/features/episode_matching/application/cloud_episode_match_service.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/repositories/cloud_hidden_video_repository.dart';
import 'package:kanyingyin/repositories/cloud_episode_match_rule_repository.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_media_tag_repository.dart';
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
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_image_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

/// 注册网盘媒体库、索引和 TMDB 协调依赖。
void registerCloudBindings(Injector i) {
  i.addSingleton<CloudHiddenVideoRepository>(
    CloudHiddenVideoRepository.new,
  );
  i.addSingleton<CloudMediaIndexRepository>(CloudMediaIndexRepository.new);
  i.addSingleton<CloudMediaTagRepository>(CloudMediaTagRepository.new);
  i.addSingleton<CloudResourceTmdbRepository>(
    CloudResourceTmdbRepository.new,
  );
  i.addSingleton<CloudWorkTmdbRepository>(CloudWorkTmdbRepository.new);
  i.addSingleton<CloudSeriesMatchRuleRepository>(
    CloudSeriesMatchRuleRepository.new,
  );
  i.addSingleton<CloudEpisodeMatchRuleRepository>(
    CloudEpisodeMatchRuleRepository.new,
  );
  i.addSingleton<CloudEpisodeMatchService>(
    () => CloudEpisodeMatchService(
      ruleRepository: Modular.get<CloudEpisodeMatchRuleRepository>(),
      indexRepository: Modular.get<CloudMediaIndexRepository>(),
    ),
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
  i.addSingleton<ConfigurationArchiveCodec>(ConfigurationArchiveCodec.new);
  i.addSingleton<ConfigurationImporter>(
    () => ConfigurationImporter(
      sourceRepository: Modular.get<CloudSourceRepository>(),
      tmdbCredentialManager: Modular.get<TmdbCredentialManager>(),
    ),
  );
  i.addSingleton<ConfigurationTransferService>(
    () => ConfigurationTransferService(
      sourceRepository: Modular.get<CloudSourceRepository>(),
      tmdbCredentialManager: Modular.get<TmdbCredentialManager>(),
      importer: Modular.get<ConfigurationImporter>(),
      codec: Modular.get<ConfigurationArchiveCodec>(),
    ),
  );
  i.addSingleton<CloudMediaIndexer>(
    () => CloudMediaIndexer(
      repository: Modular.get<CloudMediaIndexRepository>(),
      seriesMatchRuleRepository: Modular.get<CloudSeriesMatchRuleRepository>(),
      episodeMatchRuleRepository:
          Modular.get<CloudEpisodeMatchRuleRepository>(),
      minRecognizedVideoSizeBytesProvider: () =>
          Modular.get<MediaRecognitionSettings>().cloudMinSizeBytes,
    ),
  );
  i.addSingleton<CloudLibraryController>(
    () => CloudLibraryController(
      repository: Modular.get<CloudSourceRepository>(),
      credentialStore: Modular.get<CloudCredentialStore>(),
      mediaIndexRepository: Modular.get<CloudMediaIndexRepository>(),
      mediaTagRepository: Modular.get<CloudMediaTagRepository>(),
      hiddenVideoRepository: Modular.get<CloudHiddenVideoRepository>(),
      resourceTmdbRepository: Modular.get<CloudResourceTmdbRepository>(),
      workTmdbRepository: Modular.get<CloudWorkTmdbRepository>(),
      seriesMatchRuleRepository: Modular.get<CloudSeriesMatchRuleRepository>(),
      mediaIndexer: Modular.get<CloudMediaIndexer>(),
    ),
  );
  i.addSingleton<CloudResourceTmdbCoordinator>(
    () => CloudResourceTmdbCoordinator(
      repository: Modular.get<CloudResourceTmdbRepository>(),
      serviceFactory: (apiKey) async {
        final context =
            Modular.get<TmdbClientContextRegistry>().contextFor(apiKey);
        return CloudResourceTmdbService(
          repository: Modular.get<CloudResourceTmdbRepository>(),
          indexRepository: Modular.get<CloudMediaIndexRepository>(),
          client: context.client,
          cache: context.cache,
          posterCache: CloudPosterCache(
            cacheRoot: await defaultCloudCacheRoot(),
            downloader: TmdbImageClient.shared.downloadBytes,
          ),
        );
      },
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
      serviceFactory: (apiKey) async {
        final context =
            Modular.get<TmdbClientContextRegistry>().contextFor(apiKey);
        return CloudWorkTmdbService(
          repository: Modular.get<CloudWorkTmdbRepository>(),
          indexRepository: Modular.get<CloudMediaIndexRepository>(),
          client: context.client,
          cache: context.cache,
          posterCache: CloudPosterCache(
            cacheRoot: await defaultCloudCacheRoot(),
            downloader: TmdbImageClient.shared.downloadBytes,
          ),
        );
      },
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
      mediaTagRepository: Modular.get<CloudMediaTagRepository>(),
      hiddenVideoRepository: Modular.get<CloudHiddenVideoRepository>(),
      mediaIndexer: Modular.get<CloudMediaIndexer>(),
      episodeMatchService: Modular.get<CloudEpisodeMatchService>(),
      tmdbApiKeyProvider: Modular.get<TmdbApiKeyProvider>(),
      tmdbClientContextRegistry: Modular.get<TmdbClientContextRegistry>(),
      minRecognizedVideoSizeBytesProvider: () =>
          Modular.get<MediaRecognitionSettings>().cloudMinSizeBytes,
    ),
  );
}

TmdbScrapeOptions _tmdbScrapeOptions() {
  try {
    return TmdbScrapeOptions.fromMap(
      Modular.get<TypedSettings>().get('tmdbScrapeOptions'),
    );
  } on Object {
    return const TmdbScrapeOptions.defaults();
  }
}
