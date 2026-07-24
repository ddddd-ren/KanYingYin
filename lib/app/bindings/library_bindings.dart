import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/features/library/application/local_library_metadata_coordinator.dart';
import 'package:kanyingyin/features/library/application/local_library_preferences.dart';
import 'package:kanyingyin/pages/local/local_controller.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/local_media_index_repository.dart';
import 'package:kanyingyin/repositories/local_media_source_repository.dart';
import 'package:kanyingyin/services/local_media_indexer.dart';
import 'package:kanyingyin/services/local_media_scanner.dart';
import 'package:kanyingyin/services/media_recognition_settings.dart';
import 'package:kanyingyin/services/tmdb/tmdb_api_key_provider.dart';

/// 注册本地媒体库及其与网盘媒体索引的集成依赖。
void registerLibraryBindings(Injector i) {
  i.addSingleton<ILocalMediaIndexRepository>(LocalMediaIndexRepository.new);
  i.addSingleton<ILocalMediaSourceRepository>(LocalMediaSourceRepository.new);
  i.addSingleton<ILocalLibraryPreferences>(LocalLibraryPreferences.new);
  i.addSingleton<LocalLibraryMetadataCoordinator>(
    () => LocalLibraryMetadataCoordinator(
      mediaIndexRepository: Modular.get<ILocalMediaIndexRepository>(),
    ),
  );
  i.addSingleton<ILocalMediaIndexer>(
    () => LocalMediaIndexer(
      repository: Modular.get<ILocalMediaIndexRepository>(),
      minRecognizedVideoSizeBytesProvider: () =>
          Modular.get<MediaRecognitionSettings>().localMinSizeBytes,
    ),
  );
  i.addSingleton<LocalController>(
    () => LocalController(
      scanner: LocalMediaScanner(
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
      scanCloudSource: (sourceId) async {
        await Modular.get<CloudLibraryController>().scanSource(sourceId);
      },
      tmdbApiKeyProvider: Modular.get<TmdbApiKeyProvider>(),
    ),
  );
}
