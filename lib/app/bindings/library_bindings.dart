import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/core/app_version.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_archive_codec.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_exporter.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_import_planner.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_importer.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_transfer_service.dart';
import 'package:kanyingyin/features/library/application/local_library_metadata_coordinator.dart';
import 'package:kanyingyin/features/library/application/local_library_preferences.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/platform/android/android_document_provider.dart';
import 'package:kanyingyin/platform/android/android_platform_channel.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_series_match_rule_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/cloud_work_tmdb_repository.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/local_media_source_repository.dart';
import 'package:kanyingyin/services/local_media_indexer.dart';
import 'package:kanyingyin/services/local_media_scanner.dart';
import 'package:kanyingyin/services/android_media_entry_provider.dart';
import 'package:kanyingyin/services/android_document_cache.dart';
import 'package:kanyingyin/services/file_system_media_entry_provider.dart';
import 'package:kanyingyin/services/local_media_entry_provider.dart';
import 'package:kanyingyin/services/media_recognition_settings.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';
import 'package:kanyingyin/services/tmdb/tmdb_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_scrape_options.dart';

/// 注册本地媒体库及其与网盘媒体索引的集成依赖。
void registerLibraryBindings(Injector i) {
  i.addSingleton<FileSystemMediaEntryProvider>(
    FileSystemMediaEntryProvider.new,
  );
  i.addSingleton<AndroidDocumentProvider>(
    () => const MethodChannelAndroidDocumentProvider(
      AndroidPlatformChannel(),
    ),
  );
  i.addSingleton<AndroidMediaEntryProvider>(
    () => AndroidMediaEntryProvider(Modular.get<AndroidDocumentProvider>()),
  );
  i.addSingleton<AndroidDocumentCache>(
    () => AndroidDocumentCache(Modular.get<AndroidDocumentProvider>()),
  );
  i.addSingleton<ILocalMediaIndexRepository>(LocalMediaIndexRepository.new);
  i.addSingleton<ILocalMediaSourceRepository>(LocalMediaSourceRepository.new);
  i.addSingleton<ILocalLibraryPreferences>(LocalLibraryPreferences.new);
  i.addSingleton<ScrapedMetadataTransferService>(() {
    final codec = ScrapedMetadataArchiveCodec();
    final exporter = ScrapedMetadataExporter(
      localIndexRepository: Modular.get<ILocalMediaIndexRepository>(),
      localSourceRepository: Modular.get<ILocalMediaSourceRepository>(),
      cloudSourceRepository: Modular.get<CloudSourceRepository>(),
      resourceRepository: Modular.get<CloudResourceTmdbRepository>(),
      workRepository: Modular.get<CloudWorkTmdbRepository>(),
      ruleRepository: Modular.get<CloudSeriesMatchRuleRepository>(),
      appVersion: AppVersion.current,
    );
    final planner = ScrapedMetadataImportPlanner(
      localSourceRepository: Modular.get<ILocalMediaSourceRepository>(),
      localIndexRepository: Modular.get<ILocalMediaIndexRepository>(),
      cloudSourceRepository: Modular.get<CloudSourceRepository>(),
      cloudIndexRepository: Modular.get<CloudMediaIndexRepository>(),
    );
    final importer = ScrapedMetadataImporter(
      localIndexRepository: Modular.get<ILocalMediaIndexRepository>(),
      resourceRepository: Modular.get<CloudResourceTmdbRepository>(),
      workRepository: Modular.get<CloudWorkTmdbRepository>(),
      ruleRepository: Modular.get<CloudSeriesMatchRuleRepository>(),
    );
    return ScrapedMetadataTransferService(
      buildExport: exporter.build,
      writeArchive: codec.write,
      readArchive: codec.read,
      buildPlan: (payload, localOverrides) =>
          planner.plan(payload, localOverrides: localOverrides),
      importPlan: importer.apply,
    );
  });
  i.addSingleton<LocalLibraryMetadataCoordinator>(
    () => LocalLibraryMetadataCoordinator(
      mediaIndexRepository: Modular.get<ILocalMediaIndexRepository>(),
    ),
  );
  i.addSingleton<ILocalMediaIndexer>(
    () => LocalMediaIndexer(
      repository: Modular.get<ILocalMediaIndexRepository>(),
      entryProviders: <LocalMediaEntryProvider>[
        Modular.get<FileSystemMediaEntryProvider>(),
        Modular.get<AndroidMediaEntryProvider>(),
      ],
      documentCache: Modular.get<AndroidDocumentCache>(),
      minRecognizedVideoSizeBytesProvider: () =>
          Modular.get<MediaRecognitionSettings>().localMinSizeBytes,
    ),
  );
  i.addSingleton<LocalController>(
    () => LocalController(
      scanner: LocalMediaScanner(
        entryProviders: <LocalMediaEntryProvider>[
          Modular.get<FileSystemMediaEntryProvider>(),
          Modular.get<AndroidMediaEntryProvider>(),
        ],
        minRecognizedVideoSizeBytesProvider: () =>
            Modular.get<MediaRecognitionSettings>().localMinSizeBytes,
      ),
      mediaIndexer: Modular.get<ILocalMediaIndexer>(),
      preferences: Modular.get<ILocalLibraryPreferences>(),
      metadataCoordinator: Modular.get<LocalLibraryMetadataCoordinator>(),
      mediaIndexRepository: Modular.get<ILocalMediaIndexRepository>(),
      mediaSourceRepository: Modular.get<ILocalMediaSourceRepository>(),
      cloudSourceRepository: Modular.get<CloudSourceRepository>(),
      cloudMediaIndexRepository: Modular.get<CloudMediaIndexRepository>(),
      cloudWorkTmdbRepository: Modular.get<CloudWorkTmdbRepository>(),
      scanCloudSource: (sourceId) async {
        await Modular.get<CloudLibraryController>().scanSource(sourceId);
      },
      tmdbApiKeyProvider: Modular.get<TmdbApiKeyProvider>(),
      tmdbClientContextRegistry: Modular.get<TmdbClientContextRegistry>(),
      tmdbScrapeOptionsProvider: () {
        final settings = Modular.get<TypedSettings>();
        try {
          return TmdbScrapeOptions.fromMap(settings.get('tmdbScrapeOptions'));
        } on Object {
          return const TmdbScrapeOptions.defaults();
        }
      },
      tmdbAutoScrapeProvider: () => Modular.get<TypedSettings>().getTyped<bool>(
        'tmdbAutoScrape',
        defaultValue: true,
      ),
    ),
  );
}
