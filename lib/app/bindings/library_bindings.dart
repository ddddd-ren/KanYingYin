import 'dart:async';
import 'package:kanyingyin/features/library/application/media_ai_classifier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/core/app_version.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_archive_codec.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_exporter.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_import_planner.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_importer.dart';
import 'package:kanyingyin/features/scraped_metadata_transfer/application/scraped_metadata_transfer_service.dart';
import 'package:kanyingyin/features/library/application/local_library_metadata_coordinator.dart';
import 'package:kanyingyin/features/library/application/local_library_preferences.dart';
import 'package:kanyingyin/features/library/application/library_ports.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/pages/cloud/resources/cloud_resources_controller.dart';
import 'package:kanyingyin/pages/video/local_video_controller.dart';
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
import 'package:kanyingyin/services/tmdb/tmdb_vision_frame_extractor.dart';
import 'package:kanyingyin/services/tmdb/tmdb_vision_model_client.dart';
import 'package:kanyingyin/services/tmdb/tmdb_vision_model_credentials.dart';
import 'package:path/path.dart' as p;
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/local_playback_request_builder.dart';

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
      validateCloudTargets: planner.validateCloudTargets,
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
      localMinSizeBytesProvider: () => Modular.get<MediaRecognitionSettings>().localMinSizeBytes,
      cloudMinSizeBytesProvider: () => Modular.get<MediaRecognitionSettings>().cloudMinSizeBytes,
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
      tmdbVisionSearchAssist: (seriesName, items) async {
        final config = TmdbVisionModelConfig.fromMap(
          Modular.get<TypedSettings>().get('tmdbVisionModel'),
        );
        if (!config.enabled || !config.isConfigured) {
          throw StateError('请先在我页配置 AI 识别与分类模型');
        }
        final key = await Modular.get<TmdbVisionModelCredentials>().read();
        if (key.isEmpty) throw StateError('请先在我页配置 AI 识别与分类模型 API Key');
        final item = items.where((value) => value.location.isFile).firstOrNull;
        if (item == null) return null;
        final frames = await TmdbVisionFrameExtractor().extract(item);
        return Modular.get<TmdbVisionModelClient>().identify(
          config: config,
          apiKey: key,
          fileName: item.name,
          directoryName: p.basename(item.parentPath),
          seasonEpisodeInfo: <String>[
            if (item.seasonNumber != null) 'S${item.seasonNumber}',
            if (item.episodeNumber != null) 'E${item.episodeNumber}',
          ].join(' '),
          existingTmdbInfo: <String, Object?>{
            if (item.tmdb != null) ...<String, Object?>{
              'title': item.tmdb!.title,
              'overview': item.tmdb!.overview,
              'genres': item.tmdb!.genres,
            },
            'seriesName': seriesName,
          },
          frames: frames,
        );
      },
      tmdbVisionClassificationApply: (seriesName, items, metadata) async {
        unawaited(Modular.get<MediaAiClassifier>().process(
          () => Modular.get<LocalController>().localMediaLibrary,
        ));
      },
    ),
  );
  i.addSingleton<LocalLibraryPort>(
    () => _LocalControllerLibraryPort(Modular.get<LocalController>()),
  );
  i.addSingleton<CloudLibraryPort>(
    () => _CloudResourcesLibraryPort(
      Modular.get<CloudResourcesController>(),
    ),
  );
  i.addSingleton<PlaybackPort>(
    () => _LocalVideoPlaybackPort(Modular.get<LocalVideoController>()),
  );
}

class _LocalControllerLibraryPort implements LocalLibraryPort {
  _LocalControllerLibraryPort(this._controller);

  final LocalController _controller;

  @override
  CloudMediaLibrary get library => _controller.localMediaLibrary;

  @override
  CloudMediaLibrary get cachedLibrary => _controller.cachedLocalMediaLibrary;

  @override
  void reloadAvailableLibrary({bool includeUnavailable = false}) {
    if (includeUnavailable) {
      _controller.reloadLocalLibraryIndex();
    } else {
      _controller.reloadAvailableLocalLibraryIndex();
    }
  }
}

class _CloudResourcesLibraryPort implements CloudLibraryPort {
  _CloudResourcesLibraryPort(this._controller);

  final CloudResourcesController _controller;

  @override
  CloudMediaLibrary get library => _controller.mediaLibrarySnapshot;

  @override
  CloudMediaLibrary get cachedLibrary => _controller.cachedMediaLibrarySnapshot;

  @override
  Listenable get changes => _controller.mediaLibrarySnapshotListenable;

  @override
  Future<void> ensureLibrary() => _controller.ensureMediaLibrarySnapshot();

  @override
  Future<void> refreshLibrary() => _controller.reloadMediaLibrarySnapshot();

  @override
  Future<void> hideEpisodes(Iterable<MediaLibraryEpisode> episodes) =>
      _controller.hideMediaLibraryEpisodes(episodes);
}

class _LocalVideoPlaybackPort implements PlaybackPort {
  _LocalVideoPlaybackPort(this._controller);

  final LocalVideoController _controller;

  @override
  Future<void> openFile({
    required String filePath,
    required String seriesTitle,
    List<String>? legacySeriesTitles,
    List<Map<String, String>>? directoryFiles,
    List<LocalPlaybackEntry>? playbackEntries,
    bool playlistAlreadyIsolated = false,
    bool autoLoadSubtitle = true,
  }) =>
      _controller.openFilePlayback(
        filePath: filePath,
        seriesTitle: seriesTitle,
        legacySeriesTitles: legacySeriesTitles,
        directoryFiles: directoryFiles,
        playbackEntries: playbackEntries,
        playlistAlreadyIsolated: playlistAlreadyIsolated,
        autoLoadSubtitle: autoLoadSubtitle,
      );

  @override
  Future<void> openCloud({
    required String seriesTitle,
    String? workKey,
    List<String>? legacySeriesTitles,
    required List<CloudPlaybackTarget> targets,
    required String selectedStableId,
    MediaCategoryCloudPlaybackResolver? resolver,
  }) =>
      _controller.openCloudPlayback(
        seriesTitle: seriesTitle,
        workKey: workKey,
        legacySeriesTitles: legacySeriesTitles,
        targets: targets,
        selectedStableId: selectedStableId,
        resolver: resolver,
      );
}
